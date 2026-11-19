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
#include <fcntl.h>
#include <string.h>
#include <sys/resource.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#include "loop.h"
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
    const long task = linea_task_prepare_on(1UL << 18, 0);
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

/* `take` withdraws an endpoint whose peer's value waits in the session:
 * the endpoint comes back, the value stays queued, the set never delivers
 * it, and a later receive completes at once. `take_if_registered` refuses it, since it was
 * signalled. */
static void take_of_a_signalled_endpoint_leaves_the_value_queued(void) {
    const unsigned long set = linea_waitset_open();
    const unsigned long reserved = linea_waitset_reserve(set);
    const unsigned long handle = started_waiting();
    linea_waitset_received(set, slot_of(reserved), handle);
    arm(linea_pause_send_filled);
    tell_to_send();
    pass(linea_pause_send_filled);
    assert(linea_waitset_take(set, slot_of(reserved), generation_of(reserved), 1) == 0);
    assert(linea_waitset_take(set, slot_of(reserved), generation_of(reserved), 0) == 2);
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
    assert(call.answer == 2);
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
    assert(call.answer == 2);
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

/* Closing a set withdraws each registration once, signalled or not, and the
 * value queued for an endpoint it withdrew waits for its receive. */
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
        const long withdrawn = linea_waitset_withdraw(set);
        if (withdrawn < 0) break;
        const long slot = withdrawn / 2;
        assert(slot < 3);
        /* The far timer has not fired, so it is not answered signalled. */
        if (slot == (long)slot_of(b)) assert(withdrawn % 2 == 0);
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

/* Runs `body` in a child and answers whether it aborted after writing
 * `expected` to stderr. */
static int aborts_saying(void (*body)(void), const char *expected) {
    int err_pipe[2];
    if (pipe(err_pipe) != 0) return 0;
    const pid_t child = fork();
    if (child < 0) return 0;
    if (child == 0) {
        dup2(err_pipe[1], 2);
        body();
        _exit(0);
    }
    close(err_pipe[1]);
    char said[512] = {0};
    size_t have = 0;
    ssize_t n;
    while ((n = read(err_pipe[0], said + have, sizeof said - 1 - have)) > 0) have += (size_t)n;
    close(err_pipe[0]);
    int status = 0;
    if (waitpid(child, &status, 0) != child) return 0;
    return WIFSIGNALED(status) && WTERMSIG(status) == SIGABRT && strcmp(said, expected) == 0;
}

static const char router_replaced[] = "linea: the host replaced the signal router's handler for a signal Linea watches\n";

/* The host installs its own handler for `SIGUSR1` while a share lives. */
static void replace_the_router(void) {
    struct sigaction host;
    memset(&host, 0, sizeof host);
    host.sa_handler = host_handler;
    sigemptyset(&host.sa_mask);
    if (sigaction(SIGUSR1, &host, 0) != 0) _exit(20);
}

static void release_after_the_host_replaced_the_router(void) {
    if (linea_signal_acquire(3) != 0) _exit(10);
    replace_the_router();
    linea_signal_release(3, 0);
}

static void share_after_the_host_replaced_the_router(void) {
    if (linea_signal_acquire(3) != 0) _exit(10);
    replace_the_router();
    if (linea_signal_acquire(3) != 0) _exit(11);
}

/* A host handler installed in place of the router while a share of its signal
 * lives is found when a share is next taken or released, and the process
 * ends with a report rather than losing every delivery to the shares and
 * having the host's handler replaced by the action the router saved. A host
 * that leaves the router in place takes and releases shares as before. */
static void a_host_replacing_the_router_is_reported(void) {
    assert(aborts_saying(release_after_the_host_replaced_the_router, router_replaced));
    assert(aborts_saying(share_after_the_host_replaced_the_router, router_replaced));
    assert(linea_signal_acquire(3) == 0);
    assert(linea_signal_acquire(3) == 0);
    linea_signal_release(3, 0);
    linea_signal_release(3, 0);
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

/* A signal ignored by an action that also sets SA_SIGINFO is ignored all
 * the same: the flag says how a handler would be called, and there is none.
 * It is refused, its action is left as it was, and raising it does nothing. */
static void a_signal_ignored_with_siginfo_set_is_refused(void) {
    struct sigaction ignoring;
    memset(&ignoring, 0, sizeof ignoring);
    ignoring.sa_handler = SIG_IGN;
    ignoring.sa_flags = SA_SIGINFO;
    sigemptyset(&ignoring.sa_mask);
    assert(sigaction(SIGUSR2, &ignoring, 0) == 0);
    assert(linea_signal_acquire(4) == 1);
    struct sigaction now;
    assert(sigaction(SIGUSR2, 0, &now) == 0);
    assert(now.sa_handler == SIG_IGN);
    assert(raise(SIGUSR2) == 0);
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
 * registration out of the queue, and the set closes empty with the value
 * still queued. */
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
    assert(call.answer == (long)slot_of(reserved) * 2 + 1);
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
    assert(linea_waitset_take(set, slot_of(stale), generation_of(stale), 0) == 2);
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

/* The host actions the router tests chain to, each counting its calls. */
static int first_host_calls;
static int second_host_calls;
static void first_host(int number, siginfo_t *info, void *context) {
    (void)number;
    (void)info;
    (void)context;
    __atomic_add_fetch(&first_host_calls, 1, __ATOMIC_SEQ_CST);
}
static void second_host(int number) {
    (void)number;
    __atomic_add_fetch(&second_host_calls, 1, __ATOMIC_SEQ_CST);
}

/* Install a host action for `number`: `informed` with SA_SIGINFO when it is
 * given, `handler` otherwise. */
static int install_host(int number, void (*handler)(int), void (*informed)(int, siginfo_t *, void *)) {
    struct sigaction action;
    memset(&action, 0, sizeof action);
    if (informed != 0) {
        action.sa_sigaction = informed;
        action.sa_flags = SA_SIGINFO;
    } else {
        action.sa_handler = handler;
    }
    sigemptyset(&action.sa_mask);
    return sigaction(number, &action, 0);
}

#if defined(LINEA_WAITSET_PAUSES)
static void *raise_user1(void *unused) {
    (void)unused;
    assert(pthread_kill(pthread_self(), SIGUSR1) == 0);
    return 0;
}

/* A delivery the router began handling while the first share's host action
 * was saved chains to that action, though the last share is released and a
 * new first share saves another host action while it runs. */
static void a_route_chains_to_the_action_saved_when_it_began(void) {
    const pid_t child = fork();
    assert(child >= 0);
    if (child == 0) {
        if (install_host(SIGUSR1, 0, first_host) != 0) _exit(10);
        if (linea_signal_acquire(3) != 0) _exit(11);
        arm(linea_pause_route_before_chain);
        pthread_t raiser;
        if (pthread_create(&raiser, 0, raise_user1, 0) != 0) _exit(12);
        await_arrival(linea_pause_route_before_chain);
        linea_signal_release(3, 0);
        if (install_host(SIGUSR1, second_host, 0) != 0) _exit(13);
        if (linea_signal_acquire(3) != 0) _exit(14);
        release_pause(linea_pause_route_before_chain);
        if (pthread_join(raiser, 0) != 0) _exit(15);
        linea_signal_release(3, 0);
        if (__atomic_load_n(&first_host_calls, __ATOMIC_SEQ_CST) != 1) _exit(16);
        if (__atomic_load_n(&second_host_calls, __ATOMIC_SEQ_CST) != 0) _exit(17);
        _exit(0);
    }
    int status = 0;
    assert(waitpid(child, &status, 0) == child);
    assert(WIFEXITED(status) && WEXITSTATUS(status) == 0);
}
#endif

/* How many SIGUSR2 deliveries `raise_user2_repeatedly` makes. */
enum { racing_deliveries = 4000 };
static int raising_done;

static void *raise_user2_repeatedly(void *unused) {
    (void)unused;
    for (int i = 0; i < racing_deliveries; i += 1) assert(pthread_kill(pthread_self(), SIGUSR2) == 0);
    __atomic_store_n(&raising_done, 1, __ATOMIC_SEQ_CST);
    return 0;
}

/* One thread takes SIGUSR2 over and over while another releases the last
 * share and takes a first share again, each time under another host action,
 * so the router saves an action while handlers on the other thread read the
 * one saved before. Every delivery reaches a host action once, through the
 * router or directly. */
static void a_route_races_a_new_first_share(void) {
    const pid_t child = fork();
    assert(child >= 0);
    if (child == 0) {
        if (install_host(SIGUSR2, 0, first_host) != 0) _exit(10);
        if (linea_signal_acquire(4) != 0) _exit(11);
        pthread_t raiser;
        if (pthread_create(&raiser, 0, raise_user2_repeatedly, 0) != 0) _exit(12);
        for (unsigned long round = 0; !__atomic_load_n(&raising_done, __ATOMIC_SEQ_CST); round += 1) {
            linea_signal_release(4, 0);
            const int installed = round % 2 == 0 ? install_host(SIGUSR2, second_host, 0) : install_host(SIGUSR2, 0, first_host);
            if (installed != 0) _exit(13);
            if (linea_signal_acquire(4) != 0) _exit(14);
        }
        if (pthread_join(raiser, 0) != 0) _exit(15);
        linea_signal_release(4, 0);
        const int calls = __atomic_load_n(&first_host_calls, __ATOMIC_SEQ_CST) + __atomic_load_n(&second_host_calls, __ATOMIC_SEQ_CST);
        if (calls != racing_deliveries) _exit(16);
        _exit(0);
    }
    int status = 0;
    assert(waitpid(child, &status, 0) == child);
    assert(WIFEXITED(status) && WEXITSTATUS(status) == 0);
}

/* `close` withdraws one registration at a time, and a signal may arrive
 * between two withdrawals. The registration it signals is answered as
 * signalled, from the router's count, whether or not anything has drained
 * the wake descriptor since. */
static void a_signal_between_two_withdrawals_is_answered_signalled(void) {
    const pid_t child = fork();
    assert(child >= 0);
    if (child == 0) {
        if (linea_signal_acquire(3) != 0 || linea_signal_acquire(4) != 0) _exit(10);
        const unsigned long set = linea_waitset_open();
        const unsigned long a = linea_waitset_reserve(set);
        if (linea_waitset_signal(set, slot_of(a), 3, 0) != 0) _exit(11);
        const unsigned long b = linea_waitset_reserve(set);
        if (linea_waitset_signal(set, slot_of(b), 4, 0) != 0) _exit(12);
        const long first = linea_waitset_withdraw(set);
        if (raise(SIGUSR2) != 0) _exit(13);
        const long second = linea_waitset_withdraw(set);
        const long third = linea_waitset_withdraw(set);
        linea_waitset_close(set);
        linea_signal_release(4, 0);
        linea_signal_release(3, 0);
        if (first != (long)slot_of(a) * 2) _exit(14);
        if (second != (long)slot_of(b) * 2 + 1) _exit(15);
        if (third != -1) _exit(16);
        _exit(0);
    }
    int status = 0;
    assert(waitpid(child, &status, 0) == child);
    assert(WIFEXITED(status) && WEXITSTATUS(status) == 0);
}

/* `take` answers a signal registration signalled once its signal has
 * arrived, from the same count. */
static void a_signal_before_a_take_is_answered_signalled(void) {
    const pid_t child = fork();
    assert(child >= 0);
    if (child == 0) {
        if (linea_signal_acquire(4) != 0) _exit(10);
        const unsigned long set = linea_waitset_open();
        const unsigned long a = linea_waitset_reserve(set);
        if (linea_waitset_signal(set, slot_of(a), 4, 0) != 0) _exit(11);
        if (raise(SIGUSR2) != 0) _exit(12);
        const uint8_t taken = linea_waitset_take(set, slot_of(a), generation_of(a), 0);
        linea_waitset_close(set);
        linea_signal_release(4, 0);
        _exit(taken == 2 ? 0 : 13);
    }
    int status = 0;
    assert(waitpid(child, &status, 0) == child);
    assert(WIFEXITED(status) && WEXITSTATUS(status) == 0);
}

/* What the masked host action saw of the thread's mask while it ran. */
static int masked_host_calls;
static int masked_host_saw_user1_blocked;
static int masked_host_saw_user2_blocked;
static void masked_host(int number) {
    (void)number;
    sigset_t now;
    assert(pthread_sigmask(SIG_BLOCK, 0, &now) == 0);
    masked_host_saw_user1_blocked = sigismember(&now, SIGUSR1) == 1;
    masked_host_saw_user2_blocked = sigismember(&now, SIGUSR2) == 1;
    masked_host_calls += 1;
}

/* Install `masked_host` for SIGUSR1 with `flags` and SIGUSR2 in its mask,
 * take a share, raise SIGUSR1 and release the share. */
static int raise_under_masked_host(int flags) {
    struct sigaction action;
    memset(&action, 0, sizeof action);
    action.sa_handler = masked_host;
    action.sa_flags = flags;
    sigemptyset(&action.sa_mask);
    sigaddset(&action.sa_mask, SIGUSR2);
    if (sigaction(SIGUSR1, &action, 0) != 0) return 10;
    if (linea_signal_acquire(3) != 0) return 11;
    if (raise(SIGUSR1) != 0) return 12;
    linea_signal_release(3, 0);
    if (masked_host_calls != 1) return 13;
    sigset_t after;
    if (pthread_sigmask(SIG_BLOCK, 0, &after) != 0 || sigismember(&after, SIGUSR1) == 1 || sigismember(&after, SIGUSR2) == 1) return 14;
    return 0;
}

/* The router chains to a host action under the mask the system would have
 * given it: the thread's mask, the action's `sa_mask` and the signal itself,
 * and without the signal under SA_NODEFER. The thread's mask is as it was
 * once the router returns. */
static void a_routed_host_action_runs_under_its_own_mask(void) {
    for (int nodefer = 0; nodefer < 2; nodefer += 1) {
        const pid_t child = fork();
        assert(child >= 0);
        if (child == 0) {
            const int answer = raise_under_masked_host(nodefer ? SA_NODEFER : 0);
            if (answer != 0) _exit(answer);
            if (!masked_host_saw_user2_blocked) _exit(15);
            if (masked_host_saw_user1_blocked == nodefer) _exit(16);
            _exit(0);
        }
        int status = 0;
        assert(waitpid(child, &status, 0) == child);
        assert(WIFEXITED(status) && WEXITSTATUS(status) == 0);
    }
}

static int one_shot_host_calls;
static void one_shot_host(int number) {
    (void)number;
    one_shot_host_calls += 1;
}

/* A host action installed with SA_RESETHAND is chained to for the first
 * delivery only, as the system would have run it once and reset the signal
 * to its default action; the deliveries after it are counted alone while a
 * share lives, and releasing the last share leaves the default action. A
 * system that does not report SA_RESETHAND through `sigaction`, as macOS
 * does not, gives the router nothing to honour. */
static void a_one_shot_host_action_is_chained_to_once(void) {
    const pid_t child = fork();
    assert(child >= 0);
    if (child == 0) {
        struct sigaction action;
        memset(&action, 0, sizeof action);
        action.sa_handler = one_shot_host;
        action.sa_flags = (int)SA_RESETHAND;
        sigemptyset(&action.sa_mask);
        if (sigaction(SIGUSR1, &action, 0) != 0) _exit(10);
        struct sigaction reported;
        if (sigaction(SIGUSR1, 0, &reported) != 0) _exit(11);
        if (((unsigned)reported.sa_flags & (unsigned)SA_RESETHAND) == 0) _exit(0);
        if (linea_signal_acquire(3) != 0) _exit(12);
        if (raise(SIGUSR1) != 0 || raise(SIGUSR1) != 0) _exit(13);
        if (one_shot_host_calls != 1) _exit(14);
        linea_signal_release(3, 0);
        struct sigaction restored;
        if (sigaction(SIGUSR1, 0, &restored) != 0 || restored.sa_handler != SIG_DFL) _exit(15);
        /* A first share taken after that saves the default action. */
        if (linea_signal_acquire(3) != 0) _exit(16);
        if (raise(SIGUSR1) != 0) _exit(17);
        linea_signal_release(3, 0);
        if (one_shot_host_calls != 1) _exit(18);
        _exit(0);
    }
    int status = 0;
    assert(waitpid(child, &status, 0) == child);
    assert(WIFEXITED(status) && WEXITSTATUS(status) == 0);
}

/* Run `body` in a child process and check that it stops the program with
 * `message`. */
static void traps_with(void (*body)(void), const char *message) {
    int pipe_ends[2];
    assert(pipe(pipe_ends) == 0);
    const pid_t pid = fork();
    assert(pid >= 0);
    if (pid == 0) {
        dup2(pipe_ends[1], 2);
        close(pipe_ends[0]);
        body();
        _exit(0);
    }
    close(pipe_ends[1]);
    char said[512];
    size_t len = 0;
    ssize_t got;
    while ((got = read(pipe_ends[0], said + len, sizeof said - 1 - len)) > 0) len += (size_t)got;
    said[len] = '\0';
    close(pipe_ends[0]);
    int status = 0;
    assert(waitpid(pid, &status, 0) == pid);
    assert(WIFSIGNALED(status) && WTERMSIG(status) == SIGABRT);
    assert(strncmp(said, message, strlen(message)) == 0);
}

/* The loop a moved set goes to: a loop of fibers this thread switches to. */
static unsigned long another_loop;

static void *rehome_on_the_other_loop(void *set) {
    (void)linea_io_switch(another_loop);
    linea_waitset_rehome((unsigned long)set);
    (void)linea_io_switch(0);
    return 0;
}

/* A set of session endpoints moves to another loop and back. A peer that
 * sent before the move, one that sends while the move waits to take the
 * set's lock, and one that sends after it are each delivered once, in the
 * order they signalled. */
static void a_set_of_endpoints_keeps_its_signals_when_it_moves(void) {
    another_loop = linea_loop_claim_kind(0, LINEA_LOOP_FIBERS);
    assert(another_loop != 0);
    const unsigned long set = linea_waitset_open();
    arm(linea_pause_send_filled);
    const unsigned long before = started(send_one);
    pass(linea_pause_send_filled);
    const unsigned long a = linea_waitset_reserve(set);
    linea_waitset_received(set, slot_of(a), before);
    arm(linea_pause_rehome_before_lock);
    pthread_t mover;
    assert(pthread_create(&mover, 0, rehome_on_the_other_loop, (void *)set) == 0);
    await_arrival(linea_pause_rehome_before_lock);
    /* While the move waits to take the set's lock, a peer sends and is
     * registered, so its signal is posted during the move. */
    const unsigned long b = linea_waitset_reserve(set);
    __atomic_store_n(&go_ahead, 0, __ATOMIC_SEQ_CST);
    const unsigned long during = started(send_when_told);
    linea_waitset_received(set, slot_of(b), during);
    arm(linea_pause_send_filled);
    __atomic_store_n(&go_ahead, 1, __ATOMIC_SEQ_CST);
    /* The send signals the registration before it reaches this point. */
    pass(linea_pause_send_filled);
    release_pause(linea_pause_rehome_before_lock);
    assert(pthread_join(mover, 0) == 0);
    (void)linea_io_switch(another_loop);
    assert(linea_waitset_next(set) == (long)slot_of(a));
    finish_send_one(before);
    const unsigned long c = linea_waitset_reserve(set);
    const unsigned long after = started(send_one);
    linea_waitset_received(set, slot_of(c), after);
    assert(linea_waitset_next(set) == (long)slot_of(b));
    finish_send_one(during);
    (void)linea_io_switch(0);
    linea_waitset_rehome(set);
    assert(linea_waitset_next(set) == (long)slot_of(c));
    finish_send_one(after);
    assert(linea_waitset_next(set) == -1);
    linea_waitset_close(set);
    linea_loop_retire(another_loop);
}

static void move_a_set_holding_a_timer(void) {
    const unsigned long loop = linea_loop_claim_kind(0, LINEA_LOOP_FIBERS);
    const unsigned long set = linea_waitset_open();
    const unsigned long timer = linea_waitset_reserve(set);
    linea_waitset_timer(set, slot_of(timer), 1000000000UL);
    (void)linea_io_switch(loop);
    linea_waitset_rehome(set);
}

static void move_a_set_with_a_kernel_queue(void) {
    int ends[2];
    assert(pipe(ends) == 0);
    const unsigned long loop = linea_loop_claim_kind(0, LINEA_LOOP_FIBERS);
    const unsigned long set = linea_waitset_open();
    const unsigned long idle = linea_waitset_reserve(set);
    assert(linea_waitset_descriptor(set, slot_of(idle), ends[0], 0) == 0);
    assert(linea_waitset_take(set, slot_of(idle), generation_of(idle), 1) == 1);
    (void)linea_io_switch(loop);
    linea_waitset_rehome(set);
}

/* A set watched through its loop's kernel queue, or holding a timer, stays
 * on its loop: moving it traps. */
static void a_set_watching_more_than_endpoints_does_not_move(void) {
    traps_with(move_a_set_holding_a_timer, "linea: a wait set watching more than session endpoints was moved to another loop\n");
    traps_with(move_a_set_with_a_kernel_queue, "linea: a wait set watching more than session endpoints was moved to another loop\n");
}

/* A slot whose generation would wrap is retired, and the set numbers a new
 * slot past every slot it made before, so a slot's number is not bounded by
 * how many registrations are held at once. The hook that ages a slot exists
 * only where the race tests supply the pauses, so the test is compiled there
 * alone. */
#if defined(LINEA_WAITSET_PAUSES)
static void a_retired_slot_is_replaced_by_a_new_number(void) {
    const unsigned long set = linea_waitset_open();
    const unsigned long first = linea_waitset_reserve(set);
    assert(slot_of(first) == 0);
    linea_waitset_unreserve(set, slot_of(first));
    waitset_test_age(set, 0);
    const unsigned long last = linea_waitset_reserve(set);
    assert(slot_of(last) == 0 && generation_of(last) == 0xffffffffUL);
    linea_waitset_unreserve(set, slot_of(last));
    const unsigned long replaced = linea_waitset_reserve(set);
    assert(slot_of(replaced) == 1);
    const unsigned long handle = started(send_one);
    linea_waitset_received(set, slot_of(replaced), handle);
    assert(linea_waitset_next(set) == 1);
    finish_send_one(handle);
    linea_waitset_close(set);
}
#endif

long linea_loop_open(unsigned long carriers);

/* Wait on a pipe from a fiber with the descriptor table full, so the
 * fiber cannot park on the set's kernel queue, which takes a descriptor of
 * its own: the set waits on the carrier instead, and still delivers the
 * pipe. */
static void wait_with_no_descriptor_left(unsigned long endpoint, unsigned long at, unsigned long len) {
    assert(at == 0 && len == 0);
    int ends[2];
    assert(pipe(ends) == 0);
    const unsigned long set = linea_waitset_open();
    const unsigned long readable = linea_waitset_reserve(set);
    assert(linea_waitset_descriptor(set, slot_of(readable), ends[0], 0) == 0);
    struct rlimit saved, lowered;
    assert(getrlimit(RLIMIT_NOFILE, &saved) == 0);
    lowered = saved;
    lowered.rlim_cur = 64;
    assert(setrlimit(RLIMIT_NOFILE, &lowered) == 0);
    int filled[64];
    int count = 0;
    for (;;) {
        const int fd = open("/dev/null", O_RDONLY | O_CLOEXEC);
        if (fd < 0) break;
        assert(count < 64);
        filled[count++] = fd;
    }
    pthread_t writer;
    assert(pthread_create(&writer, 0, write_after_a_moment, &ends[1]) == 0);
    assert(linea_waitset_next(set) == (long)slot_of(readable));
    assert(pthread_join(writer, 0) == 0);
    for (int i = 0; i < count; i += 1) assert(close(filled[i]) == 0);
    assert(setrlimit(RLIMIT_NOFILE, &saved) == 0);
    linea_waitset_close(set);
    close(ends[0]);
    close(ends[1]);
    linea_chan_close(endpoint);
}

static void a_full_descriptor_table_leaves_a_fiber_waiting_in_place(void) {
    const long loop = linea_loop_open(1);
    assert(loop > 0);
    const long prepared = linea_task_prepare_on(1UL << 18, (unsigned long)loop);
    assert(prepared > 0);
    linea_chan_close(linea_task_start((unsigned long)prepared, wait_with_no_descriptor_left, release_nothing, 0, 0, 0));
}

int main(void) {
    a_full_descriptor_table_leaves_a_fiber_waiting_in_place();
    a_send_before_registration_is_found();
    a_send_during_registration_signals_once();
    a_send_as_next_begins_to_wait_wakes_it();
    take_of_a_signalled_endpoint_leaves_the_value_queued();
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
    a_signal_ignored_with_siginfo_set_is_refused();
    a_delivered_share_keeps_the_handler_until_it_is_released();
    a_second_terminate_after_the_last_share_ends_the_process();
    a_set_of_endpoints_keeps_its_signals_when_it_moves();
    a_set_watching_more_than_endpoints_does_not_move();
    a_route_races_a_new_first_share();
    a_signal_between_two_withdrawals_is_answered_signalled();
    a_signal_before_a_take_is_answered_signalled();
    a_routed_host_action_runs_under_its_own_mask();
    a_one_shot_host_action_is_chained_to_once();
    a_host_replacing_the_router_is_reported();
#if defined(LINEA_WAITSET_PAUSES)
    a_retired_slot_is_replaced_by_a_new_number();
    a_route_chains_to_the_action_saved_when_it_began();
#endif
    puts("native wait sets: every interleaving of a source and the owner at each linearization point delivers or takes each registration once and loses no wake; descriptors, timers and signals wake a set; the signal router chains each delivery to the host action saved when it began, while a new first share saves another, under that action's mask, and an SA_RESETHAND action once, and a host handler installed in its place while a share lives is reported; a set of endpoints moves between loops and a slot's number is not bounded by the registrations held");
    return 0;
}
