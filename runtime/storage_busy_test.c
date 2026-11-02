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

/* Set once the next `mprotect` is to stop its caller for good. */
static volatile int stop_in_mprotect = 0;
/* Written by the stopped thread once it is inside `mprotect`. */
static int stopped[2];

int linea_test_mprotect(void *at, size_t len, int prot);
int linea_test_mprotect(void *at, size_t len, int prot) {
    if (__atomic_load_n(&stop_in_mprotect, __ATOMIC_ACQUIRE)) {
        char byte = 1;
        if (write(stopped[1], &byte, 1) != 1) _exit(3);
        for (;;) pause();
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
    __atomic_store_n(&stop_in_mprotect, 1, __ATOMIC_RELEASE);
    pthread_t holder;
    assert(pthread_create(&holder, 0, allocate, 0) == 0);
    char byte = 0;
    assert(read(stopped[0], &byte, 1) == 1);
    (void)*(volatile unsigned char *)at;
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
#endif
    return 0;
}
