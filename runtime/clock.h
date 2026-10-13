#ifndef LINEA_CLOCK_H
#define LINEA_CLOCK_H

#include <stdint.h>

/* The clocks `linea_clock_read` reads. The wall clock is UTC time since the
 * Unix epoch and can be set backwards; the monotonic clock only moves
 * forward, from an unspecified start, so only differences between its
 * readings mean anything. */
enum linea_clock {
    LINEA_CLOCK_WALL = 0,
    LINEA_CLOCK_MONOTONIC = 1
};

/* Read `clock` into whole seconds and the nanoseconds past them, 0 to
 * 999999999. The result is 0, or a negated errno captured immediately, in
 * which case neither output is written. An unknown clock is -EINVAL. */
long linea_clock_read(uint8_t clock, long *seconds, unsigned long *nanoseconds);

/* Block the calling thread until the monotonic clock has moved at least
 * `nanoseconds` past its reading at the call. An interrupted or early wake-up
 * sleeps again for what remains, measured on the monotonic clock rather than
 * taken from the interrupted request, so the pause is never cut short. The
 * result is 0, or a negated errno when the clock cannot be read or the sleep
 * fails for a reason other than an interruption. */
long linea_clock_sleep(unsigned long nanoseconds);

#endif
