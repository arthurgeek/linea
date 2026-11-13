#define _GNU_SOURCE
#define _DARWIN_C_SOURCE
#include "waitset.h"
#include "fiber.h"

#include "loop.h"
#include "park.h"
#include "op.h"
#include "pipe_signal.h"
#include "signals.h"
#include "sim.h"
#include "task.h"
#include "waitset_pause.h"

#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#if defined(__linux__)
#include <sys/epoll.h>
#include <sys/eventfd.h>
#else
#include <sys/event.h>
#endif

enum state { free_slot, reserved, registered, signalled, taken, retired };
enum kind { no_source, endpoint_source, returned_source, descriptor_source, ready_source, timer_source, signal_source };

/* A kernel event's cookie names a slot and its generation, or one of these,
 * which no slot's cookie can equal since no set has 2^32 - 1 slots. */
static const unsigned long user_cookie = ~0UL;
static const unsigned long router_cookie = ~0UL - 1;
static const size_t not_in_heap = ~(size_t)0;

enum { slots_per_page = 64 };

struct waitset;

struct linea_registration {
    unsigned state; /* atomic: an `enum state` */
    uint32_t generation;
    uint32_t slot;
    uint8_t kind;
    uint8_t writable;
    /* In the set's list of signalled registrations, under the set's lock. */
    uint8_t queued;
    int fd;
    unsigned long endpoint;
    unsigned long deadline;
    size_t heap_index;
    struct waitset *set;
    struct linea_registration *previous, *next;
    struct linea_signal_watch watch;
    /* The next free slot's index plus one, 0 for none; owner only. */
    uint32_t next_free;
};

struct waitset {
    /* Guards the signalled list and the decision how to wake the owner. */
    struct linea_park park;
    unsigned long identity;
    unsigned long loop;
    int simulated;

    /* Slots, in pages that live as long as the set, so a source holding a
     * registration's address always finds it. Owner only. */
    struct linea_registration **pages;
    size_t page_count;
    uint32_t made;
    uint32_t first_free;
    unsigned long held;
    /* Where `linea_waitset_withdraw` looks next, so closing a set visits
     * each slot once. */
    uint32_t withdraw_from;

    /* Registrations signalled and not yet taken, earliest first. */
    struct linea_registration *first_signalled, *last_signalled;

    /* Timers by deadline, a binary min-heap. Owner only. */
    struct linea_registration **heap;
    size_t heap_len, heap_capacity;

    /* The kernel queue, made by the first descriptor or signal: -1 before.
     * Written under the lock, so a source posting reads it there. */
    int kernel;
    int user_event;
    int watching_router;
};

static void fail(const char *message) {
    report_bytes(message, strlen(message));
    abort();
}

/* Every set ever opened takes the next identity; none is reused. */
static unsigned long identities;

static struct waitset *set_of(unsigned long set) {
    struct waitset *s = (struct waitset *)set;
    if (s->loop != linea_io_current()) fail("linea: a wait set was used on a loop other than the one it was opened on\n");
    return s;
}

static struct linea_registration *slot_at(struct waitset *s, uint32_t slot) {
    return &s->pages[slot / slots_per_page][slot % slots_per_page];
}

static unsigned load_state(struct linea_registration *r) {
    return __atomic_load_n(&r->state, __ATOMIC_ACQUIRE);
}

static int swap_state(struct linea_registration *r, unsigned from, unsigned to) {
    return __atomic_compare_exchange_n(&r->state, &from, to, 0, __ATOMIC_ACQ_REL, __ATOMIC_ACQUIRE);
}

static unsigned long cookie_of(const struct linea_registration *r) {
    return ((unsigned long)r->slot << 32) | r->generation;
}

/* Monotonic now on the set's loop: the simulation's clock inside one. */
static unsigned long now_on(const struct waitset *s) {
    if (s->simulated) return linea_sim_now();
    struct timespec now;
    if (clock_gettime(CLOCK_MONOTONIC, &now) != 0) fail("linea: clock_gettime failed\n");
    return (unsigned long)now.tv_sec * 1000000000UL + (unsigned long)now.tv_nsec;
}

/* Wake the owner, whichever way it waits. Called locked. */
static void wake(struct waitset *s) {
    if (s->kernel < 0) {
        linea_unpark(&s->park);
        return;
    }
#if defined(__linux__)
    const uint64_t one = 1;
    if (write(s->user_event, &one, sizeof one) < 0 && errno != EAGAIN) fail("linea: a wait set's user event could not be posted\n");
#else
    struct kevent trigger;
    EV_SET(&trigger, 1, EVFILT_USER, 0, NOTE_TRIGGER, 0, (void *)user_cookie);
    if (kevent(s->kernel, &trigger, 1, 0, 0, 0) != 0) fail("linea: a wait set's user event could not be posted\n");
#endif
}

/* Queue a registration that has just been swapped to `signalled` and wake
 * the owner. */
static void post(struct linea_registration *r) {
    struct waitset *s = r->set;
    linea_park_lock(&s->park);
    r->queued = 1;
    r->next = 0;
    r->previous = s->last_signalled;
    if (s->last_signalled != 0) s->last_signalled->next = r; else s->first_signalled = r;
    s->last_signalled = r;
    wake(s);
    linea_park_unlock(&s->park);
}

/* Take `r` out of the signalled list, if it is in it. Called locked. */
static void unqueue(struct waitset *s, struct linea_registration *r) {
    if (!r->queued) return;
    if (r->previous != 0) r->previous->next = r->next; else s->first_signalled = r->next;
    if (r->next != 0) r->next->previous = r->previous; else s->last_signalled = r->previous;
    r->queued = 0;
    r->previous = r->next = 0;
}

void linea_registration_signal(struct linea_registration *r) {
    linea_waitset_pause(linea_pause_source_before_swap);
    if (!swap_state(r, registered, signalled)) return;
    linea_waitset_pause(linea_pause_source_after_swap);
    post(r);
}

/* The timer heap. */
static int earlier(struct linea_registration *a, struct linea_registration *b) {
    return a->deadline < b->deadline || (a->deadline == b->deadline && a->slot < b->slot);
}

static void heap_set(struct waitset *s, size_t i, struct linea_registration *r) {
    s->heap[i] = r;
    r->heap_index = i;
}

static void heap_up(struct waitset *s, size_t i) {
    while (i > 0) {
        const size_t parent = (i - 1) / 2;
        if (!earlier(s->heap[i], s->heap[parent])) return;
        struct linea_registration *moved = s->heap[parent];
        heap_set(s, parent, s->heap[i]);
        heap_set(s, i, moved);
        i = parent;
    }
}

static void heap_down(struct waitset *s, size_t i) {
    for (;;) {
        size_t least = i;
        const size_t left = 2 * i + 1, right = 2 * i + 2;
        if (left < s->heap_len && earlier(s->heap[left], s->heap[least])) least = left;
        if (right < s->heap_len && earlier(s->heap[right], s->heap[least])) least = right;
        if (least == i) return;
        struct linea_registration *moved = s->heap[least];
        heap_set(s, least, s->heap[i]);
        heap_set(s, i, moved);
        i = least;
    }
}

static void heap_remove(struct waitset *s, struct linea_registration *r) {
    const size_t i = r->heap_index;
    if (i == not_in_heap) return;
    r->heap_index = not_in_heap;
    s->heap_len -= 1;
    if (i == s->heap_len) return;
    heap_set(s, i, s->heap[s->heap_len]);
    heap_up(s, i);
    heap_down(s, s->heap[i]->heap_index);
}

/* Signal every timer whose deadline is at or before `now`. */
static void expire(struct waitset *s, unsigned long now) {
    while (s->heap_len > 0 && s->heap[0]->deadline <= now) {
        struct linea_registration *r = s->heap[0];
        heap_remove(s, r);
        linea_waitset_pause(linea_pause_timer_before_swap);
        linea_registration_signal(r);
    }
}

unsigned long linea_waitset_open(void) {
    struct waitset *s = calloc(1, sizeof *s);
    if (s == 0) return 0;
    if (linea_park_init(&s->park) != 0) {
        free(s);
        return 0;
    }
    const unsigned long identity = __atomic_add_fetch(&identities, 1UL, __ATOMIC_SEQ_CST);
    if (identity == ULONG_MAX) fail("linea: every wait set identity has been issued\n");
    s->identity = identity;
    s->loop = linea_io_current();
    s->simulated = linea_io_is_simulated(s->loop) != 0;
    s->kernel = -1;
    s->user_event = -1;
    return (unsigned long)s;
}

unsigned long linea_waitset_identity(unsigned long set) {
    return ((struct waitset *)set)->identity;
}

unsigned long linea_waitset_reserve(unsigned long set) {
    struct waitset *s = set_of(set);
    if (s->first_free == 0) {
        if (s->made == UINT32_MAX - 1) fail("linea: a wait set holds as many registrations as it can number\n");
        if (s->made % slots_per_page == 0) {
            struct linea_registration **pages = realloc(s->pages, (s->page_count + 1) * sizeof *pages);
            if (pages == 0) fail("linea: a wait set's registrations could not be allocated\n");
            s->pages = pages;
            struct linea_registration *page = calloc(slots_per_page, sizeof *page);
            if (page == 0) fail("linea: a wait set's registrations could not be allocated\n");
            s->pages[s->page_count] = page;
            s->page_count += 1;
        }
        struct linea_registration *made = slot_at(s, s->made);
        made->slot = s->made;
        made->set = s;
        made->heap_index = not_in_heap;
        s->made += 1;
        s->first_free = made->slot + 1;
        made->next_free = 0;
    }
    struct linea_registration *r = slot_at(s, s->first_free - 1);
    s->first_free = r->next_free;
    r->next_free = 0;
    r->kind = no_source;
    __atomic_store_n(&r->state, reserved, __ATOMIC_RELEASE);
    return ((unsigned long)r->slot << 32) | r->generation;
}

/* Give a slot back once nothing names it: its generation moves on, and a
 * slot whose generation would wrap is retired. */
static void release_slot(struct waitset *s, struct linea_registration *r) {
    r->kind = no_source;
    if (r->generation == UINT32_MAX) {
        __atomic_store_n(&r->state, retired, __ATOMIC_RELEASE);
        return;
    }
    r->generation += 1;
    __atomic_store_n(&r->state, free_slot, __ATOMIC_RELEASE);
    r->next_free = s->first_free;
    s->first_free = r->slot + 1;
}

static struct linea_registration *reserved_slot(struct waitset *s, unsigned long slot) {
    if (slot >= s->made) fail("linea: a wait set was handed a slot it never reserved\n");
    struct linea_registration *r = slot_at(s, (uint32_t)slot);
    if (load_state(r) != reserved) fail("linea: a wait set was handed a slot it never reserved\n");
    return r;
}

void linea_waitset_unreserve(unsigned long set, unsigned long slot) {
    struct waitset *s = set_of(set);
    release_slot(s, reserved_slot(s, slot));
}

/* Make a registration visible: from here its source may signal it. */
static void publish(struct linea_registration *r, uint8_t kind) {
    r->kind = kind;
    __atomic_store_n(&r->state, registered, __ATOMIC_RELEASE);
    r->set->held += 1;
}

void linea_waitset_received(unsigned long set, unsigned long slot, unsigned long endpoint) {
    struct waitset *s = set_of(set);
    struct linea_registration *r = reserved_slot(s, slot);
    r->endpoint = endpoint;
    publish(r, endpoint_source);
    linea_chan_watch(endpoint, r, 0);
}

void linea_waitset_returned(unsigned long set, unsigned long slot, unsigned long handle) {
    struct waitset *s = set_of(set);
    if ((handle & 1UL) != 0) fail("linea: only a task's handle can wait for its body to return\n");
    struct linea_registration *r = reserved_slot(s, slot);
    r->endpoint = handle;
    publish(r, returned_source);
    linea_chan_watch(handle, r, 1);
}

/* Make the set's kernel queue and its user event, if it has none. Zero or an
 * errno. */
static int ensure_kernel(struct waitset *s) {
    if (s->kernel >= 0) return 0;
#if defined(__linux__)
    const int kernel = epoll_create1(EPOLL_CLOEXEC);
    if (kernel < 0) return errno;
    const int user_event = eventfd(0, EFD_NONBLOCK | EFD_CLOEXEC);
    if (user_event < 0) {
        const int error = errno;
        close(kernel);
        return error;
    }
    struct epoll_event watch;
    memset(&watch, 0, sizeof watch);
    watch.events = EPOLLIN;
    watch.data.u64 = user_cookie;
    if (epoll_ctl(kernel, EPOLL_CTL_ADD, user_event, &watch) != 0) {
        const int error = errno;
        close(user_event);
        close(kernel);
        return error;
    }
#else
    const int kernel = kqueue();
    if (kernel < 0) return errno;
    if (fcntl(kernel, F_SETFD, FD_CLOEXEC) != 0) {
        const int error = errno;
        close(kernel);
        return error;
    }
    struct kevent user;
    EV_SET(&user, 1, EVFILT_USER, EV_ADD | EV_CLEAR, 0, 0, (void *)user_cookie);
    if (kevent(kernel, &user, 1, 0, 0, 0) != 0) {
        const int error = errno;
        close(kernel);
        return error;
    }
    const int user_event = -1;
#endif
    linea_park_lock(&s->park);
    s->kernel = kernel;
    s->user_event = user_event;
    linea_park_unlock(&s->park);
    return 0;
}

/* Ask the kernel queue to report `fd` once, as `cookie`; or, with `remove`
 * set, to stop reporting it. Zero or an errno. */
static int arm(struct waitset *s, int fd, int writable, unsigned long cookie, int once, int remove) {
#if defined(__linux__)
    if (remove) return epoll_ctl(s->kernel, EPOLL_CTL_DEL, fd, 0) == 0 ? 0 : errno;
    struct epoll_event watch;
    memset(&watch, 0, sizeof watch);
    watch.events = (writable ? EPOLLOUT : EPOLLIN) | (once ? EPOLLONESHOT : 0);
    watch.data.u64 = cookie;
    return epoll_ctl(s->kernel, EPOLL_CTL_ADD, fd, &watch) == 0 ? 0 : errno;
#else
    struct kevent change;
    const unsigned short flags = remove ? EV_DELETE : (unsigned short)(EV_ADD | (once ? EV_ONESHOT : 0));
    EV_SET(&change, (uintptr_t)fd, writable ? EVFILT_WRITE : EVFILT_READ, flags, 0, 0, (void *)cookie);
    return kevent(s->kernel, &change, 1, 0, 0, 0) == 0 ? 0 : errno;
#endif
}

long linea_waitset_descriptor(unsigned long set, unsigned long slot, int fd, uint8_t writable) {
    struct waitset *s = set_of(set);
    struct linea_registration *r = reserved_slot(s, slot);
    r->fd = fd;
    r->writable = writable != 0;
    /* `linea_sim_takes` traps for a simulated descriptor outside its
     * simulation and for a real one inside a simulation. */
    if (linea_sim_takes(fd)) {
        publish(r, descriptor_source);
        return 0;
    }
    int error = ensure_kernel(s);
    if (error != 0) return -(long)error;
    /* The set watches a duplicate of its own, closed when the registration
     * leaves. The kernel queue keys a watch by descriptor number, and one
     * descriptor can be registered twice (a copied source, or readable and
     * writable at once): `epoll` refuses the second on one number and
     * `kqueue` replaces the first, and taking either back would remove the
     * other's watch. Through its own duplicate each registration is one
     * watch on every system, and no registration's watch outlives it. */
    const int watched = fcntl(fd, F_DUPFD_CLOEXEC, 0);
    if (watched < 0) return -(long)errno;
    error = arm(s, watched, r->writable, cookie_of(r), 1, 0);
    if (error != 0) {
        close(watched);
        return -(long)error;
    }
    r->fd = watched;
    publish(r, descriptor_source);
    return 0;
}

void linea_waitset_ready(unsigned long set, unsigned long slot) {
    struct waitset *s = set_of(set);
    struct linea_registration *r = reserved_slot(s, slot);
    publish(r, ready_source);
    linea_registration_signal(r);
}

void linea_waitset_timer(unsigned long set, unsigned long slot, unsigned long after_ns) {
    struct waitset *s = set_of(set);
    struct linea_registration *r = reserved_slot(s, slot);
    const unsigned long now = now_on(s);
    r->deadline = now > ULONG_MAX - after_ns ? ULONG_MAX : now + after_ns;
    if (s->heap_len == s->heap_capacity) {
        const size_t capacity = s->heap_capacity == 0 ? 8 : s->heap_capacity * 2;
        struct linea_registration **heap = realloc(s->heap, capacity * sizeof *heap);
        if (heap == 0) fail("linea: a wait set's timers could not be allocated\n");
        s->heap = heap;
        s->heap_capacity = capacity;
    }
    publish(r, timer_source);
    heap_set(s, s->heap_len, r);
    s->heap_len += 1;
    heap_up(s, r->heap_index);
}

long linea_waitset_signal(unsigned long set, unsigned long slot, uint8_t signal, unsigned long home) {
    struct waitset *s = set_of(set);
    if (home != s->loop) fail("linea: a signal's share was registered on a loop other than the one it was taken on\n");
    struct linea_registration *r = reserved_slot(s, slot);
    if (!s->simulated && !s->watching_router) {
        const int wake = linea_signal_wake_descriptor();
        if (wake < 0) fail("linea: a signal was registered with no share of it\n");
        int error = ensure_kernel(s);
        if (error == 0) error = arm(s, wake, 0, router_cookie, 0, 0);
        if (error != 0) return -(long)error;
        s->watching_router = 1;
    }
    publish(r, signal_source);
    linea_signal_watch(&r->watch, r, s->loop, signal);
    return 0;
}

/* Stop `r`'s source from reaching it. When this returns, no source will
 * signal it or post it again, so it may leave the signalled list and its
 * slot may be released. */
static void disarm(struct waitset *s, struct linea_registration *r) {
    switch (r->kind) {
    case endpoint_source:
    case returned_source:
        linea_chan_unwatch(r->endpoint);
        break;
    case descriptor_source:
        /* A one-shot registration that fired is gone already; removing it
         * again answers ENOENT. The duplicate is the registration's own. */
        if (!s->simulated) {
            (void)arm(s, r->fd, r->writable, 0, 0, 1);
            close(r->fd);
        }
        break;
    case timer_source:
        heap_remove(s, r);
        break;
    case signal_source:
        linea_signal_unwatch(&r->watch);
        break;
    default:
        break;
    }
    linea_park_lock(&s->park);
    unqueue(s, r);
    linea_park_unlock(&s->park);
    s->held -= 1;
    release_slot(s, r);
}

/* How many kernel events one round reads. */
enum { kernel_batch = 32 };

/* Read one round of kernel events and signal what they report, waiting at
 * most until `deadline` (0 for none), or not at all when `poll_only` is
 * set. Answers how many events the round read, at most `kernel_batch`. */
static int wait_in_kernel(struct waitset *s, unsigned long deadline, int poll_only) {
    enum { batch = kernel_batch };
    unsigned long cookies[batch];
    int count;
#if defined(__linux__)
    struct epoll_event events[batch];
    int timeout_ms = poll_only ? 0 : -1;
    if (!poll_only && deadline != 0) {
        const unsigned long now = now_on(s);
        const unsigned long remaining = deadline > now ? deadline - now : 0;
        const unsigned long ms = (remaining + 999999UL) / 1000000UL;
        timeout_ms = ms > (unsigned long)INT_MAX ? INT_MAX : (int)ms;
    }
    count = epoll_wait(s->kernel, events, batch, timeout_ms);
    for (int i = 0; i < count; i += 1) cookies[i] = (unsigned long)events[i].data.u64;
#else
    struct kevent events[batch];
    struct timespec timeout;
    struct timespec *bounded = 0;
    if (poll_only) {
        timeout.tv_sec = 0;
        timeout.tv_nsec = 0;
        bounded = &timeout;
    } else if (deadline != 0) {
        const unsigned long now = now_on(s);
        /* `kevent` refuses a timeout whose seconds do not fit 32 bits, so a
         * wait lasts at most a day, after which `next` checks the deadline
         * again. */
        const unsigned long longest_wait_ns = 86400UL * 1000000000UL;
        unsigned long remaining = deadline > now ? deadline - now : 0;
        if (remaining > longest_wait_ns) remaining = longest_wait_ns;
        timeout.tv_sec = (time_t)(remaining / 1000000000UL);
        timeout.tv_nsec = (long)(remaining % 1000000000UL);
        bounded = &timeout;
    }
    count = kevent(s->kernel, 0, 0, events, batch, bounded);
    for (int i = 0; i < count; i += 1) cookies[i] = (unsigned long)events[i].udata;
#endif
    if (count < 0) {
        if (errno == EINTR) return 0;
        fail("linea: a wait set's kernel queue could not be read\n");
    }
    for (int i = 0; i < count; i += 1) {
        const unsigned long cookie = cookies[i];
#if defined(__linux__)
        if (cookie == user_cookie) {
            uint64_t posted;
            (void)read(s->user_event, &posted, sizeof posted);
            continue;
        }
#else
        if (events[i].filter == EVFILT_USER || cookie == user_cookie) {
            continue;
        }
#endif
        if (cookie == router_cookie) {
            linea_signal_drain();
            continue;
        }
        const unsigned long slot = cookie >> 32;
        if (slot >= s->made) continue;
        struct linea_registration *r = slot_at(s, (uint32_t)slot);
        if (r->generation != (uint32_t)cookie || r->kind != descriptor_source) continue;
        linea_registration_signal(r);
    }
    return count;
}

/* Signal every source that is ready now and has not been signalled, without
 * waiting: inside a simulation the descriptors the simulation says are
 * ready, in slot order, and outside one whatever the kernel queue has to
 * report; then the timers past their deadline. A descriptor ready at the
 * instant a timer expires is therefore signalled before the timer. */
static void observe(struct waitset *s) {
    if (s->simulated) {
        for (uint32_t i = 0; i < s->made; i += 1) {
            struct linea_registration *r = slot_at(s, i);
            if (r->kind == descriptor_source && load_state(r) == registered && linea_sim_ready(r->fd, r->writable)) {
                linea_registration_signal(r);
            }
        }
    } else if (s->kernel >= 0) {
        /* A full round may have left events unread. */
        while (wait_in_kernel(s, 0, 1) == kernel_batch) {
        }
    }
    expire(s, now_on(s));
}

/* The simulation's scheduler retries this predicate after runnable work
 * and virtual deliveries, so a set watches several simulated descriptors
 * without advancing time while a peer can still run. */
static long simulated_set_ready(struct linea_op *operation) {
    struct waitset *s = (struct waitset *)operation->at;
    observe(s);
    linea_park_lock(&s->park);
    const int ready = s->first_signalled != NULL;
    linea_park_unlock(&s->park);
    return ready ? 0 : -(long)EAGAIN;
}

static void wait_in_simulation(struct waitset *s) {
    const unsigned long deadline = s->heap_len == 0 ? 0 : s->heap[0]->deadline;
    if (linea_fiber_active()) {
        struct linea_op operation = { LINEA_OP_WAITSET, -1, (unsigned long)s, 0, 0, deadline };
        const long result = linea_fiber_perform(&operation, simulated_set_ready);
        if (result != 0 && result != -(long)ETIMEDOUT) fail("linea: a simulated wait set could not be awaited\n");
    } else if (!linea_fiber_sim_step(deadline)) {
        fail("linea: all simulation tasks wait forever\n");
    }
}

long linea_waitset_next(unsigned long set) {
    struct waitset *s = set_of(set);
    for (;;) {
        if (s->held == 0) return -1;
        observe(s);
        linea_park_lock(&s->park);
        struct linea_registration *r = s->first_signalled;
        if (r != 0) {
            unqueue(s, r);
            linea_park_unlock(&s->park);
            if (!swap_state(r, signalled, taken)) fail("linea: a wait set queued a registration that was not signalled\n");
            const long slot = (long)r->slot;
            disarm(s, r);
            return slot;
        }
        linea_waitset_pause(linea_pause_next_before_wait);
        const unsigned long deadline = s->heap_len > 0 ? s->heap[0]->deadline : 0;
        if (s->simulated) {
            linea_park_unlock(&s->park);
            wait_in_simulation(s);
        } else if (s->kernel >= 0) {
            linea_park_unlock(&s->park);
            if (linea_fiber_active()) {
                const long result = linea_fiber_wait_descriptor(s->kernel, 0, deadline);
                if (result < 0 && result != -(long)ETIMEDOUT) fail("linea: a wait set's queue could not be awaited\n");
            } else {
                (void)wait_in_kernel(s, deadline, 0);
            }
        } else {
            (void)linea_park(&s->park, deadline);
            linea_park_unlock(&s->park);
        }
    }
}

uint8_t linea_waitset_take(unsigned long set, unsigned long slot, unsigned long generation, uint8_t only_registered) {
    struct waitset *s = set_of(set);
    if (slot >= s->made) return 0;
    struct linea_registration *r = slot_at(s, (uint32_t)slot);
    if (r->generation != generation) return 0;
    /* A timer past its deadline or a descriptor the kernel has reported has
     * fired, whether or not `next` has looked. */
    if (r->kind == timer_source || r->kind == descriptor_source || r->kind == signal_source) observe(s);
    linea_waitset_pause(linea_pause_take_before_swap);
    if (!swap_state(r, registered, taken)) {
        if (only_registered || !swap_state(r, signalled, taken)) return 0;
    }
    linea_waitset_pause(linea_pause_take_after_swap);
    disarm(s, r);
    return 1;
}

long linea_waitset_withdraw(unsigned long set) {
    struct waitset *s = set_of(set);
    while (s->withdraw_from < s->made) {
        struct linea_registration *r = slot_at(s, s->withdraw_from);
        s->withdraw_from += 1;
        if (swap_state(r, registered, taken) || swap_state(r, signalled, taken)) {
            linea_waitset_pause(linea_pause_take_after_swap);
            disarm(s, r);
            return (long)r->slot;
        }
    }
    s->withdraw_from = 0;
    return -1;
}

void linea_waitset_close(unsigned long set) {
    struct waitset *s = set_of(set);
    if (s->held != 0) fail("linea: a wait set was closed holding a registration\n");
    if (s->kernel >= 0) close(s->kernel);
#if defined(__linux__)
    if (s->user_event >= 0) close(s->user_event);
#endif
    for (size_t i = 0; i < s->page_count; i += 1) free(s->pages[i]);
    free(s->pages);
    free(s->heap);
    linea_park_destroy(&s->park);
    free(s);
}
