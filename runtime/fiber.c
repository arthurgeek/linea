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
#include "completion.h"
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
#if defined(LINEA_FIBER_PLATFORM_STATE_TEST)
#include <signal.h>
#endif
#if defined(LINEA_FIBER_MIGRATION_TRACE_TEST)
#include <stdio.h>
#endif
#if defined(__linux__)
#include <sys/epoll.h>
#include <sys/eventfd.h>
#else
#include <sys/event.h>
#endif

#ifndef __has_feature
#define __has_feature(x) 0
#endif
/* Cross-thread restoration is enabled only on the validated native ABI.
 * Reference profiles keep their deterministic transfer policy. */
#if defined(LINEA_FIBER_MIGRATION_CANDIDATE) && (!defined(__linux__) || (!defined(__aarch64__) && !defined(__x86_64__)))
#error Migration candidate requires Linux arm64 or x86-64
#endif
#if !defined(LINEA_FIBER_SCHEDULING_PINNED_TEST) && (defined(LINEA_FIBER_MIGRATION_TEST) || defined(LINEA_FIBER_MIGRATION_CANDIDATE) || (defined(__APPLE__) && defined(__aarch64__) && !__has_feature(address_sanitizer) && !__has_feature(thread_sanitizer)))
#define LINEA_FIBER_CAN_MIGRATE 1
#endif
#if defined(LINEA_FIBER_CAN_MIGRATE) && !defined(LINEA_FIBER_MIGRATION_TEST)
#define LINEA_FIBER_AUTO_STEAL 1
#endif
#if defined(LINEA_FIBER_BUSY_SOURCE_TEST) && !defined(LINEA_FIBER_AUTO_STEAL)
#error Busy-source proof requires the normal work-stealing scheduler
#endif
#if __has_feature(address_sanitizer)
void __sanitizer_start_switch_fiber(void **save, const void *bottom, size_t size);
void __sanitizer_finish_switch_fiber(void *save, const void **bottom, size_t *size);
#if defined(LINEA_FIBER_PLATFORM_STATE_TEST)
void *__asan_get_current_fake_stack(void);
void *__asan_addr_is_in_fake_stack(void *stack, void *address, void **begin, void **end);
#endif
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
enum scheduling_claim { no_claim, dispatch_claim, transfer_claimed };
enum runnable_lane { local_lane = 1, stealable_lane = 2 };

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
    /* Kernel registrations remain with the poller that armed them, even if
     * the saved continuation later resumes on another carrier. */
    struct carrier *owner;
    /* Immutable evidence from the canonical net.c producer. */
    int audited_net;
    unsigned state;
    uint32_t slot;
    int registered;
    int readiness_only;
    uint64_t completion_cookie;
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
    struct fiber_loop *loop;
    struct carrier *bound;
    int queued, started, saved, retired, proven;
    enum scheduling_claim claimed;
#if defined(LINEA_FIBER_CAN_MIGRATE)
    int transfer_ready;
#if defined(LINEA_FIBER_FORCED_HANDOFF_TEST)
    unsigned forced_transfers;
#endif
#endif
    struct carrier *claimant;
    unsigned source_claims;
#if defined(LINEA_FIBER_MIGRATION_TRACE_TEST)
    unsigned long trace_identity, trace_epoch, trace_transfer_epoch, trace_resumed_epoch;
    int trace_entered, trace_initially_eligible, trace_ever_eligible, trace_counted, trace_ever_transferred;
#endif
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
    struct linea_fiber *stealable_first, *stealable_last;
    int prefer_stealable;
    int idle;
    unsigned long next_victim;
    struct linea_fiber **timers;
    size_t timer_count, timer_capacity;
    int kernel;
    int wake;
    struct linea_completion *completion;
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

#if defined(LINEA_FIBER_MIGRATION_TRACE_TEST)
#define TRACE_COUNTER_FIELDS(X) \
    X(started) X(retired) X(initially_eligible) X(current_eligible) X(peak_eligible) \
    X(initially_then_restricted) X(never_eligible) X(guard_requests) X(first_restrictions) \
    X(transfers) X(ever_transferred) X(eligibility_checks) X(claim_attempts) X(commit_attempts) \
    X(active_claims) X(ref_entry) X(ref_affinity) X(ref_state) X(ref_source) \
    X(ref_reservation) X(ref_target) X(ref_empty) X(ref_quota) X(normalization_attempts) X(normalization_busy)
#define TRACE_COUNTER_DECLARE(name) unsigned long name;
struct trace_counts { TRACE_COUNTER_FIELDS(TRACE_COUNTER_DECLARE) };
#undef TRACE_COUNTER_DECLARE
#endif

struct fiber_loop {
    unsigned long identity;
    unsigned long count;
    unsigned long next;
    struct carrier *carriers;
    pthread_mutex_t metadata;
    pthread_mutex_t startup_lock;
    pthread_cond_t startup;
    unsigned long began;
    int stop;
#if defined(LINEA_FIBER_MIGRATION_TRACE_TEST)
    struct trace_counts trace_counts;
#endif
};

#if defined(LINEA_FIBER_BUSY_SOURCE_TEST)
/* A bounded policy barrier delays idle thieves until the other Linea body
 * has entered its CPU loop. Eligibility and dispatch use the normal code. */
static struct {
    pthread_mutex_t lock;
    pthread_cond_t changed;
    struct linea_fiber *worker, *body;
    struct carrier *source;
    int worker_seen, body_seen, released, claimed, observed;
} busy_test = { .lock = PTHREAD_MUTEX_INITIALIZER, .changed = PTHREAD_COND_INITIALIZER };
#endif

#if defined(LINEA_FIBER_MIGRATION_TRACE_TEST)
#define TRACE_COUNT(loop, field) ((loop)->trace_counts.field += 1UL)
static void trace_update_eligibility(struct linea_fiber *f);
#else
#define TRACE_COUNT(loop, field) ((void)0)
#endif

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

/* Carrier-owned debug state: no context switch may carry this lock. */
static __thread struct fiber_loop *metadata_owner;

/* A compiler may cache a native TLS address across an ordinary function call.
 * Keep address evaluation in completed leaf frames, never in a continuation
 * that can return from linea_context_switch on another OS thread. */
__attribute__((noinline)) static struct fiber_loop *read_metadata_owner(void) {
    return metadata_owner;
}

__attribute__((noinline)) static void write_metadata_owner(struct fiber_loop *owner) {
    metadata_owner = owner;
}

int linea_fiber_metadata_held(void) { return read_metadata_owner() != NULL; }

static void lock_metadata(struct fiber_loop *loop) {
    if (read_metadata_owner() != NULL) fail("linea: scheduler metadata locks were nested\n");
    must(pthread_mutex_lock(&loop->metadata));
    write_metadata_owner(loop);
}

static void unlock_metadata(struct fiber_loop *loop) {
    if (read_metadata_owner() != loop) fail("linea: scheduler metadata was unlocked by a nonowner\n");
    write_metadata_owner(NULL);
    must(pthread_mutex_unlock(&loop->metadata));
}

static void lock_carrier(struct carrier *c) {
    if (c->loop != NULL) lock_metadata(c->loop);
    else must(pthread_mutex_lock(&c->queue_lock));
}

static void unlock_carrier(struct carrier *c) {
    if (c->loop != NULL) unlock_metadata(c->loop);
    else must(pthread_mutex_unlock(&c->queue_lock));
}

static void lock_fiber(struct linea_fiber *f) {
    if (f->loop != NULL) lock_metadata(f->loop);
    else must(pthread_mutex_lock(&f->home->queue_lock));
}

static void unlock_fiber(struct linea_fiber *f) {
    if (f->loop != NULL) unlock_metadata(f->loop);
    else must(pthread_mutex_unlock(&f->home->queue_lock));
}

static void require_metadata(struct linea_fiber *f) {
    if (f->loop != NULL && read_metadata_owner() != f->loop) fail("linea: scheduler metadata was used without its lock\n");
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

#if defined(LINEA_FIBER_PLATFORM_STATE_TEST)
/* A bounded probe of the real switch path. Control state follows the saved
 * continuation; masks and a thread-directed pending signal stay on carriers. */
static unsigned platform_signal_sent, platform_migrations, platform_scheduler_checks;

static unsigned long platform_control(void) {
#if defined(__aarch64__)
    unsigned long value;
    __asm__ volatile("mrs %0, fpcr" : "=r"(value));
    return (value >> 22) & 3UL;
#elif defined(__x86_64__)
    unsigned short x87;
    unsigned int sse;
    __asm__ volatile("fnstcw %0" : "=m"(x87));
    __asm__ volatile("stmxcsr %0" : "=m"(sse));
    return ((unsigned long)x87 >> 10 & 3UL) | (((unsigned long)sse >> 13 & 3UL) << 2);
#else
#error Unsupported platform-state probe architecture
#endif
}

static unsigned long platform_rounding(unsigned role) {
#if defined(__aarch64__)
    const unsigned long modes[] = { 2, 3, 1 }; /* down, zero, up */
    return modes[role];
#else
    const unsigned long modes[] = { 1, 3, 2 };
    return modes[role] | (modes[role] << 2);
#endif
}

static void platform_set_rounding(unsigned role) {
#if defined(__aarch64__)
    unsigned long value;
    __asm__ volatile("mrs %0, fpcr" : "=r"(value));
    value = (value & ~(3UL << 22)) | (platform_rounding(role) << 22);
    __asm__ volatile("msr fpcr, %0\n\tisb" : : "r"(value) : "memory");
#else
    unsigned short x87;
    unsigned int sse;
    const unsigned long mode = platform_rounding(role) & 3UL;
    __asm__ volatile("fnstcw %0" : "=m"(x87));
    __asm__ volatile("stmxcsr %0" : "=m"(sse));
    x87 = (unsigned short)((x87 & ~(3U << 10)) | ((unsigned int)mode << 10));
    sse = (sse & ~(3U << 13)) | ((unsigned int)mode << 13);
    __asm__ volatile("fldcw %0" : : "m"(x87) : "memory");
    __asm__ volatile("ldmxcsr %0" : : "m"(sse) : "memory");
#endif
}

static int platform_first(struct carrier *c) {
    if (c == NULL || c->loop == NULL || c->loop->count != 2) fail("linea: platform probe requires two real carriers\n");
    return c == &c->loop->carriers[0];
}

static void platform_carrier_begin(struct carrier *c) {
    sigset_t signal;
    if (sigemptyset(&signal) != 0 || sigaddset(&signal, SIGUSR1) != 0) fail("linea: platform signal setup failed\n");
    must(pthread_sigmask(platform_first(c) ? SIG_BLOCK : SIG_UNBLOCK, &signal, NULL));
    platform_set_rounding(platform_first(c) ? 0U : 1U);
}

static void platform_check(struct carrier *c, int fibre) {
    const int first = platform_first(c);
    const unsigned role = fibre ? 2U : first ? 0U : 1U;
    if (platform_control() != platform_rounding(role)) fail("linea: FP control followed the wrong execution context\n");
    sigset_t mask, pending;
    must(pthread_sigmask(SIG_SETMASK, NULL, &mask));
    if (sigpending(&pending) != 0) fail("linea: platform pending-signal query failed\n");
    const int sent = __atomic_load_n(&platform_signal_sent, __ATOMIC_ACQUIRE) != 0;
    if (sigismember(&mask, SIGUSR1) != first || sigismember(&pending, SIGUSR1) != (first && sent))
        fail("linea: signal state followed a fiber instead of its carrier\n");
    if (!fibre) __atomic_fetch_add(&platform_scheduler_checks, 1U, __ATOMIC_RELEASE);
}

static void platform_fibre_begin(void) {
    struct carrier *c = current_carrier();
    if (!platform_first(c)) fail("linea: platform probe started on the wrong carrier\n");
    if (__atomic_load_n(&platform_signal_sent, __ATOMIC_ACQUIRE)) fail("linea: platform probe entered twice\n");
    platform_set_rounding(2);
    must(pthread_kill(pthread_self(), SIGUSR1));
    __atomic_store_n(&platform_signal_sent, 1U, __ATOMIC_RELEASE);
    platform_check(c, 1);
}

#if __has_feature(address_sanitizer)
/* Check the active ASan context, not just bytes which can remain intact even
 * when the runtime forgot to restore the continuation's fake stack. */
static void platform_fake_frame(volatile unsigned char *frame) {
    void *stack = __asan_get_current_fake_stack();
    if (stack == NULL || __asan_addr_is_in_fake_stack(stack, (void *)frame, NULL, NULL) == NULL)
        fail("linea: a protected frame lost its sanitizer context\n");
}
#endif

#if defined(LINEA_FIBER_SANITIZER_FAULT_TEST)
static void platform_fault_marker(void) {
    const char message[] = "native migration: injecting a sanitizer fault after transfer\n";
    report_bytes(message, sizeof message - 1);
}
#if __has_feature(address_sanitizer)
__attribute__((noinline))
static void platform_fault_target(volatile unsigned char *frame) {
    platform_fault_marker();
    volatile size_t outside = 32;
    (void)frame[outside];
    fail("linea: ASan missed a transferred frame overflow\n");
}
#elif __has_feature(thread_sanitizer)
static unsigned platform_fault_phase;
static volatile unsigned platform_fault_value;

static void platform_fault_wait(unsigned phase) {
    /* Relaxed coordination deliberately supplies no happens-before edge for
     * the accesses this negative control requires TSan to detect. */
    for (unsigned i = 0; i < 5000; i += 1) {
        if (__atomic_load_n(&platform_fault_phase, __ATOMIC_RELAXED) >= phase) return;
        const struct timespec pause = { 0, 1000000 };
        nanosleep(&pause, NULL);
    }
    fail("linea: sanitizer fault control did not rendezvous\n");
}

static void platform_fault_source(struct carrier *source) {
    if (!platform_first(source)) return;
    platform_fault_wait(1);
    platform_fault_value = 17;
    __atomic_store_n(&platform_fault_phase, 2U, __ATOMIC_RELAXED);
}

static void platform_fault_target(volatile unsigned char *frame) {
    (void)frame;
    platform_fault_marker();
    __atomic_store_n(&platform_fault_phase, 1U, __ATOMIC_RELAXED);
    platform_fault_wait(2);
    (void)platform_fault_value;
    fail("linea: TSan missed a cross-carrier race\n");
}
#else
#error Sanitizer fault control requires ASan or TSan
#endif
#endif
#endif

/* Foreign code can leave a thread dependency after returning. This is a
 * logical fiber restriction, independent of the live native-frame depth. */
void linea_fiber_restrict_current(void) {
    const int error = errno;
    struct carrier *c = current_carrier();
    struct linea_fiber *f = c == NULL ? NULL : c->executing;
    if (f != NULL && f->loop != NULL) {
        lock_fiber(f);
        if (f->state != running || f->home != c || (f->bound != NULL && f->bound != c))
            fail("linea: a native restriction disagreed with the executing carrier\n");
        TRACE_COUNT(f->loop, guard_requests);
#if defined(LINEA_FIBER_MIGRATION_TRACE_TEST)
        if (f->bound == NULL) {
            TRACE_COUNT(f->loop, first_restrictions);
            if (f->trace_initially_eligible) TRACE_COUNT(f->loop, initially_then_restricted);
        }
#endif
        f->bound = c;
#if defined(LINEA_FIBER_MIGRATION_TRACE_TEST)
        trace_update_eligibility(f);
#endif
        unlock_fiber(f);
    }
    errno = error;
}

int linea_fiber_active(void) {
    return current_fiber() != NULL && linea_foreign_depth() == 0;
}

#if defined(LINEA_FIBER_BUSY_SOURCE_TEST)
static void busy_test_observe(struct carrier *c) {
    must(pthread_mutex_lock(&busy_test.lock));
    struct linea_fiber *f = c->executing;
    lock_fiber(f);
    int release = 0;
    if (!busy_test.worker_seen) {
        busy_test.worker_seen = 1;
        busy_test.worker = f;
        busy_test.source = c;
        if (c != &c->loop->carriers[0] || c->loop->count != 4)
            fail("linea: busy-source worker has the wrong initial placement\n");
    } else if (f != busy_test.worker && !busy_test.body_seen) {
        if (c != busy_test.source || busy_test.worker == NULL || busy_test.worker->queued != stealable_lane ||
            !busy_test.worker->saved || !busy_test.worker->transfer_ready)
            fail("linea: busy-source body did not retain an already-saved backlog\n");
        busy_test.body = f;
        busy_test.body_seen = 1;
    } else if (f == busy_test.body) {
        release = 1;
    }
    if (f == busy_test.worker && c != busy_test.source) {
        if (busy_test.body == NULL || busy_test.source->executing != busy_test.body)
            fail("linea: a stolen continuation resumed after its busy source stopped\n");
        busy_test.observed = 1;
    }
    unlock_fiber(f);
    if (release) {
        busy_test.released = 1;
        must(pthread_cond_broadcast(&busy_test.changed));
    }
    must(pthread_mutex_unlock(&busy_test.lock));
}

static void busy_test_wait(struct carrier *c) {
    if (c == &c->loop->carriers[0]) return;
    if (linea_fiber_metadata_held()) fail("linea: busy-source barrier retained scheduler metadata\n");
    must(pthread_mutex_lock(&busy_test.lock));
    while (!busy_test.released && !__atomic_load_n(&c->loop->stop, __ATOMIC_ACQUIRE)) {
        struct timespec until;
        if (clock_gettime(CLOCK_REALTIME, &until) != 0) fail("linea: busy-source barrier clock failed\n");
        until.tv_nsec += 100000000;
        if (until.tv_nsec >= 1000000000) { until.tv_sec += 1; until.tv_nsec -= 1000000000; }
        const int error = pthread_cond_timedwait(&busy_test.changed, &busy_test.lock, &until);
        if (error != ETIMEDOUT) must(error);
    }
    must(pthread_mutex_unlock(&busy_test.lock));
}
#endif

unsigned long linea_fiber_current_carrier(void) {
    const int error = errno;
    struct carrier *c = current_carrier();
    /* Real loops and their carrier arrays live until process exit, so this
     * opaque identity cannot be recycled into another carrier's identity. No
     * fiber record or scheduler claim escapes through the observation. */
    const unsigned long identity = c != NULL && c->loop != NULL && c->executing != NULL ?
        (unsigned long)c : 0;
#if defined(LINEA_FIBER_BUSY_SOURCE_TEST)
    if (identity != 0) busy_test_observe(c);
#endif
    errno = error;
    return identity;
}

static unsigned long now(void) {
    if (linea_sim_running()) return linea_sim_now();
    struct timespec instant;
    if (clock_gettime(CLOCK_MONOTONIC, &instant) != 0) fail("linea: a carrier's clock failed\n");
    return (unsigned long)instant.tv_sec * 1000000000UL + (unsigned long)instant.tv_nsec;
}

#if defined(LINEA_FIBER_MIGRATION_TRACE_TEST)
/* Bounded proof telemetry, never a production allocation or public control.
 * Clocks bracket M from outside. Payload snapshots happen under M; publishing
 * a completed event never follows a possibly reclaimed fiber pointer. */
enum { trace_capacity = 64 };
struct trace_event {
    char phase;
    unsigned long identity, epoch, carrier, lower, upper;
    int complete;
};
struct trace_ticket { unsigned long lower; struct trace_event *event; };
static struct trace_event trace_events[trace_capacity];
static unsigned long trace_count, trace_identities;

/* This is contract eligibility of live fibers, independent of runnable state
 * or source normalization. Never/initial/current/ever-transferred are distinct. */
static void trace_update_eligibility(struct linea_fiber *f) {
    require_metadata(f);
    const int eligible = f->trace_entered && f->proven && f->bound == NULL && !f->retired;
    struct trace_counts *counts = &f->loop->trace_counts;
    if (eligible && !f->trace_counted) {
        counts->current_eligible += 1;
        if (counts->current_eligible > counts->peak_eligible) counts->peak_eligible = counts->current_eligible;
        f->trace_ever_eligible = 1;
    } else if (!eligible && f->trace_counted) {
        if (counts->current_eligible == 0) fail("linea: an eligibility population underflowed\n");
        counts->current_eligible -= 1;
    }
    f->trace_counted = eligible;
}

static struct trace_ticket trace_begin(void) {
    if (linea_fiber_metadata_held()) fail("linea: a trace clock was sampled under metadata\n");
    struct trace_ticket ticket = { now(), NULL };
    return ticket;
}

static void trace_capture(struct trace_ticket *ticket, char phase, struct linea_fiber *f, struct carrier *c) {
    require_metadata(f);
    if (f->loop == NULL || c->loop != f->loop) fail("linea: a trace crossed execution loops\n");
    if (phase == 'R') f->trace_epoch += 1;
    const unsigned long index = __atomic_fetch_add(&trace_count, 1UL, __ATOMIC_RELAXED);
    if (index >= trace_capacity) return;
    struct trace_event *event = &trace_events[index];
    event->phase = phase;
    event->identity = f->trace_identity;
    event->epoch = f->trace_epoch;
    event->carrier = (unsigned long)(c - f->loop->carriers);
    event->lower = ticket->lower;
    ticket->event = event;
}

static void trace_end(struct trace_ticket *ticket) {
    if (ticket->event == NULL) return;
    if (linea_fiber_metadata_held()) fail("linea: a trace clock was sampled under metadata\n");
    ticket->event->upper = now();
    __atomic_store_n(&ticket->event->complete, 1, __ATOMIC_RELEASE);
}

static void trace_dump(struct trace_counts counts) {
    const unsigned long count = __atomic_load_n(&trace_count, __ATOMIC_ACQUIRE);
    const unsigned long kept = count < trace_capacity ? count : trace_capacity;
    unsigned long dropped = count - kept;
    for (unsigned long i = 0; i < kept; i += 1)
        if (!__atomic_load_n(&trace_events[i].complete, __ATOMIC_ACQUIRE)) dropped += 1;
    struct timespec resolution;
    if (clock_getres(CLOCK_MONOTONIC, &resolution) != 0) fail("linea: a trace clock has no resolution\n");
    const unsigned long resolution_ns = (unsigned long)resolution.tv_sec * 1000000000UL + (unsigned long)resolution.tv_nsec;
    if (resolution_ns == 0) fail("linea: a trace clock reported zero resolution\n");
    char line[256];
    int length = snprintf(line, sizeof line, "migration-trace-v1 units=ns dropped=%lu resolution_ns=%lu\n", dropped, resolution_ns);
    if (length <= 0 || (size_t)length >= sizeof line) fail("linea: a trace header overflowed\n");
    report_bytes(line, (unsigned long)length);
    for (unsigned long i = 0; i < kept; i += 1) {
        const struct trace_event *event = &trace_events[i];
        if (!__atomic_load_n(&event->complete, __ATOMIC_ACQUIRE)) continue;
        length = snprintf(line, sizeof line, "%c %lu %lu %lu %lu %lu\n", event->phase,
            event->identity, event->epoch, event->carrier, event->lower, event->upper);
        if (length <= 0 || (size_t)length >= sizeof line) fail("linea: a trace row overflowed\n");
        report_bytes(line, (unsigned long)length);
    }
    report_bytes("counts", 6);
#define TRACE_COUNTER_WRITE(name) \
    length = snprintf(line, sizeof line, " " #name "=%lu", counts.name); \
    if (length <= 0 || (size_t)length >= sizeof line) fail("linea: a trace counter overflowed\n"); \
    report_bytes(line, (unsigned long)length);
    TRACE_COUNTER_FIELDS(TRACE_COUNTER_WRITE)
#undef TRACE_COUNTER_WRITE
    report_bytes("\n", 1);
}
#define TRACE_BEGIN(name) struct trace_ticket name = trace_begin()
#define TRACE_CAPTURE(name, phase, fiber, carrier) trace_capture(&(name), (phase), (fiber), (carrier))
#define TRACE_END(name) trace_end(&(name))
#else
#define TRACE_BEGIN(name) ((void)0)
#define TRACE_CAPTURE(name, phase, fiber, carrier) ((void)0)
#define TRACE_END(name) ((void)0)
#endif

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

#if defined(LINEA_FIBER_CAN_MIGRATE)
static int clean_runnable(struct linea_fiber *f, struct carrier *source);

/* The hint never grants work. Empty-check and publication are ordered by M;
 * a peer becoming idle later searches the queues before blocking. */
static void wake_idle_peers(struct carrier *source) {
    if (linea_fiber_metadata_held()) fail("linea: peer wakeup retained scheduler metadata\n");
    struct fiber_loop *loop = source->loop;
    if (loop == NULL) return;
    for (unsigned long i = 0; i < loop->count; i += 1) {
        struct carrier *peer = &loop->carriers[i];
        if (peer != source && __atomic_load_n(&peer->idle, __ATOMIC_ACQUIRE)) wake_carrier(peer);
    }
}
#endif

/* Called with the loop metadata lock, or the simulation's existing queue
 * lock. Waking the carrier happens only after that lock is released. */
static void enqueue_locked(struct linea_fiber *f) {
    require_metadata(f);
    struct carrier *c = f->home;
    if (f->state != runnable || f->queued || f->claimed || !f->saved) fail("linea: a runnable queue entry has no exclusive saved context\n");
    f->queued = local_lane;
    if (c->simulation != 0) {
        if (c->ready_count == c->ready_capacity) {
            size_t capacity = c->ready_capacity == 0 ? 16 : c->ready_capacity * 2;
            if (capacity < c->ready_capacity || capacity > SIZE_MAX / sizeof *c->ready) fail("linea: a simulation's run queue is too large\n");
            void *ready = realloc(c->ready, capacity * sizeof *c->ready);
            if (ready == NULL) fail("linea: a simulation's run queue could not be allocated\n");
            c->ready = ready; c->ready_capacity = capacity;
        }
        c->ready[c->ready_count++] = f;
        return;
    }
    f->next = NULL;
    struct linea_fiber **first = &c->first, **last = &c->last;
#if defined(LINEA_FIBER_CAN_MIGRATE)
    if (clean_runnable(f, c)) {
        f->queued = stealable_lane;
        first = &c->stealable_first;
        last = &c->stealable_last;
    }
#endif
    if (*last == NULL) *first = f;
    else (*last)->next = f;
    *last = f;
}

static struct linea_fiber *dequeue(struct carrier *c) {
    lock_carrier(c);
    struct linea_fiber *f = NULL;
    enum runnable_lane lane = local_lane;
    if (c->simulation != 0) {
        if (c->ready_count != 0) {
            size_t index = (size_t)linea_sim_choice((unsigned long)c->ready_count);
            f = c->ready[index];
            c->ready[index] = c->ready[--c->ready_count];
        }
    } else {
        const int take_stealable = c->stealable_first != NULL && (c->first == NULL || c->prefer_stealable);
        struct linea_fiber **first = take_stealable ? &c->stealable_first : &c->first;
        struct linea_fiber **last = take_stealable ? &c->stealable_last : &c->last;
        lane = take_stealable ? stealable_lane : local_lane;
        f = *first;
        if (f != NULL) {
            *first = f->next;
            if (*first == NULL) *last = NULL;
            f->next = NULL;
            c->prefer_stealable = !take_stealable;
        }
    }
    if (f != NULL) {
        require_metadata(f);
        if (f->queued != (int)lane || f->claimed || f->state != runnable || !f->saved) fail("linea: dispatch did not claim one saved runnable entry\n");
        f->queued = 0;
        f->claimed = dispatch_claim;
        f->claimant = c;
    }
#if defined(LINEA_FIBER_CAN_MIGRATE)
    if (c->loop != NULL) __atomic_store_n(&c->idle, f == NULL, __ATOMIC_RELEASE);
#endif
    unlock_carrier(c);
    return f;
}

static int canonical_net_kind(enum linea_op_kind kind) {
    return kind == LINEA_OP_READ || kind == LINEA_OP_WRITE || kind == LINEA_OP_ACCEPT || kind == LINEA_OP_CONNECT;
}

#if defined(LINEA_FIBER_CAN_MIGRATE)
/* A detached saved continuation has one transfer claim until it is either
 * restored to its queue or claimed directly by the receiving dispatcher. */
struct transfer_claim {
    struct linea_fiber *fiber;
    struct carrier *source;
};

/* The stack record retains its original poller after retirement. A clean
 * continuation may change queue owners repeatedly before it is dispatched. */
static int completed_io_retired(struct linea_fiber *f) {
    require_metadata(f);
    struct pending_operation *op = f->operation;
    return f->waiting == waiting_io && f->park == NULL && f->waiter == NULL &&
        op != NULL && op->owner != NULL && op->owner->loop == f->loop &&
        __atomic_load_n(&op->state, __ATOMIC_ACQUIRE) == operation_complete &&
        !op->registered && op->completion_cookie == 0 &&
        ((op->audited_net && canonical_net_kind(op->operation->kind)) ||
         (op->attempt == NULL && op->operation->kind == LINEA_OP_READABLE));
}

static int clean_runnable(struct linea_fiber *f, struct carrier *source) {
    require_metadata(f);
    TRACE_COUNT(source->loop, eligibility_checks);
#if defined(LINEA_FIBER_FORCED_HANDOFF_TEST)
    if (f->forced_transfers >= 2) { TRACE_COUNT(source->loop, ref_quota); return 0; }
#endif
    if (f->home != source || f->loop != source->loop) { TRACE_COUNT(source->loop, ref_state); return 0; }
    if (!f->proven) { TRACE_COUNT(source->loop, ref_entry); return 0; }
    if (f->bound != NULL) { TRACE_COUNT(source->loop, ref_affinity); return 0; }
    if (f->state != runnable || !f->saved) { TRACE_COUNT(source->loop, ref_state); return 0; }
    if (!f->transfer_ready || f->timer_index != no_timer || f->source_claims != 0) {
        TRACE_COUNT(source->loop, ref_source); return 0;
    }
    const int retired = (f->operation == NULL &&
          ((f->waiting == waiting_yield && f->park == NULL && f->waiter == NULL) ||
           (f->waiting == waiting_park && f->park != NULL && f->waiter != NULL))) ||
         completed_io_retired(f);
    if (!retired) { TRACE_COUNT(source->loop, ref_source); return 0; }
    return 1;
}

static struct transfer_claim reserve_ready_runnable(struct carrier *source) {
    struct transfer_claim claim = { NULL, source };
    if (source->loop == NULL) return claim;
    TRACE_BEGIN(claim_trace);
    lock_carrier(source);
    TRACE_COUNT(source->loop, claim_attempts);
    const int had_entries = source->first != NULL || source->stealable_first != NULL;
    struct linea_fiber *previous = NULL;
    for (struct linea_fiber *f = source->stealable_first; f != NULL; f = f->next) {
        if (!clean_runnable(f, source)) { previous = f; continue; }
        if (f->queued != stealable_lane || f->claimed) fail("linea: transfer found a nonexclusive runnable entry\n");
        if (previous == NULL) source->stealable_first = f->next;
        else previous->next = f->next;
        if (source->stealable_last == f) source->stealable_last = previous;
        f->next = NULL;
        f->queued = 0;
        f->claimed = transfer_claimed;
        f->claimant = source;
        claim.fiber = f;
        TRACE_COUNT(source->loop, active_claims);
        TRACE_CAPTURE(claim_trace, 'C', f, source);
        break;
    }
#if defined(LINEA_FIBER_MIGRATION_TRACE_TEST)
    if (claim.fiber == NULL) {
        for (struct linea_fiber *f = source->first; f != NULL; f = f->next) (void)clean_runnable(f, source);
    }
    if (claim.fiber == NULL && !had_entries) {
        if (source->loop->trace_counts.active_claims != 0) TRACE_COUNT(source->loop, ref_reservation);
        else TRACE_COUNT(source->loop, ref_empty);
    }
#else
    (void)had_entries;
#endif
    unlock_carrier(source);
    TRACE_END(claim_trace);
    return claim;
}

static void require_transfer(struct transfer_claim *claim) {
    struct linea_fiber *f = claim->fiber;
    if (f == NULL) fail("linea: a consumed transfer claim was reused\n");
    require_metadata(f);
    if (f->queued || f->claimed != transfer_claimed || f->claimant != claim->source ||
        f->home != claim->source || f->state != runnable || !f->saved)
        fail("linea: a transfer lost exclusive scheduling authority\n");
}

static void abort_transfer(struct transfer_claim *claim) {
    lock_carrier(claim->source);
    require_transfer(claim);
    struct linea_fiber *f = claim->fiber;
    f->claimed = no_claim;
    f->claimant = NULL;
    enqueue_locked(f);
    const int wake_peers = f->queued == stealable_lane;
    claim->fiber = NULL;
#if defined(LINEA_FIBER_MIGRATION_TRACE_TEST)
    if (claim->source->loop->trace_counts.active_claims == 0) fail("linea: a trace claim underflowed\n");
    claim->source->loop->trace_counts.active_claims -= 1;
#endif
    unlock_carrier(claim->source);
    wake_carrier(claim->source);
    if (wake_peers) wake_idle_peers(claim->source);
}

static int finish_transfer(struct transfer_claim *claim, struct carrier *target, int dispatch) {
    struct carrier *source = claim->source;
    if (dispatch && current_carrier() != target) fail("linea: a thief claimed another carrier's dispatch\n");
    lock_carrier(source);
    require_transfer(claim);
    struct linea_fiber *f = claim->fiber;
    TRACE_COUNT(source->loop, commit_attempts);
    if (target == source || target->loop != source->loop) {
        TRACE_COUNT(source->loop, ref_target);
        unlock_carrier(source);
        return 0;
    }
    if (dispatch && target->executing != NULL) fail("linea: a running carrier claimed stolen work\n");
    if (!clean_runnable(f, source)) {
        unlock_carrier(source);
        return 0;
    }
#if defined(LINEA_FIBER_FORCED_HANDOFF_TEST)
    f->forced_transfers += 1;
#endif
    f->home = target;
#if defined(LINEA_FIBER_BUSY_SOURCE_TEST)
    if (dispatch && f == busy_test.worker && !busy_test.claimed) {
        if (source != busy_test.source || source->executing != busy_test.body || busy_test.body == NULL)
            fail("linea: a continuation was not stolen from its busy Linea source\n");
        busy_test.claimed = 1;
    }
#endif
#if defined(LINEA_FIBER_MIGRATION_TRACE_TEST)
    f->trace_transfer_epoch = f->trace_epoch;
    TRACE_COUNT(source->loop, transfers);
    if (!f->trace_ever_transferred) {
        f->trace_ever_transferred = 1;
        TRACE_COUNT(source->loop, ever_transferred);
    }
    if (source->loop->trace_counts.active_claims == 0) fail("linea: a trace claim underflowed\n");
    source->loop->trace_counts.active_claims -= 1;
#endif
    f->claimed = dispatch ? dispatch_claim : no_claim;
    f->claimant = dispatch ? target : NULL;
    if (!dispatch) enqueue_locked(f);
    const int wake_peers = !dispatch && f->queued == stealable_lane;
    if (dispatch) __atomic_store_n(&target->idle, 0, __ATOMIC_RELEASE);
    claim->fiber = NULL;
    unlock_carrier(source);
    if (!dispatch) wake_carrier(target);
    if (wake_peers) wake_idle_peers(target);
    return 1;
}

#if defined(LINEA_FIBER_MIGRATION_TEST)
static int commit_transfer(struct transfer_claim *claim, struct carrier *target) {
    return finish_transfer(claim, target, 0);
}
#endif

#if !defined(LINEA_FIBER_FORCED_HANDOFF_TEST)
static struct linea_fiber *steal_for_dispatch(struct carrier *target) {
    struct fiber_loop *loop = target->loop;
    if (loop == NULL || loop->count < 2) return NULL;
    if (current_carrier() != target) fail("linea: a thief selected work for another carrier\n");
    for (unsigned long visited = 0; visited < loop->count; visited += 1) {
        const unsigned long index = target->next_victim;
        target->next_victim = index + 1 == loop->count ? 0 : index + 1;
        struct carrier *source = &loop->carriers[index];
        if (source == target) continue;
        struct transfer_claim claim = reserve_ready_runnable(source);
        if (claim.fiber == NULL) continue;
        struct linea_fiber *f = claim.fiber;
        if (finish_transfer(&claim, target, 1)) return f;
        abort_transfer(&claim);
    }
    return NULL;
}
#endif
#endif

#if defined(LINEA_FIBER_FORCED_HANDOFF_TEST)
/* Internal deterministic scheduling configuration, compiled only into the
 * bounded Linea integration-test runtime. This supplies policy, not observation
 * results: the Linea programs observe their actual carriers and local values.
 * No replacement fiber/task implementation or application native source is
 * linked. Emitted-call coverage gates execution of these closed-world entries. */
static pthread_mutex_t handoff_lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t handoff_changed = PTHREAD_COND_INITIALIZER;
static int handoff_parked;
#if defined(LINEA_FIBER_STALE_COOKIE_TEST)
/* No fiber or pending-operation pointer is retained by this delayed event. */
static struct carrier *stale_owner;
static uint64_t stale_cookie;
static int replay_requested, replay_finished, replay_rejected;
#endif
#if defined(LINEA_FIBER_DELAY_NOTIFIER_TEST)
static int handoff_delayed, handoff_contended;
static unsigned handoff_busy;
#endif

void fiber_test_pause(enum linea_fiber_pause_point point) {
    struct carrier *source = current_carrier();
    if (linea_fiber_metadata_held()) fail("linea: a test scheduler policy retained metadata\n");
#if defined(LINEA_FIBER_STALE_COOKIE_TEST)
    if (point == linea_fiber_reclaimed) {
        if (source != NULL) fail("linea: the reclamation probe requires a system-thread joiner\n");
        must(pthread_mutex_lock(&handoff_lock));
        if (replay_finished) {
            must(pthread_mutex_unlock(&handoff_lock));
            return;
        }
        struct carrier *owner = stale_owner;
        if (owner == NULL) fail("linea: the reclamation probe captured no I/O event\n");
        replay_requested = 1;
        must(pthread_mutex_unlock(&handoff_lock));
        wake_carrier(owner);
        must(pthread_mutex_lock(&handoff_lock));
        while (!replay_finished) must(pthread_cond_wait(&handoff_changed, &handoff_lock));
        const int rejected = replay_rejected;
        must(pthread_mutex_unlock(&handoff_lock));
        if (!rejected) fail("linea: a reclaimed fiber's stale poll event was accepted\n");
#if defined(LINEA_COMPLETION_STALE_COOKIE_TEST)
        const char message[] = "native completion: reclaimed cookie rejected during slot reuse\n";
#else
        const char message[] = "native migration: stale poll cookie rejected after reclamation\n";
#endif
        report_bytes(message, sizeof message - 1);
        return;
    }
#endif
#if defined(LINEA_FIBER_DELAY_NOTIFIER_TEST)
    if (point == linea_fiber_notified && source == NULL) {
        must(pthread_mutex_lock(&handoff_lock));
        if (!handoff_contended) {
            handoff_delayed = 1;
            while (!handoff_contended) must(pthread_cond_wait(&handoff_changed, &handoff_lock));
            handoff_delayed = 0;
            must(pthread_cond_broadcast(&handoff_changed));
            while (handoff_busy < 2) must(pthread_cond_wait(&handoff_changed, &handoff_lock));
        }
        must(pthread_mutex_unlock(&handoff_lock));
        return;
    }
    if (point == linea_fiber_source_busy) {
        must(pthread_mutex_lock(&handoff_lock));
        handoff_busy += 1;
        handoff_contended = 1;
        must(pthread_cond_broadcast(&handoff_changed));
        while (handoff_delayed) must(pthread_cond_wait(&handoff_changed, &handoff_lock));
        must(pthread_mutex_unlock(&handoff_lock));
        return;
    }
#endif
    if (point == linea_fiber_parked) {
        must(pthread_mutex_lock(&handoff_lock));
        handoff_parked = 1;
        must(pthread_cond_broadcast(&handoff_changed));
        must(pthread_mutex_unlock(&handoff_lock));
    } else if (point == linea_fiber_entering) {
        struct linea_fiber *f = source->executing;
        lock_fiber(f);
#if defined(LINEA_FIBER_UNPROVEN_ENTRY_TEST)
        f->proven = 0;
#elif !defined(LINEA_FIBER_ENTRY_PROVENANCE_TEST)
        f->proven = 1;
#endif
#if defined(LINEA_FIBER_MIGRATION_TRACE_TEST)
        if (!f->trace_entered) {
            f->trace_entered = 1;
            f->trace_initially_eligible = f->proven && f->bound == NULL;
            TRACE_COUNT(f->loop, started);
            if (f->trace_initially_eligible) TRACE_COUNT(f->loop, initially_eligible);
        }
        trace_update_eligibility(f);
#endif
#if defined(LINEA_FIBER_REFUSAL_PROBES_TEST)
        if (clean_runnable(f, source)) fail("linea: an executing fiber was transferable\n");
#endif
        unlock_fiber(f);
    } else if (point == linea_fiber_transfer_ready) {
#if defined(LINEA_FIBER_REFUSAL_PROBES_TEST)
        /* A real source claim excludes transfer without changing saved state. */
        lock_carrier(source);
        struct linea_fiber *candidate = source->stealable_first;
        if (candidate != NULL) {
            candidate->source_claims += 1;
            if (clean_runnable(candidate, source)) fail("linea: a source-owned fiber was transferable\n");
            candidate->source_claims -= 1;
        }
        unlock_carrier(source);
#endif
        struct transfer_claim claim = reserve_ready_runnable(source);
        if (claim.fiber == NULL) return;
#if defined(LINEA_FIBER_REFUSAL_PROBES_TEST)
        struct transfer_claim duplicate = reserve_ready_runnable(source);
        if (duplicate.fiber != NULL) fail("linea: a reserved fiber was claimed twice\n");
        if (commit_transfer(&claim, source)) fail("linea: a same-carrier transfer committed\n");
#endif
        if (source->loop->count != 2) fail("linea: forced handoff requires two carriers\n");
        struct carrier *target = source == &source->loop->carriers[0] ?
            &source->loop->carriers[1] : &source->loop->carriers[0];
        if (!commit_transfer(&claim, target)) abort_transfer(&claim);
        /* No fiber access after destination publication. */
    }
}
#endif

/* A source lock protects this pointer. M owns the scheduling transition and
 * queue publication together; the source never independently queues it. */
static void notify(struct linea_fiber *f) {
    struct carrier *wake = NULL;
    TRACE_BEGIN(runnable_trace);
    lock_fiber(f);
    if (f->state == parking) f->state = notified;
    else if (f->state == parked) {
        f->state = runnable;
        TRACE_CAPTURE(runnable_trace, 'R', f, f->home);
        enqueue_locked(f);
        if (f->home->simulation == 0) wake = f->home;
    }
    unlock_fiber(f);
    TRACE_END(runnable_trace);
    if (wake != NULL) wake_carrier(wake);
#if defined(LINEA_FIBER_MIGRATION_TEST)
    if (wake != NULL) linea_fiber_pause(linea_fiber_notified);
#endif
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

static void timer_remove_locked(struct linea_fiber *f) {
    require_metadata(f);
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

static int timer_add_locked(struct linea_fiber *f) {
    require_metadata(f);
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

static void timer_remove(struct linea_fiber *f) {
    lock_fiber(f);
    timer_remove_locked(f);
    unlock_fiber(f);
}

static int timer_add(struct linea_fiber *f) {
    lock_fiber(f);
    const int error = timer_add_locked(f);
    unlock_fiber(f);
    return error;
}

#if defined(LINEA_FIBER_CAN_MIGRATE)
static int requeue_saved_dispatch(struct carrier *source, struct linea_fiber *f, int ready) {
    TRACE_BEGIN(ready_trace);
    lock_fiber(f);
    if (f->claimed != dispatch_claim || f->claimant != source || f->queued ||
        f->home != source || f->state != runnable || !f->saved)
        fail("linea: source retirement lost its dispatch claim\n");
    if (ready && (f->source_claims != 0 || f->timer_index != no_timer)) {
        unlock_fiber(f);
        return 0;
    }
    f->transfer_ready = ready;
    if (ready) TRACE_CAPTURE(ready_trace, 'N', f, source);
    f->claimed = no_claim;
    f->claimant = NULL;
    enqueue_locked(f);
    const int wake_peers = f->queued == stealable_lane;
    unlock_fiber(f);
    TRACE_END(ready_trace);
    wake_carrier(source);
    if (wake_peers) wake_idle_peers(source);
    return 1;
}

/* Completion retires kernel state on A before notifying. The saved C frame
 * still owns its pending record and result, which B consumes after resuming. */
static int normalize_completed_io(struct carrier *source, struct linea_fiber *f) {
    lock_fiber(f);
    const int ready = f->loop != NULL && f->proven && f->bound == NULL && !f->transfer_ready &&
        f->state == runnable && f->saved && f->claimed == dispatch_claim &&
        f->claimant == source && f->home == source && f->source_claims == 0 &&
        f->timer_index == no_timer && completed_io_retired(f) && f->operation->owner == source;
    if (ready) TRACE_COUNT(f->loop, normalization_attempts);
    unlock_fiber(f);
    if (!ready || !requeue_saved_dispatch(source, f, 1)) return 0;
    linea_fiber_pause(linea_fiber_transfer_ready);
    /* Publication can immediately retire this stack on B. */
    return 1;
}

/* Dispatch owns the saved continuation throughout source retirement. The
 * resumed fiber still reacquires its logical source lock and clears its
 * own stack waiter; only carrier references are retired here. */
static int normalize_completed_park(struct carrier *source, struct linea_fiber *f) {
    lock_fiber(f);
    if (f->loop == NULL || !f->proven || f->bound != NULL || f->transfer_ready ||
        f->waiting != waiting_park || f->state != runnable || !f->saved ||
        f->claimed != dispatch_claim || f->claimant != source || f->home != source ||
        f->source_claims != 0 || f->operation != NULL) {
        unlock_fiber(f);
        return 0;
    }
    struct linea_park *park = f->park;
    struct linea_fiber_waiter *waiter = f->waiter;
    TRACE_COUNT(f->loop, normalization_attempts);
    unlock_fiber(f);
    if (park == NULL || waiter == NULL) fail("linea: a saved park lost its logical waiter\n");
    if (linea_fiber_metadata_held()) fail("linea: a source lock followed scheduler metadata\n");
    const int locked = pthread_mutex_trylock(&park->lock);
    if (locked == EBUSY) {
        lock_fiber(f);
        TRACE_COUNT(f->loop, normalization_busy);
        unlock_fiber(f);
        (void)requeue_saved_dispatch(source, f, 0);
        linea_fiber_pause(linea_fiber_source_busy);
        return 1;
    }
    must(locked);
    const int unlinked = !waiter->linked;
    if (unlinked) timer_remove(f);
    linea_park_unlock(park);
    if (!unlinked) return 0;
    if (!requeue_saved_dispatch(source, f, 1)) return 0;
    linea_fiber_pause(linea_fiber_transfer_ready);
    /* Destination publication can immediately release the stack. */
    return 1;
}
#endif

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
    for (;;) {
        lock_carrier(c);
        if (c->timer_count == 0 || c->timers[0]->deadline > instant) { unlock_carrier(c); return; }
        struct linea_fiber *f = c->timers[0];
        timer_remove_locked(f);
        f->source_claims += 1;
        const enum waiting kind = f->waiting;
        struct pending_operation *operation = f->operation;
        struct linea_park *park = f->park;
        struct linea_fiber_waiter *waiter = f->waiter;
        unlock_carrier(c);
        if (kind == waiting_io) complete_operation(operation, 0);
        else {
            linea_park_lock(park);
            if (waiter->linked) {
                unlink_waiter(park, waiter);
                waiter->expired = 1;
                notify(f);
            }
            linea_park_unlock(park);
        }
        lock_fiber(f);
        f->source_claims -= 1;
        unlock_fiber(f);
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

#if defined(LINEA_FIBER_PLATFORM_STATE_TEST)
__attribute__((noinline))
#endif
static void leave_fiber(struct linea_fiber *f, int ending) {
#if defined(LINEA_FIBER_PLATFORM_STATE_TEST)
    volatile unsigned char protected_frame[32];
    for (unsigned i = 0; i < sizeof protected_frame; i += 1) protected_frame[i] = (unsigned char)(i * 7U + 29U);
#if __has_feature(address_sanitizer)
    platform_fake_frame(protected_frame);
#endif
#endif
    lock_fiber(f);
    struct carrier *c = f->home;
    const enum waiting kind = f->waiting;
    unlock_fiber(f);
    if (linea_fiber_metadata_held()) fail("linea: a context switch retained scheduler metadata\n");
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
    if (kind == waiting_park) linea_fiber_pause(linea_fiber_before_switch);
    linea_context_switch(&f->context, &c->scheduler);
    finish_switch(f->asan_stack);
#if defined(LINEA_FIBER_PLATFORM_STATE_TEST)
    struct carrier *resumed = current_carrier();
    platform_check(resumed, 1);
#if __has_feature(address_sanitizer)
    platform_fake_frame(protected_frame);
#endif
    for (unsigned i = 0; i < sizeof protected_frame; i += 1)
        if (protected_frame[i] != (unsigned char)(i * 7U + 29U)) fail("linea: a protected frame changed across transfer\n");
    if (resumed != c) {
        __atomic_fetch_add(&platform_migrations, 1U, __ATOMIC_RELEASE);
#if defined(LINEA_FIBER_SANITIZER_FAULT_TEST)
        platform_fault_target(protected_frame);
#endif
    }
#endif
#if defined(LINEA_FIBER_MIGRATION_TRACE_TEST)
    TRACE_BEGIN(resume_trace);
    lock_fiber(f);
    if (f->trace_transfer_epoch != 0 && f->trace_transfer_epoch == f->trace_epoch &&
        f->trace_resumed_epoch != f->trace_epoch) {
        TRACE_CAPTURE(resume_trace, 'X', f, current_carrier());
        f->trace_resumed_epoch = f->trace_epoch;
    }
    unlock_fiber(f);
    TRACE_END(resume_trace);
#endif
}

void linea_fiber_yield(void) {
    struct linea_fiber *f = current_fiber();
    if (f == NULL || linea_foreign_depth() != 0) return;
    lock_fiber(f);
    if (f->state != running) fail("linea: a nonrunning fiber yielded\n");
    f->waiting = waiting_yield;
    f->state = parking;
    unlock_fiber(f);
    leave_fiber(f, 0);
    lock_fiber(f);
    f->waiting = waiting_none;
    unlock_fiber(f);
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
    lock_fiber(f);
    f->waiting = waiting_park;
    f->park = p;
    f->waiter = &waiter;
    f->deadline = deadline;
    unlock_fiber(f);
    if (timer_add(f) != 0) fail("linea: a fiber's deadline could not be allocated\n");
    lock_fiber(f);
    f->state = parking;
    unlock_fiber(f);
    p->fibers = &waiter;
    linea_park_unlock(p);
    leave_fiber(f, 0);
    linea_park_lock(p);
    unlink_waiter(p, &waiter);
    lock_fiber(f);
    f->park = NULL;
    f->waiter = NULL;
    f->waiting = waiting_none;
    unlock_fiber(f);
    return waiter.expired;
}

static void fiber_entry(void *argument) {
    struct linea_fiber *f = argument;
    finish_switch(f->asan_stack);
#if defined(LINEA_FIBER_PLATFORM_STATE_TEST)
    platform_fibre_begin();
#endif
    f->entry(f->argument);
    lock_fiber(f);
    f->state = finished;
    unlock_fiber(f);
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
#if !defined(LINEA_FIBER_READINESS_TEST)
    c->completion = linea_completion_open(c->wake);
#if defined(LINEA_FIBER_RING_TEST)
    if (c->completion == NULL) {
#if defined(LINEA_FIBER_RING_FALLBACK_TEST)
        const char message[] = "native completion: unavailable kernel used readiness fallback\n";
        report_bytes(message, sizeof message - 1);
#else
        return ENOTSUP;
#endif
    }
#endif
#endif
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
    struct carrier *c = pending->owner;
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
    if (pending->completion_cookie != 0) fail("linea: an operation disarmed a live kernel request\n");
    if (!pending->registered) return;
    struct carrier *c = pending->owner;
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
    struct carrier *c = pending->owner;
    if (c->simulation != 0) {
        pending->next = c->pending;
        c->pending = pending;
        pending->registered = 1;
        return 0;
    }
    if (pending->operation->kind == LINEA_OP_SLEEP) return 0;
    if (pending->audited_net && !pending->readiness_only && c->completion != NULL) {
        pending->completion_cookie = linea_completion_submit(c->completion, pending->operation, pending);
        if (pending->completion_cookie != 0) return 0;
    }
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
    if (pending->owner->simulation != 0) return linea_sim_ready(pending->operation->fd, (uint8_t)(kind == LINEA_OP_WRITABLE)) ? 0 : -(long)EAGAIN;
    struct pollfd fd = { pending->operation->fd, kind == LINEA_OP_WRITABLE ? POLLOUT : POLLIN, 0 };
    int answer;
    do { answer = poll(&fd, 1, 0); } while (answer < 0 && errno == EINTR);
    if (answer < 0) return -(long)errno;
    return answer == 0 ? -(long)EAGAIN : 0;
}

static void complete_operation(struct pending_operation *pending, int readable) {
    unsigned expected = operation_armed;
    if (!__atomic_compare_exchange_n(&pending->state, &expected, operation_claimed, 0, __ATOMIC_ACQ_REL, __ATOMIC_ACQUIRE)) return;
    if (pending->completion_cookie != 0) {
        if (readable) fail("linea: readiness claimed a kernel-owned operation\n");
        linea_completion_cancel(pending->owner->completion, pending->completion_cookie);
        return;
    }
    struct linea_fiber *f = pending->fiber;
    const unsigned long deadline = pending->operation->deadline_ns;
#if defined(LINEA_FIBER_FORCE_REARM_TEST) || defined(LINEA_FIBER_FORCE_REARM_FAILURE_TEST)
    /* Bounded fault policy: readiness can be stale without consuming bytes.
     * The next real attempt still reads the actual socket and its real result. */
    static int forced_rearm;
    const int injected = readable && pending->audited_net && pending->operation->kind == LINEA_OP_READ && !forced_rearm;
    long result;
    if (injected) {
        forced_rearm = 1;
        result = -(long)EAGAIN;
    } else result = attempt_operation(pending);
#else
    long result = attempt_operation(pending);
#endif
    const int expired = deadline != 0 && now() >= deadline;
    if (result == -(long)EAGAIN && !expired && readable) {
        /* A readiness notification can be stale without completing the
         * operation. Its next arming gets a new generation. */
        if (pending->owner->simulation != 0) {
            __atomic_store_n(&pending->state, operation_armed, __ATOMIC_RELEASE);
            return;
        }
#if defined(LINEA_FIBER_FORCE_REARM_TEST)
        const uint64_t old_cookie = ((uint64_t)pending->slot << 32) |
            io_slot_at(pending->owner, pending->slot)->generation;
#endif
        disarm_operation(pending);
#if defined(LINEA_FIBER_FORCE_REARM_FAILURE_TEST)
        /* Fail the temporary operation's next actual dup, without closing the
         * Connection's owned descriptor or replacing arm_operation itself. */
        if (injected) pending->operation->fd = -1;
#endif
        const int error = arm_operation(pending);
        if (error == 0) {
            __atomic_store_n(&pending->state, operation_armed, __ATOMIC_RELEASE);
#if defined(LINEA_FIBER_FORCE_REARM_TEST)
            if (injected) {
                const uint64_t next_cookie = ((uint64_t)pending->slot << 32) |
                    io_slot_at(pending->owner, pending->slot)->generation;
                if (old_cookie == next_cookie) fail("linea: a rearmed operation reused its stale cookie\n");
                const char message[] = "native migration: spurious readiness rearmed with a new cookie\n";
                report_bytes(message, sizeof message - 1);
            }
#endif
            return;
        }
#if defined(LINEA_FIBER_FORCE_REARM_FAILURE_TEST)
        if (injected) {
            if (error != EBADF || pending->registered) fail("linea: the refused rearm retained its watch\n");
            const char message[] = "native migration: rearm failure propagated after retirement\n";
            report_bytes(message, sizeof message - 1);
        }
#endif
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

static long perform_operation(struct linea_op *op, linea_fiber_attempt attempt, int audited_net) {
    struct linea_fiber *f = current_fiber();
    if (f == NULL) fail("linea: an operation has no executing fiber\n");
    /* Scheduler callbacks have no current fiber to restrict. Audited socket
     * paths and callback-free readiness leave no persistent thread state.
     * Bind every other invocation, including unknown callbacks, first. */
    audited_net = audited_net && canonical_net_kind(op->kind) && attempt != NULL;
    const int neutral = audited_net ||
        (attempt == NULL && op->kind == LINEA_OP_READABLE);
    if (!neutral)
        linea_fiber_restrict_current();
    if (op->deadline_ns != 0 && now() >= op->deadline_ns) return op->kind == LINEA_OP_SLEEP ? 0 : -(long)ETIMEDOUT;
    struct pending_operation pending = { .operation = op, .attempt = attempt, .fiber = f, .owner = f->home, .audited_net = audited_net,
        .state = operation_idle, .slot = 0, .registered = 0, .result = 0 };
#if defined(LINEA_COMPLETION_CAPACITY_TEST) || defined(LINEA_COMPLETION_GENERATION_TEST)
    /* Exercise admission even if a producer wins the race to the first read.
     * The real backend still owns and performs every consuming operation. */
    const long immediate = audited_net && op->kind == LINEA_OP_READ ? -(long)EAGAIN : attempt_operation(&pending);
#else
    const long immediate = attempt_operation(&pending);
#endif
    if (immediate != -(long)EAGAIN) return immediate;
    lock_fiber(f);
    f->waiting = waiting_io;
    f->operation = &pending;
    f->deadline = op->deadline_ns;
    f->state = parking;
    unlock_fiber(f);
    /* Acquire timer storage before publishing a kernel request. An allocation
     * refusal must not return a buffer which the kernel can still access. */
    int error = timer_add(f);
    if (error == 0) error = arm_operation(&pending);
    if (error != 0) {
        disarm_operation(&pending);
        timer_remove(f);
        lock_fiber(f);
        f->state = running;
        f->waiting = waiting_none;
        f->operation = NULL;
        unlock_fiber(f);
        return -(long)error;
    }
    __atomic_store_n(&pending.state, operation_armed, __ATOMIC_RELEASE);
    leave_fiber(f, 0);
    if (__atomic_load_n(&pending.state, __ATOMIC_ACQUIRE) != operation_complete) fail("linea: an incomplete operation resumed\n");
    lock_fiber(f);
    f->waiting = waiting_none;
    f->operation = NULL;
    unlock_fiber(f);
    return pending.result;
}

long linea_fiber_perform(struct linea_op *op, linea_fiber_attempt attempt) {
    return perform_operation(op, attempt, 0);
}

long linea_fiber_perform_net(struct linea_op *op, linea_fiber_attempt attempt) {
    return perform_operation(op, attempt, 1);
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

/* Validate stable carrier-owned slot storage before following any pointer into
 * an operation's stack. This is shared by real events and delayed-event probes. */
static int dispatch_io_cookie(struct carrier *c, uint64_t cookie) {
    const uint32_t index = (uint32_t)(cookie >> 32);
    if (index >= c->slots_made) return 0;
    struct io_slot *slot = io_slot_at(c, index);
    if (slot->generation != (uint32_t)cookie || slot->operation == NULL) return 0;
#if defined(LINEA_FIBER_FORCE_TIMER_TIE_TEST)
    static int forced_tie;
    struct pending_operation *pending = slot->operation;
    if (!forced_tie && pending->audited_net && pending->operation->kind == LINEA_OP_READ) {
        forced_tie = 1;
        /* Actual descriptor readiness is already present. Schedule an expired
         * timer and let the real timer claimant attempt that same read first. */
        struct linea_fiber *f = pending->fiber;
        const unsigned long instant = now();
        lock_fiber(f);
        if (f->state != parked || !f->saved || f->home != c ||
            f->waiting != waiting_io || f->operation != pending || f->timer_index != no_timer)
            fail("linea: the readiness tie probe lost its parked operation\n");
        f->deadline = instant;
        pending->operation->deadline_ns = instant;
        unlock_fiber(f);
        if (timer_add(f) != 0) fail("linea: the readiness tie timer could not be prepared\n");
        expire_timers(c);
        /* Completion can publish the task: use no f/pending/slot pointer now. */
        const char message[] = "native migration: timer-first readiness tie completed\n";
        report_bytes(message, sizeof message - 1);
        return 1;
    }
#endif
#if defined(LINEA_FIBER_STALE_COOKIE_TEST)
    must(pthread_mutex_lock(&handoff_lock));
    if (stale_owner == NULL) {
        stale_owner = c;
        stale_cookie = cookie;
    }
    must(pthread_mutex_unlock(&handoff_lock));
#endif
    complete_operation(slot->operation, 1);
    return 1;
}

#if defined(LINEA_FIBER_STALE_COOKIE_TEST)
static void replay_stale_cookie(struct carrier *c) {
    must(pthread_mutex_lock(&handoff_lock));
    if (!replay_requested || stale_owner != c) {
        must(pthread_mutex_unlock(&handoff_lock));
        return;
    }
    const uint64_t cookie = stale_cookie;
    replay_requested = 0;
    must(pthread_mutex_unlock(&handoff_lock));
#if defined(LINEA_COMPLETION_STALE_COOKIE_TEST)
    const int rejected = linea_completion_replay_stale(c->completion, cookie);
    if (rejected < 0) {
        must(pthread_mutex_lock(&handoff_lock));
        replay_requested = 1;
        must(pthread_mutex_unlock(&handoff_lock));
        /* The next reader may already be dequeued but not yet submitted.
         * Leave a wake for the scheduler turn after it parks. */
        wake_carrier(c);
        return;
    }
#else
    const int rejected = !dispatch_io_cookie(c, cookie);
#endif
    must(pthread_mutex_lock(&handoff_lock));
    replay_rejected = rejected;
    replay_finished = 1;
    must(pthread_cond_broadcast(&handoff_changed));
    must(pthread_mutex_unlock(&handoff_lock));
}
#endif

static void drain_completions(struct carrier *c) {
    linea_completion_flush(c->completion);
    struct linea_completion_result result;
    while (linea_completion_next(c->completion, &result)) {
        struct pending_operation *pending = result.pending;
        struct linea_fiber *f = pending->fiber;
        if (pending->owner != c || pending->completion_cookie == 0 || pending->registered)
            fail("linea: a kernel completion changed its poller ownership\n");
        unsigned expected = operation_armed;
        if (!__atomic_compare_exchange_n(&pending->state, &expected, operation_claimed, 0, __ATOMIC_ACQ_REL, __ATOMIC_ACQUIRE) && expected != operation_claimed)
            fail("linea: a kernel completion lost finalization authority\n");
#if defined(LINEA_COMPLETION_STALE_COOKIE_TEST)
        must(pthread_mutex_lock(&handoff_lock));
        if (stale_owner == NULL) {
            stale_owner = c;
            stale_cookie = pending->completion_cookie;
        }
        must(pthread_mutex_unlock(&handoff_lock));
#endif
        pending->completion_cookie = 0;
        long answer = result.result;
        if (answer == -(long)ECANCELED && result.expired) answer = -(long)ETIMEDOUT;
#if defined(LINEA_FIBER_RING_TEST)
        if (result.expired && !result.cancel_submitted)
            fail("linea: the timed-out kernel operation bypassed cancellation\n");
        const char message[] = "native completion: own and control requests retired before migration\n";
        report_bytes(message, sizeof message - 1);
#endif
        const int connect_ready = pending->operation->kind == LINEA_OP_CONNECT &&
            (result.result >= 0 || (result.result == -(long)ECANCELED && result.expired));
        const int retry_native = result.result == -(long)EAGAIN || result.result == -(long)EINTR ||
            result.result == -(long)EINVAL || result.result == -(long)EOPNOTSUPP;
        if (connect_ready || retry_native) {
            /* Connect readiness needs the canonical SO_ERROR check. A CQE
             * error permits native fallback only after every submitted
             * kernel request has relinquished its references. */
            pending->readiness_only = 1;
#if defined(LINEA_COMPLETION_UNSUPPORTED_TEST)
            const char fallback[] = "native completion: unsupported operation retired before readiness fallback\n";
            report_bytes(fallback, sizeof fallback - 1);
#endif
            answer = attempt_operation(pending);
            const unsigned long deadline = pending->operation->deadline_ns;
            const int expired = result.expired || (deadline != 0 && now() >= deadline);
            if (answer == -(long)EAGAIN && !expired) {
                const int error = arm_operation(pending);
                if (error == 0) {
                    __atomic_store_n(&pending->state, operation_armed, __ATOMIC_RELEASE);
                    continue;
                }
                answer = -(long)error;
            } else if (answer == -(long)EAGAIN) answer = -(long)ETIMEDOUT;
        }
        timer_remove(f);
        pending->result = answer;
        __atomic_store_n(&pending->state, operation_complete, __ATOMIC_RELEASE);
        notify(f);
        /* No pending/fiber access after publication can permit reclamation. */
    }
}

static void poll_carrier(struct carrier *c, int poll_only) {
    drain_completions(c);
    enum { batch = 32 };
    lock_carrier(c);
    const unsigned long deadline = c->timer_count == 0 ? 0 : c->timers[0]->deadline;
    unlock_carrier(c);
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
    if (linea_completion_retry(c->completion) && (timeout < 0 || timeout > 1)) timeout = 1;
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
        (void)dispatch_io_cookie(c, cookie);
    }
    drain_completions(c);
#if defined(LINEA_FIBER_STALE_COOKIE_TEST)
    replay_stale_cookie(c);
#endif
}

static void run_fiber(struct carrier *c, struct linea_fiber *f) {
#if defined(LINEA_FIBER_CAN_MIGRATE)
    if (normalize_completed_io(c, f)) return;
    if (normalize_completed_park(c, f)) return;
#endif
    timer_remove(f);
    lock_fiber(f);
    if (f->state != runnable || f->claimed != dispatch_claim || f->claimant != c || f->home != c || f->queued || !f->saved) fail("linea: dispatch lost its saved runnable claim\n");
    f->claimed = 0;
    f->claimant = NULL;
    f->saved = 0;
#if defined(LINEA_FIBER_CAN_MIGRATE)
    f->transfer_ready = 0;
#endif
    f->state = running;
    c->executing = f;
    unlock_fiber(f);
#if __has_feature(thread_sanitizer)
    if (f->tsan_fiber == NULL) f->tsan_fiber = __tsan_create_fiber(0);
#endif
    linea_thread_guard_prepare((unsigned long)f->mapping, (unsigned long)f->mapping + guard_bytes);
    linea_fiber_pause(linea_fiber_entering);
#if __has_feature(address_sanitizer)
    __sanitizer_start_switch_fiber(&c->asan_stack, f->stack, f->stack_bytes);
#endif
#if __has_feature(thread_sanitizer)
    __tsan_switch_to_fiber(f->tsan_fiber, 0);
#endif
    if (linea_fiber_metadata_held()) fail("linea: dispatch retained scheduler metadata\n");
    linea_context_switch(&c->scheduler, &f->context);
    finish_switch(c->asan_stack);
#if defined(LINEA_FIBER_PLATFORM_STATE_TEST)
    platform_check(c, 0);
#endif
    lock_fiber(f);
    c->executing = NULL;
    f->saved = 1;
    const enum waiting kind = f->waiting;
    unlock_fiber(f);
    if (kind == waiting_park) linea_fiber_pause(linea_fiber_context_saved);
    struct carrier *wake = NULL;
    void (*ended)(void *) = NULL;
    void *argument = NULL;
    int became_parked = 0;
    TRACE_BEGIN(runnable_trace);
    TRACE_BEGIN(ready_trace);
    lock_fiber(f);
    if (f->state == parking) {
        f->state = parked;
        became_parked = 1;
        if (kind == waiting_yield) {
            f->state = runnable;
            TRACE_CAPTURE(runnable_trace, 'R', f, c);
#if defined(LINEA_FIBER_CAN_MIGRATE)
            f->transfer_ready = f->proven && f->bound == NULL && f->timer_index == no_timer &&
                f->source_claims == 0 && f->park == NULL && f->waiter == NULL && f->operation == NULL;
            if (f->transfer_ready) TRACE_CAPTURE(ready_trace, 'N', f, c);
#endif
            enqueue_locked(f);
            if (c->simulation == 0) wake = c;
        }
    } else if (f->state == notified) {
        f->state = runnable;
        TRACE_CAPTURE(runnable_trace, 'R', f, c);
        enqueue_locked(f);
        if (c->simulation == 0) wake = c;
    } else if (f->state == finished) {
        if (f->source_claims != 0) fail("linea: a finished fiber retained a source reference\n");
        f->retired = 1;
#if defined(LINEA_FIBER_MIGRATION_TRACE_TEST)
        TRACE_COUNT(f->loop, retired);
        if (!f->trace_ever_eligible) TRACE_COUNT(f->loop, never_eligible);
        trace_update_eligibility(f);
#endif
        ended = f->finished;
        argument = f->argument;
    } else fail("linea: a fiber switched in an invalid scheduling state\n");
#if defined(LINEA_FIBER_CAN_MIGRATE)
    const int wake_peers = f->queued == stealable_lane;
#endif
    unlock_fiber(f);
    TRACE_END(runnable_trace);
    TRACE_END(ready_trace);
    if (became_parked && (kind == waiting_park || kind == waiting_io)) linea_fiber_pause(linea_fiber_parked);
    if (wake != NULL) wake_carrier(wake);
#if defined(LINEA_FIBER_CAN_MIGRATE)
    if (wake_peers) wake_idle_peers(c);
#endif
#if defined(LINEA_FIBER_MIGRATION_TEST)
    if (kind == waiting_yield) linea_fiber_pause(linea_fiber_transfer_ready);
#endif
#if defined(LINEA_FIBER_SANITIZER_FAULT_TEST) && __has_feature(thread_sanitizer)
    if (kind == waiting_yield) platform_fault_source(c);
#endif
    /* Publication may let the joiner immediately reclaim the fiber. */
    if (ended != NULL) ended(argument);
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
#if defined(LINEA_FIBER_PLATFORM_STATE_TEST)
    platform_carrier_begin(c);
#endif
    (void)linea_io_switch(c->loop->identity);
    while (!__atomic_load_n(&c->loop->stop, __ATOMIC_ACQUIRE)) {
        expire_timers(c);
        struct linea_fiber *f = dequeue(c);
#if defined(LINEA_FIBER_AUTO_STEAL)
#if defined(LINEA_FIBER_BUSY_SOURCE_TEST)
        if (f == NULL) busy_test_wait(c);
#endif
        if (f == NULL) f = steal_for_dispatch(c);
#endif
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
    linea_completion_close(c->completion);
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
    int error = pthread_mutex_init(&loop->metadata, NULL);
    if (error != 0) { free(loop->carriers); free(loop); return -(long)error; }
    error = pthread_mutex_init(&loop->startup_lock, NULL);
    if (error != 0) { must(pthread_mutex_destroy(&loop->metadata)); free(loop->carriers); free(loop); return -(long)error; }
    error = pthread_cond_init(&loop->startup, NULL);
    if (error != 0) {
        must(pthread_mutex_destroy(&loop->startup_lock));
        must(pthread_mutex_destroy(&loop->metadata));
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
    must(pthread_mutex_destroy(&loop->metadata));
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
        __atomic_fetch_add(&f->home->live, 1UL, __ATOMIC_ACQ_REL);
    } else {
    struct fiber_loop *loop = linea_loop_find(identity);
    f->loop = loop;
    lock_metadata(loop);
    f->home = &loop->carriers[loop->next];
    loop->next = loop->next + 1 == loop->count ? 0 : loop->next + 1;
    unlock_metadata(loop);
    }
    f->stack = (char *)f->mapping + guard_bytes;
    f->stack_bytes = usable;
    f->entry = entry; f->finished = ended; f->argument = argument;
    f->timer_index = no_timer;
    f->state = parked;
#if defined(LINEA_FIBER_MIGRATION_TRACE_TEST)
    f->trace_identity = __atomic_add_fetch(&trace_identities, 1UL, __ATOMIC_RELAXED);
#endif
    f->saved = 1;
    linea_context_init(&f->context, f->stack, usable, fiber_entry, f);
    *error = 0;
    return f;
}

static void start_fiber(struct linea_fiber *f, int compiled) {
    struct carrier *wake = NULL;
    lock_fiber(f);
    if (f->state != parked || f->started || !f->saved) fail("linea: a fiber was started twice\n");
    if (compiled && f->loop != NULL) f->proven = 1;
    f->started = 1;
    f->state = runnable;
    enqueue_locked(f);
    if (f->home->simulation == 0) wake = f->home;
    unlock_fiber(f);
    if (wake != NULL) wake_carrier(wake);
#if defined(LINEA_FIBER_FORCED_HANDOFF_TEST)
    (void)alarm(60);
#if defined(LINEA_FIBER_WAIT_FOR_PARK_TEST)
    /* The producer cannot send until the receiver has actually suspended.
     * Only immutable local data is used after publication of the fiber. */
    must(pthread_mutex_lock(&handoff_lock));
    while (!handoff_parked) must(pthread_cond_wait(&handoff_changed, &handoff_lock));
    must(pthread_mutex_unlock(&handoff_lock));
#endif
#endif
}

void linea_fiber_start(struct linea_fiber *f) {
    start_fiber(f, 0);
}

void linea_fiber_start_compiled(struct linea_fiber *f) {
    start_fiber(f, 1);
}

void linea_fiber_destroy(struct linea_fiber *f) {
    lock_fiber(f);
    if (f->queued || f->claimed || f->source_claims != 0 || !f->saved ||
        !((!f->started && f->state == parked) || (f->state == finished && f->retired))) fail("linea: a fiber was reclaimed before scheduler retirement\n");
    f->claimed = dispatch_claim;
    struct carrier *home = f->home;
#if defined(LINEA_FIBER_STALE_COOKIE_TEST)
    const int was_started = f->started;
#endif
#if defined(LINEA_FIBER_BUSY_SOURCE_TEST)
    const int report_busy = f == busy_test.body;
    if (report_busy && (!busy_test.claimed || !busy_test.observed))
        fail("linea: busy-source proof did not observe the claimed continuation resume\n");
    if (f == busy_test.worker) busy_test.worker = NULL;
    if (report_busy) busy_test.body = NULL;
    if (busy_test.worker == f || busy_test.body == f)
        fail("linea: busy-source oracle retained a retiring fiber reference\n");
#endif
#if defined(LINEA_FIBER_MIGRATION_TRACE_TEST)
    const struct trace_counts counts = f->loop->trace_counts;
#endif
    unlock_fiber(f);
    const int simulated = home->simulation != 0;
#if __has_feature(thread_sanitizer)
    if (f->tsan_fiber != NULL) __tsan_destroy_fiber(f->tsan_fiber);
#endif
    if (munmap(f->mapping, f->mapping_bytes) != 0) fail("linea: a fiber's stack could not be unmapped\n");
    free(f);
#if defined(LINEA_FIBER_BUSY_SOURCE_TEST)
    if (report_busy) {
        const char message[] = "native stealing: saved continuation claimed while source ran Linea\n";
        report_bytes(message, sizeof message - 1);
    }
#endif
#if defined(LINEA_FIBER_PLATFORM_STATE_TEST)
    if (__atomic_load_n(&platform_migrations, __ATOMIC_ACQUIRE) != 2 ||
        __atomic_load_n(&platform_scheduler_checks, __ATOMIC_ACQUIRE) < 3)
        fail("linea: platform state was not checked across both transfers\n");
    report_bytes("native migration: FP control, carrier signals and protected frames passed\n",
        sizeof "native migration: FP control, carrier signals and protected frames passed\n" - 1);
#endif
#if defined(LINEA_FIBER_MIGRATION_TRACE_TEST)
    trace_dump(counts);
#endif
    /* Prepared tasks can be canceled from a system thread. Keep their home
     * alive until stack and sanitizer cleanup no longer need it. */
    if (simulated) __atomic_fetch_sub(&home->live, 1UL, __ATOMIC_ACQ_REL);
#if defined(LINEA_FIBER_STALE_COOKIE_TEST)
    if (!simulated && was_started) linea_fiber_pause(linea_fiber_reclaimed);
#endif
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
        if (__atomic_load_n(&next->live, __ATOMIC_ACQUIRE) != 0 && !pthread_equal(next->thread, pthread_self())) fail("linea: a simulation with live tasks moved between threads\n");
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
    if (__atomic_load_n(&c->live, __ATOMIC_ACQUIRE) != 0) fail("linea: a simulation ended with live tasks\n");
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
