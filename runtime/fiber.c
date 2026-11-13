#define _GNU_SOURCE
#define _DARWIN_C_SOURCE
#include "fiber.h"
#include "foreign.h"
#include "fiber_pause.h"

#include "context.h"
#include "loop.h"
#include "park.h"
#include "sim.h"
#include "op.h"
#include "pipe_signal.h"

#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <pthread.h>
#include <poll.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>
#if defined(__linux__)
#include <sys/epoll.h>
#include <sys/eventfd.h>
#else
#include <sys/event.h>
#endif

#ifndef __has_feature
#define __has_feature(x) 0
#endif
#if __has_feature(address_sanitizer)
void __sanitizer_start_switch_fiber(void **save, const void *bottom, size_t size);
void __sanitizer_finish_switch_fiber(void *save, const void **bottom, size_t *size);
#endif
#if __has_feature(thread_sanitizer)
void *__tsan_create_fiber(unsigned flags);
void __tsan_destroy_fiber(void *fiber);
void *__tsan_get_current_fiber(void);
void __tsan_switch_to_fiber(void *fiber, unsigned flags);
#endif

int linea_thread_begin(unsigned long at, unsigned long bytes, unsigned long low, unsigned long high);
void linea_thread_end(void);
void linea_thread_guard_prepare(unsigned long low, unsigned long high);
void linea_thread_guard_commit(void);
void linea_thread_guard_bounds(unsigned long *low, unsigned long *high);

static const unsigned long guard_bytes = 65536;
static const unsigned long signal_bytes = 65536;
static const size_t no_timer = (size_t)-1;

enum scheduling { running, parking, parked, notified, runnable, finished };
enum waiting { waiting_none, waiting_park, waiting_yield, waiting_io };

struct carrier;
struct fiber_loop;
struct pending_operation;
struct io_slot {
    uint32_t generation;
    uint32_t next_free;
    struct pending_operation *operation;
    int fd;
    uint8_t writable;
};

enum { io_slots_per_page = 64 };
enum operation_state { operation_idle, operation_armed, operation_claimed, operation_complete };
struct pending_operation {
    struct linea_op *operation;
    long (*attempt)(struct linea_op *);
    struct linea_fiber *fiber;
    unsigned state;
    uint32_t slot;
    int registered;
    long result;
    struct pending_operation *next;
};

struct linea_fiber_waiter {
    struct linea_fiber_waiter *next;
    struct linea_fiber *fiber;
    int linked;
    int expired;
    int root_woken;
};

struct linea_fiber {
    struct linea_context context;
    struct carrier *home;
    struct linea_fiber *next;
    unsigned state;
    enum waiting waiting;
    struct linea_park *park;
    struct linea_fiber_waiter *waiter;
    struct pending_operation *operation;
    unsigned long deadline;
    size_t timer_index;
    void *mapping;
    unsigned long mapping_bytes;
    void *stack;
    unsigned long stack_bytes;
    void (*entry)(void *);
    void (*finished)(void *);
    void *argument;
    void *asan_stack;
    void *tsan_fiber;
};

struct carrier {
    struct fiber_loop *loop;
    unsigned long simulation;
    unsigned long scheduler_guard_low, scheduler_guard_high;
    struct carrier *previous;
    struct linea_fiber **ready;
    size_t ready_count, ready_capacity, live;
    struct pending_operation *pending;
    pthread_t thread;
    struct linea_context scheduler;
    struct linea_fiber *executing;
    pthread_mutex_t queue_lock;
    struct linea_fiber *first, *last;
    struct linea_fiber **timers;
    size_t timer_count, timer_capacity;
    int kernel;
    int wake;
    struct io_slot **pages;
    size_t page_count;
    uint32_t slots_made;
    uint32_t first_free;
    int begin_error;
    void *signal_stack;
    void *stack;
    size_t stack_bytes;
    void *asan_stack;
    void *tsan_fiber;
};

struct fiber_loop {
    unsigned long identity;
    unsigned long count;
    unsigned long next;
    struct carrier *carriers;
    pthread_mutex_t startup_lock;
    pthread_cond_t startup;
    unsigned long began;
    int stop;
};

/* A pthread slot, rather than C TLS, keeps fault handling allocation-free. */
static pthread_key_t carrier_key;
static pthread_once_t carrier_once = PTHREAD_ONCE_INIT;

static void fail(const char *message) {
    report_bytes(message, strlen(message));
    abort();
}

static void must(int status) {
    if (status != 0) fail("linea: a carrier's synchronization failed\n");
}

static void make_carrier_key(void) {
    must(pthread_key_create(&carrier_key, NULL));
}

static struct carrier *current_carrier(void) {
    must(pthread_once(&carrier_once, make_carrier_key));
    return pthread_getspecific(carrier_key);
}

static struct linea_fiber *current_fiber(void) {
    struct carrier *c = current_carrier();
    return c == NULL ? NULL : c->executing;
}

int linea_fiber_active(void) {
    return current_fiber() != NULL && linea_foreign_depth() == 0;
}

static unsigned long now(void) {
    if (linea_sim_running()) return linea_sim_now();
    struct timespec instant;
    if (clock_gettime(CLOCK_MONOTONIC, &instant) != 0) fail("linea: a carrier's clock failed\n");
    return (unsigned long)instant.tv_sec * 1000000000UL + (unsigned long)instant.tv_nsec;
}

static void wake_carrier(struct carrier *c) {
    if (c->simulation != 0) return;
#if defined(__linux__)
    const uint64_t one = 1;
    ssize_t count;
    do { count = write(c->wake, &one, sizeof one); } while (count < 0 && errno == EINTR);
    if (count < 0 && errno != EAGAIN) fail("linea: a carrier could not be woken\n");
#else
    struct kevent event;
    EV_SET(&event, 1, EVFILT_USER, 0, NOTE_TRIGGER, 0, NULL);
    int result;
    do { result = kevent(c->kernel, &event, 1, NULL, 0, NULL); } while (result < 0 && errno == EINTR);
    if (result < 0) fail("linea: a carrier could not be woken\n");
#endif
}

static void enqueue(struct linea_fiber *f) {
    struct carrier *c = f->home;
    must(pthread_mutex_lock(&c->queue_lock));
    if (c->simulation != 0) {
        if (c->ready_count == c->ready_capacity) {
            size_t capacity = c->ready_capacity == 0 ? 16 : c->ready_capacity * 2;
            if (capacity < c->ready_capacity || capacity > SIZE_MAX / sizeof *c->ready) fail("linea: a simulation's run queue is too large\n");
            void *ready = realloc(c->ready, capacity * sizeof *c->ready);
            if (ready == NULL) fail("linea: a simulation's run queue could not be allocated\n");
            c->ready = ready; c->ready_capacity = capacity;
        }
        c->ready[c->ready_count++] = f;
        must(pthread_mutex_unlock(&c->queue_lock));
        return;
    }
    f->next = NULL;
    if (c->last == NULL) c->first = f;
    else c->last->next = f;
    c->last = f;
    must(pthread_mutex_unlock(&c->queue_lock));
    wake_carrier(c);
}

static struct linea_fiber *dequeue(struct carrier *c) {
    must(pthread_mutex_lock(&c->queue_lock));
    if (c->simulation != 0) {
        struct linea_fiber *chosen = NULL;
        if (c->ready_count != 0) {
            size_t index = (size_t)linea_sim_choice((unsigned long)c->ready_count);
            chosen = c->ready[index];
            c->ready[index] = c->ready[--c->ready_count];
        }
        must(pthread_mutex_unlock(&c->queue_lock));
        return chosen;
    }
    struct linea_fiber *f = c->first;
    if (f != NULL) {
        c->first = f->next;
        if (c->first == NULL) c->last = NULL;
        f->next = NULL;
    }
    must(pthread_mutex_unlock(&c->queue_lock));
    return f;
}

/* Only a saved context is queued. A notification during the switch records
 * Notified; the saving carrier is then the only party allowed to queue it. */
static void notify(struct linea_fiber *f) {
    unsigned state = __atomic_load_n(&f->state, __ATOMIC_ACQUIRE);
    for (;;) {
        unsigned next;
        if (state == parking) next = notified;
        else if (state == parked) next = runnable;
        else return;
        if (__atomic_compare_exchange_n(&f->state, &state, next, 0, __ATOMIC_ACQ_REL, __ATOMIC_ACQUIRE)) {
            if (next == runnable) enqueue(f);
            return;
        }
    }
}

static void timer_exchange(struct carrier *c, size_t a, size_t b) {
    struct linea_fiber *first = c->timers[a];
    c->timers[a] = c->timers[b];
    c->timers[b] = first;
    c->timers[a]->timer_index = a;
    c->timers[b]->timer_index = b;
}

static void timer_up(struct carrier *c, size_t i) {
    while (i != 0) {
        const size_t parent = (i - 1) / 2;
        if (c->timers[parent]->deadline <= c->timers[i]->deadline) break;
        timer_exchange(c, parent, i);
        i = parent;
    }
}

static void timer_remove(struct linea_fiber *f) {
    struct carrier *c = f->home;
    const size_t i = f->timer_index;
    if (i == no_timer) return;
    f->timer_index = no_timer;
    c->timer_count -= 1;
    if (i == c->timer_count) return;
    c->timers[i] = c->timers[c->timer_count];
    c->timers[i]->timer_index = i;
    if (i != 0 && c->timers[i]->deadline < c->timers[(i - 1) / 2]->deadline) {
        timer_up(c, i);
        return;
    }
    size_t at = i;
    for (;;) {
        size_t smaller = at;
        const size_t left = at * 2 + 1;
        const size_t right = left + 1;
        if (left < c->timer_count && c->timers[left]->deadline < c->timers[smaller]->deadline) smaller = left;
        if (right < c->timer_count && c->timers[right]->deadline < c->timers[smaller]->deadline) smaller = right;
        if (smaller == at) break;
        timer_exchange(c, at, smaller);
        at = smaller;
    }
}

static int timer_add(struct linea_fiber *f) {
    struct carrier *c = f->home;
    if (f->deadline == 0) return 0;
    if (c->timer_count == c->timer_capacity) {
        const size_t capacity = c->timer_capacity == 0 ? 16 : c->timer_capacity * 2;
        if (capacity < c->timer_capacity || capacity > SIZE_MAX / sizeof *c->timers) return ENOMEM;
        struct linea_fiber **timers = realloc(c->timers, capacity * sizeof *timers);
        if (timers == NULL) return ENOMEM;
        c->timers = timers;
        c->timer_capacity = capacity;
    }
    f->timer_index = c->timer_count;
    c->timers[c->timer_count++] = f;
    timer_up(c, f->timer_index);
    return 0;
}

static void unlink_waiter(struct linea_park *p, struct linea_fiber_waiter *w) {
    if (!w->linked) return;
    struct linea_fiber_waiter **at = &p->fibers;
    while (*at != w) {
        if (*at == NULL) fail("linea: a fiber's park lost its waiter\n");
        at = &(*at)->next;
    }
    *at = w->next;
    w->linked = 0;
}

void linea_fiber_unpark(struct linea_park *p) {
    while (p->fibers != NULL) {
        struct linea_fiber_waiter *w = p->fibers;
        p->fibers = w->next;
        w->linked = 0;
        if (w->fiber == NULL) w->root_woken = 1;
        else notify(w->fiber);
    }
}

static void complete_operation(struct pending_operation *pending, int readable);

static void expire_timers(struct carrier *c) {
    const unsigned long instant = now();
    while (c->timer_count != 0 && c->timers[0]->deadline <= instant) {
        struct linea_fiber *f = c->timers[0];
        timer_remove(f);
        if (f->waiting == waiting_io) {
            complete_operation(f->operation, 0);
            continue;
        }
        linea_park_lock(f->park);
        struct linea_fiber_waiter *w = f->waiter;
        if (w->linked) {
            unlink_waiter(f->park, w);
            w->expired = 1;
            notify(f);
        }
        linea_park_unlock(f->park);
    }
}

static void finish_switch(void *asan_stack) {
#if __has_feature(address_sanitizer)
    __sanitizer_finish_switch_fiber(asan_stack, NULL, NULL);
#else
    (void)asan_stack;
#endif
    linea_thread_guard_commit();
}

static void leave_fiber(struct linea_fiber *f, int ending) {
    struct carrier *c = f->home;
    linea_thread_guard_prepare(c->scheduler_guard_low, c->scheduler_guard_high);
    if (ending) linea_fiber_pause(linea_fiber_finishing);
#if __has_feature(address_sanitizer)
    __sanitizer_start_switch_fiber(ending ? NULL : &f->asan_stack, c->stack, c->stack_bytes);
#else
    (void)ending;
#endif
#if __has_feature(thread_sanitizer)
    __tsan_switch_to_fiber(c->tsan_fiber, 0);
#endif
    if (f->waiting == waiting_park) linea_fiber_pause(linea_fiber_before_switch);
    linea_context_switch(&f->context, &c->scheduler);
    finish_switch(f->asan_stack);
}

void linea_fiber_yield(void) {
    struct linea_fiber *f = current_fiber();
    if (f == NULL || linea_foreign_depth() != 0) return;
    f->waiting = waiting_yield;
    __atomic_store_n(&f->state, parking, __ATOMIC_RELEASE);
    leave_fiber(f, 0);
    f->waiting = waiting_none;
}

int linea_fiber_park(struct linea_park *p, unsigned long deadline) {
    struct linea_fiber *f = current_fiber();
    if (f == NULL) fail("linea: a fiber park has no executing fiber\n");
    if (deadline != 0 && now() >= deadline) {
        linea_park_unlock(p);
        linea_fiber_yield();
        linea_park_lock(p);
        return 1;
    }
    struct linea_fiber_waiter waiter = { .next = p->fibers, .fiber = f, .linked = 1, .expired = 0 };
    f->waiting = waiting_park;
    f->park = p;
    f->waiter = &waiter;
    f->deadline = deadline;
    if (timer_add(f) != 0) fail("linea: a fiber's deadline could not be allocated\n");
    __atomic_store_n(&f->state, parking, __ATOMIC_RELEASE);
    p->fibers = &waiter;
    linea_park_unlock(p);
    leave_fiber(f, 0);
    linea_park_lock(p);
    unlink_waiter(p, &waiter);
    f->park = NULL;
    f->waiter = NULL;
    f->waiting = waiting_none;
    return waiter.expired;
}

static void fiber_entry(void *argument) {
    struct linea_fiber *f = argument;
    finish_switch(f->asan_stack);
    f->entry(f->argument);
    __atomic_store_n(&f->state, finished, __ATOMIC_RELEASE);
    leave_fiber(f, 1);
    fail("linea: a finished fiber resumed\n");
}

static int make_poller(struct carrier *c) {
    c->kernel = -1;
    c->wake = -1;
#if defined(__linux__)
    c->kernel = epoll_create1(EPOLL_CLOEXEC);
    if (c->kernel < 0) return errno;
    c->wake = eventfd(0, EFD_CLOEXEC | EFD_NONBLOCK);
    if (c->wake < 0) return errno;
    struct epoll_event event;
    memset(&event, 0, sizeof event);
    event.events = EPOLLIN;
    event.data.u64 = UINT64_MAX;
    if (epoll_ctl(c->kernel, EPOLL_CTL_ADD, c->wake, &event) != 0) return errno;
#else
    c->kernel = kqueue();
    if (c->kernel < 0) return errno;
    struct kevent event;
    EV_SET(&event, 1, EVFILT_USER, EV_ADD | EV_CLEAR, 0, 0, NULL);
    if (kevent(c->kernel, &event, 1, NULL, 0, NULL) != 0) return errno;
#endif
    return 0;
}

static struct io_slot *io_slot_at(struct carrier *c, uint32_t index) {
    return &c->pages[index / io_slots_per_page][index % io_slots_per_page];
}

/* Releasing a reserved slot does not imply that the kernel accepted its watch. */
static void release_slot(struct pending_operation *pending) {
    struct carrier *c = pending->fiber->home;
    struct io_slot *slot = io_slot_at(c, pending->slot);
    pending->registered = 0;
    slot->operation = NULL;
    if (slot->fd >= 0 && close(slot->fd) != 0) fail("linea: an operation's watch descriptor could not be closed\n");
    slot->fd = -1;
    if (slot->generation != UINT32_MAX) {
        slot->generation += 1;
        slot->next_free = c->first_free;
        c->first_free = pending->slot + 1;
    }
}

static void disarm_operation(struct pending_operation *pending) {
    if (!pending->registered) return;
    struct carrier *c = pending->fiber->home;
    if (c->simulation != 0) {
        struct pending_operation **at = &c->pending;
        while (*at != NULL && *at != pending) at = &(*at)->next;
        if (*at == pending) *at = pending->next;
        pending->registered = 0;
        return;
    }
    struct io_slot *slot = io_slot_at(c, pending->slot);
#if defined(__linux__)
    if (epoll_ctl(c->kernel, EPOLL_CTL_DEL, slot->fd, NULL) != 0 && errno != ENOENT && errno != EBADF) {
        fail("linea: a carrier's operation could not be disarmed\n");
    }
#else
    struct kevent event;
    EV_SET(&event, (uintptr_t)slot->fd, slot->writable ? EVFILT_WRITE : EVFILT_READ, EV_DELETE, 0, 0, NULL);
    int answer;
    do { answer = kevent(c->kernel, &event, 1, NULL, 0, NULL); } while (answer < 0 && errno == EINTR);
    if (answer < 0 && errno != ENOENT && errno != EBADF) fail("linea: a carrier's operation could not be disarmed\n");
#endif
    release_slot(pending);
}

static int arm_operation(struct pending_operation *pending) {
    struct carrier *c = pending->fiber->home;
    if (c->simulation != 0) {
        pending->next = c->pending;
        c->pending = pending;
        pending->registered = 1;
        return 0;
    }
    if (pending->operation->kind == LINEA_OP_SLEEP) return 0;
    uint32_t index;
    if (c->first_free != 0) {
        index = c->first_free - 1;
        c->first_free = io_slot_at(c, index)->next_free;
    } else {
        if (c->slots_made == UINT32_MAX - 1) return ENOMEM;
        if (c->slots_made % io_slots_per_page == 0) {
            const size_t count = c->page_count + 1;
            if (count > SIZE_MAX / sizeof *c->pages) return ENOMEM;
            struct io_slot **pages = realloc(c->pages, count * sizeof *pages);
            if (pages == NULL) return ENOMEM;
            c->pages = pages;
            struct io_slot *page = calloc(io_slots_per_page, sizeof *page);
            if (page == NULL) return ENOMEM;
            c->pages[c->page_count++] = page;
        }
        index = c->slots_made++;
        io_slot_at(c, index)->generation = 1;
    }
    struct io_slot *slot = io_slot_at(c, index);
    const enum linea_op_kind kind = pending->operation->kind;
    slot->operation = pending;
    /* Distinct waits may borrow the same socket. Each watch needs its own
     * descriptor: kqueue replaces a watch with the same fd/filter, and epoll
     * refuses a second ADD for the same descriptor. */
    do { slot->fd = fcntl(pending->operation->fd, F_DUPFD_CLOEXEC, 0); } while (slot->fd < 0 && errno == EINTR);
    slot->writable = (uint8_t)(kind == LINEA_OP_WRITE || kind == LINEA_OP_CONNECT || kind == LINEA_OP_WRITABLE);
    pending->slot = index;
    pending->registered = 1;
    if (slot->fd < 0) {
        const int error = errno;
        release_slot(pending);
        return error;
    }
    const uint64_t cookie = ((uint64_t)index << 32) | slot->generation;
    int error = 0;
#if defined(__linux__)
    struct epoll_event event;
    memset(&event, 0, sizeof event);
    event.events = (uint32_t)(slot->writable ? EPOLLOUT : EPOLLIN) | EPOLLONESHOT;
    event.data.u64 = cookie;
    if (epoll_ctl(c->kernel, EPOLL_CTL_ADD, slot->fd, &event) != 0) error = errno;
#else
    struct kevent event;
    EV_SET(&event, (uintptr_t)slot->fd, slot->writable ? EVFILT_WRITE : EVFILT_READ,
           EV_ADD | EV_ONESHOT, 0, 0, (void *)(uintptr_t)cookie);
    int answer;
    do { answer = kevent(c->kernel, &event, 1, NULL, 0, NULL); } while (answer < 0 && errno == EINTR);
    if (answer < 0) error = errno;
#endif
    if (error != 0) release_slot(pending);
    return error;
}

/* Readiness-only operations consume nothing. A zero-time poll is also how a
 * timeout claimant observes a readiness/expiry tie without consuming bytes. */
static long attempt_operation(struct pending_operation *pending) {
    if (pending->attempt != NULL) return pending->attempt(pending->operation);
    const enum linea_op_kind kind = pending->operation->kind;
    if (kind == LINEA_OP_SLEEP) return -(long)EAGAIN;
    if (pending->fiber->home->simulation != 0) return linea_sim_ready(pending->operation->fd, (uint8_t)(kind == LINEA_OP_WRITABLE)) ? 0 : -(long)EAGAIN;
    struct pollfd fd = { pending->operation->fd, kind == LINEA_OP_WRITABLE ? POLLOUT : POLLIN, 0 };
    int answer;
    do { answer = poll(&fd, 1, 0); } while (answer < 0 && errno == EINTR);
    if (answer < 0) return -(long)errno;
    return answer == 0 ? -(long)EAGAIN : 0;
}

static void complete_operation(struct pending_operation *pending, int readable) {
    unsigned expected = operation_armed;
    if (!__atomic_compare_exchange_n(&pending->state, &expected, operation_claimed, 0, __ATOMIC_ACQ_REL, __ATOMIC_ACQUIRE)) return;
    struct linea_fiber *f = pending->fiber;
    const unsigned long deadline = pending->operation->deadline_ns;
    long result = attempt_operation(pending);
    const int expired = deadline != 0 && now() >= deadline;
    if (result == -(long)EAGAIN && !expired && readable) {
        /* A readiness notification can be stale without completing the
         * operation. Its next arming gets a new generation. */
        if (f->home->simulation != 0) {
            __atomic_store_n(&pending->state, operation_armed, __ATOMIC_RELEASE);
            return;
        }
        disarm_operation(pending);
        const int error = arm_operation(pending);
        if (error == 0) {
            __atomic_store_n(&pending->state, operation_armed, __ATOMIC_RELEASE);
            return;
        }
        result = -(long)error;
    }
    if (result == -(long)EAGAIN) result = -(long)ETIMEDOUT;
    if (pending->operation->kind == LINEA_OP_SLEEP) result = 0;
    disarm_operation(pending);
    timer_remove(f);
    pending->result = result;
    __atomic_store_n(&pending->state, operation_complete, __ATOMIC_RELEASE);
    notify(f);
}

long linea_fiber_perform(struct linea_op *op, linea_fiber_attempt attempt) {
    struct linea_fiber *f = current_fiber();
    if (f == NULL) fail("linea: an operation has no executing fiber\n");
    if (op->deadline_ns != 0 && now() >= op->deadline_ns) return op->kind == LINEA_OP_SLEEP ? 0 : -(long)ETIMEDOUT;
    struct pending_operation pending = { .operation = op, .attempt = attempt, .fiber = f,
        .state = operation_idle, .slot = 0, .registered = 0, .result = 0 };
    const long immediate = attempt_operation(&pending);
    if (immediate != -(long)EAGAIN) return immediate;
    f->waiting = waiting_io;
    f->operation = &pending;
    f->deadline = op->deadline_ns;
    __atomic_store_n(&f->state, parking, __ATOMIC_RELEASE);
    int error = arm_operation(&pending);
    if (error == 0) error = timer_add(f);
    if (error != 0) {
        disarm_operation(&pending);
        __atomic_store_n(&f->state, running, __ATOMIC_RELEASE);
        f->waiting = waiting_none;
        f->operation = NULL;
        return -(long)error;
    }
    __atomic_store_n(&pending.state, operation_armed, __ATOMIC_RELEASE);
    leave_fiber(f, 0);
    if (__atomic_load_n(&pending.state, __ATOMIC_ACQUIRE) != operation_complete) fail("linea: an incomplete operation resumed\n");
    f->waiting = waiting_none;
    f->operation = NULL;
    return pending.result;
}

long linea_fiber_wait_descriptor(int fd, uint8_t writable, unsigned long deadline) {
    struct linea_op op = { writable ? LINEA_OP_WRITABLE : LINEA_OP_READABLE, fd, 0, 0, 0, deadline };
    return linea_fiber_perform(&op, NULL);
}

long linea_fiber_sleep(unsigned long nanoseconds) {
    if (nanoseconds == 0) { linea_fiber_yield(); return 0; }
    const unsigned long instant = now();
    const unsigned long deadline = nanoseconds > ULONG_MAX - instant ? ULONG_MAX : instant + nanoseconds;
    struct linea_op op = { LINEA_OP_SLEEP, -1, 0, 0, 0, deadline };
    return linea_fiber_perform(&op, NULL);
}

static void poll_carrier(struct carrier *c, int poll_only) {
    enum { batch = 32 };
    const unsigned long deadline = c->timer_count == 0 ? 0 : c->timers[0]->deadline;
    uint64_t cookies[batch];
#if defined(__linux__)
    struct epoll_event events[batch];
    int timeout = poll_only ? 0 : -1;
    if (!poll_only && deadline != 0) {
        const unsigned long instant = now();
        const unsigned long remaining = deadline > instant ? deadline - instant : 0;
        const unsigned long ms = remaining / 1000000UL + (remaining % 1000000UL != 0);
        timeout = ms > (unsigned long)INT_MAX ? INT_MAX : (int)ms;
    }
    const int count = epoll_wait(c->kernel, events, batch, timeout);
    for (int i = 0; i < count; i += 1) cookies[i] = events[i].data.u64;
#else
    struct kevent events[batch];
    struct timespec timeout = { 0, 0 };
    struct timespec *limit = poll_only ? &timeout : NULL;
    if (!poll_only && deadline != 0) {
        const unsigned long instant = now();
        unsigned long remaining = deadline > instant ? deadline - instant : 0;
        if (remaining > 86400000000000UL) remaining = 86400000000000UL;
        timeout.tv_sec = (time_t)(remaining / 1000000000UL);
        timeout.tv_nsec = (long)(remaining % 1000000000UL);
        limit = &timeout;
    }
    const int count = kevent(c->kernel, NULL, 0, events, batch, limit);
    for (int i = 0; i < count; i += 1) cookies[i] = events[i].filter == EVFILT_USER ? UINT64_MAX : (uint64_t)(uintptr_t)events[i].udata;
#endif
    if (count < 0 && errno != EINTR) fail("linea: a carrier's poller failed\n");
    for (int i = 0; i < count; i += 1) {
        const uint64_t cookie = cookies[i];
        if (cookie == UINT64_MAX) {
#if defined(__linux__)
            uint64_t posted;
            ssize_t read_count;
            do { read_count = read(c->wake, &posted, sizeof posted); } while (read_count < 0 && errno == EINTR);
#endif
            continue;
        }
        const uint32_t index = (uint32_t)(cookie >> 32);
        if (index >= c->slots_made) continue;
        struct io_slot *slot = io_slot_at(c, index);
        if (slot->generation != (uint32_t)cookie || slot->operation == NULL) continue;
        complete_operation(slot->operation, 1);
    }
}

static void run_fiber(struct carrier *c, struct linea_fiber *f) {
    timer_remove(f);
    unsigned expected = runnable;
    if (!__atomic_compare_exchange_n(&f->state, &expected, running, 0, __ATOMIC_ACQ_REL, __ATOMIC_ACQUIRE)) {
        fail("linea: a carrier dequeued a fiber that was not runnable\n");
    }
    c->executing = f;
    linea_thread_guard_prepare((unsigned long)f->mapping, (unsigned long)f->mapping + guard_bytes);
    linea_fiber_pause(linea_fiber_entering);
#if __has_feature(address_sanitizer)
    __sanitizer_start_switch_fiber(&c->asan_stack, f->stack, f->stack_bytes);
#endif
#if __has_feature(thread_sanitizer)
    __tsan_switch_to_fiber(f->tsan_fiber, 0);
#endif
    linea_context_switch(&c->scheduler, &f->context);
    finish_switch(c->asan_stack);
    c->executing = NULL;
    if (f->waiting == waiting_park) linea_fiber_pause(linea_fiber_context_saved);
    expected = parking;
    if (__atomic_compare_exchange_n(&f->state, &expected, parked, 0, __ATOMIC_ACQ_REL, __ATOMIC_ACQUIRE)) {
        if (f->waiting == waiting_park) linea_fiber_pause(linea_fiber_parked);
        if (f->waiting == waiting_yield) notify(f);
    } else if (expected == notified) {
        expected = notified;
        if (!__atomic_compare_exchange_n(&f->state, &expected, runnable, 0, __ATOMIC_ACQ_REL, __ATOMIC_ACQUIRE)) {
            fail("linea: a notified fiber changed before its context was saved\n");
        }
        enqueue(f);
    } else if (expected == finished) {
        /* The callback can wake a joiner that immediately frees f. */
        f->finished(f->argument);
    } else {
        fail("linea: a fiber switched in an invalid scheduling state\n");
    }
}

static void *run_carrier(void *argument) {
    struct carrier *c = argument;
    must(pthread_once(&carrier_once, make_carrier_key));
    must(pthread_setspecific(carrier_key, c));
    c->begin_error = linea_thread_begin((unsigned long)c->signal_stack, signal_bytes, 0, 0);
#if defined(__APPLE__)
    c->stack_bytes = pthread_get_stacksize_np(pthread_self());
    c->stack = (char *)pthread_get_stackaddr_np(pthread_self()) - c->stack_bytes;
#else
    pthread_attr_t attributes;
    must(pthread_getattr_np(pthread_self(), &attributes));
    must(pthread_attr_getstack(&attributes, &c->stack, &c->stack_bytes));
    must(pthread_attr_destroy(&attributes));
#endif
#if __has_feature(thread_sanitizer)
    c->tsan_fiber = __tsan_get_current_fiber();
#endif
    must(pthread_mutex_lock(&c->loop->startup_lock));
    c->loop->began += 1;
    must(pthread_cond_signal(&c->loop->startup));
    must(pthread_mutex_unlock(&c->loop->startup_lock));
    if (c->begin_error != 0) return NULL;
    (void)linea_io_switch(c->loop->identity);
    while (!__atomic_load_n(&c->loop->stop, __ATOMIC_ACQUIRE)) {
        expire_timers(c);
        struct linea_fiber *f = dequeue(c);
        if (f == NULL) {
            poll_carrier(c, 0);
        } else {
            poll_carrier(c, 1);
            run_fiber(c, f);
        }
    }
    (void)linea_io_switch(0);
    linea_thread_end();
    must(pthread_setspecific(carrier_key, NULL));
    return NULL;
}

static void free_carrier(struct carrier *c) {
    free(c->ready);
    if (c->wake >= 0) (void)close(c->wake);
    if (c->kernel >= 0) (void)close(c->kernel);
    if (c->signal_stack != NULL) (void)munmap(c->signal_stack, signal_bytes);
    free(c->timers);
    for (size_t i = 0; i < c->page_count; i += 1) free(c->pages[i]);
    free(c->pages);
    must(pthread_mutex_destroy(&c->queue_lock));
}

long linea_loop_open(unsigned long carriers) {
    if (carriers == 0) return -(long)EINVAL;
    if (carriers > SIZE_MAX / sizeof(struct carrier)) return -(long)ENOMEM;
    struct fiber_loop *loop = calloc(1, sizeof *loop);
    if (loop == NULL) return -(long)ENOMEM;
    loop->carriers = calloc(carriers, sizeof *loop->carriers);
    if (loop->carriers == NULL) { free(loop); return -(long)ENOMEM; }
    int error = pthread_mutex_init(&loop->startup_lock, NULL);
    if (error != 0) { free(loop->carriers); free(loop); return -(long)error; }
    error = pthread_cond_init(&loop->startup, NULL);
    if (error != 0) {
        must(pthread_mutex_destroy(&loop->startup_lock));
        free(loop->carriers); free(loop); return -(long)error;
    }
    unsigned long initialized = 0, started = 0;
    loop->count = carriers;
    loop->identity = linea_loop_claim_kind(loop, LINEA_LOOP_FIBERS);
    if (loop->identity == 0) { error = ENOMEM; goto cleanup; }
    for (; initialized < carriers; initialized += 1) {
        struct carrier *c = &loop->carriers[initialized];
        c->loop = loop;
        c->kernel = -1; c->wake = -1;
        error = pthread_mutex_init(&c->queue_lock, NULL);
        if (error != 0) goto cleanup;
        error = make_poller(c);
        if (error != 0) { initialized += 1; goto cleanup; }
        c->signal_stack = mmap(NULL, signal_bytes, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0);
        if (c->signal_stack == MAP_FAILED) {
            c->signal_stack = NULL; error = errno; initialized += 1; goto cleanup;
        }
    }
    for (; started < carriers; started += 1) {
        error = pthread_create(&loop->carriers[started].thread, NULL, run_carrier, &loop->carriers[started]);
        if (error != 0) goto cleanup;
    }
    must(pthread_mutex_lock(&loop->startup_lock));
    while (loop->began < carriers) must(pthread_cond_wait(&loop->startup, &loop->startup_lock));
    must(pthread_mutex_unlock(&loop->startup_lock));
    for (unsigned long i = 0; i < carriers; i += 1) {
        if (loop->carriers[i].begin_error != 0) { error = loop->carriers[i].begin_error; goto cleanup; }
    }
    return (long)loop->identity;
cleanup:
    __atomic_store_n(&loop->stop, 1, __ATOMIC_RELEASE);
    for (unsigned long i = 0; i < started; i += 1) wake_carrier(&loop->carriers[i]);
    for (unsigned long i = 0; i < started; i += 1) must(pthread_join(loop->carriers[i].thread, NULL));
    for (unsigned long i = 0; i < initialized; i += 1) free_carrier(&loop->carriers[i]);
    if (loop->identity != 0) linea_loop_retire(loop->identity);
    must(pthread_cond_destroy(&loop->startup));
    must(pthread_mutex_destroy(&loop->startup_lock));
    free(loop->carriers); free(loop);
    return -(long)error;
}

struct linea_fiber *linea_fiber_create(unsigned long identity, unsigned long stack_bytes,
                                      linea_fiber_entry entry, linea_fiber_entry ended, void *argument, int *error) {
    const uint8_t kind = linea_loop_kind(identity);
    if (kind != LINEA_LOOP_FIBERS && kind != LINEA_LOOP_SIMULATION) { *error = EINVAL; return NULL; }
    if (kind == LINEA_LOOP_SIMULATION && linea_io_current() != identity) fail("linea: a simulated task was prepared outside its simulation\n");
    if (stack_bytes > (1UL << 40)) { *error = ENOMEM; return NULL; }
    const long page = sysconf(_SC_PAGESIZE);
    if (page <= 0) { *error = EINVAL; return NULL; }
    const unsigned long alignment = (unsigned long)page;
    unsigned long usable = (stack_bytes + alignment - 1) / alignment * alignment;
    if (usable < 16384) usable = (16384 + alignment - 1) / alignment * alignment;
    struct linea_fiber *f = calloc(1, sizeof *f);
    if (f == NULL) { *error = ENOMEM; return NULL; }
    f->mapping_bytes = usable + guard_bytes;
    f->mapping = mmap(NULL, f->mapping_bytes, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0);
    if (f->mapping == MAP_FAILED) { *error = errno; free(f); return NULL; }
    if (mprotect(f->mapping, guard_bytes, PROT_NONE) != 0) {
        *error = errno; (void)munmap(f->mapping, f->mapping_bytes); free(f); return NULL;
    }
    if (kind == LINEA_LOOP_SIMULATION) {
        f->home = linea_sim_carrier(identity);
        f->home->live += 1;
    } else {
    struct fiber_loop *loop = linea_loop_find(identity);
    must(pthread_mutex_lock(&loop->startup_lock));
    f->home = &loop->carriers[loop->next];
    loop->next = loop->next + 1 == loop->count ? 0 : loop->next + 1;
    must(pthread_mutex_unlock(&loop->startup_lock));
    }
    f->stack = (char *)f->mapping + guard_bytes;
    f->stack_bytes = usable;
    f->entry = entry; f->finished = ended; f->argument = argument;
    f->timer_index = no_timer;
    f->state = parked;
#if __has_feature(thread_sanitizer)
    f->tsan_fiber = __tsan_create_fiber(0);
#endif
    linea_context_init(&f->context, f->stack, usable, fiber_entry, f);
    *error = 0;
    return f;
}

void linea_fiber_start(struct linea_fiber *f) {
    unsigned expected = parked;
    if (!__atomic_compare_exchange_n(&f->state, &expected, runnable, 0, __ATOMIC_ACQ_REL, __ATOMIC_ACQUIRE)) {
        fail("linea: a fiber was started twice\n");
    }
    enqueue(f);
}

void linea_fiber_destroy(struct linea_fiber *f) {
    if (f->home->simulation != 0) f->home->live -= 1;
#if __has_feature(thread_sanitizer)
    __tsan_destroy_fiber(f->tsan_fiber);
#endif
    if (munmap(f->mapping, f->mapping_bytes) != 0) fail("linea: a fiber's stack could not be unmapped\n");
    free(f);
}

void *linea_fiber_sim_create(unsigned long identity) {
    struct carrier *c = calloc(1, sizeof *c);
    if (c == NULL) return NULL;
    c->simulation = identity;
    c->kernel = -1; c->wake = -1;
    if (pthread_mutex_init(&c->queue_lock, NULL) != 0) { free(c); return NULL; }
    return c;
}

void linea_fiber_sim_switch(unsigned long previous, unsigned long identity) {
    struct carrier *c = current_carrier();
    if (previous == identity) return;
    if (linea_io_is_simulated(identity)) {
        struct carrier *next = linea_sim_carrier(identity);
        /* Restoring a nested run resumes its existing scheduler frame.
         * Relinking that carrier would lose the outer frame or form a cycle. */
        for (struct carrier *ancestor = c; ancestor != NULL; ancestor = ancestor->previous) {
            if (ancestor == next) {
                if (c->executing != NULL) fail("linea: a simulated fiber resumed an active outer simulation\n");
                must(pthread_setspecific(carrier_key, next));
                return;
            }
            if (ancestor->simulation == 0) break;
        }
        if (next->live != 0 && !pthread_equal(next->thread, pthread_self())) fail("linea: a simulation with live tasks moved between threads\n");
        next->thread = pthread_self();
        next->previous = current_carrier();
#if defined(__APPLE__)
        next->stack_bytes = pthread_get_stacksize_np(pthread_self());
        next->stack = (char *)pthread_get_stackaddr_np(pthread_self()) - next->stack_bytes;
#else
        pthread_attr_t attributes;
        must(pthread_getattr_np(pthread_self(), &attributes));
        must(pthread_attr_getstack(&attributes, &next->stack, &next->stack_bytes));
        must(pthread_attr_destroy(&attributes));
#endif
        if (next->previous != NULL && next->previous->executing != NULL) {
            next->stack = next->previous->executing->stack;
            next->stack_bytes = next->previous->executing->stack_bytes;
        }
#if __has_feature(thread_sanitizer)
        next->tsan_fiber = __tsan_get_current_fiber();
#endif
        must(pthread_setspecific(carrier_key, next));
    } else if (linea_io_is_simulated(previous)) {
        if (c == NULL || c->executing != NULL) fail("linea: a simulated fiber switched its Io\n");
        /* Leaving the outermost run restores the original native carrier,
         * or the empty carrier slot of an ordinary thread. */
        do { c = c->previous; } while (c != NULL && c->simulation != 0);
        must(pthread_setspecific(carrier_key, c));
    }
}

void linea_fiber_sim_destroy(void *carrier) {
    struct carrier *c = carrier;
    if (c->live != 0) fail("linea: a simulation ended with live tasks\n");
    free_carrier(c);
    free(c);
}

static void sim_poll(struct carrier *c) {
    struct pending_operation *pending = c->pending;
    while (pending != NULL) {
        struct pending_operation *next = pending->next;
        complete_operation(pending, 1);
        pending = next;
    }
    expire_timers(c);
}

int linea_fiber_sim_step(unsigned long deadline) {
    if (linea_foreign_depth() != 0) return 0;
    struct carrier *c = current_carrier();
    if (c == NULL || c->simulation == 0 || c->executing != NULL) fail("linea: a simulation has no root scheduler\n");
    sim_poll(c);
    struct linea_fiber *f = dequeue(c);
    if (f != NULL) {
        linea_thread_guard_bounds(&c->scheduler_guard_low, &c->scheduler_guard_high);
        run_fiber(c, f);
        return 1;
    }
    unsigned long next = linea_sim_next_event();
    if (c->timer_count != 0 && (next == 0 || c->timers[0]->deadline < next)) next = c->timers[0]->deadline;
    if (deadline != 0 && (next == 0 || deadline < next)) next = deadline;
    if (next == 0) return 0;
    if (next > now()) linea_sim_jump(next);
    sim_poll(c);
    return 1;
}

int linea_fiber_sim_park(struct linea_park *p, unsigned long deadline) {
    struct linea_fiber_waiter waiter = { .next = p->fibers, .fiber = NULL, .linked = 1, .expired = 0, .root_woken = 0 };
    p->fibers = &waiter;
    linea_park_unlock(p);
    while (!waiter.root_woken && (deadline == 0 || now() < deadline)) {
        if (!linea_fiber_sim_step(deadline)) fail("linea: all simulation tasks wait forever\n");
    }
    linea_park_lock(p);
    unlink_waiter(p, &waiter);
    return !waiter.root_woken && deadline != 0 && now() >= deadline;
}
