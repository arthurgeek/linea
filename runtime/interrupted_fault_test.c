#define _GNU_SOURCE
/* Assertions execute test setup, checks, and cleanup in every build mode. */
#undef NDEBUG
#include <assert.h>
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
 * its run of faults. Once armed, it raises SIGUSR1 there, whose handler jumps
 * out of the fault handler, as a host's handler for another signal may. */

void linea_set_args(int argc, char **argv);

static volatile sig_atomic_t armed = 0;

int linea_test_memcmp(const void *left, const void *right, size_t bytes);
int linea_test_memcmp(const void *left, const void *right, size_t bytes) {
    if (armed) {
        armed = 0;
        raise(SIGUSR1);
    }
    return memcmp(left, right, bytes);
}

#if defined(__APPLE__) && !defined(LINEA_SANITIZED)
static sigjmp_buf escape;

static void jump_out(int signal) {
    (void)signal;
    siglongjmp(escape, 1);
}

/* A host handler that repairs nothing. */
static void host_on_fault_ignoring(int signal, siginfo_t *info, void *context) {
    (void)signal;
    (void)info;
    (void)context;
}

/* A thread's unrepaired fault is interrupted by a signal whose handler jumps
 * out of the fault handler; the access is then made again and left
 * unrepaired. */
static void unrepaired_after_a_jump_out_of_the_handler(void) {
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
    char *page = mmap(0, (size_t)sysconf(_SC_PAGESIZE), PROT_NONE, MAP_PRIVATE | MAP_ANON, -1, 0);
    assert(page != MAP_FAILED);
    armed = 1;
    if (sigsetjmp(escape, 1) == 0) (void)*(volatile char *)page;
    assert(!armed);
    (void)*(volatile char *)page;
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
#endif
    puts("native interrupted faults: a jump out of the fault handler leaves the thread's faults recorded");
    return 0;
}
