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
    status = pthread_cond_init(&t->changed, 0);
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

uint8_t linea_chan_recv_until(unsigned long endpoint, unsigned long at, unsigned long len, unsigned long timeout_ns) {
    struct task *t = task_of(endpoint);
    linea_storage_extent(at, len);
    struct timespec deadline;
    clock_gettime(CLOCK_REALTIME, &deadline);
    deadline.tv_sec += timeout_ns / 1000000000UL;
    deadline.tv_nsec += timeout_ns % 1000000000UL;
    if (deadline.tv_nsec >= 1000000000L) {
        deadline.tv_sec += 1;
        deadline.tv_nsec -= 1000000000L;
    }
    must(pthread_mutex_lock(&t->lock));
    while (!t->full || t->from == endpoint) {
        int rc = pthread_cond_timedwait(&t->changed, &t->lock, &deadline);
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

struct mailbox_node {
    void *data;
    unsigned long len;
    struct mailbox_node *next;
};

struct mailbox {
    pthread_mutex_t lock;
    pthread_cond_t changed;
    struct mailbox_node *head;
    struct mailbox_node *tail;
    unsigned long live_children;
    unsigned long live_timers;
    int closed;
    int refcount;
};

unsigned long linea_mailbox_open(void) {
    struct mailbox *mb = (struct mailbox *)malloc(sizeof(struct mailbox));
    if (!mb) fail("linea: mailbox allocation failed\n");
    must(pthread_mutex_init(&mb->lock, NULL));
    must(pthread_cond_init(&mb->changed, NULL));
    mb->head = NULL;
    mb->tail = NULL;
    mb->live_children = 0;
    mb->live_timers = 0;
    mb->closed = 0;
    mb->refcount = 1;
    return (unsigned long)mb;
}

void linea_mailbox_close(unsigned long mb_addr) {
    struct mailbox *mb = (struct mailbox *)mb_addr;
    must(pthread_mutex_lock(&mb->lock));
    mb->closed = 1;
    struct mailbox_node *cur = mb->head;
    while (cur) {
        struct mailbox_node *next = cur->next;
        free(cur->data);
        free(cur);
        cur = next;
    }
    mb->head = NULL;
    mb->tail = NULL;
    mb->refcount--;
    int free_it = (mb->refcount == 0);
    must(pthread_cond_broadcast(&mb->changed));
    must(pthread_mutex_unlock(&mb->lock));
    if (free_it) {
        must(pthread_cond_destroy(&mb->changed));
        must(pthread_mutex_destroy(&mb->lock));
        free(mb);
    }
}

void linea_mailbox_add_child(unsigned long mb_addr) {
    struct mailbox *mb = (struct mailbox *)mb_addr;
    must(pthread_mutex_lock(&mb->lock));
    mb->live_children++;
    mb->refcount++;
    must(pthread_mutex_unlock(&mb->lock));
}

void linea_mailbox_remove_child(unsigned long mb_addr) {
    struct mailbox *mb = (struct mailbox *)mb_addr;
    must(pthread_mutex_lock(&mb->lock));
    if (mb->live_children > 0) mb->live_children--;
    mb->refcount--;
    int free_it = (mb->refcount == 0);
    must(pthread_cond_broadcast(&mb->changed));
    must(pthread_mutex_unlock(&mb->lock));
    if (free_it) {
        must(pthread_cond_destroy(&mb->changed));
        must(pthread_mutex_destroy(&mb->lock));
        free(mb);
    }
}

void linea_mailbox_send(unsigned long mb_addr, unsigned long at, unsigned long len) {
    struct mailbox *mb = (struct mailbox *)mb_addr;
    must(pthread_mutex_lock(&mb->lock));
    if (mb->closed) {
        must(pthread_mutex_unlock(&mb->lock));
        return;
    }
    struct mailbox_node *node = (struct mailbox_node *)malloc(sizeof(struct mailbox_node));
    if (!node) fail("linea: mailbox send allocation failed\n");
    node->len = len;
    node->next = NULL;
    if (len > 0) {
        node->data = malloc(len);
        if (!node->data) fail("linea: mailbox send data allocation failed\n");
        memcpy(node->data, (const void *)at, len);
    } else {
        node->data = NULL;
    }
    if (mb->tail) {
        mb->tail->next = node;
        mb->tail = node;
    } else {
        mb->head = node;
        mb->tail = node;
    }
    must(pthread_cond_broadcast(&mb->changed));
    must(pthread_mutex_unlock(&mb->lock));
}

uint8_t linea_mailbox_recv(unsigned long mb_addr, unsigned long at, unsigned long len) {
    struct mailbox *mb = (struct mailbox *)mb_addr;
    must(pthread_mutex_lock(&mb->lock));
    while (!mb->head && (mb->live_children > 0 || mb->live_timers > 0) && !mb->closed) {
        must(pthread_cond_wait(&mb->changed, &mb->lock));
    }
    if (mb->head) {
        struct mailbox_node *node = mb->head;
        mb->head = node->next;
        if (!mb->head) mb->tail = NULL;
        if (len != 0 && node->data) {
            if (node->len != len) fail("linea: mailbox message size mismatch\n");
            memcpy((void *)at, node->data, len);
        }
        free(node->data);
        free(node);
        must(pthread_mutex_unlock(&mb->lock));
        return 1;
    }
    must(pthread_mutex_unlock(&mb->lock));
    return 0;
}

struct mailbox_timer {
    struct mailbox *mb;
    pthread_t thread;
    uint64_t nanoseconds;
    void *data;
    unsigned long len;
    int fired;
    int cancelled;
    int refcount;
    pthread_mutex_t lock;
    pthread_cond_t cond;
};

static void *mailbox_timer_runner(void *arg) {
    struct mailbox_timer *t = (struct mailbox_timer *)arg;

    struct timespec start;
    if (clock_gettime(CLOCK_MONOTONIC, &start) != 0) {
        fail("linea: clock_gettime failed\n");
    }

    struct mailbox *mb = t->mb;
    int dec_mb = 0;

    must(pthread_mutex_lock(&t->lock));
    while (!t->cancelled && !t->fired) {
        struct timespec now;
        if (clock_gettime(CLOCK_MONOTONIC, &now) != 0) {
            must(pthread_mutex_unlock(&t->lock));
            fail("linea: clock_gettime failed\n");
        }

        uint64_t elapsed_sec = 0;
        uint64_t elapsed_nsec = 0;
        if (now.tv_sec > start.tv_sec || (now.tv_sec == start.tv_sec && now.tv_nsec >= start.tv_nsec)) {
            if (now.tv_nsec >= start.tv_nsec) {
                elapsed_sec = (uint64_t)(now.tv_sec - start.tv_sec);
                elapsed_nsec = (uint64_t)(now.tv_nsec - start.tv_nsec);
            } else {
                elapsed_sec = (uint64_t)(now.tv_sec - start.tv_sec - 1);
                elapsed_nsec = (uint64_t)(now.tv_nsec + 1000000000L - start.tv_nsec);
            }
        }

        uint64_t max_sec_in_duration = t->nanoseconds / 1000000000ULL;
        if (elapsed_sec > max_sec_in_duration ||
            (elapsed_sec == max_sec_in_duration && elapsed_nsec >= (t->nanoseconds % 1000000000ULL))) {
            break;
        }

        uint64_t elapsed_ns = elapsed_sec * 1000000000ULL + elapsed_nsec;
        uint64_t remaining_ns = t->nanoseconds - elapsed_ns;

        /* Cap single wait interval to at most 86400 seconds (1 day) to prevent
         * any integer overflow in time_t, long, or kernel timeout representation. */
        const uint64_t max_step_ns = 86400ULL * 1000000000ULL;
        uint64_t step_ns = remaining_ns > max_step_ns ? max_step_ns : remaining_ns;

#if defined(__APPLE__)
        struct timespec rel_timeout;
        rel_timeout.tv_sec = (time_t)(step_ns / 1000000000ULL);
        rel_timeout.tv_nsec = (long)(step_ns % 1000000000ULL);
        int rc = pthread_cond_timedwait_relative_np(&t->cond, &t->lock, &rel_timeout);
#else
        struct timespec deadline;
        time_t step_sec = (time_t)(step_ns / 1000000000ULL);
        long step_nsec = (long)(step_ns % 1000000000ULL);
        deadline.tv_sec = now.tv_sec + step_sec;
        deadline.tv_nsec = now.tv_nsec + step_nsec;
        if (deadline.tv_nsec >= 1000000000L) {
            deadline.tv_sec += 1;
            deadline.tv_nsec -= 1000000000L;
        }
        int rc = pthread_cond_timedwait(&t->cond, &t->lock, &deadline);
#endif
        if (rc == ETIMEDOUT) {
            continue;
        }
        if (rc != 0 && rc != EINTR) {
            must(pthread_mutex_unlock(&t->lock));
            fail("linea: timer condition timedwait failed\n");
        }
    }
    if (!t->cancelled && !t->fired) {
        t->fired = 1;
        must(pthread_mutex_lock(&mb->lock));
        if (!mb->closed) {
            struct mailbox_node *node = (struct mailbox_node *)malloc(sizeof(struct mailbox_node));
            if (!node) fail("linea: mailbox send allocation failed\n");
            node->len = t->len;
            node->next = NULL;
            if (t->len > 0 && t->data) {
                node->data = malloc(t->len);
                if (!node->data) fail("linea: mailbox send data allocation failed\n");
                memcpy(node->data, (const void *)t->data, t->len);
            } else {
                node->data = NULL;
            }
            if (mb->tail) {
                mb->tail->next = node;
                mb->tail = node;
            } else {
                mb->head = node;
                mb->tail = node;
            }
        }
        if (mb->live_timers > 0) mb->live_timers--;
        dec_mb = 1;
        must(pthread_cond_broadcast(&mb->changed));
        must(pthread_mutex_unlock(&mb->lock));
    }
    t->refcount--;
    int free_t = (t->refcount == 0);
    must(pthread_mutex_unlock(&t->lock));

    if (dec_mb) {
        must(pthread_mutex_lock(&mb->lock));
        mb->refcount--;
        int free_mb = (mb->refcount == 0);
        must(pthread_mutex_unlock(&mb->lock));
        if (free_mb) {
            must(pthread_cond_destroy(&mb->changed));
            must(pthread_mutex_destroy(&mb->lock));
            free(mb);
        }
    }

    if (free_t) {
        free(t->data);
        must(pthread_cond_destroy(&t->cond));
        must(pthread_mutex_destroy(&t->lock));
        free(t);
    }
    return NULL;
}

unsigned long linea_mailbox_timer(unsigned long mb_addr, unsigned long nanoseconds, unsigned long at, unsigned long len) {
    struct mailbox *mb = (struct mailbox *)mb_addr;
    struct mailbox_timer *t = (struct mailbox_timer *)malloc(sizeof(struct mailbox_timer));
    if (!t) fail("linea: timer allocation failed\n");
    t->mb = mb;
    t->nanoseconds = nanoseconds;
    t->len = len;
    t->fired = 0;
    t->cancelled = 0;
    t->refcount = 2;
    must(pthread_mutex_init(&t->lock, NULL));
#if defined(__APPLE__)
    must(pthread_cond_init(&t->cond, NULL));
#else
    pthread_condattr_t cond_attr;
    must(pthread_condattr_init(&cond_attr));
    must(pthread_condattr_setclock(&cond_attr, CLOCK_MONOTONIC));
    must(pthread_cond_init(&t->cond, &cond_attr));
    must(pthread_condattr_destroy(&cond_attr));
#endif
    if (len > 0) {
        t->data = malloc(len);
        if (!t->data) fail("linea: timer data allocation failed\n");
        memcpy(t->data, (const void *)at, len);
    } else {
        t->data = NULL;
    }
    must(pthread_mutex_lock(&mb->lock));
    mb->live_timers++;
    mb->refcount++;
    must(pthread_mutex_unlock(&mb->lock));

    if (pthread_create(&t->thread, NULL, mailbox_timer_runner, t) != 0) {
        fail("linea: timer thread creation failed\n");
    }
    pthread_detach(t->thread);
    return (unsigned long)t;
}

uint8_t linea_mailbox_timer_cancel(unsigned long timer_handle, unsigned long at, unsigned long len) {
    struct mailbox_timer *t = (struct mailbox_timer *)timer_handle;
    struct mailbox *mb = t->mb;
    uint8_t was_fired = 0;
    int dec_mb = 0;

    must(pthread_mutex_lock(&t->lock));
    if (!t->fired) {
        t->cancelled = 1;
        must(pthread_cond_broadcast(&t->cond));
        if (len > 0 && t->data) {
            memcpy((void *)at, t->data, len);
        }
        must(pthread_mutex_lock(&mb->lock));
        if (mb->live_timers > 0) mb->live_timers--;
        dec_mb = 1;
        must(pthread_cond_broadcast(&mb->changed));
        must(pthread_mutex_unlock(&mb->lock));
        was_fired = 0;
    } else {
        was_fired = 1;
    }
    t->refcount--;
    int free_t = (t->refcount == 0);
    must(pthread_mutex_unlock(&t->lock));

    if (dec_mb) {
        must(pthread_mutex_lock(&mb->lock));
        mb->refcount--;
        int free_mb = (mb->refcount == 0);
        must(pthread_mutex_unlock(&mb->lock));
        if (free_mb) {
            must(pthread_cond_destroy(&mb->changed));
            must(pthread_mutex_destroy(&mb->lock));
            free(mb);
        }
    }

    if (free_t) {
        free(t->data);
        must(pthread_cond_destroy(&t->cond));
        must(pthread_mutex_destroy(&t->lock));
        free(t);
    }
    return was_fired;
}

struct linea_worker_job {
    void (*fn)(unsigned long ctx);
    unsigned long ctx;
};

#define LINEA_WORKER_QUEUE_CAP 16384
#define LINEA_MAX_POOL_THREADS 128

static struct linea_worker_job worker_queue[LINEA_WORKER_QUEUE_CAP];
static size_t worker_queue_head = 0;
static size_t worker_queue_tail = 0;
static size_t worker_queue_count = 0;

static pthread_t worker_pool_threads[LINEA_MAX_POOL_THREADS];
static size_t worker_pool_size = 0;
static size_t active_running_workers = 0;

static pthread_mutex_t worker_pool_lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t worker_pool_not_empty = PTHREAD_COND_INITIALIZER;
static pthread_cond_t worker_pool_not_full = PTHREAD_COND_INITIALIZER;
static pthread_cond_t worker_pool_drained = PTHREAD_COND_INITIALIZER;

static void init_worker_thread(void) {
    static __thread char worker_signal_stack[65536];
    unsigned long low = 0;
#if defined(__APPLE__)
    pthread_t self = pthread_self();
    low = (unsigned long)pthread_get_stackaddr_np(self) - (unsigned long)pthread_get_stacksize_np(self);
#elif defined(__linux__)
    pthread_attr_t attributes;
    void *start = 0;
    size_t size = 0;
    if (pthread_getattr_np(pthread_self(), &attributes) == 0) {
        if (pthread_attr_getstack(&attributes, &start, &size) == 0) low = (unsigned long)start;
        (void)pthread_attr_destroy(&attributes);
    }
#endif
    const long page = sysconf(_SC_PAGESIZE);
    const unsigned long above = page > 0 ? (unsigned long)page : 4096UL;
    const unsigned long pool_guard_bytes = 1UL << 20;
    const unsigned long guard = low > pool_guard_bytes ? low - pool_guard_bytes : 0;
    const unsigned long limit = low > pool_guard_bytes ? low + above : 0;
    if (linea_thread_begin((unsigned long)worker_signal_stack, sizeof worker_signal_stack, guard, limit) != 0) {
        fail("linea: a worker thread cannot install its signal stack\n");
    }
}

static __thread unsigned long thread_worker_id = 0;
static __thread unsigned long thread_worker_slot = 0;

unsigned long linea_task_worker_id(void) {
    return thread_worker_id;
}

void linea_task_set_worker_id(unsigned long wid) {
    thread_worker_id = wid;
}

unsigned long linea_task_worker_slot(void) {
    return thread_worker_slot;
}

void linea_task_set_worker_slot(unsigned long slot) {
    thread_worker_slot = slot;
}

static void *worker_loop_run(void *arg) {
    thread_worker_id = (unsigned long)(uintptr_t)arg;
    thread_worker_slot = 0;
    init_worker_thread();
    while (1) {
        must(pthread_mutex_lock(&worker_pool_lock));
        while (worker_queue_count == 0) {
            must(pthread_cond_wait(&worker_pool_not_empty, &worker_pool_lock));
        }
        struct linea_worker_job job = worker_queue[worker_queue_head];
        worker_queue_head = (worker_queue_head + 1) % LINEA_WORKER_QUEUE_CAP;
        worker_queue_count--;
        active_running_workers++;
        must(pthread_cond_signal(&worker_pool_not_full));
        must(pthread_mutex_unlock(&worker_pool_lock));

        job.fn(job.ctx);

        must(pthread_mutex_lock(&worker_pool_lock));
        active_running_workers--;
        if (active_running_workers <= 1 && worker_queue_count == 0) {
            must(pthread_cond_broadcast(&worker_pool_drained));
        }
        must(pthread_mutex_unlock(&worker_pool_lock));
    }
    return NULL;
}

static void ensure_worker_pool_size(size_t target_size) {
    if (target_size > LINEA_MAX_POOL_THREADS) target_size = LINEA_MAX_POOL_THREADS;
    if (target_size == 0) target_size = 4;
    while (worker_pool_size < target_size) {
        must(pthread_create(&worker_pool_threads[worker_pool_size], NULL, worker_loop_run, (void *)(uintptr_t)(worker_pool_size + 1)));
        must(pthread_detach(worker_pool_threads[worker_pool_size]));
        worker_pool_size++;
    }
}

void linea_task_dispatch_worker(linea_task_worker fn, unsigned long ctx, unsigned long max_workers) {
    must(pthread_mutex_lock(&worker_pool_lock));
    size_t target = max_workers > 0 ? (size_t)max_workers : 4;
    ensure_worker_pool_size(target);
    while (worker_queue_count >= LINEA_WORKER_QUEUE_CAP) {
        must(pthread_cond_wait(&worker_pool_not_full, &worker_pool_lock));
    }
    worker_queue[worker_queue_tail].fn = fn;
    worker_queue[worker_queue_tail].ctx = ctx;
    worker_queue_tail = (worker_queue_tail + 1) % LINEA_WORKER_QUEUE_CAP;
    worker_queue_count++;
    must(pthread_cond_signal(&worker_pool_not_empty));
    must(pthread_mutex_unlock(&worker_pool_lock));
}

void linea_task_drain_workers(void) {
    must(pthread_mutex_lock(&worker_pool_lock));
    if (thread_worker_id > 0) {
        /* Called from a pool worker thread: process queue jobs inline to avoid deadlock,
         * and only wait for other workers (active_running_workers > 1) to finish. */
        while (worker_queue_count > 0 || active_running_workers > 1) {
            if (worker_queue_count > 0) {
                struct linea_worker_job job = worker_queue[worker_queue_head];
                worker_queue_head = (worker_queue_head + 1) % LINEA_WORKER_QUEUE_CAP;
                worker_queue_count--;
                must(pthread_cond_signal(&worker_pool_not_full));
                must(pthread_mutex_unlock(&worker_pool_lock));

                job.fn(job.ctx);

                must(pthread_mutex_lock(&worker_pool_lock));
                if (active_running_workers <= 1 && worker_queue_count == 0) {
                    must(pthread_cond_broadcast(&worker_pool_drained));
                }
            } else {
                must(pthread_cond_wait(&worker_pool_drained, &worker_pool_lock));
            }
        }
    } else {
        while (worker_queue_count > 0 || active_running_workers > 0) {
            must(pthread_cond_wait(&worker_pool_drained, &worker_pool_lock));
        }
    }
    must(pthread_mutex_unlock(&worker_pool_lock));
}

struct linea_conn_queue {
    pthread_mutex_t lock;
    pthread_cond_t not_empty;
    pthread_cond_t not_full;
    int fds[LINEA_WORKER_QUEUE_CAP];
    size_t head;
    size_t tail;
    size_t count;
    uint8_t closed;
};

unsigned long linea_conn_queue_open(void) {
    struct linea_conn_queue *q = malloc(sizeof(struct linea_conn_queue));
    if (!q) return 0;
    must(pthread_mutex_init(&q->lock, NULL));
    must(pthread_cond_init(&q->not_empty, NULL));
    must(pthread_cond_init(&q->not_full, NULL));
    q->head = 0;
    q->tail = 0;
    q->count = 0;
    q->closed = 0;
    return (unsigned long)(uintptr_t)q;
}

void linea_conn_queue_push(unsigned long handle, int fd) {
    struct linea_conn_queue *q = (struct linea_conn_queue *)(uintptr_t)handle;
    if (!q) return;
    must(pthread_mutex_lock(&q->lock));
    while (q->count >= LINEA_WORKER_QUEUE_CAP && !q->closed) {
        must(pthread_cond_wait(&q->not_full, &q->lock));
    }
    if (q->closed) {
        must(pthread_mutex_unlock(&q->lock));
        return;
    }
    q->fds[q->tail] = fd;
    q->tail = (q->tail + 1) % LINEA_WORKER_QUEUE_CAP;
    q->count++;
    must(pthread_cond_signal(&q->not_empty));
    must(pthread_mutex_unlock(&q->lock));
}

int linea_conn_queue_pop(unsigned long handle) {
    struct linea_conn_queue *q = (struct linea_conn_queue *)(uintptr_t)handle;
    if (!q) return -1;
    must(pthread_mutex_lock(&q->lock));
    while (q->count == 0 && !q->closed) {
        must(pthread_cond_wait(&q->not_empty, &q->lock));
    }
    if (q->count == 0 && q->closed) {
        must(pthread_mutex_unlock(&q->lock));
        return -1;
    }
    int fd = q->fds[q->head];
    q->head = (q->head + 1) % LINEA_WORKER_QUEUE_CAP;
    q->count--;
    must(pthread_cond_signal(&q->not_full));
    must(pthread_mutex_unlock(&q->lock));
    return fd;
}

void linea_conn_queue_close(unsigned long handle) {
    struct linea_conn_queue *q = (struct linea_conn_queue *)(uintptr_t)handle;
    if (!q) return;
    must(pthread_mutex_lock(&q->lock));
    q->closed = 1;
    must(pthread_cond_broadcast(&q->not_empty));
    must(pthread_cond_broadcast(&q->not_full));
    must(pthread_mutex_unlock(&q->lock));
}

void linea_conn_queue_free(unsigned long handle) {
    struct linea_conn_queue *q = (struct linea_conn_queue *)(uintptr_t)handle;
    if (!q) return;
    must(pthread_mutex_destroy(&q->lock));
    must(pthread_cond_destroy(&q->not_empty));
    must(pthread_cond_destroy(&q->not_full));
    free(q);
}

static pthread_mutex_t handler_mutex = PTHREAD_MUTEX_INITIALIZER;

void linea_handler_lock(void) {
    must(pthread_mutex_lock(&handler_mutex));
}

void linea_handler_unlock(void) {
    must(pthread_mutex_unlock(&handler_mutex));
}

struct linea_latch {
    pthread_mutex_t lock;
    pthread_cond_t cond;
    unsigned long count;
};

unsigned long linea_latch_open(unsigned long count) {
    struct linea_latch *l = (struct linea_latch *)malloc(sizeof(struct linea_latch));
    if (!l) fail("linea: latch allocation failed\n");
    l->count = count;
    must(pthread_mutex_init(&l->lock, NULL));
#if defined(__APPLE__)
    must(pthread_cond_init(&l->cond, NULL));
#else
    pthread_condattr_t cond_attr;
    must(pthread_condattr_init(&cond_attr));
    must(pthread_condattr_setclock(&cond_attr, CLOCK_MONOTONIC));
    must(pthread_cond_init(&l->cond, &cond_attr));
    must(pthread_condattr_destroy(&cond_attr));
#endif
    return (unsigned long)l;
}

void linea_latch_count_down(unsigned long handle) {
    struct linea_latch *l = (struct linea_latch *)handle;
    if (!l) return;
    must(pthread_mutex_lock(&l->lock));
    if (l->count > 0) {
        l->count--;
        if (l->count == 0) {
            must(pthread_cond_broadcast(&l->cond));
        }
    }
    must(pthread_mutex_unlock(&l->lock));
}

void linea_latch_wait(unsigned long handle) {
    struct linea_latch *l = (struct linea_latch *)handle;
    if (!l) return;
    must(pthread_mutex_lock(&l->lock));
    while (l->count > 0) {
        must(pthread_cond_wait(&l->cond, &l->lock));
    }
    must(pthread_mutex_unlock(&l->lock));
}

uint8_t linea_latch_arrive_and_wait(unsigned long handle) {
    struct linea_latch *l = (struct linea_latch *)handle;
    if (!l) return 0;
    must(pthread_mutex_lock(&l->lock));
    if (l->count > 0) {
        l->count--;
        if (l->count == 0) {
            must(pthread_cond_broadcast(&l->cond));
            must(pthread_mutex_unlock(&l->lock));
            return 1;
        }
    }
    while (l->count > 0) {
        must(pthread_cond_wait(&l->cond, &l->lock));
    }
    must(pthread_mutex_unlock(&l->lock));
    return 1;
}

uint8_t linea_latch_arrive_and_wait_timeout(unsigned long handle, unsigned long timeout_ms) {
    struct linea_latch *l = (struct linea_latch *)handle;
    if (!l) return 0;
    must(pthread_mutex_lock(&l->lock));
    if (l->count > 0) {
        l->count--;
        if (l->count == 0) {
            must(pthread_cond_broadcast(&l->cond));
            must(pthread_mutex_unlock(&l->lock));
            return 1;
        }
    }
    if (timeout_ms == 0) {
        must(pthread_mutex_unlock(&l->lock));
        return 0;
    }

    struct timespec start;
    if (clock_gettime(CLOCK_MONOTONIC, &start) != 0) {
        must(pthread_mutex_unlock(&l->lock));
        fail("linea: clock_gettime failed\n");
    }

    const uint64_t target_sec = (uint64_t)timeout_ms / 1000ULL;
    const uint64_t target_nsec = ((uint64_t)timeout_ms % 1000ULL) * 1000000ULL;

    while (l->count > 0) {
        struct timespec now;
        if (clock_gettime(CLOCK_MONOTONIC, &now) != 0) {
            must(pthread_mutex_unlock(&l->lock));
            fail("linea: clock_gettime failed\n");
        }

        uint64_t elapsed_sec = 0;
        uint64_t elapsed_nsec = 0;
        if (now.tv_sec > start.tv_sec || (now.tv_sec == start.tv_sec && now.tv_nsec >= start.tv_nsec)) {
            if (now.tv_nsec >= start.tv_nsec) {
                elapsed_sec = (uint64_t)(now.tv_sec - start.tv_sec);
                elapsed_nsec = (uint64_t)(now.tv_nsec - start.tv_nsec);
            } else {
                elapsed_sec = (uint64_t)(now.tv_sec - start.tv_sec - 1);
                elapsed_nsec = (uint64_t)(now.tv_nsec + 1000000000L - start.tv_nsec);
            }
        }

        if (elapsed_sec > target_sec || (elapsed_sec == target_sec && elapsed_nsec >= target_nsec)) {
            must(pthread_mutex_unlock(&l->lock));
            return 0;
        }

        uint64_t rem_sec = 0;
        uint64_t rem_nsec = 0;
        if (target_nsec >= elapsed_nsec) {
            rem_sec = target_sec - elapsed_sec;
            rem_nsec = target_nsec - elapsed_nsec;
        } else {
            rem_sec = target_sec - elapsed_sec - 1;
            rem_nsec = target_nsec + 1000000000ULL - elapsed_nsec;
        }

        /* Cap single wait interval to at most 86400 seconds (1 day) to prevent
         * any integer overflow in time_t, long, or kernel timeout representation. */
        const uint64_t max_step_sec = 86400ULL;
        uint64_t step_sec = rem_sec;
        uint64_t step_nsec = rem_nsec;
        if (step_sec > max_step_sec) {
            step_sec = max_step_sec;
            step_nsec = 0;
        }

#if defined(__APPLE__)
        struct timespec rel_timeout;
        rel_timeout.tv_sec = (time_t)step_sec;
        rel_timeout.tv_nsec = (long)step_nsec;
        int rc = pthread_cond_timedwait_relative_np(&l->cond, &l->lock, &rel_timeout);
#else
        struct timespec deadline;
        deadline.tv_sec = now.tv_sec + (time_t)step_sec;
        deadline.tv_nsec = now.tv_nsec + (long)step_nsec;
        if (deadline.tv_nsec >= 1000000000L) {
            deadline.tv_sec += 1;
            deadline.tv_nsec -= 1000000000L;
        }
        int rc = pthread_cond_timedwait(&l->cond, &l->lock, &deadline);
#endif
        if (rc == ETIMEDOUT) {
            continue;
        }
        if (rc != 0 && rc != EINTR) {
            must(pthread_mutex_unlock(&l->lock));
            fail("linea: latch condition timedwait failed\n");
        }
    }
    must(pthread_mutex_unlock(&l->lock));
    return 1;
}

void linea_latch_free(unsigned long handle) {
    struct linea_latch *l = (struct linea_latch *)handle;
    if (!l) return;
    must(pthread_mutex_destroy(&l->lock));
    must(pthread_cond_destroy(&l->cond));
    free(l);
}

static struct linea_latch *test_hold_latch = NULL;
static struct linea_latch *test_start_latch = NULL;

void linea_test_net_latch_init(void) {
    if (test_hold_latch) linea_latch_free((unsigned long)test_hold_latch);
    if (test_start_latch) linea_latch_free((unsigned long)test_start_latch);
    test_hold_latch = (struct linea_latch *)linea_latch_open(1);
    test_start_latch = (struct linea_latch *)linea_latch_open(1);
}

void linea_test_net_latch_signal_started(void) {
    if (test_start_latch) linea_latch_count_down((unsigned long)test_start_latch);
}

void linea_test_net_latch_wait_started(void) {
    if (test_start_latch) linea_latch_wait((unsigned long)test_start_latch);
}

void linea_test_net_latch_wait_hold(void) {
    if (test_hold_latch) linea_latch_wait((unsigned long)test_hold_latch);
}

void linea_test_net_latch_release_hold(void) {
    if (test_hold_latch) linea_latch_count_down((unsigned long)test_hold_latch);
}

void linea_test_net_latch_cleanup(void) {
    if (test_hold_latch) {
        linea_latch_free((unsigned long)test_hold_latch);
        test_hold_latch = NULL;
    }
    if (test_start_latch) {
        linea_latch_free((unsigned long)test_start_latch);
        test_start_latch = NULL;
    }
}

