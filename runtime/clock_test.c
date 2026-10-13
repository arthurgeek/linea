#define _GNU_SOURCE
/* Assertions execute test setup, checks, and cleanup in every build mode. */
#undef NDEBUG
#include "clock.h"

#include <assert.h>
#include <errno.h>
#include <stdio.h>
#include <time.h>

/* 2026-01-01T00:00:00Z is 1767225600 seconds after the Unix epoch; a wall
 * clock earlier than that is set wrong, and the test says so. */
static const long first_second_of_2026 = 1767225600L;

static void wall_clock_reads_the_present(void) {
    long seconds = 0;
    unsigned long nanoseconds = 0;
    assert(linea_clock_read(LINEA_CLOCK_WALL, &seconds, &nanoseconds) == 0);
    assert(seconds >= first_second_of_2026);
    assert(nanoseconds < 1000000000UL);
    /* The runtime reads the same clock C does, to within a second. */
    const time_t c_seconds = time(NULL);
    assert(seconds - (long)c_seconds <= 1 && (long)c_seconds - seconds <= 1);
}

static void monotonic_clock_moves_forward(void) {
    long first_seconds = 0;
    unsigned long first_nanoseconds = 0;
    assert(linea_clock_read(LINEA_CLOCK_MONOTONIC, &first_seconds, &first_nanoseconds) == 0);
    assert(first_nanoseconds < 1000000000UL);
    /* Sleep 2 ms, so the second reading is strictly later. */
    struct timespec pause = { 0, 2000000L };
    assert(nanosleep(&pause, NULL) == 0);
    long second_seconds = 0;
    unsigned long second_nanoseconds = 0;
    assert(linea_clock_read(LINEA_CLOCK_MONOTONIC, &second_seconds, &second_nanoseconds) == 0);
    assert(second_seconds > first_seconds || (second_seconds == first_seconds && second_nanoseconds > first_nanoseconds));
}

static void an_unknown_clock_is_refused_and_writes_nothing(void) {
    long seconds = 7;
    unsigned long nanoseconds = 9;
    assert(linea_clock_read(2, &seconds, &nanoseconds) == -EINVAL);
    assert(seconds == 7 && nanoseconds == 9);
}

/* A sleep lasts at least as long as it was asked to, on the monotonic clock,
 * and a sleep of no time returns at once. */
static void sleep_lasts_at_least_its_duration(void) {
    struct timespec start;
    assert(clock_gettime(CLOCK_MONOTONIC, &start) == 0);
    assert(linea_clock_sleep(20000000UL) == 0);
    struct timespec end;
    assert(clock_gettime(CLOCK_MONOTONIC, &end) == 0);
    const long long elapsed = (long long)(end.tv_sec - start.tv_sec) * 1000000000LL + (end.tv_nsec - start.tv_nsec);
    assert(elapsed >= 20000000LL);
    assert(linea_clock_sleep(0) == 0);
}

int main(void) {
    wall_clock_reads_the_present();
    monotonic_clock_moves_forward();
    an_unknown_clock_is_refused_and_writes_nothing();
    sleep_lasts_at_least_its_duration();
    puts("native clock: the wall clock reads the present; the monotonic clock moves forward; an unknown clock is refused; a sleep lasts its duration");
    return 0;
}
