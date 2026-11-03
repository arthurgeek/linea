#define _GNU_SOURCE
/* Assertions execute test setup, checks, and cleanup in every build mode. */
#undef NDEBUG
#include <assert.h>
#include <signal.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

/* The runtime is built with `clock_gettime` replaced by the function below,
 * which moves the monotonic clock on by 200 ms at every read, as a thread
 * that waits that long for a processor between two reads sees it. The
 * thread's CPU clock reads as it is. */

void linea_set_args(int argc, char **argv);

static long monotonic_offset_ns = 0;

int linea_test_clock_gettime(clockid_t clock, struct timespec *now);
int linea_test_clock_gettime(clockid_t clock, struct timespec *now) {
    const int read = clock_gettime(clock, now);
    if (read != 0 || clock != CLOCK_MONOTONIC) return read;
    monotonic_offset_ns += 200000000L;
    const long nanoseconds = now->tv_nsec + monotonic_offset_ns % 1000000000L;
    now->tv_sec += (time_t)(monotonic_offset_ns / 1000000000L + nanoseconds / 1000000000L);
    now->tv_nsec = nanoseconds % 1000000000L;
    return 0;
}

/* A host handler that repairs nothing. */
static void host_on_fault_ignoring(int signal, siginfo_t *info, void *context) {
    (void)signal;
    (void)info;
    (void)context;
}

/* A host handler leaves an access unrepaired on a machine so loaded that the
 * faulting thread waits 200 ms for a processor between every two faults. */
static void unrepaired_on_a_loaded_machine(void) {
    struct sigaction fault;
    memset(&fault, 0, sizeof fault);
    fault.sa_sigaction = host_on_fault_ignoring;
    fault.sa_flags = SA_SIGINFO;
    assert(sigemptyset(&fault.sa_mask) == 0);
    assert(sigaction(SIGSEGV, &fault, 0) == 0 && sigaction(SIGBUS, &fault, 0) == 0);
    char name[] = "loaded";
    char *argv[] = {name, NULL};
    linea_set_args(1, argv);
    char *page = mmap(0, (size_t)sysconf(_SC_PAGESIZE), PROT_NONE, MAP_PRIVATE | MAP_ANON, -1, 0);
    assert(page != MAP_FAILED);
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

int main(void) {
    /* Only macOS hides `SA_RESETHAND`, so only there does the runtime end a
     * fault its host's handler leaves unrepaired; a sanitized runtime
     * installs no fault handler. */
#if defined(__APPLE__) && !defined(LINEA_SANITIZED)
    ends_by_memory_fault(unrepaired_on_a_loaded_machine);
#endif
    puts("native preempted faults: an unrepaired fault is ended however long the thread waits for a processor");
    return 0;
}
