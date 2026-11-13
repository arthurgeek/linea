#define _GNU_SOURCE
#define _DARWIN_C_SOURCE
#undef NDEBUG
#include <assert.h>
#include <pthread.h>
#include <stdio.h>
#include <sys/mman.h>
#include <unistd.h>
static pthread_mutex_t cleanup_lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t cleanup_changed = PTHREAD_COND_INITIALIZER;
static int pause_cleanup, cleanup_entered, cleanup_released;
static int cancel_munmap(void *at, size_t bytes) {
    assert(pthread_mutex_lock(&cleanup_lock) == 0);
    if (pause_cleanup) {
        cleanup_entered = 1;
        assert(pthread_cond_signal(&cleanup_changed) == 0);
        while (!cleanup_released) assert(pthread_cond_wait(&cleanup_changed, &cleanup_lock) == 0);
    }
    assert(pthread_mutex_unlock(&cleanup_lock) == 0);
    return munmap(at, bytes);
}
#define munmap cancel_munmap
#include "fiber.c"
#undef munmap
#include "task.h"

/* A prepared empty-body task may leave Simulation.run and move to a system
 * task for cancellation. Its owner may reenter the simulation meanwhile. */
enum { queue_capacity = 128, cancellers = 8, prepared_tasks = 32768 };
static pthread_mutex_t handoff_lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t available = PTHREAD_COND_INITIALIZER;
static pthread_cond_t space = PTHREAD_COND_INITIALIZER;
static unsigned long queue[queue_capacity];
static unsigned head, count;
static int closed;
static void *cancel_prepared(void *unused) {
    (void)unused;
    assert(linea_io_current() == 0);
    for (;;) {
        assert(pthread_mutex_lock(&handoff_lock) == 0);
        while (count == 0 && !closed) assert(pthread_cond_wait(&available, &handoff_lock) == 0);
        if (count == 0) {
            assert(pthread_mutex_unlock(&handoff_lock) == 0);
            return NULL;
        }
        const unsigned long task = queue[head];
        head = (head + 1U) % queue_capacity;
        count -= 1;
        assert(pthread_cond_signal(&space) == 0);
        assert(pthread_mutex_unlock(&handoff_lock) == 0);
        linea_task_cancel(task);
    }
}
static void *cancel_one(void *argument) {
    linea_task_cancel(*(unsigned long *)argument);
    return NULL;
}
static void cancellation_keeps_home_until_cleanup_finishes(void) {
    const unsigned long simulation = linea_sim_open(19, 0, 0, 0, 64, 0, 0);
    assert(simulation != 0);
    assert(linea_io_switch(simulation) == 0);
    const long prepared = linea_task_prepare_on(16384, simulation);
    assert(prepared > 0);
    assert(linea_io_switch(0) == simulation);
    struct carrier *carrier = linea_sim_carrier(simulation);
    unsigned long task = (unsigned long)prepared;
    assert(pthread_mutex_lock(&cleanup_lock) == 0);
    pause_cleanup = 1;
    assert(pthread_mutex_unlock(&cleanup_lock) == 0);
    pthread_t worker;
    assert(pthread_create(&worker, NULL, cancel_one, &task) == 0);
    assert(pthread_mutex_lock(&cleanup_lock) == 0);
    while (!cleanup_entered) assert(pthread_cond_wait(&cleanup_changed, &cleanup_lock) == 0);
    /* Sim.close must still reject this carrier while stack cleanup is live. */
    assert(__atomic_load_n(&carrier->live, __ATOMIC_ACQUIRE) == 1);
    cleanup_released = 1;
    assert(pthread_cond_signal(&cleanup_changed) == 0);
    assert(pthread_mutex_unlock(&cleanup_lock) == 0);
    assert(pthread_join(worker, NULL) == 0);
    pause_cleanup = 0;
    assert(__atomic_load_n(&carrier->live, __ATOMIC_ACQUIRE) == 0);
    linea_sim_close(simulation);
}
int main(void) {
    alarm(40);
    cancellation_keeps_home_until_cleanup_finishes();
    const unsigned long simulation = linea_sim_open(17, 0, 0, 0, 64, 0, 0);
    assert(simulation != 0);
    struct carrier *carrier = linea_sim_carrier(simulation);
    pthread_t workers[cancellers];
    for (unsigned i = 0; i < cancellers; i += 1) assert(pthread_create(&workers[i], NULL, cancel_prepared, NULL) == 0);
    for (unsigned i = 0; i < prepared_tasks; i += 1) {
        assert(linea_io_switch(simulation) == 0);
        const long prepared = linea_task_prepare_on(16384, simulation);
        assert(prepared > 0);
        assert(linea_io_switch(0) == simulation);
        assert(pthread_mutex_lock(&handoff_lock) == 0);
        while (count == queue_capacity) assert(pthread_cond_wait(&space, &handoff_lock) == 0);
        queue[(head + count) % queue_capacity] = (unsigned long)prepared;
        count += 1;
        assert(pthread_cond_signal(&available) == 0);
        assert(pthread_mutex_unlock(&handoff_lock) == 0);
    }
    assert(pthread_mutex_lock(&handoff_lock) == 0);
    closed = 1;
    assert(pthread_cond_broadcast(&available) == 0);
    assert(pthread_mutex_unlock(&handoff_lock) == 0);
    for (unsigned i = 0; i < cancellers; i += 1) assert(pthread_join(workers[i], NULL) == 0);
    const size_t live = __atomic_load_n(&carrier->live, __ATOMIC_ACQUIRE);
    if (live != 0) fprintf(stderr, "remaining simulated tasks: %zu\n", live);
    assert(live == 0);
    linea_sim_close(simulation);
    assert(pthread_cond_destroy(&space) == 0);
    assert(pthread_cond_destroy(&available) == 0);
    assert(pthread_mutex_destroy(&handoff_lock) == 0);
    assert(pthread_cond_destroy(&cleanup_changed) == 0);
    assert(pthread_mutex_destroy(&cleanup_lock) == 0);
    return 0;
}
