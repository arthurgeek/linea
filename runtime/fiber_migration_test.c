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
    assert(claim.fiber == NULL && carrier.stealable_first == &fiber && carrier.stealable_last == &fiber);
    claim = reserve_ready_runnable(&carrier);
    assert(claim.fiber == &fiber);
    struct carrier outside = {0};
    assert(!commit_transfer(&claim, &outside));
    assert(claim.fiber == &fiber && fiber.home == &carrier);
    assert(commit_transfer(&claim, &other));
    assert(claim.fiber == NULL && fiber.home == &other);
    assert(carrier.stealable_first == NULL && other.stealable_first == &fiber);
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

static void check_repeated_completed_transfer(void) {
    struct carrier second = { .loop = &loop }, third = { .loop = &loop };
    assert(pthread_mutex_init(&second.queue_lock, NULL) == 0);
    assert(pthread_mutex_init(&third.queue_lock, NULL) == 0);
    assert(make_poller(&second) == 0 && make_poller(&third) == 0);
    struct linea_op operation = { .kind = LINEA_OP_READABLE };
    struct pending_operation completed = {
        .operation = &operation, .fiber = &fiber, .owner = &carrier,
        .state = operation_complete, .result = 37,
    };
    const struct linea_context context = fiber.context;
    fiber.claimed = no_claim;
    fiber.claimant = NULL;
    fiber.waiting = waiting_io;
    fiber.operation = &completed;
    fiber.transfer_ready = 1;
    lock_fiber(&fiber);
    enqueue_locked(&fiber);
    unlock_fiber(&fiber);
    completed.registered = 1;
    assert(reserve_ready_runnable(&carrier).fiber == NULL);
    completed.registered = 0;
    completed.state = operation_armed;
    assert(reserve_ready_runnable(&carrier).fiber == NULL);
    completed.state = operation_complete;
    fiber.source_claims = 1;
    assert(reserve_ready_runnable(&carrier).fiber == NULL);
    fiber.source_claims = 0;
    fiber.timer_index = 0;
    assert(reserve_ready_runnable(&carrier).fiber == NULL);
    fiber.timer_index = no_timer;
    struct carrier *source = &carrier;
    struct carrier *targets[] = { &second, &third, &carrier };
    for (size_t i = 0; i < sizeof targets / sizeof targets[0]; i += 1) {
        struct transfer_claim claim = reserve_ready_runnable(source);
        if (i == 0) assert(claim.fiber == &fiber);
        else assert(claim.fiber == &fiber && completed.owner != source);
        assert(commit_transfer(&claim, targets[i]));
        assert(claim.fiber == NULL && fiber.home == targets[i]);
        assert(completed.owner == &carrier && completed.result == 37);
        assert(fiber.operation == &completed && completed.operation == &operation);
        assert(memcmp(&context, &fiber.context, sizeof context) == 0);
        source = targets[i];
    }
    assert(dequeue(&carrier) == &fiber && dequeue(&second) == NULL && dequeue(&third) == NULL);
    fiber.operation = NULL;
    fiber.waiting = waiting_yield;
    fiber.transfer_ready = 0;
    free_carrier(&second);
    free_carrier(&third);
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

static void check_prepared_entry_grant(void) {
    struct linea_fiber parent = { .loop = &loop, .home = &carrier, .state = running };
    assert(pthread_once(&carrier_once, make_carrier_key) == 0);
    assert(pthread_setspecific(carrier_key, &carrier) == 0);
    carrier.executing = &parent;
    for (unsigned i = 0; i < 3; i += 1) {
        struct linea_fiber prepared = {
            .loop = &loop, .home = &carrier, .state = parked, .saved = 1,
            .timer_index = no_timer, .bound = i == 2 ? &carrier : NULL,
        };
        if (i == 1) linea_fiber_start(&prepared);
        else linea_fiber_start_compiled(&prepared);
        assert(prepared.proven == (i != 1));
        assert(parent.proven == 0);
        assert(prepared.bound == (i == 2 ? &carrier : NULL));
        assert(dequeue(&carrier) == &prepared && dequeue(&carrier) == NULL);
    }
    carrier.executing = NULL;
    assert(pthread_setspecific(carrier_key, NULL) == 0);
    struct carrier simulation = { .simulation = 1, .kernel = -1, .wake = -1 };
    assert(pthread_mutex_init(&simulation.queue_lock, NULL) == 0);
    struct linea_fiber simulated = {
        .home = &simulation, .state = parked, .saved = 1, .timer_index = no_timer,
    };
    linea_fiber_start_compiled(&simulated);
    assert(simulated.proven == 0 && simulation.ready_count == 1 && simulation.ready[0] == &simulated);
    free_carrier(&simulation);
}

static void check_queue_lane_progress(void) {
    struct linea_fiber work[3];
    memset(work, 0, sizeof work);
    for (size_t i = 0; i < 3; i += 1) {
        work[i].home = &carrier;
        work[i].loop = &loop;
        work[i].state = runnable;
        work[i].saved = 1;
        work[i].waiting = waiting_yield;
        work[i].timer_index = no_timer;
        work[i].proven = i == 2;
        work[i].transfer_ready = i == 2;
        lock_fiber(&work[i]);
        enqueue_locked(&work[i]);
        unlock_fiber(&work[i]);
    }
    struct linea_fiber *first = dequeue(&carrier);
    struct linea_fiber *second = dequeue(&carrier);
    assert(first == &work[2] || second == &work[2]);
    assert(first == &work[0] || second == &work[0]);
    assert(first != second && dequeue(&carrier) == &work[1]);
    assert(dequeue(&carrier) == NULL);
}

struct steal_gate {
    pthread_mutex_t lock;
    pthread_cond_t changed;
    unsigned waiting;
    int start;
};

struct thief_call {
    struct steal_gate *gate;
    struct carrier *carrier;
    struct linea_fiber *selected;
};

static void *compete_for_work(void *argument) {
    struct thief_call *call = argument;
    assert(pthread_setspecific(carrier_key, call->carrier) == 0);
    assert(pthread_mutex_lock(&call->gate->lock) == 0);
    call->gate->waiting += 1;
    assert(pthread_cond_broadcast(&call->gate->changed) == 0);
    while (!call->gate->start) assert(pthread_cond_wait(&call->gate->changed, &call->gate->lock) == 0);
    assert(pthread_mutex_unlock(&call->gate->lock) == 0);
    call->selected = steal_for_dispatch(call->carrier);
    assert(pthread_setspecific(carrier_key, NULL) == 0);
    return NULL;
}

static void check_idle_steal_claim(int concurrent) {
    struct carrier peers[3];
    memset(peers, 0, sizeof peers);
    struct fiber_loop stealing = { .count = 3, .carriers = peers };
    assert(pthread_mutex_init(&stealing.metadata, NULL) == 0);
    for (size_t i = 0; i < 3; i += 1) {
        peers[i].loop = &stealing;
        assert(pthread_mutex_init(&peers[i].queue_lock, NULL) == 0);
        assert(make_poller(&peers[i]) == 0);
    }
    struct linea_fiber busy = { .home = &peers[0], .loop = &stealing, .state = running };
    peers[0].executing = &busy;
    struct linea_fiber work = {
        .home = &peers[0], .loop = &stealing, .state = runnable, .saved = 1,
        .proven = 1, .waiting = waiting_yield, .transfer_ready = 1, .timer_index = no_timer,
    };
    struct linea_fiber pinned = {
        .home = &peers[0], .loop = &stealing, .bound = &peers[0],
        .state = runnable, .saved = 1, .waiting = waiting_yield, .timer_index = no_timer,
    };
    lock_fiber(&work);
    enqueue_locked(&pinned);
    enqueue_locked(&work);
    unlock_fiber(&work);
    assert(pthread_once(&carrier_once, make_carrier_key) == 0);
    struct carrier *winner;
    if (concurrent) {
        struct steal_gate gate = {0};
        assert(pthread_mutex_init(&gate.lock, NULL) == 0);
        assert(pthread_cond_init(&gate.changed, NULL) == 0);
        struct thief_call calls[] = { { .gate = &gate, .carrier = &peers[1] }, { .gate = &gate, .carrier = &peers[2] } };
        pthread_t threads[2];
        for (size_t i = 0; i < 2; i += 1) assert(pthread_create(&threads[i], NULL, compete_for_work, &calls[i]) == 0);
        assert(pthread_mutex_lock(&gate.lock) == 0);
        while (gate.waiting != 2) assert(pthread_cond_wait(&gate.changed, &gate.lock) == 0);
        gate.start = 1;
        assert(pthread_cond_broadcast(&gate.changed) == 0);
        assert(pthread_mutex_unlock(&gate.lock) == 0);
        for (size_t i = 0; i < 2; i += 1) assert(pthread_join(threads[i], NULL) == 0);
        assert((calls[0].selected == &work) + (calls[1].selected == &work) == 1);
        assert(calls[0].selected == NULL || calls[1].selected == NULL);
        winner = calls[0].selected != NULL ? &peers[1] : &peers[2];
        assert(pthread_cond_destroy(&gate.changed) == 0);
        assert(pthread_mutex_destroy(&gate.lock) == 0);
    } else {
        assert(pthread_setspecific(carrier_key, &peers[1]) == 0);
        assert(steal_for_dispatch(&peers[1]) == &work);
        winner = &peers[1];
        assert(pthread_setspecific(carrier_key, &peers[2]) == 0);
        assert(steal_for_dispatch(&peers[2]) == NULL);
    }
    assert(work.home == winner && work.claimed == dispatch_claim && work.claimant == winner);
    assert(work.state == runnable && work.saved && !work.queued);
    assert(peers[0].executing == &busy && busy.state == running);
    assert(dequeue(&peers[0]) == &pinned && dequeue(&peers[0]) == NULL);
    assert(dequeue(&peers[1]) == NULL && dequeue(&peers[2]) == NULL);
    assert(pthread_setspecific(carrier_key, NULL) == 0);
    for (size_t i = 0; i < 3; i += 1) free_carrier(&peers[i]);
    assert(pthread_mutex_destroy(&stealing.metadata) == 0);
}

static void check_idle_wakeup(void) {
    struct carrier peers[3];
    memset(peers, 0, sizeof peers);
    struct fiber_loop waking = { .count = 3, .carriers = peers };
    assert(pthread_mutex_init(&waking.metadata, NULL) == 0);
    for (size_t i = 0; i < 3; i += 1) {
        peers[i].loop = &waking;
        assert(pthread_mutex_init(&peers[i].queue_lock, NULL) == 0);
        assert(make_poller(&peers[i]) == 0);
    }
    struct linea_fiber work = {
        .home = &peers[0], .loop = &waking, .state = runnable, .saved = 1,
        .proven = 1, .waiting = waiting_yield, .transfer_ready = 1, .timer_index = no_timer,
    };
    lock_fiber(&work);
    __atomic_store_n(&peers[1].idle, 1, __ATOMIC_RELEASE);
    enqueue_locked(&work);
    unlock_fiber(&work);
    wake_idle_peers(&peers[0]);
    struct pollfd observed[3];
    for (size_t i = 0; i < 3; i += 1) observed[i] = (struct pollfd){ peers[i].kernel, POLLIN, 0 };
    assert(poll(observed, 3, 0) == 1);
    assert(observed[0].revents == 0 && observed[2].revents == 0 && (observed[1].revents & POLLIN));
    poll_carrier(&peers[1], 1);
    assert(poll(observed, 3, 0) == 0);
    assert(dequeue(&peers[2]) == NULL);
    assert(__atomic_load_n(&peers[2].idle, __ATOMIC_ACQUIRE) == 1);
    assert(pthread_setspecific(carrier_key, &peers[2]) == 0);
    assert(steal_for_dispatch(&peers[2]) == &work);
    assert(__atomic_load_n(&peers[2].idle, __ATOMIC_ACQUIRE) == 0);
    assert(pthread_setspecific(carrier_key, NULL) == 0);
    for (size_t i = 0; i < 3; i += 1) free_carrier(&peers[i]);
    assert(pthread_mutex_destroy(&waking.metadata) == 0);
}

struct sleeping_thief {
    struct steal_gate gate;
    struct carrier *carrier;
    struct linea_fiber *selected;
};

static void *sleep_after_empty_scan(void *argument) {
    struct sleeping_thief *call = argument;
    struct carrier *c = call->carrier;
    assert(pthread_setspecific(carrier_key, c) == 0);
    assert(dequeue(c) == NULL && steal_for_dispatch(c) == NULL);
    assert(pthread_mutex_lock(&call->gate.lock) == 0);
    call->gate.waiting = 1;
    assert(pthread_cond_signal(&call->gate.changed) == 0);
    while (!call->gate.start) assert(pthread_cond_wait(&call->gate.changed, &call->gate.lock) == 0);
    assert(pthread_mutex_unlock(&call->gate.lock) == 0);
    /* Publication occurred after the last empty scan but before blocking.
     * A retained kernel notification must make this wait return immediately. */
    struct pollfd observed = { c->kernel, POLLIN, 0 };
    assert(poll(&observed, 1, 1000) == 1 && (observed.revents & POLLIN));
    poll_carrier(c, 1);
    call->selected = steal_for_dispatch(c);
    assert(pthread_setspecific(carrier_key, NULL) == 0);
    return NULL;
}

static void check_publication_before_sleep(void) {
    struct carrier peers[2];
    memset(peers, 0, sizeof peers);
    struct fiber_loop waking = { .count = 2, .carriers = peers };
    assert(pthread_mutex_init(&waking.metadata, NULL) == 0);
    for (size_t i = 0; i < 2; i += 1) {
        peers[i].loop = &waking;
        assert(pthread_mutex_init(&peers[i].queue_lock, NULL) == 0);
        assert(make_poller(&peers[i]) == 0);
    }
    struct sleeping_thief call = { .carrier = &peers[1] };
    assert(pthread_mutex_init(&call.gate.lock, NULL) == 0);
    assert(pthread_cond_init(&call.gate.changed, NULL) == 0);
    pthread_t thief;
    assert(pthread_create(&thief, NULL, sleep_after_empty_scan, &call) == 0);
    assert(pthread_mutex_lock(&call.gate.lock) == 0);
    while (!call.gate.waiting) assert(pthread_cond_wait(&call.gate.changed, &call.gate.lock) == 0);
    struct linea_fiber work = {
        .home = &peers[0], .loop = &waking, .state = runnable, .saved = 1,
        .proven = 1, .waiting = waiting_yield, .transfer_ready = 1, .timer_index = no_timer,
    };
    lock_fiber(&work);
    enqueue_locked(&work);
    unlock_fiber(&work);
    wake_idle_peers(&peers[0]);
    call.gate.start = 1;
    assert(pthread_cond_signal(&call.gate.changed) == 0);
    assert(pthread_mutex_unlock(&call.gate.lock) == 0);
    assert(pthread_join(thief, NULL) == 0);
    assert(call.selected == &work && work.home == &peers[1]);
    assert(pthread_cond_destroy(&call.gate.changed) == 0);
    assert(pthread_mutex_destroy(&call.gate.lock) == 0);
    for (size_t i = 0; i < 2; i += 1) free_carrier(&peers[i]);
    assert(pthread_mutex_destroy(&waking.metadata) == 0);
}

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
    check_repeated_completed_transfer();
    check_prepared_entry_grant();
    check_queue_lane_progress();
    check_idle_steal_claim(0);
    check_idle_steal_claim(1);
    check_idle_wakeup();
    check_publication_before_sleep();
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
