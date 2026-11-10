#define _GNU_SOURCE
#include "loop.h"

#include "pipe_signal.h"

#include <pthread.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

enum { slots_per_page = 64, page_count = 1024 };

struct slot {
    uint32_t generation;
    int in_use;
    /* How many threads have this loop as their own. */
    unsigned long runs;
    void *state;
    /* The next free slot's index plus one, 0 for none. */
    unsigned long next_free;
};

/* Pages are allocated as the table grows and are never freed, so a slot
 * read under the lock always exists. */
static struct slot *pages[page_count];
static unsigned long slots_made;
static unsigned long first_free;
static pthread_mutex_t table_lock = PTHREAD_MUTEX_INITIALIZER;

/* The calling thread's loop: its identity and its state, in two
 * thread-specific slots, which every thread starts with empty, so a thread
 * runs on the system until it switches. */
static pthread_key_t identity_key;
static pthread_key_t state_key;
static pthread_once_t keys_once = PTHREAD_ONCE_INIT;

static void fail(const char *message) {
    report_bytes(message, strlen(message));
    abort();
}

static void lock(void) {
    if (pthread_mutex_lock(&table_lock) != 0) fail("linea: the loop table's lock failed\n");
}

static void unlock(void) {
    if (pthread_mutex_unlock(&table_lock) != 0) fail("linea: the loop table's lock failed\n");
}

static void make_keys(void) {
    if (pthread_key_create(&identity_key, NULL) != 0 || pthread_key_create(&state_key, NULL) != 0) {
        fail("linea: the loop table's thread slots could not be made\n");
    }
}

static void keys(void) {
    if (pthread_once(&keys_once, make_keys) != 0) fail("linea: the loop table's thread slots could not be made\n");
}

static struct slot *slot_at(unsigned long index) {
    return &pages[index / slots_per_page][index % slots_per_page];
}

unsigned long linea_loop_claim(void *state) {
    lock();
    unsigned long index;
    if (first_free != 0) {
        index = first_free - 1;
        first_free = slot_at(index)->next_free;
    } else {
        if (slots_made == (unsigned long)slots_per_page * page_count) { unlock(); return 0; }
        if (slots_made % slots_per_page == 0) {
            struct slot *page = calloc(slots_per_page, sizeof *page);
            if (page == NULL) { unlock(); return 0; }
            pages[slots_made / slots_per_page] = page;
        }
        index = slots_made;
        slots_made += 1;
        slot_at(index)->generation = 1;
    }
    struct slot *s = slot_at(index);
    s->in_use = 1;
    s->runs = 0;
    s->state = state;
    s->next_free = 0;
    const unsigned long identity = ((index + 1) << 32) | s->generation;
    unlock();
    return identity;
}

/* The slot `identity` names while its loop lasts, or null. Called locked. */
static struct slot *live_slot(unsigned long identity) {
    const unsigned long index_plus_one = identity >> 32;
    if (index_plus_one == 0 || index_plus_one > slots_made) return NULL;
    struct slot *s = slot_at(index_plus_one - 1);
    if (!s->in_use || s->generation != (uint32_t)identity) return NULL;
    return s;
}

void *linea_loop_find(unsigned long identity) {
    lock();
    struct slot *s = live_slot(identity);
    void *state = s == NULL ? NULL : s->state;
    unlock();
    if (s == NULL) fail("linea: an Io names a loop that has ended\n");
    return state;
}

void linea_loop_retire(unsigned long identity) {
    lock();
    struct slot *s = live_slot(identity);
    if (s == NULL) { unlock(); fail("linea: an Io names a loop that has ended\n"); }
    s->in_use = 0;
    s->state = NULL;
    /* A slot whose generation would wrap stays off the free list. */
    if (s->generation != UINT32_MAX) {
        s->generation += 1;
        s->next_free = first_free;
        first_free = (identity >> 32);
    }
    unlock();
}

void *linea_loop_running(void) {
    keys();
    return pthread_getspecific(state_key);
}

unsigned long linea_io_current(void) {
    keys();
    return (unsigned long)(uintptr_t)pthread_getspecific(identity_key);
}

/* Count `identity`'s threads up or down by one. Called with the table
 * unlocked. */
static void count_run(unsigned long identity, int entering) {
    if (identity == 0) return;
    lock();
    struct slot *s = live_slot(identity);
    if (s != NULL) s->runs = entering ? s->runs + 1 : s->runs - 1;
    unlock();
}

unsigned long linea_loop_runs(unsigned long identity) {
    lock();
    const struct slot *s = live_slot(identity);
    const unsigned long runs = s == NULL ? 0 : s->runs;
    unlock();
    return runs;
}

unsigned long linea_io_switch(unsigned long identity) {
    void *state = identity == 0 ? NULL : linea_loop_find(identity);
    const unsigned long previous = linea_io_current();
    count_run(previous, 0);
    count_run(identity, 1);
    if (pthread_setspecific(identity_key, (void *)(uintptr_t)identity) != 0 || pthread_setspecific(state_key, state) != 0) {
        fail("linea: a thread's loop could not be recorded\n");
    }
    return previous;
}

uint8_t linea_io_is_simulated(unsigned long identity) {
    if (identity == 0) return 0;
    (void)linea_loop_find(identity);
    return 1;
}
