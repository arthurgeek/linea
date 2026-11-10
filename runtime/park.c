#define _GNU_SOURCE
#define _DARWIN_C_SOURCE
#include "park.h"

#include "pipe_signal.h"

#include <errno.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static const unsigned long nanoseconds_per_second = 1000000000UL;

static void fail(const char *message) {
    report_bytes(message, strlen(message));
    abort();
}

/* A pthread call on a lock or condition variable `linea_park_init` made can
 * fail only when the record holding it is corrupt, which is no state to
 * continue in. */
static void must(int status) {
    if (status != 0) fail("linea: a task's lock failed\n");
}

int linea_park_init(struct linea_park *p) {
    int status = pthread_mutex_init(&p->lock, 0);
    if (status != 0) return status;
#if defined(__APPLE__)
    /* Darwin's condition variable cannot read the monotonic clock; a timed
     * park measures on it itself. */
    status = pthread_cond_init(&p->changed, 0);
#else
    pthread_condattr_t attributes;
    status = pthread_condattr_init(&attributes);
    if (status == 0) {
        status = pthread_condattr_setclock(&attributes, CLOCK_MONOTONIC);
        if (status == 0) status = pthread_cond_init(&p->changed, &attributes);
        if (pthread_condattr_destroy(&attributes) != 0) fail("linea: a condition variable's attributes could not be released\n");
    }
#endif
    if (status != 0) must(pthread_mutex_destroy(&p->lock));
    return status;
}

void linea_park_destroy(struct linea_park *p) {
    must(pthread_cond_destroy(&p->changed));
    must(pthread_mutex_destroy(&p->lock));
}

void linea_park_lock(struct linea_park *p) {
    must(pthread_mutex_lock(&p->lock));
}

void linea_park_unlock(struct linea_park *p) {
    must(pthread_mutex_unlock(&p->lock));
}

void linea_unpark(struct linea_park *p) {
    must(pthread_cond_broadcast(&p->changed));
}

static struct timespec monotonic_now(void) {
    struct timespec now;
    if (clock_gettime(CLOCK_MONOTONIC, &now) != 0) fail("linea: clock_gettime failed\n");
    return now;
}

/* Write `now` in nanoseconds to `*total` and answer 1, or answer 0 when 64
 * bits cannot count it. */
static int nanoseconds_of(struct timespec now, unsigned long *total) {
    unsigned long seconds_ns;
    if (now.tv_sec < 0) return 0;
    if (__builtin_mul_overflow((unsigned long)now.tv_sec, nanoseconds_per_second, &seconds_ns)) return 0;
    return !__builtin_add_overflow(seconds_ns, (unsigned long)now.tv_nsec, total);
}

unsigned long linea_park_deadline_after(unsigned long after_ns) {
    unsigned long now;
    unsigned long deadline;
    if (!nanoseconds_of(monotonic_now(), &now) || __builtin_add_overflow(now, after_ns, &deadline)) return 0;
    /* 0 means no deadline, so a deadline at the clock's first nanosecond is
     * named by its second. */
    return deadline == 0 ? 1 : deadline;
}

int linea_park(struct linea_park *p, unsigned long deadline_ns) {
    if (deadline_ns == 0) {
        must(pthread_cond_wait(&p->changed, &p->lock));
        return 0;
    }
#if defined(__APPLE__)
    /* The wait is relative and recomputed from the monotonic clock on every
     * park. It is at most `longest_relative_wait_sec` long, since Darwin
     * refuses a relative time it cannot add to its own; a capped wait that
     * ends answers 0, and the parker parks again. */
    enum { longest_relative_wait_sec = 86400 };
    /* A clock past what 64 bits count is past every deadline. */
    unsigned long now;
    if (!nanoseconds_of(monotonic_now(), &now) || now >= deadline_ns) return 1;
    const unsigned long remaining_ns = deadline_ns - now;
    struct timespec remaining = {.tv_sec = (time_t)(remaining_ns / nanoseconds_per_second),
                                 .tv_nsec = (long)(remaining_ns % nanoseconds_per_second)};
    if (remaining.tv_sec >= longest_relative_wait_sec) {
        remaining.tv_sec = longest_relative_wait_sec;
        remaining.tv_nsec = 0;
    }
    const int status = pthread_cond_timedwait_relative_np(&p->changed, &p->lock, &remaining);
    if (status != 0 && status != ETIMEDOUT) fail("linea: a timed park failed\n");
    return 0;
#else
    const struct timespec deadline = {.tv_sec = (time_t)(deadline_ns / nanoseconds_per_second),
                                      .tv_nsec = (long)(deadline_ns % nanoseconds_per_second)};
    const int status = pthread_cond_timedwait(&p->changed, &p->lock, &deadline);
    if (status == ETIMEDOUT) return 1;
    if (status != 0) fail("linea: a timed park failed\n");
    return 0;
#endif
}
