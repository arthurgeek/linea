#define _GNU_SOURCE
/* Assertions execute test setup, checks, and cleanup in every build mode. */
#undef NDEBUG
#include <assert.h>
#include <pthread.h>
#include <signal.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

/* The checking allocator is built with `mprotect` replaced by the function
 * below, so a test can stop a thread inside the allocator while that thread
 * holds the storage table. */

unsigned long linea_alloc(unsigned long size, unsigned long align);
void linea_free(unsigned long at, unsigned long size, unsigned long align);

/* Set once the next `mprotect` is to stop its caller: `stop_for_good`, or
 * `stop_until_resumed`, until `resume` is set, or `exit_thread`, which ends
 * the calling thread with the table still held. */
enum { stop_for_good = 1, stop_until_resumed = 2, exit_thread = 3 };
static volatile int stop_in_mprotect = 0;
static volatile int resume = 0;
/* Written by the stopped thread once it is inside `mprotect`. */
static int stopped[2];

/* Nonzero once the next `mprotect` is to load from this freed address. */
static volatile unsigned long load_in_mprotect = 0;

int linea_test_mprotect(void *at, size_t len, int prot);
int linea_test_mprotect(void *at, size_t len, int prot) {
    const unsigned long freed = __atomic_exchange_n(&load_in_mprotect, 0, __ATOMIC_ACQ_REL);
    if (freed != 0) (void)*(volatile unsigned char *)freed;
    const int stop = __atomic_exchange_n(&stop_in_mprotect, 0, __ATOMIC_ACQ_REL);
    if (stop != 0) {
        char byte = 1;
        if (write(stopped[1], &byte, 1) != 1) _exit(3);
        if (stop == exit_thread) pthread_exit(0);
        if (stop == stop_for_good) {
            for (;;) pause();
        }
        while (!__atomic_load_n(&resume, __ATOMIC_ACQUIRE)) {
            struct timespec pause_for = {0, 1000000};
            nanosleep(&pause_for, 0);
        }
    }
    return mprotect(at, len, prot);
}

/* The checking allocator is also built with `nanosleep` replaced by the
 * function below, so a test can hold a fault handler in its pause while it
 * waits for the storage table. Set `hold_in_pause`, and the next pause
 * writes to `pausing` and waits until something is written to `go_on`. */
static volatile int hold_in_pause = 0;
static int pausing[2];
static int go_on[2];

int linea_test_nanosleep(const struct timespec *duration, struct timespec *left);
int linea_test_nanosleep(const struct timespec *duration, struct timespec *left) {
    if (__atomic_exchange_n(&hold_in_pause, 0, __ATOMIC_ACQ_REL) != 0) {
        char byte = 1;
        if (write(pausing[1], &byte, 1) != 1) _exit(3);
        if (read(go_on[0], &byte, 1) != 1) _exit(3);
    }
    return nanosleep(duration, left);
}

/* The tests below read faults through the runtime's fault handler, which a
 * sanitized runtime does not install. */
#if !defined(LINEA_SANITIZED)
static void *allocate(void *unused) {
    (void)unused;
    (void)linea_alloc(16, 8);
    return 0;
}

/* Frees an allocation, stops another thread inside the allocator while it
 * holds the storage table, then reads the freed storage. The fault handler
 * cannot read the table, so it reports the fault without naming what the
 * access reached rather than waiting for a thread that never releases it. */
static void fault_while_the_table_is_held(void) {
    unsigned long at = linea_alloc(16, 8);
    linea_free(at, 16, 8);
    assert(pipe(stopped) == 0);
    __atomic_store_n(&stop_in_mprotect, stop_for_good, __ATOMIC_RELEASE);
    pthread_t holder;
    assert(pthread_create(&holder, 0, allocate, 0) == 0);
    char byte = 0;
    assert(read(stopped[0], &byte, 1) == 1);
    (void)*(volatile unsigned char *)at;
}

/* Faults on freed storage from inside the allocator, on the thread that
 * holds the storage table while it may be changing it. The fault handler
 * does not read a table its own thread may have left half changed, and does
 * not wait for a flag its own thread holds: it reports the fault without
 * naming what the access reached. */
static void fault_while_this_thread_holds_the_table(void) {
    unsigned long at = linea_alloc(16, 8);
    linea_free(at, 16, 8);
    __atomic_store_n(&load_in_mprotect, at, __ATOMIC_RELEASE);
    (void)linea_alloc(16, 8);
}

/* Freed storage two threads read at once. */
static unsigned long freed_storage = 0;

static void *read_freed_storage(void *unused) {
    (void)unused;
    (void)*(volatile unsigned char *)freed_storage;
    return 0;
}

/* Starts two threads that read freed storage at once, so their fault
 * handlers contend for the storage table. */
static void two_threads_read_freed_storage(void) {
    pthread_t readers[2];
    for (int i = 0; i < 2; i += 1) assert(pthread_create(&readers[i], 0, read_freed_storage, 0) == 0);
}

/* Two faults at once on freed storage: one handler takes the table and
 * reports the use after free, which ends the process before the other. */
static void two_faults_at_once(void) {
    freed_storage = linea_alloc(16, 8);
    linea_free(freed_storage, 16, 8);
    two_threads_read_freed_storage();
    for (;;) pause();
}

/* Two faults at once on freed storage while a third thread holds the table
 * for a tenth of a second: both handlers wait for it, and once it is
 * released one of them reports the use after free. */
static void two_faults_at_once_while_the_table_is_held(void) {
    freed_storage = linea_alloc(16, 8);
    linea_free(freed_storage, 16, 8);
    assert(pipe(stopped) == 0);
    __atomic_store_n(&stop_in_mprotect, stop_until_resumed, __ATOMIC_RELEASE);
    pthread_t holder;
    assert(pthread_create(&holder, 0, allocate, 0) == 0);
    char byte = 0;
    assert(read(stopped[0], &byte, 1) == 1);
    two_threads_read_freed_storage();
    struct timespec pause_for = {0, 100000000};
    nanosleep(&pause_for, 0);
    __atomic_store_n(&resume, 1, __ATOMIC_RELEASE);
    for (;;) pause();
}

/* Forks while a fault handler on another thread is pausing between two
 * attempts to take the storage table. The child, where that thread does not
 * exist, still allocates: nothing in it waits for a handler that is gone.
 * Exits zero when the child allocated within five seconds. */
static void fork_while_a_fault_handler_waits(void) {
    freed_storage = linea_alloc(16, 8);
    linea_free(freed_storage, 16, 8);
    assert(pipe(stopped) == 0 && pipe(pausing) == 0 && pipe(go_on) == 0);
    __atomic_store_n(&stop_in_mprotect, stop_until_resumed, __ATOMIC_RELEASE);
    pthread_t holder;
    assert(pthread_create(&holder, 0, allocate, 0) == 0);
    char byte = 0;
    assert(read(stopped[0], &byte, 1) == 1);
    __atomic_store_n(&hold_in_pause, 1, __ATOMIC_RELEASE);
    pthread_t reader;
    assert(pthread_create(&reader, 0, read_freed_storage, 0) == 0);
    assert(read(pausing[0], &byte, 1) == 1);
    __atomic_store_n(&resume, 1, __ATOMIC_RELEASE);
    assert(pthread_join(holder, 0) == 0);
    const pid_t child = fork();
    assert(child >= 0);
    if (child == 0) {
        (void)linea_alloc(16, 8);
        _exit(0);
    }
    int status = 0;
    pid_t ended = 0;
    for (int tenth = 0; tenth < 50 && ended == 0; tenth += 1) {
        ended = waitpid(child, &status, WNOHANG);
        if (ended == 0) {
            struct timespec pause_for = {0, 100000000};
            nanosleep(&pause_for, 0);
        }
    }
    if (ended == 0) {
        kill(child, SIGKILL);
        (void)waitpid(child, &status, 0);
        _exit(1);
    }
    _exit(WIFEXITED(status) && WEXITSTATUS(status) == 0 ? 0 : 2);
}

/* Runs `body` in a child and checks it exited cleanly. */
static void exits_cleanly(void (*body)(void)) {
    pid_t pid = fork();
    assert(pid >= 0);
    if (pid == 0) {
        body();
        _exit(0);
    }
    int status = 0;
    assert(waitpid(pid, &status, 0) == pid);
    if (!WIFEXITED(status) || WEXITSTATUS(status) != 0) {
        static const char failed[] = "a child forked beside a waiting fault handler did not allocate\n";
        if (write(2, failed, sizeof failed - 1) < 0) {
        }
    }
    assert(WIFEXITED(status) && WEXITSTATUS(status) == 0);
}

/* Ends a thread inside the allocator while it holds the storage table, and
 * joins it, so the system may hand its thread record to the next thread. */
static void end_a_thread_holding_the_table(void) {
    assert(pipe(stopped) == 0);
    __atomic_store_n(&stop_in_mprotect, exit_thread, __ATOMIC_RELEASE);
    pthread_t holder;
    assert(pthread_create(&holder, 0, allocate, 0) == 0);
    char byte = 0;
    assert(read(stopped[0], &byte, 1) == 1);
    assert(pthread_join(holder, 0) == 0);
}

/* A thread ended while it held the storage table, and a thread started
 * after it, which may reuse its thread record, reads freed storage. The fault
 * handler does not take the new thread for the table's owner: it waits its
 * bounded time for the table and reports the fault without naming what the
 * access reached. */
static void fault_after_the_owner_ended(void) {
    freed_storage = linea_alloc(16, 8);
    linea_free(freed_storage, 16, 8);
    end_a_thread_holding_the_table();
    pthread_t reader;
    assert(pthread_create(&reader, 0, read_freed_storage, 0) == 0);
    for (;;) pause();
}

/* The same in the child of a `fork` made after the owner ended, where the
 * table stays as the owner left it. */
static void fault_in_a_child_after_the_owner_ended(void) {
    freed_storage = linea_alloc(16, 8);
    linea_free(freed_storage, 16, 8);
    end_a_thread_holding_the_table();
    const pid_t child = fork();
    assert(child >= 0);
    if (child == 0) {
        (void)*(volatile unsigned char *)freed_storage;
        _exit(0);
    }
    int status = 0;
    assert(waitpid(child, &status, 0) == child);
    if (WIFSIGNALED(status)) {
        signal(WTERMSIG(status), SIG_DFL);
        raise(WTERMSIG(status));
    }
    _exit(1);
}

/* Runs `body` in a child, and checks it aborted within ten seconds after
 * writing `expected` to stderr. A child still running then is killed and the
 * check fails, since it is waiting for something that will not happen. */
static void aborts_in_time_saying(void (*body)(void), const char *expected) {
    int err_pipe[2];
    assert(pipe(err_pipe) == 0);
    pid_t pid = fork();
    assert(pid >= 0);
    if (pid == 0) {
        dup2(err_pipe[1], 2);
        body();
        _exit(0);
    }
    close(err_pipe[1]);
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
        static const char hung[] = "the fault handler waited for the storage table without end\n";
        if (write(2, hung, sizeof hung - 1) < 0) {
        }
        abort();
    }
    char said[512] = {0};
    size_t have = 0;
    ssize_t n;
    while ((n = read(err_pipe[0], said + have, sizeof said - 1 - have)) > 0) have += (size_t)n;
    close(err_pipe[0]);
    assert(WIFSIGNALED(status) && WTERMSIG(status) == SIGABRT);
    assert(strcmp(said, expected) == 0);
}
#endif

int main(void) {
    /* A sanitized runtime installs no fault handler and leaves faults to the
     * sanitizer. */
#if !defined(LINEA_SANITIZED)
    aborts_in_time_saying(
        fault_while_the_table_is_held,
        "linea: a memory access faulted while storage checking was busy, so what it reached is not known\n"
    );
    aborts_in_time_saying(
        fault_while_this_thread_holds_the_table,
        "linea: a memory access faulted while storage checking was busy, so what it reached is not known\n"
    );
    exits_cleanly(fork_while_a_fault_handler_waits);
    aborts_in_time_saying(
        fault_after_the_owner_ended,
        "linea: a memory access faulted while storage checking was busy, so what it reached is not known\n"
    );
    aborts_in_time_saying(
        fault_in_a_child_after_the_owner_ended,
        "linea: a memory access faulted while storage checking was busy, so what it reached is not known\n"
    );
    aborts_in_time_saying(two_faults_at_once, "linea: storage was used after it was freed\n");
    aborts_in_time_saying(two_faults_at_once_while_the_table_is_held, "linea: storage was used after it was freed\n");
#endif
    return 0;
}
