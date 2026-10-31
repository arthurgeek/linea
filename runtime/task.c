/* A task's thread and the rendezvous channel of its session.
 *
 * Each task is one operating-system thread, created parked by
 * `linea_task_prepare` and released by `linea_task_start`. A task and its
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
 * Every wait is on the record's condition variable, and every change to the
 * record's state is made with its mutex held and followed by a broadcast, so
 * a mutex release by one thread and its acquire by the other order everything
 * either did before. `pthread_create` orders what the creator did before the
 * start, since the thread reads the body only after it observes the start
 * under the mutex, and `pthread_join` orders everything the body did before
 * the handle's close returns. */

#define _GNU_SOURCE
#define _DARWIN_C_SOURCE
#include <errno.h>
#include <limits.h>
#include <pthread.h>
#include <signal.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>

#include "task.h"

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

/* The alternate signal stack each task's thread runs its fault handler on. */
static const unsigned long signal_stack_bytes = 65536;

/* No address space this runtime targets maps a stack this large, so a
 * request past it is refused before any system call sees it. */
static const unsigned long largest_stack = 1UL << 40;

/* A thread is `beginning` until it has installed its signal stack, then
 * `parked` until the task is started or cancelled, or `failed` where it could
 * not begin and has ended. */
enum { beginning, failed, parked, started, cancelled };

struct task {
    pthread_mutex_t lock;
    pthread_cond_t changed;
    pthread_t thread;
    int state;
    int begin_error;

    /* What `linea_task_start` hands the thread, read once it has started. */
    linea_task_entry entry;
    linea_task_release release;
    unsigned long at;
    unsigned long len;

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

    /* The mapping the thread's stack lives in, guard pages first. */
    void *stack;
    unsigned long stack_mapping;
    void *signal_stack;
};

/* Writes a runtime failure and aborts. */
static void fail(const char *message) {
    if (write(2, message, strlen(message)) < 0) {
    }
    abort();
}

/* A pthread call on a mutex or condition variable this file initialised can
 * fail only when the record is corrupt, which is no state to continue in. */
static void must(int status) {
    if (status != 0) fail("linea: a task's lock failed\n");
}

/* Initialises a record's condition variable. On Linux its timed waits read
 * the monotonic clock, which a change to the system's time does not move;
 * Darwin has no such setting, and `wait_until` measures there instead. */
static int condition_init(pthread_cond_t *cond) {
#if defined(__APPLE__)
    return pthread_cond_init(cond, 0);
#else
    pthread_condattr_t attributes;
    int status = pthread_condattr_init(&attributes);
    if (status != 0) return status;
    status = pthread_condattr_setclock(&attributes, CLOCK_MONOTONIC);
    if (status == 0) status = pthread_cond_init(cond, &attributes);
    if (pthread_condattr_destroy(&attributes) != 0) fail("linea: a condition variable's attributes could not be released\n");
    return status;
#endif
}

static struct task *task_of(unsigned long endpoint) {
    return (struct task *)(endpoint & ~1UL);
}

static unsigned long round_up(unsigned long n, unsigned long to) {
    return (n + to - 1) / to * to;
}

/* Frees what `linea_task_prepare` made, once no thread uses it. */
static void destroy(struct task *t) {
    if (munmap(t->stack, t->stack_mapping) != 0 || munmap(t->signal_stack, signal_stack_bytes) != 0) {
        fail("linea: a task's stack could not be unmapped\n");
    }
    must(pthread_cond_destroy(&t->changed));
    must(pthread_mutex_destroy(&t->lock));
    free(t);
}

static void *run(void *arg) {
    struct task *t = arg;
    const unsigned long base = (unsigned long)t->stack;
    const int begun = linea_thread_begin((unsigned long)t->signal_stack, signal_stack_bytes, base, base + guard_bytes);
    must(pthread_mutex_lock(&t->lock));
    t->begin_error = begun;
    t->state = begun == 0 ? parked : failed;
    must(pthread_cond_broadcast(&t->changed));
    if (begun != 0) {
        must(pthread_mutex_unlock(&t->lock));
        return 0;
    }
    while (t->state == parked) must(pthread_cond_wait(&t->changed, &t->lock));
    const int state = t->state;
    must(pthread_mutex_unlock(&t->lock));
    if (state == started) t->entry((unsigned long)t | 1UL, t->at, t->len);
    linea_thread_end();
    return 0;
}

long linea_task_prepare(unsigned long stack_bytes) {
    if (stack_bytes > largest_stack) return -ENOMEM;
    const long page = sysconf(_SC_PAGESIZE);
    if (page <= 0) return -EINVAL;
    unsigned long usable = round_up(stack_bytes, (unsigned long)page);
    if (usable < (unsigned long)PTHREAD_STACK_MIN) usable = round_up((unsigned long)PTHREAD_STACK_MIN, (unsigned long)page);

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
    status = pthread_mutex_init(&t->lock, 0);
    if (status != 0) goto unmap_signal_stack;
    status = condition_init(&t->changed);
    if (status != 0) goto destroy_lock;
    t->state = beginning;

    pthread_attr_t attributes;
    status = pthread_attr_init(&attributes);
    if (status != 0) goto destroy_condition;
    status = pthread_attr_setstack(&attributes, (char *)t->stack + guard_bytes, usable);
    if (status == 0) status = pthread_create(&t->thread, &attributes, run, t);
    if (pthread_attr_destroy(&attributes) != 0) fail("linea: a thread's attributes could not be released\n");
    if (status != 0) goto destroy_condition;

    /* The thread installs its signal stack before it parks, and a failure
     * there is this call's to report, so it waits until the thread has
     * parked or ended. */
    must(pthread_mutex_lock(&t->lock));
    while (t->state == beginning) must(pthread_cond_wait(&t->changed, &t->lock));
    const int parked_now = t->state == parked;
    status = t->begin_error;
    must(pthread_mutex_unlock(&t->lock));
    if (parked_now) return (long)t;
    if (pthread_join(t->thread, 0) != 0) fail("linea: a task's thread could not be joined\n");

destroy_condition:
    must(pthread_cond_destroy(&t->changed));
destroy_lock:
    must(pthread_mutex_destroy(&t->lock));
unmap_signal_stack:
    (void)munmap(t->signal_stack, signal_stack_bytes);
unmap_stack:
    (void)munmap(t->stack, t->stack_mapping);
    free(t);
    return -(long)status;
}

unsigned long linea_task_start(unsigned long task, linea_task_entry entry, linea_task_release release, unsigned long at,
                               unsigned long len) {
    struct task *t = task_of(task);
    must(pthread_mutex_lock(&t->lock));
    t->entry = entry;
    t->release = release;
    t->at = at;
    t->len = len;
    t->state = started;
    must(pthread_cond_broadcast(&t->changed));
    must(pthread_mutex_unlock(&t->lock));
    return task;
}

void linea_task_cancel(unsigned long task) {
    struct task *t = task_of(task);
    must(pthread_mutex_lock(&t->lock));
    t->state = cancelled;
    must(pthread_cond_broadcast(&t->changed));
    must(pthread_mutex_unlock(&t->lock));
    if (pthread_join(t->thread, 0) != 0) fail("linea: a task's thread could not be joined\n");
    destroy(t);
}

void linea_chan_send(unsigned long endpoint, unsigned long at, unsigned long len) {
    struct task *t = task_of(endpoint);
    linea_storage_extent(at, len);
    must(pthread_mutex_lock(&t->lock));
    while (t->full) must(pthread_cond_wait(&t->changed, &t->lock));
    t->full = 1;
    t->from = endpoint;
    t->slot_at = at;
    t->slot_len = len;
    t->filled += 1;
    const unsigned long mine = t->filled;
    must(pthread_cond_broadcast(&t->changed));
    while (t->emptied != mine) must(pthread_cond_wait(&t->changed, &t->lock));
    must(pthread_mutex_unlock(&t->lock));
}

void linea_chan_recv(unsigned long endpoint, unsigned long at, unsigned long len) {
    struct task *t = task_of(endpoint);
    linea_storage_extent(at, len);
    must(pthread_mutex_lock(&t->lock));
    while (!t->full || t->from == endpoint) must(pthread_cond_wait(&t->changed, &t->lock));
    if (t->slot_len != len) fail("linea: the two ends of a session disagree about a payload's size\n");
    if (len != 0) memcpy((void *)at, (const void *)t->slot_at, len);
    t->full = 0;
    t->emptied += 1;
    must(pthread_cond_broadcast(&t->changed));
    must(pthread_mutex_unlock(&t->lock));
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

void linea_chan_close(unsigned long endpoint) {
    /* The task's own end has nothing to wait for: the creator's close waits
     * for the thread itself. */
    if ((endpoint & 1UL) != 0) return;
    struct task *t = task_of(endpoint);
    if (pthread_join(t->thread, 0) != 0) fail("linea: a task's thread could not be joined\n");
    t->release(t->at, t->len);
    destroy(t);
}

/* An owning task's call queue. One request slot is filled by a caller and
 * emptied by the owner; `issued` and `finished` count requests, so each
 * caller waits for its own to finish and a later caller cannot take a slot
 * that is still being served. */
struct owner_queue {
    pthread_mutex_t lock;
    pthread_cond_t changed;
    int closed;
    int full;
    unsigned long at;
    unsigned long len;
    unsigned long issued;
    unsigned long finished;
};

unsigned long linea_owner_open(void) {
    struct owner_queue *q = calloc(1, sizeof *q);
    if (q == 0) fail("linea: an owning task's queue could not be allocated\n");
    must(pthread_mutex_init(&q->lock, 0));
    must(pthread_cond_init(&q->changed, 0));
    return (unsigned long)q;
}

void linea_owner_call(unsigned long queue, unsigned long at, unsigned long len) {
    struct owner_queue *q = (struct owner_queue *)queue;
    linea_storage_extent(at, len);
    must(pthread_mutex_lock(&q->lock));
    if (q->closed) fail("linea: a call reached an owning task that was closed\n");
    while (q->full) must(pthread_cond_wait(&q->changed, &q->lock));
    q->full = 1;
    q->at = at;
    q->len = len;
    q->issued += 1;
    const unsigned long mine = q->issued;
    must(pthread_cond_broadcast(&q->changed));
    while (q->finished < mine) must(pthread_cond_wait(&q->changed, &q->lock));
    must(pthread_mutex_unlock(&q->lock));
}

uint8_t linea_owner_next(unsigned long queue, unsigned long at, unsigned long len) {
    struct owner_queue *q = (struct owner_queue *)queue;
    linea_storage_extent(at, len);
    must(pthread_mutex_lock(&q->lock));
    while (!q->full && !q->closed) must(pthread_cond_wait(&q->changed, &q->lock));
    if (!q->full) {
        must(pthread_mutex_unlock(&q->lock));
        return 0;
    }
    if (q->len != len) fail("linea: a call and its owning task disagree about a request's size\n");
    if (len != 0) memcpy((void *)at, (const void *)q->at, len);
    must(pthread_mutex_unlock(&q->lock));
    return 1;
}

void linea_owner_done(unsigned long queue) {
    struct owner_queue *q = (struct owner_queue *)queue;
    must(pthread_mutex_lock(&q->lock));
    q->full = 0;
    q->finished += 1;
    must(pthread_cond_broadcast(&q->changed));
    must(pthread_mutex_unlock(&q->lock));
}

void linea_owner_close(unsigned long queue) {
    struct owner_queue *q = (struct owner_queue *)queue;
    must(pthread_mutex_lock(&q->lock));
    q->closed = 1;
    must(pthread_cond_broadcast(&q->changed));
    must(pthread_mutex_unlock(&q->lock));
}

void linea_owner_free(unsigned long queue) {
    struct owner_queue *q = (struct owner_queue *)queue;
    must(pthread_cond_destroy(&q->changed));
    must(pthread_mutex_destroy(&q->lock));
    free(q);
}

/* Waits on the record's condition variable until `deadline` on the monotonic
 * clock, answering 0 when woken and ETIMEDOUT once the deadline has passed.
 * Darwin's condition variable cannot read the monotonic clock, so there the
 * wait is relative and recomputed from that clock on every call; a wait is
 * at most `longest_relative_wait_sec` long, since Darwin refuses a relative
 * time it cannot add to its own, and a capped wait that ends answers 0 so the
 * caller waits again. */
static int wait_until(struct task *t, const struct timespec *deadline) {
#if defined(__APPLE__)
    enum { longest_relative_wait_sec = 86400 };
    struct timespec now;
    if (clock_gettime(CLOCK_MONOTONIC, &now) != 0) fail("linea: clock_gettime failed\n");
    if (now.tv_sec > deadline->tv_sec || (now.tv_sec == deadline->tv_sec && now.tv_nsec >= deadline->tv_nsec))
        return ETIMEDOUT;
    struct timespec remaining = {.tv_sec = deadline->tv_sec - now.tv_sec, .tv_nsec = deadline->tv_nsec - now.tv_nsec};
    if (remaining.tv_nsec < 0) {
        remaining.tv_sec -= 1;
        remaining.tv_nsec += 1000000000L;
    }
    if (remaining.tv_sec >= longest_relative_wait_sec) {
        remaining.tv_sec = longest_relative_wait_sec;
        remaining.tv_nsec = 0;
    }
    const int rc = pthread_cond_timedwait_relative_np(&t->changed, &t->lock, &remaining);
    return rc == ETIMEDOUT ? 0 : rc;
#else
    return pthread_cond_timedwait(&t->changed, &t->lock, deadline);
#endif
}

/* Sets `*deadline` to `now` plus `step_sec` seconds and `step_nsec`
 * nanoseconds and answers 1, or answers 0 when that time is past the largest
 * `time_t`. No clock reaches a time `time_t` cannot hold, so a wait whose
 * deadline would be past it waits without one. `step_nsec` is below one
 * second. */
static int deadline_after(struct timespec now, uint64_t step_sec, long step_nsec, struct timespec *deadline) {
    long nsec = now.tv_nsec + step_nsec;
    int carry = 0;
    if (nsec >= 1000000000L) {
        carry = 1;
        nsec -= 1000000000L;
    }
    time_t sec;
    if (__builtin_add_overflow(now.tv_sec, step_sec, &sec) || __builtin_add_overflow(sec, carry, &sec)) return 0;
    deadline->tv_sec = sec;
    deadline->tv_nsec = nsec;
    return 1;
}

uint8_t linea_chan_recv_until(unsigned long endpoint, unsigned long at, unsigned long len, unsigned long timeout_ns) {
    struct task *t = task_of(endpoint);
    linea_storage_extent(at, len);
    struct timespec now;
    if (clock_gettime(CLOCK_MONOTONIC, &now) != 0) fail("linea: clock_gettime failed\n");
    struct timespec deadline;
    const int timed = deadline_after(now, timeout_ns / 1000000000UL, (long)(timeout_ns % 1000000000UL), &deadline);
    must(pthread_mutex_lock(&t->lock));
    while (!t->full || t->from == endpoint) {
        int rc = timed ? wait_until(t, &deadline) : pthread_cond_wait(&t->changed, &t->lock);
        if (rc == ETIMEDOUT && (!t->full || t->from == endpoint)) {
            must(pthread_mutex_unlock(&t->lock));
            return 0;
        }
        if (rc != 0 && rc != ETIMEDOUT) {
            must(pthread_mutex_unlock(&t->lock));
            fail("linea: channel timed wait failed\n");
        }
    }
    if (t->slot_len != len) fail("linea: the two ends of a session disagree about a payload's size\n");
    if (len != 0) memcpy((void *)at, (const void *)t->slot_at, len);
    t->full = 0;
    t->emptied += 1;
    must(pthread_cond_broadcast(&t->changed));
    must(pthread_mutex_unlock(&t->lock));
    return 1;
}
