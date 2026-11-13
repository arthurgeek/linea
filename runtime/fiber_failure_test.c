#define _GNU_SOURCE
#define _DARWIN_C_SOURCE
#undef NDEBUG
#include <assert.h>
#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <signal.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/socket.h>
#include <unistd.h>
#if defined(__linux__)
#include <sys/epoll.h>
#include <sys/eventfd.h>
#else
#include <sys/event.h>
#endif
#include "loop.h"
#include "signals.h"
#include "task.h"
#include "waitset.h"

/* Interpose only fiber.c, so resources allocated by the surrounding runtime
 * do not disguise a missing unwind in the carrier/fiber owner. */
enum failure { no_failure, allocation_failure, mutex_failure, condition_failure,
               claim_failure, poller_failure, registration_failure, mapping_failure,
               protection_failure, thread_failure, begin_failure };
static enum failure refusal;
static unsigned fail_at, attempts;
static long allocations, mappings, mutexes, conditions, descriptors, threads;
static unsigned long last_identity;
static int tracked_fds[128];
static size_t tracked_fd_count;
static uint64_t injected_cookie;
static int inject_event;
static int reject_next_add, rejected_fd = -1, rejected_error;
static unsigned unexpected_deletes;
static unsigned kernel_add_calls, kernel_delete_calls, duplication_calls, duplicate_interruptions;
static int duplicate_error;
static int should_refuse(enum failure kind) {
    return refusal == kind && __atomic_add_fetch(&attempts, 1U, __ATOMIC_SEQ_CST) == fail_at;
}
static void *test_calloc(size_t count, size_t bytes) {
    if (should_refuse(allocation_failure)) return NULL;
    void *out = calloc(count, bytes);
    if (out != NULL) (void)__atomic_add_fetch(&allocations, 1L, __ATOMIC_RELAXED);
    return out;
}
static void *test_realloc(void *old, size_t bytes) {
    if (should_refuse(allocation_failure)) return NULL;
    const int was_null = old == NULL;
    void *out = realloc(old, bytes);
    if (out != NULL && was_null) (void)__atomic_add_fetch(&allocations, 1L, __ATOMIC_RELAXED);
    return out;
}
static void test_free(void *at) {
    if (at != NULL) (void)__atomic_sub_fetch(&allocations, 1L, __ATOMIC_RELAXED);
    free(at);
}
static void *test_mmap(void *at, size_t bytes, int prot, int flags, int fd, off_t offset) {
    if (should_refuse(mapping_failure)) { errno = ENOMEM; return MAP_FAILED; }
    void *out = mmap(at, bytes, prot, flags, fd, offset);
    if (out != MAP_FAILED) (void)__atomic_add_fetch(&mappings, 1L, __ATOMIC_RELAXED);
    return out;
}
static int test_munmap(void *at, size_t bytes) {
    int answer = munmap(at, bytes);
    if (answer == 0) (void)__atomic_sub_fetch(&mappings, 1L, __ATOMIC_RELAXED);
    return answer;
}
static int test_mprotect(void *at, size_t bytes, int prot) {
    if (should_refuse(protection_failure)) { errno = EACCES; return -1; }
    return mprotect(at, bytes, prot);
}
static int test_mutex_init(pthread_mutex_t *mutex, const pthread_mutexattr_t *attrs) {
    if (should_refuse(mutex_failure)) return EAGAIN;
    int answer = pthread_mutex_init(mutex, attrs);
    if (answer == 0) mutexes += 1;
    return answer;
}
static int test_mutex_destroy(pthread_mutex_t *mutex) {
    int answer = pthread_mutex_destroy(mutex);
    if (answer == 0) mutexes -= 1;
    return answer;
}
static int test_cond_init(pthread_cond_t *condition, const pthread_condattr_t *attrs) {
    if (should_refuse(condition_failure)) return EAGAIN;
    int answer = pthread_cond_init(condition, attrs);
    if (answer == 0) conditions += 1;
    return answer;
}
static int test_cond_destroy(pthread_cond_t *condition) {
    int answer = pthread_cond_destroy(condition);
    if (answer == 0) conditions -= 1;
    return answer;
}
static int test_create(pthread_t *thread, const pthread_attr_t *attrs, void *(*entry)(void *), void *arg) {
    if (should_refuse(thread_failure)) return EAGAIN;
    int answer = pthread_create(thread, attrs, entry, arg);
    if (answer == 0) threads += 1;
    return answer;
}
static int test_join(pthread_t thread, void **answer) {
    int status = pthread_join(thread, answer);
    if (status == 0) threads -= 1;
    return status;
}
int linea_thread_begin(unsigned long at, unsigned long bytes, unsigned long low, unsigned long high);
static int test_begin(unsigned long at, unsigned long bytes, unsigned long low, unsigned long high) {
    if (should_refuse(begin_failure)) return EIO;
    return linea_thread_begin(at, bytes, low, high);
}
static unsigned long test_claim(void *state, uint8_t kind) {
    if (should_refuse(claim_failure)) return 0;
    last_identity = linea_loop_claim_kind(state, kind);
    return last_identity;
}
static int track_fd(int fd) {
    if (fd >= 0) {
        assert(tracked_fd_count < sizeof tracked_fds / sizeof tracked_fds[0]);
        tracked_fds[tracked_fd_count++] = fd;
        descriptors += 1;
    }
    return fd;
}
static int test_close(int fd) {
    int answer = close(fd);
    if (answer == 0) {
        for (size_t i = 0; i < tracked_fd_count; i += 1) {
            if (tracked_fds[i] == fd) {
                tracked_fds[i] = tracked_fds[--tracked_fd_count];
                descriptors -= 1;
                break;
            }
        }
    }
    return answer;
}
static int test_fcntl(int fd, int command, int minimum) {
    assert(command == F_DUPFD_CLOEXEC);
    duplication_calls += 1;
    if (duplicate_interruptions != 0) {
        duplicate_interruptions -= 1;
        errno = EINTR; return -1;
    }
    if (duplicate_error != 0) {
        errno = duplicate_error; duplicate_error = 0;
        return -1;
    }
    return track_fd(fcntl(fd, command, minimum));
}
#if defined(__linux__)
static int test_epoll_create1(int flags) {
    if (should_refuse(poller_failure)) { errno = EMFILE; return -1; }
    return track_fd(epoll_create1(flags));
}
static int test_eventfd(unsigned initial, int flags) {
    if (should_refuse(poller_failure)) { errno = EMFILE; return -1; }
    return track_fd(eventfd(initial, flags));
}
static int test_epoll_ctl(int fd, int operation, int watched, struct epoll_event *event) {
    if (operation == EPOLL_CTL_ADD) kernel_add_calls += 1;
    if (operation == EPOLL_CTL_DEL) kernel_delete_calls += 1;
    if (operation == EPOLL_CTL_ADD && reject_next_add != 0) {
        rejected_fd = watched; rejected_error = reject_next_add; reject_next_add = 0;
        errno = rejected_error; return -1;
    }
    if (operation == EPOLL_CTL_DEL && watched == rejected_fd) {
        unexpected_deletes += 1;
        if (rejected_error == EPERM) { errno = EPERM; return -1; }
    }
    if (operation == EPOLL_CTL_ADD && should_refuse(registration_failure)) { errno = ENOMEM; return -1; }
    return epoll_ctl(fd, operation, watched, event);
}
static int test_epoll_wait(int fd, struct epoll_event *events, int count, int timeout) {
    if (inject_event) {
        assert(count > 0);
        inject_event = 0;
        memset(events, 0, sizeof *events);
        events[0].events = EPOLLIN;
        events[0].data.u64 = injected_cookie;
        return 1;
    }
    return epoll_wait(fd, events, count, timeout);
}
#else
static int test_kqueue(void) {
    if (should_refuse(poller_failure)) { errno = EMFILE; return -1; }
    return track_fd(kqueue());
}
static int test_kevent(int fd, const struct kevent *changes, int change_count,
                       struct kevent *events, int count, const struct timespec *timeout) {
    if (change_count > 0 && (changes[0].flags & EV_ADD) != 0) kernel_add_calls += 1;
    if (change_count > 0 && (changes[0].flags & EV_DELETE) != 0) kernel_delete_calls += 1;
    if (change_count > 0 && (changes[0].flags & EV_ADD) != 0 && reject_next_add != 0) {
        rejected_fd = (int)changes[0].ident; rejected_error = reject_next_add; reject_next_add = 0;
        errno = rejected_error; return -1;
    }
    if (change_count > 0 && (changes[0].flags & EV_DELETE) != 0 && changes[0].ident == (uintptr_t)rejected_fd) {
        unexpected_deletes += 1;
        if (rejected_error == EPERM) { errno = EPERM; return -1; }
    }
    if (change_count > 0 && (changes[0].flags & EV_ADD) != 0 && should_refuse(registration_failure)) {
        errno = ENOMEM; return -1;
    }
    if (inject_event && events != NULL) {
        assert(count > 0);
        inject_event = 0;
        EV_SET(events, 0, EVFILT_READ, 0, 0, 0, (void *)(uintptr_t)injected_cookie);
        return 1;
    }
    return kevent(fd, changes, change_count, events, count, timeout);
}
#endif

#define fcntl test_fcntl
#define calloc test_calloc
#define realloc test_realloc
#define free test_free
#define mmap test_mmap
#define munmap test_munmap
#define mprotect test_mprotect
#define pthread_mutex_init test_mutex_init
#define pthread_mutex_destroy test_mutex_destroy
#define pthread_cond_init test_cond_init
#define pthread_cond_destroy test_cond_destroy
#define pthread_create test_create
#define pthread_join test_join
#define linea_thread_begin test_begin
#define linea_loop_claim_kind test_claim
#define close test_close
#if defined(__linux__)
#define epoll_create1 test_epoll_create1
#define eventfd test_eventfd
#define epoll_ctl test_epoll_ctl
#define epoll_wait test_epoll_wait
#else
#define kqueue test_kqueue
#define kevent(...) test_kevent(__VA_ARGS__)
#endif
#include "fiber.c"
#undef fcntl
#undef calloc
#undef realloc
#undef free
#undef mmap
#undef munmap
#undef mprotect
#undef pthread_mutex_init
#undef pthread_mutex_destroy
#undef pthread_cond_init
#undef pthread_cond_destroy
#undef pthread_create
#undef pthread_join
#undef linea_thread_begin
#undef linea_loop_claim_kind
#undef close
#if defined(__linux__)
#undef epoll_create1
#undef eventfd
#undef epoll_ctl
#undef epoll_wait
#else
#undef kqueue
#undef kevent
#endif

static void balanced(void) {
    assert(allocations == 0 && mappings == 0 && mutexes == 0 && conditions == 0);
    assert(descriptors == 0 && threads == 0 && tracked_fd_count == 0);
}
static void refuse(enum failure kind, unsigned nth) {
    refusal = kind; fail_at = nth; attempts = 0; last_identity = 0;
}
static void startup_unwinds(void) {
    const struct { enum failure kind; unsigned count; long error; } cases[] = {
        { allocation_failure, 2, ENOMEM }, { mutex_failure, 3, EAGAIN },
        { condition_failure, 1, EAGAIN }, { claim_failure, 1, ENOMEM },
#if defined(__linux__)
        { poller_failure, 4, EMFILE },
#else
        { poller_failure, 2, EMFILE },
#endif
        { registration_failure, 2, ENOMEM }, { mapping_failure, 2, ENOMEM },
        { thread_failure, 2, EAGAIN }, { begin_failure, 2, EIO },
    };
    assert(linea_loop_open(0) == -EINVAL);
    balanced();
    for (size_t i = 0; i < sizeof cases / sizeof cases[0]; i += 1) {
        for (unsigned nth = 1; nth <= cases[i].count; nth += 1) {
            refuse(cases[i].kind, nth);
            assert(linea_loop_open(2) == -cases[i].error);
            balanced();
            if (last_identity != 0) assert(linea_loop_runs(last_identity) == 0);
        }
    }
    refuse(no_failure, 0);
}
static void never_entered(void *argument) { (void)argument; assert(0); }
static void fiber_preparation_unwinds(void) {
    struct carrier carrier;
    memset(&carrier, 0, sizeof carrier);
    struct fiber_loop loop;
    memset(&loop, 0, sizeof loop);
    loop.count = 1; loop.carriers = &carrier;
    assert(pthread_mutex_init(&loop.startup_lock, NULL) == 0);
    const unsigned long identity = linea_loop_claim_kind(&loop, LINEA_LOOP_FIBERS);
    assert(identity != 0);
    const enum failure cases[] = { allocation_failure, mapping_failure, protection_failure };
    for (size_t i = 0; i < sizeof cases / sizeof cases[0]; i += 1) {
        refuse(cases[i], 1);
        int error = 0;
        assert(linea_fiber_create(identity, 65536, never_entered, never_entered, NULL, &error) == NULL);
        assert(error == (cases[i] == protection_failure ? EACCES : ENOMEM));
        balanced();
    }
    refuse(no_failure, 0);
    int error = -1;
    struct linea_fiber *fiber = linea_fiber_create(identity, 65536, never_entered, never_entered, NULL, &error);
    assert(fiber != NULL && error == 0);
    linea_fiber_destroy(fiber);
    balanced();
    linea_loop_retire(identity);
    assert(pthread_mutex_destroy(&loop.startup_lock) == 0);
}

static unsigned operation_attempts;
static long completes_once(struct linea_op *operation) {
    (void)operation;
    operation_attempts += 1;
    return 23;
}
static uint64_t cookie_of(struct carrier *carrier, struct pending_operation *pending) {
    return ((uint64_t)pending->slot << 32) | io_slot_at(carrier, pending->slot)->generation;
}
static void deliver_cookie(struct carrier *carrier, uint64_t cookie) {
    injected_cookie = cookie; inject_event = 1;
    poll_carrier(carrier, 1);
    assert(!inject_event);
}
static void stale_events_do_not_complete_reused_slots(void) {
    operation_attempts = 0;
    struct carrier carrier;
    memset(&carrier, 0, sizeof carrier);
    assert(test_mutex_init(&carrier.queue_lock, NULL) == 0);
    assert(make_poller(&carrier) == 0);
    int pair[2];
    assert(socketpair(AF_UNIX, SOCK_STREAM, 0, pair) == 0);
    struct linea_fiber fiber;
    memset(&fiber, 0, sizeof fiber);
    fiber.home = &carrier; fiber.state = parking; fiber.timer_index = no_timer;
    struct linea_op operation;
    memset(&operation, 0, sizeof operation);
    operation.kind = LINEA_OP_READ; operation.fd = pair[0];
    struct pending_operation pending;
    memset(&pending, 0, sizeof pending);
    pending.operation = &operation; pending.fiber = &fiber;
    pending.attempt = completes_once; pending.state = operation_armed;
    assert(arm_operation(&pending) == 0);
    const uint64_t stale = cookie_of(&carrier, &pending);
    disarm_operation(&pending);
    assert(arm_operation(&pending) == 0);
    const uint64_t current = cookie_of(&carrier, &pending);
    assert((stale >> 32) == (current >> 32) && stale != current);
    deliver_cookie(&carrier, stale);
    deliver_cookie(&carrier, ((uint64_t)(carrier.slots_made + 7U) << 32) | 1U);
    assert(operation_attempts == 0 && pending.state == operation_armed);
    deliver_cookie(&carrier, current);
    assert(operation_attempts == 1 && pending.result == 23 && pending.state == operation_complete);
    assert(fiber.state == notified && !pending.registered);
    deliver_cookie(&carrier, current);
    assert(operation_attempts == 1);
    /* A slot whose generation has no successor is retired, never reused. */
    pending.state = operation_armed;
    assert(arm_operation(&pending) == 0);
    const uint32_t retired = pending.slot;
    io_slot_at(&carrier, retired)->generation = UINT32_MAX;
    disarm_operation(&pending);
    assert(arm_operation(&pending) == 0);
    assert(pending.slot != retired);
    disarm_operation(&pending);
    free_carrier(&carrier);
    assert(close(pair[0]) == 0 && close(pair[1]) == 0);
    balanced();
}

/* A failed kernel ADD installed nothing. DEL must not follow it: a
 * descriptor the kernel rejects can reject DEL too; EEXIST means another
 * operation already owns the registration, which must remain untouched. */
static void rejected_add_preserves_its_error_and_existing_watch(int error) {
    struct carrier carrier;
    memset(&carrier, 0, sizeof carrier);
    assert(test_mutex_init(&carrier.queue_lock, NULL) == 0);
    assert(make_poller(&carrier) == 0);
    int pair[2];
    assert(socketpair(AF_UNIX, SOCK_STREAM, 0, pair) == 0);
    struct linea_fiber fiber;
    memset(&fiber, 0, sizeof fiber);
    fiber.home = &carrier; fiber.state = parking; fiber.timer_index = no_timer;
    struct linea_op operation;
    memset(&operation, 0, sizeof operation);
    operation.kind = LINEA_OP_READ; operation.fd = pair[0];
    struct pending_operation existing, rejected;
    memset(&existing, 0, sizeof existing);
    existing.operation = &operation; existing.fiber = &fiber;
    existing.attempt = completes_once; existing.state = operation_armed;
    rejected = existing;
    if (error == EEXIST) assert(arm_operation(&existing) == 0);
    reject_next_add = error;
    assert(arm_operation(&rejected) == error);
    assert(!rejected.registered && unexpected_deletes == 0);
    rejected_fd = -1;
    if (error == EEXIST) {
        const unsigned before = operation_attempts;
        assert(write(pair[1], "x", 1) == 1);
        poll_carrier(&carrier, 1);
        assert(operation_attempts == before + 1 && existing.state == operation_complete);
    }
    free_carrier(&carrier);
    assert(close(pair[0]) == 0 && close(pair[1]) == 0);
    balanced();
}

static void duplicate_failure_releases_only_its_slot(void) {
    struct carrier carrier;
    memset(&carrier, 0, sizeof carrier);
    assert(test_mutex_init(&carrier.queue_lock, NULL) == 0);
    assert(make_poller(&carrier) == 0);
    const long poller_descriptors = descriptors;
    int pair[2];
    assert(socketpair(AF_UNIX, SOCK_STREAM, 0, pair) == 0);
    struct linea_fiber fiber;
    memset(&fiber, 0, sizeof fiber);
    fiber.home = &carrier; fiber.state = parking; fiber.timer_index = no_timer;
    struct linea_op operation;
    memset(&operation, 0, sizeof operation);
    operation.kind = LINEA_OP_READ; operation.fd = pair[0];
    struct pending_operation pending;
    memset(&pending, 0, sizeof pending);
    pending.operation = &operation; pending.fiber = &fiber;
    pending.attempt = completes_once; pending.state = operation_armed;
    const int errors[] = { EMFILE, EBADF };
    for (size_t i = 0; i < sizeof errors / sizeof errors[0]; i += 1) {
        const unsigned adds_before = kernel_add_calls;
        const unsigned deletes_before = kernel_delete_calls;
        duplicate_error = errors[i];
        assert(arm_operation(&pending) == errors[i]);
        assert(duplicate_error == 0 && !pending.registered);
        assert(kernel_add_calls == adds_before && kernel_delete_calls == deletes_before);
        assert(descriptors == poller_descriptors);
        assert(carrier.slots_made == 1 && carrier.first_free == pending.slot + 1);
        assert(io_slot_at(&carrier, pending.slot)->operation == NULL);
        assert(io_slot_at(&carrier, pending.slot)->fd == -1);
        assert(fcntl(pair[0], F_GETFD) >= 0);
    }
    const uint32_t reused_slot = pending.slot;
    const unsigned before = duplication_calls;
    duplicate_interruptions = 2;
    assert(arm_operation(&pending) == 0);
    assert(duplicate_interruptions == 0 && duplication_calls == before + 3);
    assert(pending.slot == reused_slot && carrier.slots_made == 1);
    const int watched = io_slot_at(&carrier, pending.slot)->fd;
    assert(watched != pair[0] && (fcntl(watched, F_GETFD) & FD_CLOEXEC) != 0);
    assert(operation.fd == pair[0] && descriptors == poller_descriptors + 1);
    disarm_operation(&pending);
    assert(descriptors == poller_descriptors && fcntl(pair[0], F_GETFD) >= 0);
    errno = 0;
    assert(fcntl(watched, F_GETFD) == -1 && errno == EBADF);
    free_carrier(&carrier);
    assert(close(pair[0]) == 0 && close(pair[1]) == 0);
    balanced();
}

static volatile sig_atomic_t host_deliveries;
static void host_handler(int signal_number) {
    if (signal_number == SIGUSR1) host_deliveries += 1;
}
static void release_body(unsigned long at, unsigned long len) { assert(at == 0 && len == 0); }
static void signal_sender(unsigned long endpoint, unsigned long at, unsigned long len) {
    assert(at == 0 && len == 0);
    assert(kill(getpid(), SIGUSR1) == 0);
    linea_chan_close(endpoint);
}
static void signal_waiter(unsigned long endpoint, unsigned long at, unsigned long len) {
    assert(at == 0 && len == 0);
    const unsigned long identity = linea_io_current();
    assert(linea_signal_acquire(3) == 0);
    const unsigned long set = linea_waitset_open();
    assert(set != 0);
    const unsigned long key = linea_waitset_reserve(set);
    const unsigned long slot = key >> 32;
    assert(linea_waitset_signal(set, slot, 3, identity) == 0);
    const unsigned long timeout = linea_waitset_reserve(set) >> 32;
    linea_waitset_timer(set, timeout, 2000000000UL);
    const long prepared = linea_task_prepare_on(65536, identity);
    assert(prepared > 0);
    const unsigned long sender = linea_task_start((unsigned long)prepared, signal_sender, release_body, 0, 0, 0);
    assert(linea_waitset_next(set) == (long)slot);
    assert(linea_waitset_withdraw(set) == (long)timeout);
    assert(linea_waitset_withdraw(set) == -1);
    linea_waitset_close(set);
    linea_chan_close(sender);
    linea_signal_release(3, identity);
    linea_chan_close(endpoint);
}
static void real_signal_wakes_a_fiber(void) {
    struct sigaction host, previous;
    memset(&host, 0, sizeof host);
    host.sa_handler = host_handler;
    assert(sigemptyset(&host.sa_mask) == 0);
    assert(sigaction(SIGUSR1, &host, &previous) == 0);
    const long identity = linea_loop_open(1);
    assert(identity > 0);
    const long prepared = linea_task_prepare_on(65536, (unsigned long)identity);
    assert(prepared > 0);
    linea_chan_close(linea_task_start((unsigned long)prepared, signal_waiter, release_body, 0, 0, 0));
    assert(host_deliveries == 1);
    struct sigaction restored;
    assert(sigaction(SIGUSR1, NULL, &restored) == 0);
    assert(restored.sa_handler == host_handler);
    assert(sigaction(SIGUSR1, &previous, NULL) == 0);
}

int main(int argc, char **argv) {
    alarm(20);
    if (argc == 2) {
        rejected_add_preserves_its_error_and_existing_watch(strcmp(argv[1], "--failed-add-eperm") == 0 ? EPERM : EEXIST);
        return 0;
    }
    rejected_add_preserves_its_error_and_existing_watch(EPERM);
    rejected_add_preserves_its_error_and_existing_watch(EEXIST);
    startup_unwinds();
    fiber_preparation_unwinds();
    stale_events_do_not_complete_reused_slots();
    duplicate_failure_releases_only_its_slot();
    real_signal_wakes_a_fiber();
    return 0;
}
