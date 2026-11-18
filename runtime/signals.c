#define _GNU_SOURCE
#define _DARWIN_C_SOURCE
#include "signals.h"

#include "loop.h"
#include "pipe_signal.h"
#include "waitset.h"
#include "waitset_pause.h"

#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <signal.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#if defined(__linux__)
#include <sys/eventfd.h>
#endif

static const int numbers[linea_signal_kinds] = { SIGTERM, SIGINT, SIGHUP, SIGUSR1, SIGUSR2 };

/* Deliveries of each signal since the process started, counted by the
 * handler. */
static unsigned long counts[linea_signal_kinds];

/* Shares of each signal on the system and the registrations the router
 * signals, under `router_lock`. */
static unsigned long shares[linea_signal_kinds];
static struct linea_signal_watch *watches;
static pthread_mutex_t router_lock = PTHREAD_MUTEX_INITIALIZER;

/* The action each signal's first share replaced, as the handler reads it.
 *
 * The handler runs on any thread and cannot take `router_lock`, and a
 * delivery the router began handling before the last share was released may
 * still be reading the action when a new first share saves another. So the
 * action is published with a sequence count, and read as a snapshot: the
 * writer, under `router_lock`, makes the count odd, stores the action's words,
 * and makes it even again, and a reader copies the words between two reads of
 * the same even count. Every access is atomic, so a read that overlaps a write
 * is retried, never torn. A write happens only while no share of the signal
 * exists, when the router's handler is not installed, so no handler spins on
 * the thread whose write it waits for. */
enum { action_words = (sizeof(struct sigaction) + sizeof(unsigned long) - 1) / sizeof(unsigned long) };

union action_copy {
    struct sigaction action;
    unsigned long words[action_words];
};

struct published_action {
    unsigned long sequence;
    union action_copy saved;
};

static struct published_action published[linea_signal_kinds];

/* Publish `action` as `signal`'s saved action. Called locked, while no share
 * of `signal` exists. */
static void publish_action(uint8_t signal, const struct sigaction *action) {
    struct published_action *p = &published[signal];
    union action_copy copy;
    memset(&copy, 0, sizeof copy);
    copy.action = *action;
    const unsigned long sequence = __atomic_load_n(&p->sequence, __ATOMIC_RELAXED);
    __atomic_store_n(&p->sequence, sequence + 1, __ATOMIC_RELAXED);
    __atomic_thread_fence(__ATOMIC_RELEASE);
    for (size_t i = 0; i < action_words; i += 1) __atomic_store_n(&p->saved.words[i], copy.words[i], __ATOMIC_RELAXED);
    __atomic_store_n(&p->sequence, sequence + 2, __ATOMIC_RELEASE);
}

/* Copy the saved action of signal `which` into `out`, as one published
 * write left it. */
static void snapshot_action(int which, union action_copy *out) {
    struct published_action *p = &published[which];
    for (;;) {
        const unsigned long before = __atomic_load_n(&p->sequence, __ATOMIC_ACQUIRE);
        if ((before & 1UL) != 0) continue;
        for (size_t i = 0; i < action_words; i += 1) out->words[i] = __atomic_load_n(&p->saved.words[i], __ATOMIC_RELAXED);
        __atomic_thread_fence(__ATOMIC_ACQUIRE);
        if (__atomic_load_n(&p->sequence, __ATOMIC_RELAXED) == before) return;
    }
}

/* The wake descriptor: an eventfd on Linux, a pipe's two ends on macOS. Made
 * by the first share and never closed, so the handler can always write it. */
static int wake_read = -1;
static int wake_write = -1;

static void fail(const char *message) {
    report_bytes(message, strlen(message));
    abort();
}

static void lock(void) {
    if (pthread_mutex_lock(&router_lock) != 0) fail("linea: the signal router's lock failed\n");
}

static void unlock(void) {
    if (pthread_mutex_unlock(&router_lock) != 0) fail("linea: the signal router's lock failed\n");
}

static void check(uint8_t signal) {
    if (signal >= linea_signal_kinds) fail("linea: a signal the router does not offer was named\n");
}

/* Whether an action calls a handler, and neither ignores its signal nor
 * leaves it its default. `SIG_IGN` and `SIG_DFL` are read first: SA_SIGINFO
 * says how a handler is called and may be set beside either, and the two
 * handler fields share their storage. */
static int names_a_handler(const struct sigaction *action) {
    return action->sa_handler != SIG_DFL && action->sa_handler != SIG_IGN;
}

/* The handler: take a snapshot of the saved action, count, wake, chain to
 * the snapshot's handler, and leave `errno` as the interrupted code had it.
 * A delivery chains to the action saved when the handler began, even when the
 * last share is released and a new first share saves another while it runs.
 * Only async-signal-safe calls are made. A full pipe is already awake, so a
 * failed write is ignored. */
static void route(int number, siginfo_t *info, void *context) {
    const int interrupted_errno = errno;
    int which = 0;
    while (which < linea_signal_kinds && numbers[which] != number) which += 1;
    if (which == linea_signal_kinds) return;
    union action_copy host;
    snapshot_action(which, &host);
    __atomic_add_fetch(&counts[which], 1UL, __ATOMIC_SEQ_CST);
#if defined(__linux__)
    const uint64_t one = 1;
    ssize_t written = write(wake_write, &one, sizeof one);
#else
    const unsigned char one = 1;
    ssize_t written = write(wake_write, &one, sizeof one);
#endif
    (void)written;
    linea_waitset_pause(linea_pause_route_before_chain);
    if (names_a_handler(&host.action)) {
        if ((host.action.sa_flags & SA_SIGINFO) != 0) host.action.sa_sigaction(number, info, context);
        else host.action.sa_handler(number);
    }
    errno = interrupted_errno;
}

/* Make the wake descriptor, nonblocking and closed on exec. Zero or an
 * errno. Called locked. */
static int make_wake(void) {
    if (wake_read >= 0) return 0;
#if defined(__linux__)
    const int fd = eventfd(0, EFD_NONBLOCK | EFD_CLOEXEC);
    if (fd < 0) return errno;
    wake_read = wake_write = fd;
#else
    int ends[2];
    if (pipe(ends) != 0) return errno;
    for (int i = 0; i < 2; i += 1) {
        const int flags = fcntl(ends[i], F_GETFL, 0);
        if (flags == -1 || fcntl(ends[i], F_SETFL, flags | O_NONBLOCK) != 0 || fcntl(ends[i], F_SETFD, FD_CLOEXEC) != 0) {
            const int error = errno;
            close(ends[0]);
            close(ends[1]);
            return error;
        }
    }
    wake_read = ends[0];
    wake_write = ends[1];
#endif
    return 0;
}

long linea_signal_acquire(uint8_t signal) {
    check(signal);
    if (linea_io_is_simulated(linea_io_current()) != 0) return 0;
    lock();
    int error = make_wake();
    if (error != 0) {
        unlock();
        return -(long)error;
    }
    if (shares[signal] == 0) {
        struct sigaction old;
        if (sigaction(numbers[signal], 0, &old) != 0) {
            error = errno;
            unlock();
            return -(long)error;
        }
        if (old.sa_handler == SIG_IGN) {
            unlock();
            return 1;
        }
        publish_action(signal, &old);
        struct sigaction installed;
        memset(&installed, 0, sizeof installed);
        installed.sa_sigaction = route;
        installed.sa_flags = SA_SIGINFO | SA_ONSTACK | SA_RESTART;
        sigemptyset(&installed.sa_mask);
        if (sigaction(numbers[signal], &installed, 0) != 0) {
            error = errno;
            unlock();
            return -(long)error;
        }
    }
    shares[signal] += 1;
    unlock();
    return 0;
}

void linea_signal_release(uint8_t signal, unsigned long loop) {
    check(signal);
    if (linea_io_is_simulated(loop) != 0) return;
    lock();
    if (shares[signal] == 0) fail("linea: a signal's share was released twice\n");
    shares[signal] -= 1;
    if (shares[signal] == 0 && sigaction(numbers[signal], &published[signal].saved.action, 0) != 0) {
        fail("linea: a signal's saved action could not be restored\n");
    }
    unlock();
}

int linea_signal_wake_descriptor(void) {
    lock();
    const int fd = wake_read;
    unlock();
    return fd;
}

void linea_signal_watch(struct linea_signal_watch *watch, struct linea_registration *r, unsigned long loop, uint8_t signal) {
    check(signal);
    lock();
    watch->registration = r;
    watch->loop = loop;
    watch->simulated = linea_io_is_simulated(loop) != 0;
    watch->signal = signal;
    watch->recorded = __atomic_load_n(&counts[signal], __ATOMIC_SEQ_CST);
    watch->previous = 0;
    watch->next = watches;
    if (watches != 0) watches->previous = watch;
    watches = watch;
    watch->listed = 1;
    unlock();
}

void linea_signal_unwatch(struct linea_signal_watch *watch) {
    lock();
    if (watch->listed) {
        if (watch->previous != 0) watch->previous->next = watch->next; else watches = watch->next;
        if (watch->next != 0) watch->next->previous = watch->previous;
        watch->listed = 0;
    }
    unlock();
}

void linea_signal_drain(void) {
    lock();
    if (wake_read >= 0) {
        unsigned char sink[64];
        while (read(wake_read, sink, sizeof sink) > 0) {
        }
    }
    unsigned long now[linea_signal_kinds];
    for (int i = 0; i < linea_signal_kinds; i += 1) now[i] = __atomic_load_n(&counts[i], __ATOMIC_SEQ_CST);
    for (struct linea_signal_watch *w = watches; w != 0; w = w->next) {
        if (!w->simulated && now[w->signal] != w->recorded) linea_registration_signal(w->registration);
    }
    unlock();
}

void linea_signal_deliver_simulated(unsigned long loop, uint8_t signal) {
    check(signal);
    if (!linea_io_is_simulated(loop) || linea_io_current() != loop) fail("linea: a simulation's world was used outside its run\n");
    lock();
    for (struct linea_signal_watch *w = watches; w != 0; w = w->next) {
        if (w->loop == loop && w->signal == signal) linea_registration_signal(w->registration);
    }
    unlock();
}
