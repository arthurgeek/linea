/* A task's execution and the queue of its session.
 *
 * A prepared task runs on a system thread or a pinned fiber. Its creator
 * shares one record with it, holding execution resources and the session's
 * queue. A system task owns its mapped stack and alternate signal stack;
 * a fiber owns its guarded stack through the carrier scheduler. The queue is
 * guarded by the record's mutex and holds at most `queue_values` values one
 * end sent and the other has not received: a send copies its bytes in and
 * returns, waiting only while the queue is full, and a receive copies the
 * oldest value out, waiting while none from the peer is queued.
 *
 * The creator's endpoint is the record's address and the task's own endpoint
 * is that address with its lowest bit set, which an allocation's alignment
 * leaves clear. The body may send its own end away, so another task can hold
 * and close it after the body has returned and after the creator has closed.
 * The creator's close waits for the body and its execution to finish, then
 * frees the execution's stack; the record itself is freed by whichever end's
 * `linea_chan_close` comes last, once both ends have closed, so neither close
 * reads the record after the other freed it. A task cancelled before it
 * started never had an end of its own, and `linea_task_cancel` frees it.
 *
 * Every wait is a park on the record's park (`park.h`), and every change to
 * the record's state is made with the park's lock held and followed by an
 * unpark, so a lock release and its later acquire order the bodies' accesses.
 * A system task reads its body after acquiring the start latch's lock; a
 * fiber reads it after its carrier acquires the published queue entry.
 * Close parks until the body is marked finished under the record's lock.
 * A fiber publishes completion from the scheduler stack after its final
 * switch; `pthread_join` reclaims a system task's thread after its body ends. */
#define _GNU_SOURCE
#define _DARWIN_C_SOURCE
#include <errno.h>
#include <limits.h>
#include <pthread.h>
#include <sched.h>
#include <signal.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

#if defined(__APPLE__)
#include <mach/mach.h>
#endif

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

/* The most values a session holds that its receiver has not taken. Two let
 * a choice and the payload after it be sent without waiting for the
 * receiver, and bound what a sender may run ahead of its peer. */
enum { queue_values = 2 };

/* A queued value of at most this many bytes is kept in the record; a larger
 * one in bytes the runtime allocates. A branch, a scalar and a `Vec` fit. */
enum { held_bytes = 32 };

struct queued {
    unsigned long len;
    unsigned char *allocated;
    unsigned char held[held_bytes];
};

/* A thread is `beginning` until it has installed its signal stack, then
 * `parked` until the task is started or cancelled, or `failed` where it could
 * not begin and has ended. A started or cancelled thread is `finished` once
 * it has run its body, or nothing, and will run no more Linea code. */
enum { beginning, failed, parked, started, cancelled, finished };

struct task {
    struct linea_park park;
    pthread_t thread;
#if defined(__APPLE__)
    /* A send right to a system task's kernel thread port, which the thread
     * takes for its joiner before it publishes its first state. */
    mach_port_t port;
#endif
    struct linea_fiber *fiber;
    unsigned long loop;
    int state;
    int begin_error;

    /* What `linea_task_start` hands the task, read once it has started. */
    linea_task_entry entry;
    linea_task_release release;
    unsigned long at;
    unsigned long len;
    unsigned long release_at;

    /* The session's queue: `count` values starting at `oldest`, all sent by
     * the endpoint `from`. Dual protocols send in one direction until the
     * receiver has taken every value, so the queue never holds both ends'. */
    struct queued queue[queue_values];
    unsigned long oldest;
    unsigned long count;
    unsigned long from;

    /* The wait-set registration watching each end of the session, by the
     * endpoint's lowest bit, and whether the handle's watches for the body
     * to return rather than for a send. Under the park's lock, so a source
     * signals a registration only while it is watched. */
    struct linea_registration *watching[2];
    int watching_return;

    /* The ends that have been closed, as a bit for each endpoint's lowest
     * bit, under the park's lock. The end that sets the second bit frees the
     * record. */
    unsigned ends_closed;

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

/* Frees the fiber or the stacks `linea_task_prepare_on` made, once no
 * execution uses them. */
static void destroy_execution(struct task *t) {
    if (t->fiber != NULL) {
        linea_fiber_destroy(t->fiber);
    } else if (munmap(t->stack, t->stack_mapping) != 0 || munmap(t->signal_stack, signal_stack_bytes) != 0) {
        fail("linea: a task's stack could not be unmapped\n");
    }
}

/* Frees the record, once no end can reach it. */
static void destroy_record(struct task *t) {
    linea_park_destroy(&t->park);
    free(t);
}

static void *run(void *arg) {
    struct task *t = arg;
#if defined(__APPLE__)
    t->port = mach_thread_self();
#endif
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

/* Join a system task's thread, answering once the thread runs no more user
 * code, so the stack the runtime mapped for it may be unmapped. macOS's
 * `pthread_join` can return while the ending thread still runs the last
 * instructions of its exit on that stack, when the join begins as the thread
 * is ending; a stack unmapped then and mapped again for another task, zeroed,
 * sends the ending thread to address zero. So on macOS the thread takes a
 * send right to its own kernel port when it starts, and the joiner, after
 * the join, waits until the kernel no longer answers for the thread, which
 * it stops doing only once the thread has entered the kernel to terminate
 * and will not return to user code. Linux's join already waits for the
 * kernel to clear the thread's id once it has exited. */
static void join_thread(struct task *t) {
    if (pthread_join(t->thread, 0) != 0) fail("linea: a task's thread could not be joined\n");
#if defined(__APPLE__)
    for (;;) {
        struct thread_basic_info info;
        mach_msg_type_number_t count = THREAD_BASIC_INFO_COUNT;
        if (thread_info(t->port, THREAD_BASIC_INFO, (thread_info_t)&info, &count) != KERN_SUCCESS) break;
        sched_yield();
    }
    (void)mach_port_deallocate(mach_task_self(), t->port);
#endif
}

/* Park until the body has finished, then join a system thread if present. */
static void join(struct task *t) {
    linea_park_lock(&t->park);
    while (t->state != finished) (void)linea_park(&t->park, 0);
    linea_park_unlock(&t->park);
    if (t->fiber == NULL) join_thread(t);
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
    join_thread(t);

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
 * last unlock can release a joiner which immediately destroys the fiber and,
 * when the task's own end is already closed, the record. */
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

static unsigned long start_task(unsigned long task, linea_task_entry entry, linea_task_release release, unsigned long at,
                                unsigned long len, unsigned long release_at, int compiled) {
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
    if (t->fiber != NULL) {
        if (compiled) linea_fiber_start_compiled(t->fiber);
        else linea_fiber_start(t->fiber);
    }
    return task;
}

unsigned long linea_task_start(unsigned long task, linea_task_entry entry, linea_task_release release, unsigned long at,
                               unsigned long len, unsigned long release_at) {
    return start_task(task, entry, release, at, len, release_at, 0);
}

unsigned long linea_task_start_migratable(unsigned long task, linea_task_entry entry, linea_task_release release, unsigned long at,
                                          unsigned long len, unsigned long release_at) {
    return start_task(task, entry, release, at, len, release_at, 1);
}

void linea_task_cancel(unsigned long task) {
    struct task *t = task_of(task);
    if (t->fiber == NULL) {
        linea_park_lock(&t->park);
        t->state = cancelled;
        linea_unpark(&t->park);
        linea_park_unlock(&t->park);
        join(t);
    }
    destroy_execution(t);
    destroy_record(t);
}

void linea_chan_send(unsigned long endpoint, unsigned long at, unsigned long len) {
    struct task *t = task_of(endpoint);
    execution_context(t->loop);
    linea_storage_extent(at, len);
    /* A value too large for the record gets bytes of its own before the
     * lock is taken, so no other end waits on the allocation. */
    unsigned char *allocated = 0;
    if (len > held_bytes) {
        allocated = malloc(len);
        if (allocated == 0) fail("linea: a session could not hold the value it was sent\n");
        memcpy(allocated, (const void *)at, len);
    }
    linea_park_lock(&t->park);
    while (t->count == queue_values || (t->count != 0 && t->from != endpoint)) (void)linea_park(&t->park, 0);
    struct queued *q = &t->queue[(t->oldest + t->count) % queue_values];
    q->len = len;
    q->allocated = allocated;
    if (allocated == 0 && len != 0) memcpy(q->held, (const void *)at, len);
    t->from = endpoint;
    t->count += 1;
    linea_unpark(&t->park);
    /* The peer's end is the other bit. A handle watched for its body's
     * return is at its end, so no send reaches it. */
    const unsigned long peer = (endpoint & 1UL) ^ 1UL;
    if (t->watching[peer] != 0 && !(peer == 0 && t->watching_return)) linea_registration_signal(t->watching[peer]);
    linea_waitset_pause(linea_pause_send_filled);
    linea_park_unlock(&t->park);
}

/* Whether a value from the peer of `endpoint` waits in the queue. */
static int queued_for(const struct task *t, unsigned long endpoint) {
    return t->count != 0 && t->from != endpoint;
}

/* Copy the oldest queued value to the `len` bytes at `at` and remove it,
 * waking a sender that waits for room, then unlock. Called with the lock
 * held and a value from the other end queued. Bytes allocated for the
 * value are freed after the lock is released. */
static void take_oldest(struct task *t, unsigned long at, unsigned long len) {
    struct queued *q = &t->queue[t->oldest];
    if (q->len != len) fail("linea: the two ends of a session disagree about a payload's size\n");
    unsigned char *allocated = q->allocated;
    if (len != 0) memcpy((void *)at, allocated != 0 ? allocated : q->held, len);
    q->allocated = 0;
    t->oldest = (t->oldest + 1) % queue_values;
    t->count -= 1;
    linea_unpark(&t->park);
    linea_park_unlock(&t->park);
    free(allocated);
}

void linea_chan_recv(unsigned long endpoint, unsigned long at, unsigned long len) {
    struct task *t = task_of(endpoint);
    execution_context(t->loop);
    linea_storage_extent(at, len);
    linea_park_lock(&t->park);
    while (!queued_for(t, endpoint)) (void)linea_park(&t->park, 0);
    take_oldest(t, at, len);
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
    const int ready = returned ? t->state == finished : queued_for(t, endpoint);
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

/* The creator's close joins the body, releases what the body captured and
 * frees its execution; the task's own end has nothing to wait for. Each
 * then records its end as closed, and the end that closes second frees the
 * record. Until this end is recorded closed the record is alive, because the
 * other end cannot free it before then. */
void linea_chan_close(unsigned long endpoint) {
    struct task *t = task_of(endpoint);
    execution_context(t->loop);
    const unsigned side = (unsigned)(endpoint & 1UL);
    if (side == 0) {
        join(t);
        t->release(t->release_at, t->len);
        destroy_execution(t);
    }
    linea_park_lock(&t->park);
    t->ends_closed |= 1U << side;
    const int last = t->ends_closed == 3U;
    linea_park_unlock(&t->park);
    if (!last) return;
    /* Dual protocols receive every value before both ends close, and the
     * runtime cannot release what a value owns. */
    if (t->count != 0) fail("linea: a session ended holding a value its receiver never took\n");
    destroy_record(t);
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
    while (!queued_for(t, endpoint)) {
        if (linea_park(&t->park, deadline) && !queued_for(t, endpoint)) {
            linea_park_unlock(&t->park);
            return 0;
        }
    }
    take_oldest(t, at, len);
    return 1;
}
