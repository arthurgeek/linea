/* The wait set's protocol, with each interleaving of a source and the set's
 * owner forced by pausing one party at a linearization point: registration,
 * a peer's arrival, a body's return, a timer's expiry, `next`, `take` and
 * `close`. Each test checks that a registration leaves the set exactly once
 * and that no wake is lost. */

#define _GNU_SOURCE
#define _DARWIN_C_SOURCE
/* Assertions execute test setup, checks, and cleanup in every build mode. */
#undef NDEBUG
#include <assert.h>
#include <errno.h>
#include <pthread.h>
#include <sched.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#include "signals.h"
#include "task.h"
#include "waitset.h"
#include "waitset_pause.h"

/* The pauses: a thread reaching an armed point stops there, once, until the
 * test releases that point. Several points may be armed at once, so a test
 * holds two parties each at its own point. */
static int armed[linea_pause_points];
static int arrived[linea_pause_points];
static int released[linea_pause_points];

void waitset_test_pause(enum linea_pause_point point) {
    int expected = 1;
    if (!__atomic_compare_exchange_n(&armed[point], &expected, 0, 0, __ATOMIC_SEQ_CST, __ATOMIC_SEQ_CST)) return;
    __atomic_store_n(&arrived[point], 1, __ATOMIC_SEQ_CST);
    while (!__atomic_load_n(&released[point], __ATOMIC_SEQ_CST)) sched_yield();
}

static void arm(enum linea_pause_point point) {
    __atomic_store_n(&arrived[point], 0, __ATOMIC_SEQ_CST);
    __atomic_store_n(&released[point], 0, __ATOMIC_SEQ_CST);
    __atomic_store_n(&armed[point], 1, __ATOMIC_SEQ_CST);
}

static void await_arrival(enum linea_pause_point point) {
    while (!__atomic_load_n(&arrived[point], __ATOMIC_SEQ_CST)) sched_yield();
}

static void release_pause(enum linea_pause_point point) {
    __atomic_store_n(&released[point], 1, __ATOMIC_SEQ_CST);
}

/* Arm `point`, then wait until a thread stops there and let it go: once this
 * returns, that thread has passed the point. */
static void pass(enum linea_pause_point point) {
    await_arrival(point);
    release_pause(point);
}

static void release_nothing(unsigned long at, unsigned long len) {
    (void)at;
    (void)len;
}

/* A task whose body sends one number and closes its end. */
static void send_one(unsigned long endpoint, unsigned long at, unsigned long len) {
    (void)at;
    (void)len;
    unsigned long value = 7;
    linea_chan_send(endpoint, (unsigned long)&value, sizeof value);
    linea_chan_close(endpoint);
}

/* A task whose body returns at once. */
static void return_at_once(unsigned long endpoint, unsigned long at, unsigned long len) {
    (void)at;
    (void)len;
    linea_chan_close(endpoint);
}

static unsigned long started(linea_task_entry body) {
    const long task = linea_task_prepare(1UL << 18);
    assert(task > 0);
    return linea_task_start((unsigned long)task, body, release_nothing, 0, 0, 0);
}

static unsigned long slot_of(unsigned long reserved) {
    return reserved >> 32;
}

static unsigned long generation_of(unsigned long reserved) {
    return reserved & 0xffffffffUL;
}

/* Receive the number `send_one` sends and join the task. */
static void finish_send_one(unsigned long handle) {
    unsigned long value = 0;
    linea_chan_recv(handle, (unsigned long)&value, sizeof value);
    assert(value == 7);
    linea_chan_close(handle);
}

/* The peer's send arrives before the registration: the registration's own
 * check finds it. */
static void a_send_before_registration_is_found(void) {
    const unsigned long set = linea_waitset_open();
    arm(linea_pause_send_filled);
    const unsigned long handle = started(send_one);
    pass(linea_pause_send_filled);
    const unsigned long reserved = linea_waitset_reserve(set);
    linea_waitset_received(set, slot_of(reserved), handle);
    assert(linea_waitset_next(set) == (long)slot_of(reserved));
    assert(linea_waitset_next(set) == -1);
    finish_send_one(handle);
    linea_waitset_close(set);
}

/* A task whose body waits for its creator's go-ahead, then sends. */
static int go_ahead = 0;

static void send_when_told(unsigned long endpoint, unsigned long at, unsigned long len) {
    (void)at;
    (void)len;
    while (!__atomic_load_n(&go_ahead, __ATOMIC_SEQ_CST)) sched_yield();
    unsigned long value = 7;
    linea_chan_send(endpoint, (unsigned long)&value, sizeof value);
    linea_chan_close(endpoint);
}

static unsigned long started_waiting(void) {
    __atomic_store_n(&go_ahead, 0, __ATOMIC_SEQ_CST);
    return started(send_when_told);
}

static void tell_to_send(void) {
    __atomic_store_n(&go_ahead, 1, __ATOMIC_SEQ_CST);
}

struct register_call {
    unsigned long set, slot, handle;
};

static void *call_received(void *arg) {
    struct register_call *call = arg;
    linea_waitset_received(call->set, call->slot, call->handle);
    return 0;
}

/* The registration has published its mark and is paused before its check
 * when the peer's send arrives: the send waits for the session's lock, finds
 * the mark, and signals the registration once. */
static void a_send_during_registration_signals_once(void) {
    const unsigned long set = linea_waitset_open();
    const unsigned long reserved = linea_waitset_reserve(set);
    const unsigned long handle = started_waiting();
    arm(linea_pause_watch_after_publish);
    struct register_call call = { set, slot_of(reserved), handle };
    pthread_t registering;
    assert(pthread_create(&registering, 0, call_received, &call) == 0);
    await_arrival(linea_pause_watch_after_publish);
    arm(linea_pause_send_filled);
    tell_to_send();
    release_pause(linea_pause_watch_after_publish);
    assert(pthread_join(registering, 0) == 0);
    pass(linea_pause_send_filled);
    assert(linea_waitset_next(set) == (long)slot_of(reserved));
    assert(linea_waitset_next(set) == -1);
    finish_send_one(handle);
    linea_waitset_close(set);
}

struct next_call {
    unsigned long set;
    long answer;
};

static void *call_next(void *arg) {
    struct next_call *call = arg;
    call->answer = linea_waitset_next(call->set);
    return 0;
}

/* `next` has found nothing signalled and holds the set's lock, about to
 * wait, when the peer's send swaps the registration: the post waits for the
 * lock, and its wake reaches the owner once it waits. */
static void a_send_as_next_begins_to_wait_wakes_it(void) {
    const unsigned long set = linea_waitset_open();
    const unsigned long handle = started_waiting();
    const unsigned long reserved = linea_waitset_reserve(set);
    linea_waitset_received(set, slot_of(reserved), handle);
    arm(linea_pause_next_before_wait);
    struct next_call call = { set, -2 };
    pthread_t waiter;
    assert(pthread_create(&waiter, 0, call_next, &call) == 0);
    await_arrival(linea_pause_next_before_wait);
    arm(linea_pause_source_after_swap);
    tell_to_send();
    pass(linea_pause_source_after_swap);
    release_pause(linea_pause_next_before_wait);
    assert(pthread_join(waiter, 0) == 0);
    assert(call.answer == (long)slot_of(reserved));
    finish_send_one(handle);
    linea_waitset_close(set);
}

/* `take` withdraws an endpoint whose peer waits in its send: the endpoint
 * comes back, the sender still waits, the set never delivers it, and a later
 * receive completes at once. `take_if_registered` refuses it, since it was
 * signalled. */
static void take_of_a_signalled_endpoint_leaves_the_sender_waiting(void) {
    const unsigned long set = linea_waitset_open();
    const unsigned long reserved = linea_waitset_reserve(set);
    const unsigned long handle = started_waiting();
    linea_waitset_received(set, slot_of(reserved), handle);
    arm(linea_pause_send_filled);
    tell_to_send();
    pass(linea_pause_send_filled);
    assert(linea_waitset_take(set, slot_of(reserved), generation_of(reserved), 1) == 0);
    assert(linea_waitset_take(set, slot_of(reserved), generation_of(reserved), 0) == 1);
    assert(linea_waitset_take(set, slot_of(reserved), generation_of(reserved), 0) == 0);
    assert(linea_waitset_next(set) == -1);
    finish_send_one(handle);
    linea_waitset_close(set);
}

struct take_call {
    unsigned long set, slot, generation;
    uint8_t answer;
};

static void *call_take(void *arg) {
    struct take_call *call = arg;
    call->answer = linea_waitset_take(call->set, call->slot, call->generation, 0);
    return 0;
}

/* The source has swapped the registration to signalled and is paused before
 * it queues it when `take` swaps it to taken: `take` then waits for the
 * session's lock, so the source's post lands first, and `take` takes the
 * registration back out of the queue. `next` never delivers it. */
static void take_between_a_sources_swap_and_its_post(void) {
    const unsigned long set = linea_waitset_open();
    const unsigned long reserved = linea_waitset_reserve(set);
    const unsigned long handle = started_waiting();
    linea_waitset_received(set, slot_of(reserved), handle);
    arm(linea_pause_source_after_swap);
    tell_to_send();
    await_arrival(linea_pause_source_after_swap);
    arm(linea_pause_take_after_swap);
    struct take_call call = { set, slot_of(reserved), generation_of(reserved), 9 };
    pthread_t taker;
    assert(pthread_create(&taker, 0, call_take, &call) == 0);
    pass(linea_pause_take_after_swap);
    release_pause(linea_pause_source_after_swap);
    assert(pthread_join(taker, 0) == 0);
    assert(call.answer == 1);
    assert(linea_waitset_next(set) == -1);
    finish_send_one(handle);
    linea_waitset_close(set);
}

/* `take` swaps while the source is paused before its own swap: the source's
 * swap fails and it posts nothing. */
static void take_before_a_sources_swap(void) {
    const unsigned long set = linea_waitset_open();
    const unsigned long reserved = linea_waitset_reserve(set);
    const unsigned long handle = started_waiting();
    linea_waitset_received(set, slot_of(reserved), handle);
    arm(linea_pause_source_before_swap);
    tell_to_send();
    await_arrival(linea_pause_source_before_swap);
    arm(linea_pause_take_after_swap);
    struct take_call call = { set, slot_of(reserved), generation_of(reserved), 9 };
    pthread_t taker;
    assert(pthread_create(&taker, 0, call_take, &call) == 0);
    pass(linea_pause_take_after_swap);
    release_pause(linea_pause_source_before_swap);
    assert(pthread_join(taker, 0) == 0);
    assert(call.answer == 1);
    assert(linea_waitset_next(set) == -1);
    finish_send_one(handle);
    linea_waitset_close(set);
}

/* A body's return, before and after its handle is registered. */
static void a_return_is_delivered_once_either_way(void) {
    const unsigned long set = linea_waitset_open();
    arm(linea_pause_body_finished);
    const unsigned long early = started(return_at_once);
    pass(linea_pause_body_finished);
    const unsigned long first = linea_waitset_reserve(set);
    linea_waitset_returned(set, slot_of(first), early);
    const unsigned long late = started_waiting();
    const unsigned long second = linea_waitset_reserve(set);
    linea_waitset_returned(set, slot_of(second), late);
    assert(linea_waitset_next(set) == (long)slot_of(first));
    linea_chan_close(early);
    tell_to_send();
    /* The late body sends before it returns; it is not watched for a send. */
    unsigned long value = 0;
    linea_chan_recv(late, (unsigned long)&value, sizeof value);
    assert(linea_waitset_next(set) == (long)slot_of(second));
    linea_chan_close(late);
    assert(linea_waitset_next(set) == -1);
    linea_waitset_close(set);
}

/* An expired timer races `take`: `take` sees the expiry first, so the
 * message comes back and is never delivered; `take_if_registered` refuses
 * one that has expired, and `next` delivers it. */
static void an_expired_timer_is_taken_or_delivered_once(void) {
    const unsigned long set = linea_waitset_open();
    const unsigned long a = linea_waitset_reserve(set);
    linea_waitset_timer(set, slot_of(a), 0);
    arm(linea_pause_take_after_swap);
    struct take_call call = { set, slot_of(a), generation_of(a), 9 };
    pthread_t taker;
    assert(pthread_create(&taker, 0, call_take, &call) == 0);
    pass(linea_pause_take_after_swap);
    assert(pthread_join(taker, 0) == 0);
    assert(call.answer == 1);
    assert(linea_waitset_next(set) == -1);

    const unsigned long b = linea_waitset_reserve(set);
    linea_waitset_timer(set, slot_of(b), 0);
    assert(linea_waitset_take(set, slot_of(b), generation_of(b), 1) == 0);
    assert(linea_waitset_next(set) == (long)slot_of(b));
    assert(linea_waitset_take(set, slot_of(b), generation_of(b), 0) == 0);

    /* A far timer is withdrawn while registered. */
    const unsigned long c = linea_waitset_reserve(set);
    linea_waitset_timer(set, slot_of(c), 3600UL * 1000000000UL);
    assert(linea_waitset_take(set, slot_of(c), generation_of(c), 1) == 1);
    assert(linea_waitset_next(set) == -1);
    linea_waitset_close(set);
}

/* A slot reused after its registration was taken has a new generation, so a
 * key of the old one is refused. */
static void a_reused_slot_refuses_an_old_key(void) {
    const unsigned long set = linea_waitset_open();
    const unsigned long first = linea_waitset_reserve(set);
    linea_waitset_timer(set, slot_of(first), 3600UL * 1000000000UL);
    assert(linea_waitset_take(set, slot_of(first), generation_of(first), 0) == 1);
    const unsigned long second = linea_waitset_reserve(set);
    linea_waitset_timer(set, slot_of(second), 3600UL * 1000000000UL);
    assert(slot_of(second) == slot_of(first));
    assert(generation_of(second) != generation_of(first));
    assert(linea_waitset_take(set, slot_of(first), generation_of(first), 0) == 0);
    assert(linea_waitset_take(set, slot_of(second), generation_of(second), 0) == 1);
    linea_waitset_close(set);
}

/* Closing a set withdraws each registration once, signalled or not, and a
 * sender whose endpoint was withdrawn still waits for its receive. */
static void close_withdraws_each_registration_once(void) {
    const unsigned long set = linea_waitset_open();
    arm(linea_pause_send_filled);
    const unsigned long handle = started(send_one);
    pass(linea_pause_send_filled);
    const unsigned long a = linea_waitset_reserve(set);
    linea_waitset_received(set, slot_of(a), handle);
    const unsigned long b = linea_waitset_reserve(set);
    linea_waitset_timer(set, slot_of(b), 3600UL * 1000000000UL);
    const unsigned long c = linea_waitset_reserve(set);
    linea_waitset_timer(set, slot_of(c), 0);
    int seen[3] = { 0, 0, 0 };
    for (;;) {
        const long slot = linea_waitset_withdraw(set);
        if (slot < 0) break;
        assert(slot < 3);
        seen[slot] += 1;
    }
    assert(seen[0] == 1 && seen[1] == 1 && seen[2] == 1);
    linea_waitset_close(set);
    finish_send_one(handle);
}

/* Several sources signalled before one `next` are delivered one per call,
 * earliest first. */
static void the_earliest_signalled_is_delivered_first(void) {
    const unsigned long set = linea_waitset_open();
    const unsigned long late = linea_waitset_reserve(set);
    linea_waitset_timer(set, slot_of(late), 2000000UL);
    const unsigned long now = linea_waitset_reserve(set);
    linea_waitset_ready(set, slot_of(now));
    const unsigned long soon = linea_waitset_reserve(set);
    linea_waitset_timer(set, slot_of(soon), 1000000UL);
    assert(linea_waitset_next(set) == (long)slot_of(now));
    assert(linea_waitset_next(set) == (long)slot_of(soon));
    assert(linea_waitset_next(set) == (long)slot_of(late));
    assert(linea_waitset_next(set) == -1);
    linea_waitset_close(set);
}

/* A pipe's read end is ready once a byte is written, through the set's
 * kernel queue, and a timer still wakes a set that has one. */
static void a_descriptor_and_a_timer_wake_the_kernel_queue(void) {
    int ends[2];
    assert(pipe(ends) == 0);
    const unsigned long set = linea_waitset_open();
    const unsigned long readable = linea_waitset_reserve(set);
    assert(linea_waitset_descriptor(set, slot_of(readable), ends[0], 0) == 0);
    const unsigned long timer = linea_waitset_reserve(set);
    linea_waitset_timer(set, slot_of(timer), 1000000UL);
    assert(linea_waitset_next(set) == (long)slot_of(timer));
    assert(write(ends[1], "x", 1) == 1);
    assert(linea_waitset_next(set) == (long)slot_of(readable));
    /* Registered again, the byte still unread makes it ready at once. */
    const unsigned long again = linea_waitset_reserve(set);
    assert(linea_waitset_descriptor(set, slot_of(again), ends[0], 0) == 0);
    assert(linea_waitset_next(set) == (long)slot_of(again));
    /* A session's peer still wakes a set waiting in its kernel queue. */
    const unsigned long handle = started(send_one);
    const unsigned long peer = linea_waitset_reserve(set);
    linea_waitset_received(set, slot_of(peer), handle);
    assert(linea_waitset_next(set) == (long)slot_of(peer));
    finish_send_one(handle);
    linea_waitset_close(set);
    close(ends[0]);
    close(ends[1]);
}

static int host_calls = 0;

static void host_handler(int number) {
    (void)number;
    __atomic_add_fetch(&host_calls, 1, __ATOMIC_SEQ_CST);
}

/* `SIGUSR1` raised at the process wakes every set holding a registration for
 * it, deliveries before `next` coalesce, a delivery before a registration
 * does not signal it, the host's handler is still called, and the last share
 * restores the host's action. */
static void a_signal_wakes_every_set_that_waits_for_it(void) {
    struct sigaction host;
    memset(&host, 0, sizeof host);
    host.sa_handler = host_handler;
    sigemptyset(&host.sa_mask);
    assert(sigaction(SIGUSR1, &host, 0) == 0);
    assert(linea_signal_acquire(3) == 0);
    assert(linea_signal_acquire(3) == 0);
    const unsigned long one = linea_waitset_open();
    const unsigned long two = linea_waitset_open();
    const unsigned long a = linea_waitset_reserve(one);
    assert(linea_waitset_signal(one, slot_of(a), 3, 0) == 0);
    const unsigned long b = linea_waitset_reserve(two);
    assert(linea_waitset_signal(two, slot_of(b), 3, 0) == 0);
    assert(raise(SIGUSR1) == 0);
    assert(raise(SIGUSR1) == 0);
    assert(linea_waitset_next(one) == (long)slot_of(a));
    assert(linea_waitset_next(two) == (long)slot_of(b));
    assert(linea_waitset_next(one) == -1);
    assert(__atomic_load_n(&host_calls, __ATOMIC_SEQ_CST) == 2);

    /* A registration made after the deliveries waits for the next one. */
    const unsigned long c = linea_waitset_reserve(one);
    assert(linea_waitset_signal(one, slot_of(c), 3, 0) == 0);
    const unsigned long d = linea_waitset_reserve(one);
    linea_waitset_timer(one, slot_of(d), 1000000UL);
    assert(linea_waitset_next(one) == (long)slot_of(d));
    assert(raise(SIGUSR1) == 0);
    assert(linea_waitset_next(one) == (long)slot_of(c));
    linea_waitset_close(one);
    linea_waitset_close(two);

    linea_signal_release(3, 0);
    struct sigaction now;
    assert(sigaction(SIGUSR1, 0, &now) == 0);
    assert(now.sa_handler != host_handler);
    linea_signal_release(3, 0);
    assert(sigaction(SIGUSR1, 0, &now) == 0);
    assert(now.sa_handler == host_handler);
    signal(SIGUSR1, SIG_DFL);
}

/* An ignored signal is refused, and its action is left as it was. */
static void an_ignored_signal_is_refused(void) {
    signal(SIGUSR2, SIG_IGN);
    assert(linea_signal_acquire(4) == 1);
    struct sigaction now;
    assert(sigaction(SIGUSR2, 0, &now) == 0);
    assert(now.sa_handler == SIG_IGN);
    signal(SIGUSR2, SIG_DFL);
}

/* While a share of `SIGTERM` lives the process survives it, and once the
 * last share is released a second `SIGTERM` ends the process. */
static void a_second_terminate_after_the_last_share_ends_the_process(void) {
    const pid_t child = fork();
    assert(child >= 0);
    if (child == 0) {
        if (linea_signal_acquire(0) != 0) _exit(10);
        const unsigned long set = linea_waitset_open();
        const unsigned long a = linea_waitset_reserve(set);
        if (linea_waitset_signal(set, slot_of(a), 0, 0) != 0) _exit(11);
        raise(SIGTERM);
        if (linea_waitset_next(set) != (long)slot_of(a)) _exit(12);
        linea_waitset_close(set);
        linea_signal_release(0, 0);
        raise(SIGTERM);
        _exit(13);
    }
    int status = 0;
    assert(waitpid(child, &status, 0) == child);
    assert(WIFSIGNALED(status) && WTERMSIG(status) == SIGTERM);
}

/* A task whose body waits for its creator's go-ahead, then returns. */
static void return_when_told(unsigned long endpoint, unsigned long at, unsigned long len) {
    (void)at;
    (void)len;
    while (!__atomic_load_n(&go_ahead, __ATOMIC_SEQ_CST)) sched_yield();
    linea_chan_close(endpoint);
}

static unsigned long started_to_return(void) {
    __atomic_store_n(&go_ahead, 0, __ATOMIC_SEQ_CST);
    return started(return_when_told);
}

static void *call_returned(void *arg) {
    struct register_call *call = arg;
    linea_waitset_returned(call->set, call->slot, call->handle);
    return 0;
}

/* The registration of a handle has published its mark and is paused before
 * its check when the body returns: the body waits for the record's lock,
 * finds the mark, and signals the registration once. */
static void a_return_during_registration_signals_once(void) {
    const unsigned long set = linea_waitset_open();
    const unsigned long reserved = linea_waitset_reserve(set);
    const unsigned long handle = started_to_return();
    arm(linea_pause_watch_after_publish);
    struct register_call call = { set, slot_of(reserved), handle };
    pthread_t registering;
    assert(pthread_create(&registering, 0, call_returned, &call) == 0);
    await_arrival(linea_pause_watch_after_publish);
    arm(linea_pause_body_finished);
    tell_to_send();
    release_pause(linea_pause_watch_after_publish);
    assert(pthread_join(registering, 0) == 0);
    pass(linea_pause_body_finished);
    assert(linea_waitset_next(set) == (long)slot_of(reserved));
    assert(linea_waitset_next(set) == -1);
    linea_chan_close(handle);
    linea_waitset_close(set);
}

/* `next` has found nothing signalled and is about to wait when the body
 * returns: the return's wake reaches the owner once it waits. */
static void a_return_as_next_begins_to_wait_wakes_it(void) {
    const unsigned long set = linea_waitset_open();
    const unsigned long handle = started_to_return();
    const unsigned long reserved = linea_waitset_reserve(set);
    linea_waitset_returned(set, slot_of(reserved), handle);
    arm(linea_pause_next_before_wait);
    struct next_call call = { set, -2 };
    pthread_t waiter;
    assert(pthread_create(&waiter, 0, call_next, &call) == 0);
    await_arrival(linea_pause_next_before_wait);
    arm(linea_pause_source_after_swap);
    tell_to_send();
    pass(linea_pause_source_after_swap);
    release_pause(linea_pause_next_before_wait);
    assert(pthread_join(waiter, 0) == 0);
    assert(call.answer == (long)slot_of(reserved));
    linea_chan_close(handle);
    linea_waitset_close(set);
}

/* `take` withdraws a handle while its body is paused before it signals: the
 * handle comes back, the set never delivers it, and its `close` joins the
 * task. */
static void take_before_a_return_signals(void) {
    const unsigned long set = linea_waitset_open();
    const unsigned long handle = started_to_return();
    const unsigned long reserved = linea_waitset_reserve(set);
    linea_waitset_returned(set, slot_of(reserved), handle);
    arm(linea_pause_source_before_swap);
    tell_to_send();
    await_arrival(linea_pause_source_before_swap);
    arm(linea_pause_take_after_swap);
    struct take_call call = { set, slot_of(reserved), generation_of(reserved), 9 };
    pthread_t taker;
    assert(pthread_create(&taker, 0, call_take, &call) == 0);
    pass(linea_pause_take_after_swap);
    release_pause(linea_pause_source_before_swap);
    assert(pthread_join(taker, 0) == 0);
    assert(call.answer == 1);
    assert(linea_waitset_next(set) == -1);
    linea_chan_close(handle);
    linea_waitset_close(set);
}

struct withdraw_call {
    unsigned long set;
    long answer;
};

static void *call_withdraw(void *arg) {
    struct withdraw_call *call = arg;
    call->answer = linea_waitset_withdraw(call->set);
    return 0;
}

/* `close` withdraws a registration its source has swapped to signalled and
 * not yet queued: the withdrawal waits for the source's post, takes the
 * registration out of the queue, and the set closes empty with the sender
 * still waiting. */
static void close_between_a_sources_swap_and_its_post(void) {
    const unsigned long set = linea_waitset_open();
    const unsigned long reserved = linea_waitset_reserve(set);
    const unsigned long handle = started_waiting();
    linea_waitset_received(set, slot_of(reserved), handle);
    arm(linea_pause_source_after_swap);
    tell_to_send();
    await_arrival(linea_pause_source_after_swap);
    arm(linea_pause_take_after_swap);
    struct withdraw_call call = { set, -2 };
    pthread_t closer;
    assert(pthread_create(&closer, 0, call_withdraw, &call) == 0);
    pass(linea_pause_take_after_swap);
    release_pause(linea_pause_source_after_swap);
    assert(pthread_join(closer, 0) == 0);
    assert(call.answer == (long)slot_of(reserved));
    assert(linea_waitset_withdraw(set) == -1);
    linea_waitset_close(set);
    finish_send_one(handle);
}

/* A timer expires while `next` waits on an endpoint whose peer has not
 * sent: the timer is delivered, the endpoint stays registered, and it is
 * delivered once its peer sends. */
static void a_timer_expires_while_next_waits_on_a_peer(void) {
    const unsigned long set = linea_waitset_open();
    const unsigned long handle = started_waiting();
    const unsigned long peer = linea_waitset_reserve(set);
    linea_waitset_received(set, slot_of(peer), handle);
    const unsigned long timer = linea_waitset_reserve(set);
    linea_waitset_timer(set, slot_of(timer), 2000000UL);
    assert(linea_waitset_next(set) == (long)slot_of(timer));
    tell_to_send();
    assert(linea_waitset_next(set) == (long)slot_of(peer));
    assert(linea_waitset_next(set) == -1);
    finish_send_one(handle);
    linea_waitset_close(set);
}

/* A timer expires at the instant its peer's send arrives: both are
 * signalled, one `next` delivers each, and neither is delivered twice. */
static void a_timer_and_a_send_together_are_each_delivered_once(void) {
    const unsigned long set = linea_waitset_open();
    arm(linea_pause_send_filled);
    const unsigned long handle = started(send_one);
    pass(linea_pause_send_filled);
    const unsigned long timer = linea_waitset_reserve(set);
    linea_waitset_timer(set, slot_of(timer), 0);
    const unsigned long peer = linea_waitset_reserve(set);
    linea_waitset_received(set, slot_of(peer), handle);
    const long first = linea_waitset_next(set);
    const long second = linea_waitset_next(set);
    assert(first != second);
    assert(first == (long)slot_of(timer) || first == (long)slot_of(peer));
    assert(second == (long)slot_of(timer) || second == (long)slot_of(peer));
    assert(linea_waitset_next(set) == -1);
    finish_send_one(handle);
    linea_waitset_close(set);
}

/* A descriptor's readiness is taken back exactly while it is not ready:
 * `take_if_registered` withdraws a pipe with nothing to read and refuses one
 * with a byte waiting, though `next` has not yet looked. */
static void a_descriptor_is_withdrawn_only_while_it_is_not_ready(void) {
    int ends[2];
    assert(pipe(ends) == 0);
    const unsigned long set = linea_waitset_open();
    const unsigned long idle = linea_waitset_reserve(set);
    assert(linea_waitset_descriptor(set, slot_of(idle), ends[0], 0) == 0);
    assert(linea_waitset_take(set, slot_of(idle), generation_of(idle), 1) == 1);
    const unsigned long busy = linea_waitset_reserve(set);
    assert(linea_waitset_descriptor(set, slot_of(busy), ends[0], 0) == 0);
    assert(write(ends[1], "x", 1) == 1);
    assert(linea_waitset_take(set, slot_of(busy), generation_of(busy), 1) == 0);
    assert(linea_waitset_next(set) == (long)slot_of(busy));
    assert(linea_waitset_next(set) == -1);
    linea_waitset_close(set);
    close(ends[0]);
    close(ends[1]);
}

/* A registration watches the descriptor it was given as it was when
 * registered. Taking back a registration whose descriptor has since been
 * closed, and whose number a new pipe now holds, leaves the new pipe's own
 * registration watched. The stale registration is readable from the moment
 * its pipe closes, since its duplicate reads the end; it is taken back before
 * `next` looks. */
static void a_withdrawn_descriptor_leaves_its_reused_number_watched(void) {
    int first[2], second[2];
    assert(pipe(first) == 0);
    const unsigned long set = linea_waitset_open();
    const unsigned long stale = linea_waitset_reserve(set);
    assert(linea_waitset_descriptor(set, slot_of(stale), first[0], 0) == 0);
    const int number = first[0];
    close(first[0]);
    close(first[1]);
    assert(pipe(second) == 0);
    /* The lowest free numbers are taken first, so the new read end has the
     * old one's number. */
    assert(second[0] == number);
    const unsigned long current = linea_waitset_reserve(set);
    assert(linea_waitset_descriptor(set, slot_of(current), second[0], 0) == 0);
    assert(linea_waitset_take(set, slot_of(stale), generation_of(stale), 0) == 1);
    const unsigned long timer = linea_waitset_reserve(set);
    linea_waitset_timer(set, slot_of(timer), 2000000000UL);
    assert(write(second[1], "x", 1) == 1);
    assert(linea_waitset_next(set) == (long)slot_of(current));
    assert(linea_waitset_take(set, slot_of(timer), generation_of(timer), 0) == 1);
    assert(linea_waitset_next(set) == -1);
    linea_waitset_close(set);
    close(second[0]);
    close(second[1]);
}

/* One descriptor registered twice is two registrations, each delivered once
 * it is ready, on every system. */
static void a_descriptor_registered_twice_is_delivered_twice(void) {
    int ends[2];
    assert(pipe(ends) == 0);
    const unsigned long set = linea_waitset_open();
    const unsigned long one = linea_waitset_reserve(set);
    assert(linea_waitset_descriptor(set, slot_of(one), ends[0], 0) == 0);
    const unsigned long two = linea_waitset_reserve(set);
    assert(linea_waitset_descriptor(set, slot_of(two), ends[0], 0) == 0);
    const unsigned long timer = linea_waitset_reserve(set);
    linea_waitset_timer(set, slot_of(timer), 2000000000UL);
    assert(write(ends[1], "x", 1) == 1);
    const long first = linea_waitset_next(set);
    const long second = linea_waitset_next(set);
    assert((first == (long)slot_of(one) && second == (long)slot_of(two)) || (first == (long)slot_of(two) && second == (long)slot_of(one)));
    assert(linea_waitset_take(set, slot_of(timer), generation_of(timer), 0) == 1);
    linea_waitset_close(set);
    close(ends[0]);
    close(ends[1]);
}

static void *write_after_a_moment(void *arg) {
    const struct timespec moment = { 0, 20000000L };
    nanosleep(&moment, 0);
    assert(write(*(int *)arg, "x", 1) == 1);
    return 0;
}

/* A timer that will not expire in any lifetime, such as one set for the
 * longest duration there is, leaves a set waiting in its kernel queue for its
 * other sources. */
static void a_timer_past_any_lifetime_waits_in_the_kernel_queue(void) {
    int ends[2];
    assert(pipe(ends) == 0);
    const unsigned long set = linea_waitset_open();
    const unsigned long readable = linea_waitset_reserve(set);
    assert(linea_waitset_descriptor(set, slot_of(readable), ends[0], 0) == 0);
    const unsigned long never = linea_waitset_reserve(set);
    linea_waitset_timer(set, slot_of(never), ~0UL);
    pthread_t writer;
    assert(pthread_create(&writer, 0, write_after_a_moment, &ends[1]) == 0);
    assert(linea_waitset_next(set) == (long)slot_of(readable));
    assert(pthread_join(writer, 0) == 0);
    assert(linea_waitset_take(set, slot_of(never), generation_of(never), 1) == 1);
    linea_waitset_close(set);
    close(ends[0]);
    close(ends[1]);
}

/* An idle descriptor registered alongside a timer does not fire when the timer
 * expires and wakes the kernel queue. */
static void an_idle_descriptor_does_not_fire_when_a_timer_expires(void) {
    int ends[2];
    assert(pipe(ends) == 0);
    const unsigned long set = linea_waitset_open();
    const unsigned long idle = linea_waitset_reserve(set);
    assert(linea_waitset_descriptor(set, slot_of(idle), ends[0], 0) == 0);

    for (int i = 0; i < 4; i += 1) {
        const unsigned long timer = linea_waitset_reserve(set);
        linea_waitset_timer(set, slot_of(timer), 1000000UL);
        assert(linea_waitset_next(set) == (long)slot_of(timer));
    }
    assert(linea_waitset_take(set, slot_of(idle), generation_of(idle), 1) == 1);
    linea_waitset_close(set);
    close(ends[0]);
    close(ends[1]);
}

/* A delivered registration's share keeps the handler installed: a second
 * `SIGTERM` is counted, not fatal, while the share lives, and wakes a new
 * registration made with it; once the share is released the saved action is
 * back and the next `SIGTERM` ends the process. */
static void a_delivered_share_keeps_the_handler_until_it_is_released(void) {
    const pid_t child = fork();
    assert(child >= 0);
    if (child == 0) {
        if (linea_signal_acquire(0) != 0) _exit(10);
        const unsigned long set = linea_waitset_open();
        const unsigned long a = linea_waitset_reserve(set);
        if (linea_waitset_signal(set, slot_of(a), 0, 0) != 0) _exit(11);
        raise(SIGTERM);
        if (linea_waitset_next(set) != (long)slot_of(a)) _exit(12);
        /* The registration is gone and the share is still held. */
        raise(SIGTERM);
        struct sigaction now;
        if (sigaction(SIGTERM, 0, &now) != 0 || (now.sa_flags & SA_SIGINFO) == 0) _exit(13);
        /* Registering again with the same share waits for a delivery after
         * this one. */
        const unsigned long b = linea_waitset_reserve(set);
        if (linea_waitset_signal(set, slot_of(b), 0, 0) != 0) _exit(14);
        const unsigned long timer = linea_waitset_reserve(set);
        linea_waitset_timer(set, slot_of(timer), 1000000UL);
        if (linea_waitset_next(set) != (long)slot_of(timer)) _exit(15);
        raise(SIGTERM);
        if (linea_waitset_next(set) != (long)slot_of(b)) _exit(16);
        linea_waitset_close(set);
        linea_signal_release(0, 0);
        raise(SIGTERM);
        _exit(17);
    }
    int status = 0;
    assert(waitpid(child, &status, 0) == child);
    assert(WIFSIGNALED(status) && WTERMSIG(status) == SIGTERM);
}

int main(void) {
    a_send_before_registration_is_found();
    a_send_during_registration_signals_once();
    a_send_as_next_begins_to_wait_wakes_it();
    take_of_a_signalled_endpoint_leaves_the_sender_waiting();
    take_between_a_sources_swap_and_its_post();
    take_before_a_sources_swap();
    a_return_is_delivered_once_either_way();
    an_expired_timer_is_taken_or_delivered_once();
    a_reused_slot_refuses_an_old_key();
    close_withdraws_each_registration_once();
    the_earliest_signalled_is_delivered_first();
    a_descriptor_and_a_timer_wake_the_kernel_queue();
    a_signal_wakes_every_set_that_waits_for_it();
    a_return_during_registration_signals_once();
    a_return_as_next_begins_to_wait_wakes_it();
    take_before_a_return_signals();
    close_between_a_sources_swap_and_its_post();
    a_timer_expires_while_next_waits_on_a_peer();
    a_timer_and_a_send_together_are_each_delivered_once();
    a_descriptor_is_withdrawn_only_while_it_is_not_ready();
    a_withdrawn_descriptor_leaves_its_reused_number_watched();
    a_descriptor_registered_twice_is_delivered_twice();
    a_timer_past_any_lifetime_waits_in_the_kernel_queue();
    an_idle_descriptor_does_not_fire_when_a_timer_expires();
    an_ignored_signal_is_refused();
    a_delivered_share_keeps_the_handler_until_it_is_released();
    a_second_terminate_after_the_last_share_ends_the_process();
    puts("native wait sets: every interleaving of a source and the owner at each linearization point delivers or takes each registration once and loses no wake; descriptors, timers and signals wake a set");
    return 0;
}
