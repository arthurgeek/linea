#define _GNU_SOURCE
/* Assertions execute test setup, checks, and cleanup in every build mode. */
#undef NDEBUG
#include "clock.h"

#include <assert.h>
#include <errno.h>
#include <stdio.h>
#include <time.h>

/* The next call to the clock boundary fails with this errno when it is
 * nonzero; the wrapper clears it on the one call it fires for. The clock it
 * was asked for is recorded, so a test can see which clock was read. */
static int fail_clock_with = 0;
static clockid_t last_clock = (clockid_t)-1;

/* While `simulated` is set, the monotonic clock reads `simulated_now`, and a
 * sleep moves it forward instead of blocking, so a test decides exactly how
 * much time each sleep takes. */
static int simulated = 0;
static struct timespec simulated_now;

int linea_test_clock_gettime(clockid_t id, struct timespec *now) {
    last_clock = id;
    if (fail_clock_with != 0) {
        errno = fail_clock_with;
        fail_clock_with = 0;
        return -1;
    }
    if (simulated && id == CLOCK_MONOTONIC) {
        *now = simulated_now;
        return 0;
    }
    return clock_gettime(id, now);
}

/* Each sleep follows the next step of a script: it moves the simulated clock
 * forward by `advance` nanoseconds, or by the whole request when `advance` is
 * negative, and then fails with `error` when that is nonzero. Every request
 * is recorded. */
struct sleep_step {
    long advance;
    int error;
};

static const struct sleep_step *script = NULL;
static int sleep_calls = 0;
static struct timespec sleep_requests[4];

static void advance_clock(long nanoseconds) {
    simulated_now.tv_sec += nanoseconds / 1000000000L;
    simulated_now.tv_nsec += nanoseconds % 1000000000L;
    if (simulated_now.tv_nsec >= 1000000000L) {
        simulated_now.tv_sec += 1;
        simulated_now.tv_nsec -= 1000000000L;
    }
}

int linea_test_nanosleep(const struct timespec *request, struct timespec *remaining) {
    (void)remaining;
    assert(sleep_calls < 4);
    sleep_requests[sleep_calls] = *request;
    const struct sleep_step step = script[sleep_calls];
    sleep_calls += 1;
    advance_clock(step.advance < 0 ? request->tv_sec * 1000000000L + request->tv_nsec : step.advance);
    if (step.error != 0) {
        errno = step.error;
        return -1;
    }
    return 0;
}

static void simulate_from(long seconds, long nanoseconds, const struct sleep_step *steps) {
    simulated = 1;
    simulated_now.tv_sec = seconds;
    simulated_now.tv_nsec = nanoseconds;
    script = steps;
    sleep_calls = 0;
}

static int requested(int call, long seconds, long nanoseconds) {
    return sleep_requests[call].tv_sec == seconds && sleep_requests[call].tv_nsec == nanoseconds;
}

static void a_failed_read_is_reported_and_writes_nothing(int error, uint8_t clock, clockid_t expected) {
    long seconds = 7;
    unsigned long nanoseconds = 9;
    fail_clock_with = error;
    assert(linea_clock_read(clock, &seconds, &nanoseconds) == -(long)error);
    assert(last_clock == expected);
    assert(seconds == 7 && nanoseconds == 9);
    /* The failure is not sticky: the next read succeeds. */
    assert(linea_clock_read(clock, &seconds, &nanoseconds) == 0);
    assert(nanoseconds < 1000000000UL);
}

/* A sleep interrupted after 0.5 s of 1.5 s sleeps again for the 1 s the
 * monotonic clock says remains, and returns once the whole 1.5 s has passed. */
static void an_interrupted_sleep_sleeps_for_what_remains(void) {
    static const struct sleep_step steps[] = { { 500000000L, EINTR }, { -1, 0 } };
    simulate_from(100, 900000000L, steps);
    assert(linea_clock_sleep(1500000000UL) == 0);
    assert(sleep_calls == 2);
    assert(requested(0, 1, 500000000L));
    assert(requested(1, 1, 0));
    assert(simulated_now.tv_sec == 102 && simulated_now.tv_nsec == 400000000L);
}

/* A sleep that wakes early without an error sleeps again for what remains. */
static void an_early_wake_up_sleeps_again(void) {
    static const struct sleep_step steps[] = { { 300000000L, 0 }, { -1, 0 } };
    simulate_from(5, 0, steps);
    assert(linea_clock_sleep(1500000000UL) == 0);
    assert(sleep_calls == 2);
    assert(requested(1, 1, 200000000L));
    assert(simulated_now.tv_sec == 6 && simulated_now.tv_nsec == 500000000L);
}

/* A sleep that fails for a reason other than an interruption is reported and
 * not retried. */
static void a_failed_sleep_is_reported(void) {
    static const struct sleep_step steps[] = { { 0, EINVAL } };
    simulate_from(5, 0, steps);
    assert(linea_clock_sleep(1000UL) == -EINVAL);
    assert(sleep_calls == 1);
}

/* A clock that cannot be read ends the sleep before it starts. */
static void a_sleep_without_a_clock_is_reported(void) {
    static const struct sleep_step steps[] = { { -1, 0 } };
    simulate_from(5, 0, steps);
    fail_clock_with = EOVERFLOW;
    assert(linea_clock_sleep(1000UL) == -EOVERFLOW);
    assert(sleep_calls == 0);
}

/* A sleep of no time returns without sleeping. */
static void a_sleep_of_no_time_returns_at_once(void) {
    static const struct sleep_step steps[] = { { -1, 0 } };
    simulate_from(5, 0, steps);
    assert(linea_clock_sleep(0) == 0);
    assert(sleep_calls == 0);
}

int main(void) {
    a_failed_read_is_reported_and_writes_nothing(EINVAL, LINEA_CLOCK_WALL, CLOCK_REALTIME);
    a_failed_read_is_reported_and_writes_nothing(EOVERFLOW, LINEA_CLOCK_MONOTONIC, CLOCK_MONOTONIC);
    an_interrupted_sleep_sleeps_for_what_remains();
    an_early_wake_up_sleeps_again();
    a_failed_sleep_is_reported();
    a_sleep_without_a_clock_is_reported();
    a_sleep_of_no_time_returns_at_once();
    puts("native clock: failed reads are reported as their errno and write nothing; an interrupted sleep sleeps for what remains; a failed sleep is reported");
    return 0;
}
