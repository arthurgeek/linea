#define _GNU_SOURCE
#define _DARWIN_C_SOURCE
/* Assertions execute test setup, checks, and cleanup in every build mode. */
#undef NDEBUG
#include <assert.h>
#include <errno.h>
#include <pthread.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <unistd.h>

#include "task.h"

/* `task.c` is compiled with its thread creation, joins, mappings and record
 * allocation renamed to these, and `linea_rt.c` with its `sigaltstack`, so
 * each can be made to fail where the system would. Each counts what it made
 * and otherwise does what the system call does. */
static int refuse_create = 0;
static int refuse_record = 0;
static int refuse_signal_stack = 0;
static unsigned long refuse_map = 0;
static unsigned long attempted_maps = 0;
static unsigned long creates = 0;
static unsigned long joins = 0;
static unsigned long maps = 0;
static unsigned long unmaps = 0;

int linea_test_pthread_create(pthread_t *thread, const pthread_attr_t *attributes, void *(*start)(void *), void *arg);
int linea_test_pthread_create(pthread_t *thread, const pthread_attr_t *attributes, void *(*start)(void *), void *arg) {
    if (refuse_create) return EAGAIN;
    creates += 1;
    return pthread_create(thread, attributes, start, arg);
}

int linea_test_pthread_join(pthread_t thread, void **result);
int linea_test_pthread_join(pthread_t thread, void **result) {
    joins += 1;
    return pthread_join(thread, result);
}

void *linea_test_mmap(void *at, size_t len, int protection, int flags, int fd, off_t offset);
void *linea_test_mmap(void *at, size_t len, int protection, int flags, int fd, off_t offset) {
    attempted_maps += 1;
    if (refuse_map == attempted_maps) {
        errno = ENOMEM;
        return MAP_FAILED;
    }
    void *mapped = mmap(at, len, protection, flags, fd, offset);
    if (mapped != MAP_FAILED) maps += 1;
    return mapped;
}

int linea_test_munmap(void *at, size_t len);
int linea_test_munmap(void *at, size_t len) {
    unmaps += 1;
    return munmap(at, len);
}

void *linea_test_calloc(size_t count, size_t size);
void *linea_test_calloc(size_t count, size_t size) {
    if (refuse_record) return 0;
    return calloc(count, size);
}

int linea_test_sigaltstack(const stack_t *installed, stack_t *previous);
int linea_test_sigaltstack(const stack_t *installed, stack_t *previous) {
    if (refuse_signal_stack && installed != 0 && (installed->ss_flags & SS_DISABLE) == 0) {
        errno = ENOMEM;
        return -1;
    }
    return sigaltstack(installed, previous);
}

/* The body a task would run: a count of the times it ran. */
static volatile int ran = 0;
static volatile int released = 0;

static void entry(unsigned long endpoint, unsigned long at, unsigned long len) {
    (void)at;
    (void)len;
    ran += 1;
    linea_chan_close(endpoint);
}

static void release(unsigned long at, unsigned long len) {
    (void)at;
    (void)len;
    released += 1;
}

/* A failed prepare unmapped every mapping it made and joined every thread
 * it created, and the body it was not given still runs once a prepare
 * succeeds. */
static void nothing_is_left_and_the_body_still_runs(long refused, long expected) {
    assert(refused == expected);
    assert(maps == unmaps && creates == joins && ran == 0);
    const long task = linea_task_prepare(1UL << 16);
    assert(task > 0);
    linea_chan_close(linea_task_start((unsigned long)task, entry, release, 0, 0));
    assert(ran == 1 && released == 1 && maps == unmaps && creates == joins);
    ran = 0;
    released = 0;
}

int main(void) {
    refuse_record = 1;
    long refused = linea_task_prepare(1UL << 16);
    refuse_record = 0;
    nothing_is_left_and_the_body_still_runs(refused, -ENOMEM);

    /* The first mapping is the stack, the second the signal stack. */
    for (unsigned long which = 1; which <= 2; which += 1) {
        refuse_map = attempted_maps + which;
        refused = linea_task_prepare(1UL << 16);
        refuse_map = 0;
        nothing_is_left_and_the_body_still_runs(refused, -ENOMEM);
    }

    refuse_create = 1;
    refused = linea_task_prepare(1UL << 16);
    refuse_create = 0;
    nothing_is_left_and_the_body_still_runs(refused, -EAGAIN);

    /* The thread installs its signal stack before it parks; a refusal there
     * ends the thread, and prepare joins it and reports the refusal. */
    refuse_signal_stack = 1;
    refused = linea_task_prepare(1UL << 16);
    refuse_signal_stack = 0;
    nothing_is_left_and_the_body_still_runs(refused, -ENOMEM);

    /* A cancelled task is joined and unmapped. */
    const long task = linea_task_prepare(1UL << 16);
    assert(task > 0);
    linea_task_cancel((unsigned long)task);
    assert(maps == unmaps && creates == joins && ran == 0 && released == 0);

    puts("native task faults: refused records, mappings, threads and signal stacks leave nothing behind");
    return 0;
}
