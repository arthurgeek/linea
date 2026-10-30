#define _GNU_SOURCE
#define _DARWIN_C_SOURCE
/* Assertions execute test setup, checks, and cleanup in every build mode. */
#undef NDEBUG
#include <assert.h>
#include <pthread.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#include "task.h"

#if defined(__has_feature)
#if __has_feature(address_sanitizer) || __has_feature(thread_sanitizer)
#define LINEA_SANITIZED 1
#endif
#endif

unsigned long linea_alloc(unsigned long size, unsigned long align);
void linea_free(unsigned long at, unsigned long size, unsigned long align);
void linea_set_args(int argc, char **argv);

/* The tests stand in for the code the compiler generates: an entry reads the
 * body kept at `at`, a `struct body`, and a release records that it ran. */
struct body {
    int kind;
    volatile int ran;
    volatile int returned;
    volatile int released;
    unsigned long endpoint;
    unsigned long delay_ms;
    unsigned long rounds;
    unsigned long answer;
};

static void sleep_ms(unsigned long ms) {
    struct timespec wait = {.tv_sec = (time_t)(ms / 1000), .tv_nsec = (long)(ms % 1000) * 1000000L};
    while (nanosleep(&wait, &wait) != 0) {
    }
}

static unsigned long elapsed_ms(const struct timespec *since) {
    struct timespec now;
    assert(clock_gettime(CLOCK_MONOTONIC, &now) == 0);
    const long ms = (now.tv_sec - since->tv_sec) * 1000L + (now.tv_nsec - since->tv_nsec) / 1000000L;
    return ms < 0 ? 0UL : (unsigned long)ms;
}

enum { counts, doubles, offers, ping_pong, allocates, recurses };

static unsigned long send_word(unsigned long endpoint, unsigned long word) {
    unsigned long sent = word;
    linea_chan_send(endpoint, (unsigned long)&sent, sizeof sent);
    return sent;
}

static unsigned long recv_word(unsigned long endpoint) {
    unsigned long received = 0;
    linea_chan_recv(endpoint, (unsigned long)&received, sizeof received);
    return received;
}

/* Recurses until the stack runs out, a kibibyte a frame. */
static volatile unsigned long deepest = ~0UL;

static void recurse(unsigned long depth) {
    volatile char frame[1024];
    frame[0] = (char)depth;
    if (depth != deepest) recurse(depth + 1);
    frame[1] = frame[0];
}

static void entry(unsigned long endpoint, unsigned long at, unsigned long len) {
    assert(len == sizeof(struct body));
    struct body *b = (struct body *)at;
    b->ran += 1;
    b->endpoint = endpoint;
    switch (b->kind) {
    case counts:
        sleep_ms(b->delay_ms);
        break;
    case doubles: {
        sleep_ms(b->delay_ms);
        const unsigned long number = recv_word(endpoint);
        (void)send_word(endpoint, number * 2);
        break;
    }
    case offers: {
        const uint8_t branch = linea_chan_offer(endpoint);
        (void)send_word(endpoint, branch == 0 ? 100 : 200);
        break;
    }
    case ping_pong:
        /* A receive followed at once by a send: the peer's send must return
         * before this send fills the slot again. */
        for (unsigned long i = 0; i < b->rounds; i += 1) (void)send_word(endpoint, recv_word(endpoint) + 1);
        break;
    case allocates: {
        unsigned long held[64] = {0};
        for (unsigned long i = 0; i < b->rounds; i += 1) {
            const unsigned long slot = i % 64;
            const unsigned long size = 8 + (i * 7 + b->delay_ms) % 200;
            if (held[slot] != 0) linea_free(held[slot], ((unsigned char *)held[slot])[0] + 8UL, 8);
            held[slot] = linea_alloc(size, 8);
            assert(held[slot] != 0);
            memset((void *)held[slot], (int)(size - 8), size);
        }
        for (unsigned long slot = 0; slot < 64; slot += 1) {
            if (held[slot] != 0) linea_free(held[slot], ((unsigned char *)held[slot])[0] + 8UL, 8);
        }
        break;
    }
    case recurses:
        recurse(0);
        break;
    }
    linea_chan_close(endpoint);
    b->returned = 1;
}

static void release(unsigned long at, unsigned long len) {
    assert(len == sizeof(struct body));
    struct body *b = (struct body *)at;
    /* The release runs only once the body has returned. */
    assert(b->returned);
    b->released += 1;
}

static unsigned long started(struct body *b, unsigned long stack) {
    const long task = linea_task_prepare(stack);
    assert(task > 0);
    return linea_task_start((unsigned long)task, entry, release, (unsigned long)b, sizeof *b);
}

/* `close` on the handle returns only once the body has returned and its
 * thread has been joined, and then releases the body's bytes. */
static void close_joins_after_the_body_returns(void) {
    struct body b = {.kind = counts, .delay_ms = 50};
    const unsigned long handle = started(&b, 1UL << 20);
    linea_chan_close(handle);
    assert(b.ran == 1 && b.returned == 1 && b.released == 1);
    /* The two ends are told apart, and the task's own is the odd one. */
    assert(b.endpoint == (handle | 1UL) && handle != b.endpoint);
}

/* A prepared task runs nothing until it is started. */
static void a_body_never_runs_before_start(void) {
    struct body b = {.kind = counts};
    const long task = linea_task_prepare(1UL << 20);
    assert(task > 0);
    sleep_ms(50);
    assert(b.ran == 0);
    const unsigned long handle = linea_task_start((unsigned long)task, entry, release, (unsigned long)&b, sizeof b);
    linea_chan_close(handle);
    assert(b.ran == 1 && b.released == 1);
}

/* A cancelled task's thread ends without running a body or releasing
 * anything, and the cancel returns once it is joined. */
static void cancel_settles_the_parked_thread(void) {
    for (int i = 0; i < 200; i += 1) {
        const long task = linea_task_prepare(1UL << 16);
        assert(task > 0);
        linea_task_cancel((unsigned long)task);
    }
}

/* A send returns only once the peer has taken the value: the body waits
 * before it receives, and the send waits with it. The bytes the sender
 * named may be reused as soon as it returns. */
static void a_send_waits_for_its_receiver(void) {
    struct body b = {.kind = doubles, .delay_ms = 60};
    const unsigned long handle = started(&b, 1UL << 20);
    struct timespec before;
    assert(clock_gettime(CLOCK_MONOTONIC, &before) == 0);
    unsigned long word = 21;
    linea_chan_send(handle, (unsigned long)&word, sizeof word);
    assert(elapsed_ms(&before) >= 50);
    word = 0;
    assert(recv_word(handle) == 42);
    linea_chan_close(handle);
    assert(b.released == 1);
}

/* A choice is a send of its branch, and an offer answers it. */
static void an_offer_answers_the_choice(void) {
    for (uint8_t branch = 0; branch < 2; branch += 1) {
        struct body b = {.kind = offers};
        const unsigned long handle = started(&b, 1UL << 20);
        linea_chan_choose(handle, branch);
        assert(recv_word(handle) == (branch == 0 ? 100UL : 200UL));
        linea_chan_close(handle);
    }
}

/* Values alternate direction with no pause between them, many times. */
static void values_alternate_through_one_slot(void) {
    struct body b = {.kind = ping_pong, .rounds = 20000};
    const unsigned long handle = started(&b, 1UL << 20);
    unsigned long value = 0;
    for (unsigned long i = 0; i < b.rounds; i += 1) {
        (void)send_word(handle, value);
        value = recv_word(handle);
    }
    linea_chan_close(handle);
    assert(value == b.rounds);
}

/* Many tasks run at once, each with its own session. */
static void many_tasks_run_at_once(void) {
    enum { tasks = 64 };
    static struct body bodies[tasks];
    unsigned long handles[tasks];
    for (unsigned long i = 0; i < tasks; i += 1) {
        bodies[i] = (struct body){.kind = ping_pong, .rounds = 200};
        handles[i] = started(&bodies[i], 1UL << 18);
    }
    unsigned long values[tasks] = {0};
    for (unsigned long round = 0; round < 200; round += 1) {
        for (unsigned long i = 0; i < tasks; i += 1) (void)send_word(handles[i], values[i]);
        for (unsigned long i = 0; i < tasks; i += 1) values[i] = recv_word(handles[i]);
    }
    for (unsigned long i = 0; i < tasks; i += 1) {
        linea_chan_close(handles[i]);
        assert(values[i] == 200 && bodies[i].released == 1);
    }
}

/* Tasks allocate and free at once, and the allocator, the checking one
 * included, keeps every allocation whole. */
static void tasks_allocate_at_once(void) {
    enum { tasks = 8 };
    static struct body bodies[tasks];
    unsigned long handles[tasks];
    for (unsigned long i = 0; i < tasks; i += 1) {
        bodies[i] = (struct body){.kind = allocates, .rounds = 4000, .delay_ms = i};
        handles[i] = started(&bodies[i], 1UL << 20);
    }
    for (unsigned long i = 0; i < tasks; i += 1) linea_chan_close(handles[i]);
}

/* Concurrent prepare and cancel under thread contention: threads repeatedly
 * prepare and cancel tasks to verify no leaked thread mappings or metadata races. */
static void *canceller_thread(void *arg) {
    (void)arg;
    for (int i = 0; i < 100; i += 1) {
        long task = linea_task_prepare(1UL << 18);
        assert(task > 0);
        linea_task_cancel((unsigned long)task);
    }
    return NULL;
}

static void concurrent_prepare_and_cancel_stress(void) {
    enum { threads = 8 };
    pthread_t workers[threads];
    for (int i = 0; i < threads; i += 1) {
        assert(pthread_create(&workers[i], NULL, canceller_thread, NULL) == 0);
    }
    for (int i = 0; i < threads; i += 1) {
        assert(pthread_join(workers[i], NULL) == 0);
    }
}

#if !defined(LINEA_SANITIZED)
/* Runs `body` in a child and checks it aborted after writing `expected` to
 * stderr. */
static void aborts_saying(void (*body)(void), const char *expected) {
    int err_pipe[2];
    assert(pipe(err_pipe) == 0);
    pid_t pid = fork();
    assert(pid >= 0);
    if (pid == 0) {
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
    assert(waitpid(pid, &status, 0) == pid);
    assert(WIFSIGNALED(status) && WTERMSIG(status) == SIGABRT);
    assert(strcmp(said, expected) == 0);
}

static void overflow_on_a_worker(void) {
    struct body b = {.kind = recurses};
    linea_chan_close(started(&b, 1UL << 18));
}

static void overflow_on_main(void) {
    char name[] = "task_test";
    char *argv[] = {name, NULL};
    linea_set_args(1, argv);
    recurse(0);
}

/* The fault handler runs on the alternate signal stack of the thread that
 * overflowed, so it reports the overflow rather than the process ending
 * with no word. */
static void an_overflow_is_reported(void) {
    aborts_saying(overflow_on_a_worker, "linea: a stack overflowed\n");
    aborts_saying(overflow_on_main, "linea: a stack overflowed\n");
}

/* The handler is installed to run on the alternate signal stack. */
static void the_fault_handler_runs_on_the_signal_stack(void) {
    char name[] = "task_test";
    char *argv[] = {name, NULL};
    linea_set_args(1, argv);
    struct sigaction installed;
    assert(sigaction(SIGSEGV, 0, &installed) == 0);
    assert((installed.sa_flags & SA_ONSTACK) != 0 && (installed.sa_flags & SA_SIGINFO) != 0);
    stack_t alternate;
    assert(sigaltstack(0, &alternate) == 0);
    assert((alternate.ss_flags & SS_DISABLE) == 0 && alternate.ss_size >= 65536);
}
#endif

/* A stack size nothing can map is refused, and the refusal leaves nothing
 * behind to settle. */
static void an_impossible_stack_is_refused(void) {
    assert(linea_task_prepare(1UL << 62) < 0);
}

static void mailbox_and_timers_work(void) {
    unsigned long mb = linea_mailbox_open();
    linea_mailbox_add_child(mb);

    unsigned long msg = 999;
    linea_mailbox_send(mb, (unsigned long)&msg, sizeof(msg));

    unsigned long out = 0;
    uint8_t rc = linea_mailbox_recv(mb, (unsigned long)&out, sizeof(out));
    assert(rc == 1);
    assert(out == 999);

    /* 1. Timer fires naturally */
    unsigned long timer_val = 12345;
    linea_mailbox_timer(mb, 5000000UL /* 5ms */, (unsigned long)&timer_val, sizeof(timer_val));
    rc = linea_mailbox_recv(mb, (unsigned long)&out, sizeof(out));
    assert(rc == 1);
    assert(out == 12345);

    /* 2. Timer cancelled before expiration */
    unsigned long cancel_val = 54321;
    unsigned long t2 = linea_mailbox_timer(mb, 500000000UL /* 500ms */, (unsigned long)&cancel_val, sizeof(cancel_val));
    unsigned long recovered = 0;
    uint8_t fired = linea_mailbox_timer_cancel(t2, (unsigned long)&recovered, sizeof(recovered));
    assert(fired == 0);
    assert(recovered == 54321);

    /* 3. Timer at and beyond signed 64-bit duration boundary */
    struct timespec short_wait = { .tv_sec = 0, .tv_nsec = 10000000L /* 10ms */ };

    /* INT64_MAX */
    unsigned long val_signed = 77777;
    unsigned long t_signed = linea_mailbox_timer(mb, 0x7fffffffffffffffULL, (unsigned long)&val_signed, sizeof(val_signed));
    nanosleep(&short_wait, NULL);
    unsigned long rec_signed = 0;
    uint8_t fired_signed = linea_mailbox_timer_cancel(t_signed, (unsigned long)&rec_signed, sizeof(rec_signed));
    assert(fired_signed == 0);
    assert(rec_signed == 77777);

    /* INT64_MAX + 1 (right beyond signed boundary) */
    unsigned long val_past = 66666;
    unsigned long t_past = linea_mailbox_timer(mb, 0x8000000000000000ULL, (unsigned long)&val_past, sizeof(val_past));
    nanosleep(&short_wait, NULL);
    unsigned long rec_past = 0;
    uint8_t fired_past = linea_mailbox_timer_cancel(t_past, (unsigned long)&rec_past, sizeof(rec_past));
    assert(fired_past == 0);
    assert(rec_past == 66666);

    /* UINT64_MAX (maximum unsigned 64-bit value) */
    unsigned long val_max = 88888;
    unsigned long t_max = linea_mailbox_timer(mb, ~0ULL, (unsigned long)&val_max, sizeof(val_max));
    nanosleep(&short_wait, NULL);
    unsigned long rec_max = 0;
    uint8_t fired_max = linea_mailbox_timer_cancel(t_max, (unsigned long)&rec_max, sizeof(rec_max));
    assert(fired_max == 0);
    assert(rec_max == 88888);

    /* 4. Sleep briefly to ensure the cancelled runner threads wake up and terminate safely without UAF */
    struct timespec sleep_req = { .tv_sec = 0, .tv_nsec = 20000000L /* 20ms */ };
    nanosleep(&sleep_req, NULL);

    linea_mailbox_remove_child(mb);
    rc = linea_mailbox_recv(mb, (unsigned long)&out, sizeof(out));
    assert(rc == 0);

    linea_mailbox_close(mb);
}

static volatile int worker_sum = 0;
static void test_worker_fn(unsigned long ctx) {
    sleep_ms(10);
    __sync_fetch_and_add(&worker_sum, (int)ctx);
}

static void workers_dispatch_and_drain(void) {
    worker_sum = 0;
    for (int i = 0; i < 10; i++) {
        linea_task_dispatch_worker(test_worker_fn, 5, 4);
    }
    linea_task_drain_workers();
    assert(worker_sum == 50);
}

static void *worker_id_check_thread(void *arg) {
    (void)arg;
    assert(linea_task_worker_id() == 0);
    assert(linea_task_worker_slot() == 0);
    linea_task_set_worker_id(77);
    linea_task_set_worker_slot(88);
    assert(linea_task_worker_id() == 77);
    assert(linea_task_worker_slot() == 88);
    return NULL;
}

static void worker_id_and_slot_are_thread_local(void) {
    assert(linea_task_worker_id() == 0);
    assert(linea_task_worker_slot() == 0);
    linea_task_set_worker_id(42);
    linea_task_set_worker_slot(100);
    assert(linea_task_worker_id() == 42);
    assert(linea_task_worker_slot() == 100);

    pthread_t thread;
    assert(pthread_create(&thread, NULL, worker_id_check_thread, NULL) == 0);
    assert(pthread_join(thread, NULL) == 0);

    /* Main thread values remain untouched. */
    assert(linea_task_worker_id() == 42);
    assert(linea_task_worker_slot() == 100);
    linea_task_set_worker_id(0);
    linea_task_set_worker_slot(0);
    assert(linea_task_worker_id() == 0);
    assert(linea_task_worker_slot() == 0);
}

static void conn_queue_fifo_and_close(void) {
    unsigned long q = linea_conn_queue_open();
    assert(q != 0);

    linea_conn_queue_push(q, 101);
    linea_conn_queue_push(q, 102);
    linea_conn_queue_push(q, 103);

    assert(linea_conn_queue_pop(q) == 101);
    assert(linea_conn_queue_pop(q) == 102);
    assert(linea_conn_queue_pop(q) == 103);

    linea_conn_queue_close(q);
    assert(linea_conn_queue_pop(q) == -1);

    /* Pushes to a closed queue are dropped safely. */
    linea_conn_queue_push(q, 999);
    assert(linea_conn_queue_pop(q) == -1);

    linea_conn_queue_free(q);
}

struct conn_test_worker_args {
    unsigned long q;
    long long sum;
};

static void *conn_queue_consumer(void *arg) {
    struct conn_test_worker_args *args = (struct conn_test_worker_args *)arg;
    long long local_sum = 0;
    while (1) {
        int32_t fd = linea_conn_queue_pop(args->q);
        if (fd < 0) break;
        local_sum += fd;
    }
    args->sum = local_sum;
    return NULL;
}

static void conn_queue_concurrent_multi_worker(void) {
    unsigned long q = linea_conn_queue_open();
    assert(q != 0);

    enum { num_consumers = 4, total_items = 1000 };
    pthread_t consumers[num_consumers];
    struct conn_test_worker_args args[num_consumers];

    for (int i = 0; i < num_consumers; i++) {
        args[i].q = q;
        args[i].sum = 0;
        assert(pthread_create(&consumers[i], NULL, conn_queue_consumer, &args[i]) == 0);
    }

    long long expected_sum = 0;
    for (int i = 1; i <= total_items; i++) {
        linea_conn_queue_push(q, (int32_t)i);
        expected_sum += i;
    }

    linea_conn_queue_close(q);

    long long actual_sum = 0;
    for (int i = 0; i < num_consumers; i++) {
        assert(pthread_join(consumers[i], NULL) == 0);
        actual_sum += args[i].sum;
    }

    assert(actual_sum == expected_sum);
    linea_conn_queue_free(q);
}

struct latch_thread_arg {
    unsigned long latch;
    volatile int arrived;
};

static void *latch_thread_fn(void *arg) {
    struct latch_thread_arg *a = (struct latch_thread_arg *)arg;
    a->arrived = 1;
    uint8_t ok = linea_latch_arrive_and_wait(a->latch);
    assert(ok == 1);
    return NULL;
}

static void latch_synchronization_and_timeouts(void) {
    /* 1. Latch arrive_and_wait between two threads */
    unsigned long l = linea_latch_open(2);
    struct latch_thread_arg arg = { .latch = l, .arrived = 0 };
    pthread_t th;
    assert(pthread_create(&th, NULL, latch_thread_fn, &arg) == 0);
    while (!arg.arrived) {
        sleep_ms(1);
    }
    uint8_t ok = linea_latch_arrive_and_wait(l);
    assert(ok == 1);
    assert(pthread_join(th, NULL) == 0);
    linea_latch_free(l);

    /* 2. Latch timeout */
    unsigned long l2 = linea_latch_open(2);
    /* Nobody else arrives; timeout after 20ms */
    uint8_t timed_out = linea_latch_arrive_and_wait_timeout(l2, 20);
    assert(timed_out == 0);
    linea_latch_free(l2);

    /* 3. Latch timeout with 0ms: immediate timeout if count remains > 0 */
    unsigned long l_zero = linea_latch_open(2);
    uint8_t zero_to = linea_latch_arrive_and_wait_timeout(l_zero, 0);
    assert(zero_to == 0);
    linea_latch_free(l_zero);

    /* 4. Latch with count 1: arrive_and_wait_timeout(0) succeeds immediately */
    unsigned long l_one = linea_latch_open(1);
    uint8_t one_ok = linea_latch_arrive_and_wait_timeout(l_one, 0);
    assert(one_ok == 1);
    linea_latch_free(l_one);

    /* 5. Latch timeout at signed boundary (INT64_MAX ms) */
    unsigned long l_int64_max = linea_latch_open(2);
    struct latch_thread_arg arg_int64 = { .latch = l_int64_max, .arrived = 0 };
    pthread_t th_int64;
    assert(pthread_create(&th_int64, NULL, latch_thread_fn, &arg_int64) == 0);
    while (!arg_int64.arrived) {
        sleep_ms(1);
    }
    uint8_t ok_int64 = linea_latch_arrive_and_wait_timeout(l_int64_max, 0x7fffffffffffffffULL);
    assert(ok_int64 == 1);
    assert(pthread_join(th_int64, NULL) == 0);
    linea_latch_free(l_int64_max);

    /* 6. Latch timeout beyond signed boundary (INT64_MAX + 1 ms) */
    unsigned long l_past_int64 = linea_latch_open(2);
    struct latch_thread_arg arg_past = { .latch = l_past_int64, .arrived = 0 };
    pthread_t th_past;
    assert(pthread_create(&th_past, NULL, latch_thread_fn, &arg_past) == 0);
    while (!arg_past.arrived) {
        sleep_ms(1);
    }
    uint8_t ok_past = linea_latch_arrive_and_wait_timeout(l_past_int64, 0x8000000000000000ULL);
    assert(ok_past == 1);
    assert(pthread_join(th_past, NULL) == 0);
    linea_latch_free(l_past_int64);

    /* 7. Latch timeout at UINT64_MAX ms */
    unsigned long l_uint64_max = linea_latch_open(2);
    struct latch_thread_arg arg_u64 = { .latch = l_uint64_max, .arrived = 0 };
    pthread_t th_u64;
    assert(pthread_create(&th_u64, NULL, latch_thread_fn, &arg_u64) == 0);
    while (!arg_u64.arrived) {
        sleep_ms(1);
    }
    uint8_t ok_u64 = linea_latch_arrive_and_wait_timeout(l_uint64_max, 0xffffffffffffffffULL);
    assert(ok_u64 == 1);
    assert(pthread_join(th_u64, NULL) == 0);
    linea_latch_free(l_uint64_max);
}

int main(void) {
    close_joins_after_the_body_returns();
    a_body_never_runs_before_start();
    cancel_settles_the_parked_thread();
    a_send_waits_for_its_receiver();
    an_offer_answers_the_choice();
    values_alternate_through_one_slot();
    many_tasks_run_at_once();
    tasks_allocate_at_once();
    concurrent_prepare_and_cancel_stress();
    an_impossible_stack_is_refused();
    mailbox_and_timers_work();
    workers_dispatch_and_drain();
    worker_id_and_slot_are_thread_local();
    conn_queue_fifo_and_close();
    conn_queue_concurrent_multi_worker();
    latch_synchronization_and_timeouts();
    /* A sanitizer reports an overflow through a fault handler of its own. */
#if !defined(LINEA_SANITIZED)
    an_overflow_is_reported();
    the_fault_handler_runs_on_the_signal_stack();
#endif
    puts("native task: prepare, start, cancel, rendezvous, choice, join, overflow and concurrent allocation passed");
    return 0;
}
