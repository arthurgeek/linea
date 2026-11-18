#define _GNU_SOURCE
#define _DARWIN_C_SOURCE
/* Assertions execute test setup, checks, and cleanup in every build mode. */
#undef NDEBUG
#include <assert.h>
#include <pthread.h>
#include <sched.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#include "task.h"

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

enum { counts, doubles, offers, ping_pong, allocates, recurses, sums, sends_and_returns, echoes_large };

/* A payload larger than a session keeps in its own record. */
enum { large_bytes = 4096 };

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
        /* A receive followed at once by a send, so the session's values
         * change direction every step. */
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
    case sums: {
        /* Receive `rounds` words after a pause, each one more than the last,
         * and answer their sum, or zero if one came out of order. */
        sleep_ms(b->delay_ms);
        unsigned long total = 0;
        int in_order = 1;
        for (unsigned long i = 0; i < b->rounds; i += 1) {
            const unsigned long word = recv_word(endpoint);
            if (word != i + 1) in_order = 0;
            total += word;
        }
        (void)send_word(endpoint, in_order ? total : 0);
        break;
    }
    case sends_and_returns:
        (void)send_word(endpoint, b->answer);
        break;
    case echoes_large: {
        /* Receive a value larger than the record holds and send it back
         * with every byte one higher. */
        sleep_ms(b->delay_ms);
        unsigned char value[large_bytes];
        linea_chan_recv(endpoint, (unsigned long)value, sizeof value);
        for (unsigned long i = 0; i < sizeof value; i += 1) value[i] = (unsigned char)((value[i] + 1U) & 0xffU);
        linea_chan_send(endpoint, (unsigned long)value, sizeof value);
        break;
    }
    }
    linea_chan_close(endpoint);
    /* A test may watch this flag while the task runs, so it is set
     * atomically. */
    __atomic_store_n(&b->returned, 1, __ATOMIC_SEQ_CST);
}

static void release(unsigned long at, unsigned long len) {
    assert(len == sizeof(struct body));
    struct body *b = (struct body *)at;
    /* The release runs only once the body has returned. */
    assert(b->returned);
    b->released += 1;
}

static unsigned long started(struct body *b, unsigned long stack) {
    const long task = linea_task_prepare_on(stack, 0);
    assert(task > 0);
    return linea_task_start((unsigned long)task, entry, release, (unsigned long)b, sizeof *b, (unsigned long)b);
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
    const long task = linea_task_prepare_on(1UL << 20, 0);
    assert(task > 0);
    sleep_ms(50);
    assert(b.ran == 0);
    const unsigned long handle = linea_task_start((unsigned long)task, entry, release, (unsigned long)&b, sizeof b, (unsigned long)&b);
    linea_chan_close(handle);
    assert(b.ran == 1 && b.released == 1);
}

/* A cancelled task's thread ends without running a body or releasing
 * anything, and the cancel returns once it is joined. */
static void cancel_settles_the_parked_thread(void) {
    for (int i = 0; i < 200; i += 1) {
        const long task = linea_task_prepare_on(1UL << 16, 0);
        assert(task > 0);
        linea_task_cancel((unsigned long)task);
    }
}

/* A send returns before the peer has taken the value: the body waits
 * before it receives, and the send does not wait with it. The bytes the
 * sender named may be reused as soon as it returns. */
static void a_send_returns_before_its_receiver_takes_it(void) {
    struct body b = {.kind = doubles, .delay_ms = 200};
    const unsigned long handle = started(&b, 1UL << 20);
    struct timespec before;
    assert(clock_gettime(CLOCK_MONOTONIC, &before) == 0);
    unsigned long word = 21;
    linea_chan_send(handle, (unsigned long)&word, sizeof word);
    assert(elapsed_ms(&before) < 150);
    word = 0;
    assert(recv_word(handle) == 42);
    linea_chan_close(handle);
    assert(b.released == 1);
}

/* A session holds two values its receiver has not taken. A third send
 * waits until the receiver takes one, and the values arrive in the order
 * they were sent. */
static void a_third_send_waits_for_the_receiver(void) {
    struct body b = {.kind = sums, .delay_ms = 200, .rounds = 3};
    const unsigned long handle = started(&b, 1UL << 20);
    struct timespec before;
    assert(clock_gettime(CLOCK_MONOTONIC, &before) == 0);
    (void)send_word(handle, 1);
    (void)send_word(handle, 2);
    assert(elapsed_ms(&before) < 150);
    (void)send_word(handle, 3);
    assert(elapsed_ms(&before) >= 190);
    assert(recv_word(handle) == 6);
    linea_chan_close(handle);
}

/* Many values sent with no answer between them arrive in order. */
static void values_arrive_in_the_order_they_were_sent(void) {
    struct body b = {.kind = sums, .rounds = 100000};
    const unsigned long handle = started(&b, 1UL << 20);
    for (unsigned long i = 1; i <= b.rounds; i += 1) (void)send_word(handle, i);
    assert(recv_word(handle) == b.rounds * (b.rounds + 1) / 2);
    linea_chan_close(handle);
}

/* A task that sends and returns at once leaves its value in the session,
 * and its creator receives it after the body has returned. */
static void a_value_outlives_the_body_that_sent_it(void) {
    struct body b = {.kind = sends_and_returns, .answer = 77};
    const unsigned long handle = started(&b, 1UL << 20);
    while (!__atomic_load_n(&b.returned, __ATOMIC_SEQ_CST)) sched_yield();
    assert(recv_word(handle) == 77);
    linea_chan_close(handle);
    assert(b.released == 1);
}

/* A value larger than the session's record is queued in bytes of its own,
 * and comes back whole once the slow receiver takes it. */
static void a_large_value_is_queued_whole(void) {
    struct body b = {.kind = echoes_large, .delay_ms = 100};
    const unsigned long handle = started(&b, 1UL << 20);
    unsigned char value[large_bytes];
    for (unsigned long i = 0; i < sizeof value; i += 1) value[i] = (unsigned char)((i * 13) & 0xffUL);
    linea_chan_send(handle, (unsigned long)value, sizeof value);
    memset(value, 0, sizeof value);
    linea_chan_recv(handle, (unsigned long)value, sizeof value);
    for (unsigned long i = 0; i < sizeof value; i += 1) assert(value[i] == (unsigned char)((i * 13 + 1) & 0xffUL));
    linea_chan_close(handle);
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
static void values_alternate_direction(void) {
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

/* Many sessions each hold two queued values at once, sent before any of
 * their receivers runs, and each sum comes back whole. */
static void many_sessions_queue_at_once(void) {
    enum { tasks = 64 };
    static struct body bodies[tasks];
    unsigned long handles[tasks];
    for (unsigned long i = 0; i < tasks; i += 1) {
        bodies[i] = (struct body){.kind = sums, .rounds = 2, .delay_ms = 20};
        handles[i] = started(&bodies[i], 1UL << 18);
    }
    for (unsigned long i = 0; i < tasks; i += 1) {
        (void)send_word(handles[i], 1);
        (void)send_word(handles[i], 2);
    }
    for (unsigned long i = 0; i < tasks; i += 1) {
        assert(recv_word(handles[i]) == 3);
        linea_chan_close(handles[i]);
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
        long task = linea_task_prepare_on(1UL << 18, 0);
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

static void close_with_a_value_never_received(void) {
    struct body b = {.kind = sends_and_returns, .answer = 5};
    linea_chan_close(started(&b, 1UL << 18));
}

/* Dual protocols receive every value before a session ends, so a session
 * freed with a value still queued stops the program rather than dropping
 * bytes a value may own. */
static void a_session_ended_holding_a_value_stops_the_program(void) {
    aborts_saying(close_with_a_value_never_received, "linea: a session ended holding a value its receiver never took\n");
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
    assert(linea_task_prepare_on(1UL << 62, 0) < 0);
}

/* Each caller adds one to the owner's total `calls_each` times. The owner
 * runs every call alone, so the total counts every call. */
enum { callers = 4, calls_each = 2000 };

static unsigned long owner_total = 0;

static void *owner_thread(void *arg) {
    const unsigned long queue = *(unsigned long *)arg;
    unsigned long request = 0;
    while (linea_owner_next(queue, (unsigned long)&request, sizeof request) == 1) {
        owner_total += request;
        unsigned long answer = owner_total;
        linea_owner_answer(queue, (unsigned long)&answer, sizeof answer);
        linea_owner_done(queue);
    }
    return 0;
}

static void *caller_thread(void *arg) {
    const unsigned long queue = *(unsigned long *)arg;
    unsigned long last = 0;
    for (int i = 0; i < calls_each; i += 1) {
        unsigned long one = 1;
        unsigned long total = 0;
        linea_owner_call(queue, (unsigned long)&one, sizeof one, (unsigned long)&total, sizeof total);
        /* Each answer is the total after this call, so it only grows. */
        assert(total > last);
        last = total;
    }
    return 0;
}

static void an_owner_serves_every_call_alone(void) {
    unsigned long queue = linea_owner_open();
    owner_total = 0;
    pthread_t owner;
    assert(pthread_create(&owner, 0, owner_thread, &queue) == 0);
    pthread_t calling[callers];
    for (int i = 0; i < callers; i += 1) assert(pthread_create(&calling[i], 0, caller_thread, &queue) == 0);
    for (int i = 0; i < callers; i += 1) assert(pthread_join(calling[i], 0) == 0);
    linea_owner_close(queue);
    assert(pthread_join(owner, 0) == 0);
    linea_owner_free(queue);
    assert(owner_total == (unsigned long)callers * calls_each);
}

int main(void) {
    close_joins_after_the_body_returns();
    a_body_never_runs_before_start();
    cancel_settles_the_parked_thread();
    a_send_returns_before_its_receiver_takes_it();
    a_third_send_waits_for_the_receiver();
    values_arrive_in_the_order_they_were_sent();
    a_value_outlives_the_body_that_sent_it();
    a_large_value_is_queued_whole();
    an_offer_answers_the_choice();
    values_alternate_direction();
    many_tasks_run_at_once();
    tasks_allocate_at_once();
    concurrent_prepare_and_cancel_stress();
    many_sessions_queue_at_once();
    an_impossible_stack_is_refused();
    an_owner_serves_every_call_alone();
    /* A sanitizer reports an overflow through a fault handler of its own. */
#if !defined(LINEA_SANITIZED)
    an_overflow_is_reported();
    a_session_ended_holding_a_value_stops_the_program();
    the_fault_handler_runs_on_the_signal_stack();
#endif
    puts("native task: prepare, start, cancel, queued sends, choice, join, owner calls, overflow and concurrent allocation passed");
    return 0;
}
