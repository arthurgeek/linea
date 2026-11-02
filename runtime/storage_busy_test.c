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
 * `stop_until_resumed`, until `resume` is set. */
enum { stop_for_good = 1, stop_until_resumed = 2 };
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
    aborts_in_time_saying(two_faults_at_once, "linea: storage was used after it was freed\n");
    aborts_in_time_saying(two_faults_at_once_while_the_table_is_held, "linea: storage was used after it was freed\n");
#endif
    return 0;
}
