#define _GNU_SOURCE
/* Assertions execute test setup, checks, and cleanup in every build mode. */
#undef NDEBUG
#include <assert.h>
#include <pthread.h>
#include <setjmp.h>
#include <signal.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

/* The runtime is built with `memcmp` replaced by the function below, which
 * the fault handler calls only while it holds the faulting thread's record of
 * its run of faults. While armed, it raises SIGUSR1 there, whose handler
 * jumps out of the fault handler, as a host's handler for another signal may.
 * The signal is blocked while the record is held, so it arrives just after
 * the record is released and before the fault handler returns. */

void linea_set_args(int argc, char **argv);

/* How many more times `memcmp` raises SIGUSR1. */
static volatile sig_atomic_t armed = 0;

int linea_test_memcmp(const void *left, const void *right, size_t bytes);
int linea_test_memcmp(const void *left, const void *right, size_t bytes) {
    if (armed > 0) {
        armed -= 1;
        raise(SIGUSR1);
    }
    return memcmp(left, right, bytes);
}

#if defined(__APPLE__) && !defined(LINEA_SANITIZED)
static sigjmp_buf escape;
static volatile sig_atomic_t jumps = 0;

static void jump_out(int signal) {
    (void)signal;
    jumps += 1;
    siglongjmp(escape, 1);
}

/* A host handler that repairs nothing. */
static void host_on_fault_ignoring(int signal, siginfo_t *info, void *context) {
    (void)signal;
    (void)info;
    (void)context;
}

static char *inaccessible_page = 0;

/* Installs the host's handlers and starts the runtime, then maps a page
 * every access to faults. */
static void prepare(void) {
    struct sigaction fault;
    memset(&fault, 0, sizeof fault);
    fault.sa_sigaction = host_on_fault_ignoring;
    fault.sa_flags = SA_SIGINFO;
    assert(sigemptyset(&fault.sa_mask) == 0);
    assert(sigaction(SIGSEGV, &fault, 0) == 0 && sigaction(SIGBUS, &fault, 0) == 0);
    struct sigaction usr1;
    memset(&usr1, 0, sizeof usr1);
    usr1.sa_handler = jump_out;
    assert(sigemptyset(&usr1.sa_mask) == 0);
    assert(sigaction(SIGUSR1, &usr1, 0) == 0);
    char name[] = "interrupted";
    char *argv[] = {name, NULL};
    linea_set_args(1, argv);
    inaccessible_page = mmap(0, (size_t)sysconf(_SC_PAGESIZE), PROT_NONE, MAP_PRIVATE | MAP_ANON, -1, 0);
    assert(inaccessible_page != MAP_FAILED);
}

/* Faults on the page until the fault handler has been jumped out of `times`
 * times since `jumps` was last zero. */
static void jumped_out_of(int times) {
    armed = times;
    (void)sigsetjmp(escape, 1);
    if (jumps < times) (void)*(volatile char *)inaccessible_page;
    assert(jumps == times && armed == 0);
}

/* A thread's unrepaired fault is interrupted by a signal whose handler jumps
 * out of the fault handler; the access is then made again and left
 * unrepaired. */
static void unrepaired_after_a_jump_out_of_the_handler(void) {
    prepare();
    jumped_out_of(1);
    (void)*(volatile char *)inaccessible_page;
}

/* The same, jumped out of three runs in turn before the last. */
static void unrepaired_after_three_jumps_out_of_the_handler(void) {
    prepare();
    jumped_out_of(3);
    (void)*(volatile char *)inaccessible_page;
}

static void *jump_out_then_end(void *unused) {
    jumped_out_of(1);
    return unused;
}

/* A thread jumped out of the fault handler and ended; another thread's
 * unrepaired fault is still ended. */
static void unrepaired_after_a_thread_jumped_out_and_ended(void) {
    prepare();
    pthread_t thread;
    assert(pthread_create(&thread, 0, jump_out_then_end, 0) == 0);
    assert(pthread_join(thread, 0) == 0);
    (void)*(volatile char *)inaccessible_page;
}

/* Runs `body` in a child and checks it was ended by a memory fault within ten
 * seconds. */
static void ends_by_memory_fault(void (*body)(void)) {
    const pid_t pid = fork();
    assert(pid >= 0);
    if (pid == 0) {
        body();
        _exit(0);
    }
    int status = 0;
    pid_t ended = 0;
    for (int tenth = 0; tenth < 100 && ended == 0; tenth += 1) {
        ended = waitpid(pid, &status, WNOHANG);
        if (ended == 0) {
            struct timespec pause_for = {0, 100000000};
            nanosleep(&pause_for, 0);
        }
    }
    if (ended == 0) {
        kill(pid, SIGKILL);
        assert(waitpid(pid, &status, 0) == pid);
        fprintf(stderr, "the faulting process still ran after ten seconds\n");
    }
    assert(WIFSIGNALED(status) && (WTERMSIG(status) == SIGSEGV || WTERMSIG(status) == SIGBUS));
}
#endif

int main(void) {
    /* Only macOS keeps runs of faults, to end one its host's handler leaves
     * unrepaired; a sanitized runtime installs no fault handler. */
#if defined(__APPLE__) && !defined(LINEA_SANITIZED)
    ends_by_memory_fault(unrepaired_after_a_jump_out_of_the_handler);
    ends_by_memory_fault(unrepaired_after_three_jumps_out_of_the_handler);
    ends_by_memory_fault(unrepaired_after_a_thread_jumped_out_and_ended);
#endif
    puts("native interrupted faults: a jump out of the fault handler leaves the thread's faults recorded");
    return 0;
}
