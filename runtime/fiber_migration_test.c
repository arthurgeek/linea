#define _GNU_SOURCE
#define _DARWIN_C_SOURCE
#undef NDEBUG
#define LINEA_FIBER_MIGRATION_TEST 1
#define LINEA_FIBER_PAUSES 1
#include "fiber.c"
#include <assert.h>
#include <stdio.h>
#include "clock.h"
#include <sys/wait.h>

/* A saved fiber stays alive until every producer has joined. These tests
 * isolate queue authority from the source protocols exercised by the park,
 * I/O and wait-set race suites. */
static struct fiber_loop loop;
static struct carrier carrier;
static struct linea_fiber fiber;

static void *check_mutex(void *unused) {
    (void)unused;
    assert(pthread_mutex_trylock(&loop.metadata) == EBUSY);
    return NULL;
}

static void *publish(void *unused) {
    (void)unused;
    for (unsigned i = 0; i < 100; i += 1) notify(&fiber);
    return NULL;
}

static void publish_together(void) {
    pthread_t producers[8];
    for (size_t i = 0; i < 8; i += 1) assert(pthread_create(&producers[i], NULL, publish, NULL) == 0);
    for (size_t i = 0; i < 8; i += 1) assert(pthread_join(producers[i], NULL) == 0);
}

static void reject_lock_inversion(void) {
    const pid_t child = fork();
    assert(child >= 0);
    if (child == 0) {
        struct linea_park park;
        assert(linea_park_init(&park) == 0);
        lock_metadata(&loop);
        linea_park_lock(&park);
        _exit(0);
    }
    int status;
    assert(waitpid(child, &status, 0) == child);
    assert(WIFSIGNALED(status) && WTERMSIG(status) == SIGABRT);
}

static void check_transfer_claim(void) {
    struct carrier other = { .loop = &loop };
    assert(pthread_mutex_init(&other.queue_lock, NULL) == 0);
    assert(make_poller(&other) == 0);
    fiber.claimed = 0;
    fiber.claimant = NULL;
    fiber.state = runnable;
    fiber.waiting = waiting_yield;
    fiber.transfer_ready = 1;
    fiber.proven = 1;
    lock_fiber(&fiber);
    enqueue_locked(&fiber);
    unlock_fiber(&fiber);
    struct transfer_claim claim = reserve_ready_runnable(&carrier);
    assert(claim.fiber == &fiber && fiber.claimed && !fiber.queued);
    publish_together();
    assert(dequeue(&carrier) == NULL);
    abort_transfer(&claim);
    assert(claim.fiber == NULL && carrier.first == &fiber && carrier.last == &fiber);
    claim = reserve_ready_runnable(&carrier);
    assert(claim.fiber == &fiber);
    struct carrier outside = {0};
    assert(!commit_transfer(&claim, &outside));
    assert(claim.fiber == &fiber && fiber.home == &carrier);
    assert(commit_transfer(&claim, &other));
    assert(claim.fiber == NULL && fiber.home == &other);
    assert(carrier.first == NULL && other.first == &fiber);
    assert(dequeue(&other) == &fiber && dequeue(&other) == NULL);

    fiber.claimed = 0;
    fiber.claimant = NULL;
    fiber.home = &carrier;
    fiber.bound = &carrier;
    lock_fiber(&fiber);
    enqueue_locked(&fiber);
    unlock_fiber(&fiber);
    claim = reserve_ready_runnable(&carrier);
    assert(claim.fiber == NULL && carrier.first == &fiber);
    fiber.bound = NULL;
    fiber.proven = 0;
    claim = reserve_ready_runnable(&carrier);
    assert(claim.fiber == NULL && carrier.first == &fiber);
    fiber.proven = 1;
    fiber.source_claims = 1;
    claim = reserve_ready_runnable(&carrier);
    assert(claim.fiber == NULL && carrier.first == &fiber);
    fiber.source_claims = 0;
    fiber.transfer_ready = 0;
    claim = reserve_ready_runnable(&carrier);
    assert(claim.fiber == NULL && carrier.first == &fiber);
    assert(dequeue(&carrier) == &fiber);
    free_carrier(&other);
}

#if defined(__APPLE__) && defined(__aarch64__) && !__has_feature(address_sanitizer) && !__has_feature(thread_sanitizer)
struct continuation_proof {
    pthread_mutex_t lock;
    pthread_cond_t changed;
    struct linea_fiber *fiber;
    struct carrier *observed[3];
    void *mapping;
    volatile uint64_t *sentinel_address;
    unsigned entries, sequence, transfers, refused;
    int done, bind_after_first;
};
static struct continuation_proof *proof;

void fiber_test_pause(enum linea_fiber_pause_point point) {
    assert(!linea_fiber_metadata_held());
    if (point != linea_fiber_transfer_ready || proof == NULL) return;
    struct carrier *source = current_carrier();
    struct transfer_claim claim = reserve_ready_runnable(source);
    if (claim.fiber == NULL) { proof->refused += 1; return; }
    assert(claim.fiber == proof->fiber);
    assert(source->loop->count == 2);
    struct carrier *target = source == &source->loop->carriers[0] ?
        &source->loop->carriers[1] : &source->loop->carriers[0];
    proof->transfers += 1;
    assert(commit_transfer(&claim, target));
    /* The destination can finish and be reclaimed immediately. */
}

static long unknown_attempt(struct linea_op *operation) {
    (void)operation;
    struct linea_fiber *f = current_fiber();
    assert(f != NULL && f->bound == current_carrier());
    return 17;
}

static void continuation_entry(void *argument) {
    struct continuation_proof *r = argument;
    struct linea_fiber *f = current_fiber();
    volatile uint64_t sentinel = 0x175bf09aUL;
    assert(r->entries++ == 0 && r->sequence++ == 0);
    r->mapping = f->mapping;
    r->sentinel_address = &sentinel;
    r->observed[0] = current_carrier();
    sentinel += 27;
    assert(linea_clock_sleep(0) == 0);
    assert(r->sequence++ == 1 && current_fiber() == f);
    assert(f->mapping == r->mapping && &sentinel == r->sentinel_address && sentinel == 0x175bf0b5UL);
    r->observed[1] = current_carrier();
    if (r->bind_after_first == 3) {
        struct linea_op operation = { .kind = LINEA_OP_READ };
        assert(linea_fiber_perform(&operation, unknown_attempt) == 17);
        assert(f->bound == r->observed[1]);
    } else if (r->bind_after_first == 2) {
        assert(linea_clock_sleep(1) == 0);
        assert(f->bound == r->observed[1]);
    } else if (r->bind_after_first) {
        linea_foreign_enter();
        errno = ENOTTY;
        linea_foreign_leave();
        assert(errno == ENOTTY && f->bound == r->observed[1]);
    }
    sentinel ^= 0x3434;
    assert(linea_clock_sleep(0) == 0);
    assert(r->sequence++ == 2 && current_fiber() == f);
    assert(f->mapping == r->mapping && &sentinel == r->sentinel_address && sentinel == (0x175bf0b5UL ^ 0x3434UL));
    r->observed[2] = current_carrier();
}

static void continuation_finished(void *argument) {
    struct continuation_proof *r = argument;
    assert(pthread_mutex_lock(&r->lock) == 0);
    r->done = 1;
    assert(pthread_cond_signal(&r->changed) == 0);
    assert(pthread_mutex_unlock(&r->lock) == 0);
}

static void prove_continuation(int bind_after_first, int proven) {
    struct continuation_proof r = { .bind_after_first = bind_after_first };
    assert(pthread_mutex_init(&r.lock, NULL) == 0);
    assert(pthread_cond_init(&r.changed, NULL) == 0);
    const long identity = linea_loop_open(2);
    assert(identity > 0);
    int error;
    r.fiber = linea_fiber_create((unsigned long)identity, 2097152, continuation_entry, continuation_finished, &r, &error);
    assert(r.fiber != NULL && error == 0);
    r.fiber->proven = proven;
    proof = &r;
    linea_fiber_start(r.fiber);
    assert(pthread_mutex_lock(&r.lock) == 0);
    while (!r.done) assert(pthread_cond_wait(&r.changed, &r.lock) == 0);
    assert(pthread_mutex_unlock(&r.lock) == 0);
    assert(r.entries == 1 && r.sequence == 3);
    assert((r.observed[0] != r.observed[1]) == proven);
    assert(r.observed[2] == (bind_after_first ? r.observed[1] : r.observed[0]));
    assert(r.transfers == (proven ? (bind_after_first ? 1U : 2U) : 0U));
    assert(r.refused == (proven ? (bind_after_first ? 1U : 0U) : 2U));
    linea_fiber_destroy(r.fiber);
    proof = NULL;
    assert(pthread_cond_destroy(&r.changed) == 0);
    assert(pthread_mutex_destroy(&r.lock) == 0);
}
#else
void fiber_test_pause(enum linea_fiber_pause_point point) { (void)point; }
#endif

static void check_affinity(void) {
    /* A system task has no logical fiber to bind. */
    errno = EDOM;
    linea_fiber_restrict_current();
    assert(errno == EDOM && fiber.bound == NULL);
    assert(pthread_once(&carrier_once, make_carrier_key) == 0);
    assert(pthread_setspecific(carrier_key, &carrier) == 0);
    carrier.executing = &fiber;
    fiber.state = running;
    fiber.saved = 0;
    errno = ERANGE;
    linea_foreign_enter();
    assert(fiber.bound == &carrier && errno == ERANGE);
    assert(linea_foreign_depth() == 1);
    /* Nested callback/native execution cannot clear the outer dependency. */
    errno = ENOTTY;
    linea_foreign_enter();
    assert(fiber.bound == &carrier && errno == ENOTTY);
    linea_foreign_leave();
    assert(linea_foreign_depth() == 1 && fiber.bound == &carrier && errno == ENOTTY);
    linea_foreign_leave();
    assert(linea_foreign_depth() == 0 && fiber.bound == &carrier && errno == ENOTTY);
    linea_fiber_restrict_current();
    assert(fiber.bound == &carrier && errno == ENOTTY);
    carrier.executing = NULL;
    assert(pthread_setspecific(carrier_key, NULL) == 0);
}

int main(void) {
    (void)alarm(30);
    assert(pthread_mutex_init(&loop.metadata, NULL) == 0);
    carrier.loop = &loop;
    assert(pthread_mutex_init(&carrier.queue_lock, NULL) == 0);
    assert(make_poller(&carrier) == 0);
    fiber.loop = &loop;
    fiber.home = &carrier;
    fiber.timer_index = no_timer;
    fiber.state = parking;
    fiber.saved = 0;

    lock_fiber(&fiber);
    assert(linea_fiber_metadata_held());
    pthread_t observer;
    assert(pthread_create(&observer, NULL, check_mutex, NULL) == 0);
    assert(pthread_join(observer, NULL) == 0);
    unlock_fiber(&fiber);
    assert(!linea_fiber_metadata_held());

    publish_together();
    assert(fiber.state == notified && !fiber.queued && !fiber.claimed);
    assert(carrier.first == NULL && carrier.last == NULL);

    /* The context-save owner publishes once after the early notification. */
    lock_fiber(&fiber);
    fiber.saved = 1;
    fiber.state = runnable;
    enqueue_locked(&fiber);
    unlock_fiber(&fiber);
    publish_together();
    assert(carrier.first == &fiber && carrier.last == &fiber && fiber.next == NULL);
    assert(dequeue(&carrier) == &fiber);
    assert(fiber.claimed && fiber.claimant == &carrier && !fiber.queued);
    /* A poller may notify while dispatch owns the popped continuation. */
    publish_together();
    assert(dequeue(&carrier) == NULL);
    assert(fiber.claimed && fiber.saved && fiber.state == runnable);

    lock_fiber(&fiber);
    fiber.claimed = 0;
    fiber.claimant = NULL;
    fiber.state = parked;
    unlock_fiber(&fiber);
    publish_together();
    assert(dequeue(&carrier) == &fiber);
    assert(dequeue(&carrier) == NULL);
    reject_lock_inversion();
    check_transfer_claim();
    check_affinity();
#if defined(__APPLE__) && defined(__aarch64__) && !__has_feature(address_sanitizer) && !__has_feature(thread_sanitizer)
    prove_continuation(0, 1);
    prove_continuation(1, 1);
    prove_continuation(2, 1);
    prove_continuation(3, 1);
    prove_continuation(0, 0);
    puts("native continuation: forced A-B-A, binding on B, and unproven pinned fallback passed");
#endif
    free_carrier(&carrier);
    assert(pthread_mutex_destroy(&loop.metadata) == 0);
    (void)alarm(0);
    puts("native scheduler: concurrent notifications coalesce, dispatch stays exclusive, source inversion is refused");
    return 0;
}
