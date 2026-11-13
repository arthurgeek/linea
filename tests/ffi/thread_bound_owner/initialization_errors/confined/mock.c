#define _POSIX_C_SOURCE 200809L
#include <assert.h>
#include <pthread.h>
#include <stdint.h>
#include <stdlib.h>
struct resource { pthread_t thread; unsigned failures; uint64_t calls; };
static unsigned live, closes, refused;
static pthread_mutex_t gate_lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t gate_changed = PTHREAD_COND_INITIALIZER;
static unsigned block_first, blocked, allowed;
void mock_block_first(void) { assert(pthread_mutex_lock(&gate_lock) == 0); block_first = 1; assert(pthread_mutex_unlock(&gate_lock) == 0); }
uint8_t mock_blocked(void) { assert(pthread_mutex_lock(&gate_lock) == 0); unsigned value = blocked; assert(pthread_mutex_unlock(&gate_lock) == 0); return (uint8_t)value; }
void mock_unblock(void) { assert(pthread_mutex_lock(&gate_lock) == 0); allowed = 1; assert(pthread_cond_broadcast(&gate_changed) == 0); assert(pthread_mutex_unlock(&gate_lock) == 0); }
uint64_t mock_calls;

uint64_t mock_open(uint8_t mode) {
    if (mode == 1) return 0;
    struct resource *r = calloc(1, sizeof *r);
    assert(r != NULL);
    r->thread = pthread_self(); r->failures = mode == 3 ? 0 : 1;
    live += 1;
    return (uint64_t)(uintptr_t)r;
}
uint64_t mock_read(uint64_t handle) {
    struct resource *r = (void *)(uintptr_t)handle;
    assert(pthread_equal(r->thread, pthread_self()));
    assert(pthread_mutex_lock(&gate_lock) == 0);
    if (block_first && r->calls == 0) {
        blocked = 1;
        while (!allowed) assert(pthread_cond_wait(&gate_changed, &gate_lock) == 0);
    }
    assert(pthread_mutex_unlock(&gate_lock) == 0);
    mock_calls += 1;
    return ++r->calls;
}
uint8_t mock_close(uint64_t *handle) {
    struct resource *r = (void *)(uintptr_t)*handle;
    assert(pthread_equal(r->thread, pthread_self()));
    if (r->failures != 0) { r->failures -= 1; refused += 1; return 1; }
    free(r); *handle = 0; live -= 1; closes += 1; return 0;
}
uint8_t mock_balanced(void) { return live == 0 && closes == 3 && refused == 2; }

int64_t mock_operate(uint64_t handle, uint8_t fail) {
    struct resource *r = (void *)(uintptr_t)handle;
    assert(pthread_equal(r->thread, pthread_self()));
    if (fail) return -77;
    return (int64_t)mock_read(handle);
}
