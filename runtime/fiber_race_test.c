#define _GNU_SOURCE
#ifndef LINEA_FIBER_PAUSES
#define LINEA_FIBER_PAUSES 1
#endif
#undef NDEBUG
#include "fiber.h"
#include "fiber_pause.h"
#include "park.h"
#include "task.h"

#include <assert.h>
#include <pthread.h>
#include <stdio.h>
#include <unistd.h>

static pthread_mutex_t control_lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t control_changed = PTHREAD_COND_INITIALIZER;
static enum linea_fiber_pause_point target;
static int enabled, reached, proceed;
static struct linea_park record;
static int ready;
static unsigned returned, released, barriers;

/* Only the test build calls this hook. None of the record's locks may be
 * held here: the controller must be able to publish the wake while the
 * carrier is stopped at each handoff boundary. */
void fiber_test_pause(enum linea_fiber_pause_point point) {
    assert(pthread_mutex_lock(&control_lock) == 0);
    if (enabled && point == target && !reached) {
        reached = 1;
        assert(pthread_cond_signal(&control_changed) == 0);
        while (!proceed) assert(pthread_cond_wait(&control_changed, &control_lock) == 0);
    }
    assert(pthread_mutex_unlock(&control_lock) == 0);
}

static void release_body(unsigned long at, unsigned long len) {
    assert(at == 0 && len == 0);
    released += 1;
}

static void wait_body(unsigned long endpoint, unsigned long at, unsigned long len) {
    assert(at == 0 && len == 0);
    linea_park_lock(&record);
    while (!ready) (void)linea_park(&record, 0);
    linea_park_unlock(&record);
    __atomic_add_fetch(&returned, 1, __ATOMIC_RELEASE);
    linea_chan_close(endpoint);
}

static void barrier_body(unsigned long endpoint, unsigned long at, unsigned long len) {
    assert(at == 0 && len == 0);
    barriers += 1;
    linea_chan_close(endpoint);
}

static void wake_at(unsigned long loop, enum linea_fiber_pause_point point) {
    assert(linea_park_init(&record) == 0);
    ready = 0;
    __atomic_store_n(&returned, 0, __ATOMIC_RELAXED);
    assert(pthread_mutex_lock(&control_lock) == 0);
    target = point; enabled = 1; reached = 0; proceed = 0;
    assert(pthread_mutex_unlock(&control_lock) == 0);
    const long prepared = linea_task_prepare_on(2097152, loop);
    assert(prepared > 0);
    const unsigned long handle = linea_task_start((unsigned long)prepared, wait_body, release_body, 0, 0, 0);
    assert(pthread_mutex_lock(&control_lock) == 0);
    while (!reached) assert(pthread_cond_wait(&control_changed, &control_lock) == 0);
    assert(pthread_mutex_unlock(&control_lock) == 0);

    assert(__atomic_load_n(&returned, __ATOMIC_ACQUIRE) == 0);
    linea_park_lock(&record);
    ready = 1;
    linea_unpark(&record);
    linea_park_unlock(&record);
    /* A wake recorded in Parking must not run the unsaved context. A wake
     * after Parked must still wait for the home carrier to take it. */
    assert(__atomic_load_n(&returned, __ATOMIC_ACQUIRE) == 0);
    assert(pthread_mutex_lock(&control_lock) == 0);
    proceed = 1;
    assert(pthread_cond_signal(&control_changed) == 0);
    assert(pthread_mutex_unlock(&control_lock) == 0);
    linea_chan_close(handle);
    assert(__atomic_load_n(&returned, __ATOMIC_ACQUIRE) == 1);
    assert(pthread_mutex_lock(&control_lock) == 0);
    enabled = 0;
    assert(pthread_mutex_unlock(&control_lock) == 0);
    linea_park_destroy(&record);

    /* Force another scheduler turn after reclaiming the first task. A
     * duplicate queue entry would now reach a retired record or context. */
    const long barrier = linea_task_prepare_on(2097152, loop);
    assert(barrier > 0);
    linea_chan_close(linea_task_start((unsigned long)barrier, barrier_body, release_body, 0, 0, 0));
}

int main(void) {
    (void)alarm(30);
    const long loop = linea_loop_open(1);
    assert(loop > 0);
    for (unsigned i = 0; i < 16; i += 1) {
        wake_at((unsigned long)loop, linea_fiber_before_switch);
        wake_at((unsigned long)loop, linea_fiber_context_saved);
        wake_at((unsigned long)loop, linea_fiber_parked);
    }
    assert(barriers == 48 && released == 96);
    (void)alarm(0);
    puts("native fibers: every park handoff boundary preserves one wake and one execution");
    return 0;
}
