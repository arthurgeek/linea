/* A task's thread and the rendezvous channel of its session.
 *
 * Each task is one operating-system thread, created parked by
 * `linea_task_prepare_on` and released by `linea_task_start`. A task and its
 * creator share one record, which holds the thread, the bytes its stack and
 * its alternate signal stack occupy, and the session's one slot. The slot is
 * guarded by the record's mutex and goes from empty to full to empty: a
 * sender fills it and waits until the receiver has copied the bytes and
 * emptied it, so a send returns only once its peer holds the value.
 *
 * The creator's endpoint is the record's address and the task's own endpoint
 * is that address with its lowest bit set, which an allocation's alignment
 * leaves clear. The record is freed by the creator's `linea_chan_close`, after
 * the join, or by `linea_task_cancel`; the task's own end never frees it,
 * since the creator's close waits for the thread to end.
 *
 * Every wait is a park on the record's park (`park.h`), and every change to
 * the record's state is made with the park's lock held and followed by an
 * unpark, so a lock release by one thread and its acquire by the other order
 * everything either did before. The thread reads the body only after it
 * observes the start under the lock, which orders what the creator did
 * before the start, and the handle's close parks until the thread has
 * marked the body finished under the lock, which orders everything the body
 * did before the close returns; `pthread_join` then reclaims the thread. */

#define _GNU_SOURCE
#define _DARWIN_C_SOURCE
#include <errno.h>
#include <limits.h>
#include <pthread.h>
#include <signal.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

#include "loop.h"
#include "fiber.h"
#include "park.h"
#include "pipe_signal.h"
#include "task.h"
#include "waitset.h"
#include "waitset_pause.h"

/* Defined in `linea_rt.c`: install and remove the calling thread's
 * alternate signal stack, and record where its stack's guard pages lie so a
 * fault there is reported as an overflow. Beginning answers zero, or the
 * errno that kept the signal stack from being installed. */
int linea_thread_begin(unsigned long at, unsigned long bytes, unsigned long low, unsigned long high);
void linea_thread_end(void);
void linea_storage_extent(unsigned long at, unsigned long len);

/* Inaccessible bytes below every task's stack. A frame larger than a page
 * touches each of its pages in turn, because the compiler emits stack probes,
 * so any guard of a page or more stops an overflow; sixty-four kibibytes also
 * stops C code compiled without probes that keeps its frames under that. */
static const unsigned long guard_bytes = 65536;

/* glibc places a thread's static thread-local storage at the top of a stack
 * its caller supplies, so each task's stack holds this much beside the bytes
 * it asked for. Sixty-four kibibytes covers the runtime's own and a
 * sanitizer's; pages the storage does not reach are never touched. */
static const unsigned long thread_storage_bytes = 65536;

/* The fewest bytes a task's stack holds for its own frames. A sanitizer's
 * `pthread_create` wants 128 KiB beside the thread-local storage whatever
 * the system's own minimum is, and reports a smaller stack on standard
 * error. */
#if defined(LINEA_SANITIZED)
#define LEAST_STACK_BYTES ((unsigned long)PTHREAD_STACK_MIN > 131072UL ? (unsigned long)PTHREAD_STACK_MIN : 131072UL)
#else
#define LEAST_STACK_BYTES ((unsigned long)PTHREAD_STACK_MIN)
#endif

/* The alternate signal stack each task's thread runs its fault handler on. */
static const unsigned long signal_stack_bytes = 65536;

/* No address space this runtime targets maps a stack this large, so a
 * request past it is refused before any system call sees it. */
static const unsigned long largest_stack = 1UL << 40;

/* A thread is `beginning` until it has installed its signal stack, then
 * `parked` until the task is started or cancelled, or `failed` where it could
 * not begin and has ended. A started or cancelled thread is `finished` once
 * it has run its body, or nothing, and will run no more Linea code. */
enum { beginning, failed, parked, started, cancelled, finished };

struct task {
    struct linea_park park;
    pthread_t thread;
    struct linea_fiber *fiber;
    unsigned long loop;
    int state;
    int begin_error;

    /* What `linea_task_start` hands the thread, read once it has started. */
    linea_task_entry entry;
    linea_task_release release;
    unsigned long at;
    unsigned long len;
    unsigned long release_at;

    /* The session's slot: whether a value waits in it, which endpoint put it
     * there, and where its bytes are. `filled` and `emptied` count the values
     * that have entered and left it, so a sender waits for its own value to
     * be taken and not merely for the slot to be empty. */
    int full;
    unsigned long from;
    unsigned long slot_at;
    unsigned long slot_len;
    unsigned long filled;
    unsigned long emptied;

    /* The wait-set registration watching each end of the session, by the
     * endpoint's lowest bit, and whether the handle's watches for the body
     * to return rather than for a send. Under the park's lock, so a source
     * signals a registration only while it is watched. */
    struct linea_registration *watching[2];
    int watching_return;

    /* The mapping the thread's stack lives in, guard pages first. */
    void *stack;
    unsigned long stack_mapping;
    void *signal_stack;
};

/* Writes a runtime failure and aborts. */
static void fail(const char *message) {
    report_bytes(message, strlen(message));
    abort();
}

/* A simulation cannot acquire a scheduling dependency on the real world
 * or on another seed. Real loops and thread tasks may communicate freely. */
static void execution_context(unsigned long home) {
    const unsigned long current = linea_io_current();
    const int simulated = linea_io_is_simulated(home) != 0;
    const int inside = linea_io_is_simulated(current) != 0;
    if ((simulated || inside) && home != current) fail("linea: a session crosses a simulation's boundary\n");
}

static struct task *task_of(unsigned long endpoint) {
    return (struct task *)(endpoint & ~1UL);
}

static unsigned long round_up(unsigned long n, unsigned long to) {
    return (n + to - 1) / to * to;
}

/* Frees what `linea_task_prepare_on` made, once no thread uses it. */
static void destroy(struct task *t) {
    if (t->fiber != NULL) {
        linea_fiber_destroy(t->fiber);
    } else if (munmap(t->stack, t->stack_mapping) != 0 || munmap(t->signal_stack, signal_stack_bytes) != 0) {
        fail("linea: a task's stack could not be unmapped\n");
    }
    linea_park_destroy(&t->park);
    free(t);
}

static void *run(void *arg) {
    struct task *t = arg;
    const unsigned long base = (unsigned long)t->stack;
    const int begun = linea_thread_begin((unsigned long)t->signal_stack, signal_stack_bytes, base, base + guard_bytes);
    linea_park_lock(&t->park);
    t->begin_error = begun;
    t->state = begun == 0 ? parked : failed;
    linea_unpark(&t->park);
    if (begun != 0) {
        linea_park_unlock(&t->park);
        return 0;
    }
    while (t->state == parked) (void)linea_park(&t->park, 0);
    const int state = t->state;
    linea_park_unlock(&t->park);
    if (state == started) t->entry((unsigned long)t | 1UL, t->at, t->len);
    linea_park_lock(&t->park);
    t->state = finished;
    linea_unpark(&t->park);
    if (t->watching[0] != 0 && t->watching_return) linea_registration_signal(t->watching[0]);
    linea_waitset_pause(linea_pause_body_finished);
    linea_park_unlock(&t->park);
    linea_thread_end();
    return 0;
}

/* Park until the thread has finished, then reclaim it. */
static void join(struct task *t) {
    linea_park_lock(&t->park);
    while (t->state != finished) (void)linea_park(&t->park, 0);
    linea_park_unlock(&t->park);
    if (t->fiber == NULL && pthread_join(t->thread, 0) != 0) fail("linea: a task's thread could not be joined\n");
}

static long prepare_thread(unsigned long stack_bytes) {
    if (stack_bytes > largest_stack) return -ENOMEM;
    const long page = sysconf(_SC_PAGESIZE);
    if (page <= 0) return -EINVAL;
    unsigned long usable = round_up(stack_bytes, (unsigned long)page);
    if (usable < LEAST_STACK_BYTES) usable = round_up(LEAST_STACK_BYTES, (unsigned long)page);
    usable += round_up(thread_storage_bytes, (unsigned long)page);

    struct task *t = calloc(1, sizeof *t);
    if (t == 0) return -ENOMEM;
    t->stack_mapping = guard_bytes + usable;
    t->stack = mmap(0, t->stack_mapping, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0);
    if (t->stack == MAP_FAILED) {
        const int error = errno;
        free(t);
        return -(long)error;
    }
    int status = 0;
    t->signal_stack = mmap(0, signal_stack_bytes, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0);
    if (t->signal_stack == MAP_FAILED) {
        status = errno;
        goto unmap_stack;
    }
    if (mprotect(t->stack, guard_bytes, PROT_NONE) != 0) {
        status = errno;
        goto unmap_signal_stack;
    }
    status = linea_park_init(&t->park);
    if (status != 0) goto unmap_signal_stack;
    t->state = beginning;

    pthread_attr_t attributes;
    status = pthread_attr_init(&attributes);
    if (status != 0) goto destroy_park;
    status = pthread_attr_setstack(&attributes, (char *)t->stack + guard_bytes, usable);
    if (status == 0) status = pthread_create(&t->thread, &attributes, run, t);
    if (pthread_attr_destroy(&attributes) != 0) fail("linea: a thread's attributes could not be released\n");
    if (status != 0) goto destroy_park;

    /* The thread installs its signal stack before it parks, and a failure
     * there is this call's to report, so it waits until the thread has
     * parked or ended. */
    linea_park_lock(&t->park);
    while (t->state == beginning) (void)linea_park(&t->park, 0);
    const int parked_now = t->state == parked;
    status = t->begin_error;
    linea_park_unlock(&t->park);
    if (parked_now) return (long)t;
    if (pthread_join(t->thread, 0) != 0) fail("linea: a task's thread could not be joined\n");

destroy_park:
    linea_park_destroy(&t->park);
unmap_signal_stack:
    (void)munmap(t->signal_stack, signal_stack_bytes);
unmap_stack:
    (void)munmap(t->stack, t->stack_mapping);
    free(t);
    return -(long)status;
}

static void run_fiber_body(void *argument) {
    struct task *t = argument;
    t->entry((unsigned long)t | 1UL, t->at, t->len);
}

/* Only the scheduler calls this, after it has left the finished stack. The
 * last unlock can release a joiner which immediately destroys the task. */
static void fiber_body_finished(void *argument) {
    struct task *t = argument;
    linea_park_lock(&t->park);
    t->state = finished;
    linea_unpark(&t->park);
    if (t->watching[0] != 0 && t->watching_return) linea_registration_signal(t->watching[0]);
    linea_park_unlock(&t->park);
}

long linea_task_prepare_on(unsigned long stack_bytes, unsigned long identity) {
    if (identity == 0) return prepare_thread(stack_bytes);
    struct task *t = calloc(1, sizeof *t);
    if (t == NULL) return -(long)ENOMEM;
    int error = linea_park_init(&t->park);
    if (error != 0) { free(t); return -(long)error; }
    t->fiber = linea_fiber_create(identity, stack_bytes, run_fiber_body, fiber_body_finished, t, &error);
    if (t->fiber == NULL) {
        linea_park_destroy(&t->park);
        free(t);
        return -(long)error;
    }
    t->state = parked;
    t->loop = identity;
    return (long)t;
}

unsigned long linea_task_start(unsigned long task, linea_task_entry entry, linea_task_release release, unsigned long at,
                               unsigned long len, unsigned long release_at) {
    struct task *t = task_of(task);
    execution_context(t->loop);
    linea_park_lock(&t->park);
    t->entry = entry;
    t->release = release;
    t->at = at;
    t->len = len;
    t->release_at = release_at;
    t->state = started;
    linea_unpark(&t->park);
    linea_park_unlock(&t->park);
    if (t->fiber != NULL) linea_fiber_start(t->fiber);
    return task;
}

void linea_task_cancel(unsigned long task) {
    struct task *t = task_of(task);
    if (t->fiber != NULL) { destroy(t); return; }
    linea_park_lock(&t->park);
    t->state = cancelled;
    linea_unpark(&t->park);
    linea_park_unlock(&t->park);
    join(t);
    destroy(t);
}

void linea_chan_send(unsigned long endpoint, unsigned long at, unsigned long len) {
    struct task *t = task_of(endpoint);
    execution_context(t->loop);
    linea_storage_extent(at, len);
    linea_park_lock(&t->park);
    while (t->full) (void)linea_park(&t->park, 0);
    t->full = 1;
    t->from = endpoint;
    t->slot_at = at;
    t->slot_len = len;
    t->filled += 1;
    const unsigned long mine = t->filled;
    linea_unpark(&t->park);
    /* The peer's end is the other bit. A handle watched for its body's
     * return is at its end, so no send reaches it. */
    const unsigned long peer = (endpoint & 1UL) ^ 1UL;
    if (t->watching[peer] != 0 && !(peer == 0 && t->watching_return)) linea_registration_signal(t->watching[peer]);
    linea_waitset_pause(linea_pause_send_filled);
    while (t->emptied != mine) (void)linea_park(&t->park, 0);
    linea_park_unlock(&t->park);
}

/* Copy the value waiting in the slot to the `len` bytes at `at` and empty
 * the slot, waking its sender. Called with the lock held and the slot full
 * from the other end. */
static void take_slot(struct task *t, unsigned long at, unsigned long len) {
    if (t->slot_len != len) fail("linea: the two ends of a session disagree about a payload's size\n");
    if (len != 0) memcpy((void *)at, (const void *)t->slot_at, len);
    t->full = 0;
    t->emptied += 1;
    linea_unpark(&t->park);
}

void linea_chan_recv(unsigned long endpoint, unsigned long at, unsigned long len) {
    struct task *t = task_of(endpoint);
    execution_context(t->loop);
    linea_storage_extent(at, len);
    linea_park_lock(&t->park);
    while (!t->full || t->from == endpoint) (void)linea_park(&t->park, 0);
    take_slot(t, at, len);
    linea_park_unlock(&t->park);
}

void linea_chan_choose(unsigned long endpoint, uint8_t branch) {
    uint8_t sent = branch;
    linea_chan_send(endpoint, (unsigned long)&sent, 1);
}

uint8_t linea_chan_offer(unsigned long endpoint) {
    uint8_t chosen = 0;
    linea_chan_recv(endpoint, (unsigned long)&chosen, 1);
    if (chosen > 1) fail("linea: a session's peer chose a branch that does not exist\n");
    return chosen;
}

void linea_chan_watch(unsigned long endpoint, struct linea_registration *r, int returned) {
    struct task *t = task_of(endpoint);
    execution_context(t->loop);
    const unsigned long side = endpoint & 1UL;
    linea_park_lock(&t->park);
    if (t->watching[side] != 0) fail("linea: an endpoint was registered twice\n");
    t->watching[side] = r;
    if (side == 0) t->watching_return = returned;
    linea_waitset_pause(linea_pause_watch_after_publish);
    const int ready = returned ? t->state == finished : (t->full && t->from != endpoint);
    if (ready) linea_registration_signal(r);
    linea_park_unlock(&t->park);
}

void linea_chan_unwatch(unsigned long endpoint) {
    struct task *t = task_of(endpoint);
    execution_context(t->loop);
    linea_park_lock(&t->park);
    t->watching[endpoint & 1UL] = 0;
    if ((endpoint & 1UL) == 0) t->watching_return = 0;
    linea_park_unlock(&t->park);
}

void linea_chan_close(unsigned long endpoint) {
    execution_context(task_of(endpoint)->loop);
    /* The task's own end has nothing to wait for: the creator's close waits
     * for the thread itself. */
    if ((endpoint & 1UL) != 0) return;
    struct task *t = task_of(endpoint);
    join(t);
    t->release(t->release_at, t->len);
    destroy(t);
}

/* An owning task's call queue. One request slot is filled by a caller and
 * emptied by the owner, which copies its answer to the bytes the caller named
 * beside the request. The slot also names the caller's `finished` flag, which
 * the owner sets when it empties the slot, so each caller waits for its own
 * request to finish however many requests other callers make before it next
 * runs, and a later caller cannot take a slot that is still being served. */
struct owner_queue {
    struct linea_park park;
    unsigned long loop;
    int closed;
    int full;
    unsigned long at;
    unsigned long len;
    unsigned long answer_at;
    unsigned long answer_len;
    int answered;
    int *finished;
};

unsigned long linea_owner_open(void) {
    struct owner_queue *q = calloc(1, sizeof *q);
    if (q == 0) return 0;
    if (linea_park_init(&q->park) != 0) {
        free(q);
        return 0;
    }
    q->loop = linea_io_current();
    return (unsigned long)q;
}

void linea_owner_call(unsigned long queue, unsigned long at, unsigned long len, unsigned long answer_at,
                      unsigned long answer_len) {
    struct owner_queue *q = (struct owner_queue *)queue;
    execution_context(q->loop);
    linea_storage_extent(at, len);
    linea_storage_extent(answer_at, answer_len);
    linea_park_lock(&q->park);
    if (q->closed) fail("linea: a call reached an owning task that was closed\n");
    while (q->full) (void)linea_park(&q->park, 0);
    q->full = 1;
    q->at = at;
    q->len = len;
    q->answer_at = answer_at;
    q->answer_len = answer_len;
    int finished = 0;
    q->finished = &finished;
    linea_unpark(&q->park);
    while (!finished) (void)linea_park(&q->park, 0);
    linea_park_unlock(&q->park);
}

uint8_t linea_owner_next(unsigned long queue, unsigned long at, unsigned long len) {
    struct owner_queue *q = (struct owner_queue *)queue;
    execution_context(q->loop);
    linea_storage_extent(at, len);
    linea_park_lock(&q->park);
    while (!q->full && !q->closed) (void)linea_park(&q->park, 0);
    if (!q->full) {
        linea_park_unlock(&q->park);
        return 0;
    }
    if (q->len != len) fail("linea: a call and its owning task disagree about a request's size\n");
    if (len != 0) memcpy((void *)at, (const void *)q->at, len);
    linea_park_unlock(&q->park);
    return 1;
}

void linea_owner_answer(unsigned long queue, unsigned long at, unsigned long len) {
    struct owner_queue *q = (struct owner_queue *)queue;
    execution_context(q->loop);
    linea_storage_extent(at, len);
    linea_park_lock(&q->park);
    if (!q->full || q->answered) fail("linea: an owning task answered a call it was not serving\n");
    if (q->answer_len != len) fail("linea: a call and its owning task disagree about an answer's size\n");
    if (len != 0) memcpy((void *)q->answer_at, (const void *)at, len);
    q->answered = 1;
    linea_park_unlock(&q->park);
}

void linea_owner_done(unsigned long queue) {
    struct owner_queue *q = (struct owner_queue *)queue;
    execution_context(q->loop);
    linea_park_lock(&q->park);
    if (!q->answered) fail("linea: an owning task finished a call it did not answer\n");
    q->answered = 0;
    q->full = 0;
    *q->finished = 1;
    q->finished = 0;
    linea_unpark(&q->park);
    linea_park_unlock(&q->park);
}

void linea_owner_close(unsigned long queue) {
    struct owner_queue *q = (struct owner_queue *)queue;
    execution_context(q->loop);
    linea_park_lock(&q->park);
    q->closed = 1;
    linea_unpark(&q->park);
    linea_park_unlock(&q->park);
}

void linea_owner_free(unsigned long queue) {
    struct owner_queue *q = (struct owner_queue *)queue;
    linea_park_destroy(&q->park);
    free(q);
}

uint8_t linea_chan_recv_until(unsigned long endpoint, unsigned long at, unsigned long len, unsigned long timeout_ns) {
    struct task *t = task_of(endpoint);
    execution_context(t->loop);
    linea_storage_extent(at, len);
    /* A deadline past what the clock can count is none: no clock reaches
     * it, so the receive waits until the peer sends. */
    const unsigned long deadline = linea_park_deadline_after(timeout_ns);
    linea_park_lock(&t->park);
    while (!t->full || t->from == endpoint) {
        if (linea_park(&t->park, deadline) && (!t->full || t->from == endpoint)) {
            linea_park_unlock(&t->park);
            return 0;
        }
    }
    take_slot(t, at, len);
    linea_park_unlock(&t->park);
    return 1;
}
