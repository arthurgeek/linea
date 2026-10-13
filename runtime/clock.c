#define _GNU_SOURCE
#include "clock.h"

#include <errno.h>
#include <time.h>

static const long nanoseconds_per_second = 1000000000L;

long linea_clock_read(uint8_t clock, long *seconds, unsigned long *nanoseconds) {
    clockid_t id;
    switch (clock) {
    case LINEA_CLOCK_WALL: id = CLOCK_REALTIME; break;
    case LINEA_CLOCK_MONOTONIC: id = CLOCK_MONOTONIC; break;
    default: return -(long)EINVAL;
    }
    struct timespec now;
    if (clock_gettime(id, &now) != 0) return -(long)errno;
    *seconds = (long)now.tv_sec;
    *nanoseconds = (unsigned long)now.tv_nsec;
    return 0;
}

long linea_clock_sleep(unsigned long nanoseconds) {
    struct timespec deadline;
    if (clock_gettime(CLOCK_MONOTONIC, &deadline) != 0) return -(long)errno;
    /* A duration of at most 2^64 - 1 nanoseconds is under 585 years, so the
     * deadline fits a 64-bit time_t. */
    deadline.tv_sec += (time_t)(nanoseconds / (unsigned long)nanoseconds_per_second);
    deadline.tv_nsec += (long)(nanoseconds % (unsigned long)nanoseconds_per_second);
    if (deadline.tv_nsec >= nanoseconds_per_second) {
        deadline.tv_sec += 1;
        deadline.tv_nsec -= nanoseconds_per_second;
    }
    for (;;) {
        struct timespec now;
        if (clock_gettime(CLOCK_MONOTONIC, &now) != 0) return -(long)errno;
        if (now.tv_sec > deadline.tv_sec || (now.tv_sec == deadline.tv_sec && now.tv_nsec >= deadline.tv_nsec)) return 0;
        struct timespec remaining;
        remaining.tv_sec = deadline.tv_sec - now.tv_sec;
        remaining.tv_nsec = deadline.tv_nsec - now.tv_nsec;
        if (remaining.tv_nsec < 0) {
            remaining.tv_sec -= 1;
            remaining.tv_nsec += nanoseconds_per_second;
        }
        if (nanosleep(&remaining, NULL) != 0 && errno != EINTR) return -(long)errno;
    }
}
