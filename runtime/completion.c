#define _GNU_SOURCE
#include "completion.h"
#include "op.h"
#include "pipe_signal.h"

#include <errno.h>
#include <limits.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#if defined(__linux__)
#include <linux/io_uring.h>
#include <poll.h>
#include <sys/socket.h>
#include <sys/mman.h>
#include <sys/syscall.h>
#include <unistd.h>

#if defined(LINEA_COMPLETION_CAPACITY_TEST)
enum { completion_slots = 1, submission_entries = completion_slots * 2 };
static unsigned capacity_refused, capacity_retired;
#else
enum { completion_slots = 64, submission_entries = completion_slots * 2 };
#endif

struct completion_slot {
    void *pending;
    uint32_t generation;
    int original_live, cancel_live, cancel_wanted, cancel_submitted, expired;
    long result;
#if defined(LINEA_FIBER_RING_TEST)
    uint8_t opcode;
#endif
#if defined(LINEA_COMPLETION_CANCEL_RETRY_TEST)
    unsigned cancel_attempts;
#endif
#if defined(LINEA_COMPLETION_OWN_FIRST_TEST) || defined(LINEA_COMPLETION_CANCEL_FIRST_TEST)
    int first_retirement;
#endif
};

struct linea_completion {
    int fd;
    void *sq_mapping, *cq_mapping;
    size_t sq_bytes, cq_bytes, sqe_bytes;
    struct io_uring_sqe *sqes;
    unsigned *sq_head, *sq_tail, *sq_mask, *sq_entries, *sq_array;
    unsigned *cq_head, *cq_tail, *cq_mask, *cq_overflow;
    struct io_uring_cqe *cqes;
    struct completion_slot slots[completion_slots];
    unsigned active;
    uint8_t supported[256];
#if defined(LINEA_COMPLETION_STALE_COOKIE_TEST)
    struct { uint64_t user_data; int32_t res; uint32_t flags; } retired;
    int recorded;
#endif
#if defined(LINEA_COMPLETION_PARTIAL_TEST) || defined(LINEA_COMPLETION_INTERRUPTED_TEST) || defined(LINEA_COMPLETION_SHORTAGE_TEST)
    unsigned submission_probes;
#endif
#if defined(LINEA_COMPLETION_OWN_FIRST_TEST) || defined(LINEA_COMPLETION_CANCEL_FIRST_TEST)
    struct { uint64_t user_data; int32_t res; uint32_t flags; } held;
    int holding;
#endif
};

static void completion_fail(void) {
    const char message[] = "linea: a kernel completion lost its operation lifetime\n";
    report_bytes(message, sizeof message - 1);
    abort();
}

static unsigned load_acquire(const unsigned *at) {
    return __atomic_load_n(at, __ATOMIC_ACQUIRE);
}

static void store_release(unsigned *at, unsigned value) {
    __atomic_store_n(at, value, __ATOMIC_RELEASE);
}

/* Kernel ring counters wrap at UINT_MAX. Spell that protocol explicitly so
 * the runtime's integer-overflow checks remain enabled for all other work. */
static unsigned advance(unsigned value) {
    return value == UINT_MAX ? 0 : value + 1;
}

static unsigned distance(unsigned end, unsigned begin) {
    return end >= begin ? end - begin : (UINT_MAX - begin) + end + 1;
}

static int probe_operations(struct linea_completion *queue) {
    const size_t bytes = sizeof(struct io_uring_probe) + 256 * sizeof(struct io_uring_probe_op);
    struct io_uring_probe *probe = calloc(1, bytes);
    if (probe == NULL) return 0;
    const long answer = syscall(SYS_io_uring_register, queue->fd, IORING_REGISTER_PROBE, probe, 256U);
    if (answer == 0) for (unsigned i = 0; i < probe->ops_len; i += 1) {
        if (!(probe->ops[i].flags & IO_URING_OP_SUPPORTED)) continue;
        queue->supported[probe->ops[i].op] = 1;
    }
    free(probe);
    return queue->supported[IORING_OP_ASYNC_CANCEL];
}

static struct linea_completion *completion_open(int eventfd) {
#if defined(LINEA_COMPLETION_DENIED_TEST)
    errno = EPERM;
    return NULL;
#endif
    struct io_uring_params parameters;
    memset(&parameters, 0, sizeof parameters);
    const long opened = syscall(SYS_io_uring_setup, submission_entries, &parameters);
    if (opened < 0) return NULL;
    const int fd = (int)opened;
    if (!(parameters.features & IORING_FEAT_NODROP) || parameters.sq_entries < submission_entries ||
        parameters.sq_entries > 4096 || parameters.cq_entries < submission_entries * 2 ||
        parameters.cq_entries > 8192) {
        close(fd);
        return NULL;
    }
    struct linea_completion *queue = calloc(1, sizeof *queue);
    if (queue == NULL) { close(fd); return NULL; }
    queue->fd = fd;
    if (!probe_operations(queue)) goto failed;
    queue->sq_bytes = parameters.sq_off.array + (size_t)parameters.sq_entries * sizeof(unsigned);
    queue->cq_bytes = parameters.cq_off.cqes + (size_t)parameters.cq_entries * sizeof(struct io_uring_cqe);
    queue->sqe_bytes = (size_t)parameters.sq_entries * sizeof(struct io_uring_sqe);
    const int shared = (parameters.features & IORING_FEAT_SINGLE_MMAP) != 0;
    if (shared && queue->sq_bytes < queue->cq_bytes) queue->sq_bytes = queue->cq_bytes;
    queue->sq_mapping = mmap(NULL, queue->sq_bytes, PROT_READ | PROT_WRITE, MAP_SHARED, fd, IORING_OFF_SQ_RING);
    if (queue->sq_mapping == MAP_FAILED) { queue->sq_mapping = NULL; goto failed; }
    if (shared) queue->cq_mapping = queue->sq_mapping;
    else {
        queue->cq_mapping = mmap(NULL, queue->cq_bytes, PROT_READ | PROT_WRITE, MAP_SHARED, fd, IORING_OFF_CQ_RING);
        if (queue->cq_mapping == MAP_FAILED) { queue->cq_mapping = NULL; goto failed; }
    }
    queue->sqes = mmap(NULL, queue->sqe_bytes, PROT_READ | PROT_WRITE, MAP_SHARED, fd, IORING_OFF_SQES);
    if (queue->sqes == MAP_FAILED) { queue->sqes = NULL; goto failed; }
    char *sq = queue->sq_mapping, *cq = queue->cq_mapping;
    queue->sq_head = (unsigned *)(sq + parameters.sq_off.head);
    queue->sq_tail = (unsigned *)(sq + parameters.sq_off.tail);
    queue->sq_mask = (unsigned *)(sq + parameters.sq_off.ring_mask);
    queue->sq_entries = (unsigned *)(sq + parameters.sq_off.ring_entries);
    queue->sq_array = (unsigned *)(sq + parameters.sq_off.array);
    queue->cq_head = (unsigned *)(cq + parameters.cq_off.head);
    queue->cq_tail = (unsigned *)(cq + parameters.cq_off.tail);
    queue->cq_mask = (unsigned *)(cq + parameters.cq_off.ring_mask);
    queue->cq_overflow = (unsigned *)(cq + parameters.cq_off.overflow);
    queue->cqes = (struct io_uring_cqe *)(cq + parameters.cq_off.cqes);
    if (syscall(SYS_io_uring_register, fd, IORING_REGISTER_EVENTFD, &eventfd, 1U) != 0) goto failed;
    return queue;
failed:
    linea_completion_close(queue);
    return NULL;
}

static void completion_close(struct linea_completion *queue) {
    if (queue == NULL) return;
    if (queue->active != 0) completion_fail();
    if (queue->sqes != NULL) munmap(queue->sqes, queue->sqe_bytes);
    if (queue->cq_mapping != NULL && queue->cq_mapping != queue->sq_mapping) munmap(queue->cq_mapping, queue->cq_bytes);
    if (queue->sq_mapping != NULL) munmap(queue->sq_mapping, queue->sq_bytes);
    close(queue->fd);
    free(queue);
}

static uint64_t slot_cookie(unsigned index, uint32_t generation, int cancel) {
    return ((uint64_t)generation << 32) | ((uint64_t)index << 1) | (unsigned)cancel;
}

static struct io_uring_sqe *next_sqe(struct linea_completion *queue, unsigned *tail) {
    *tail = load_acquire(queue->sq_tail);
    if (distance(*tail, load_acquire(queue->sq_head)) >= *queue->sq_entries) return NULL;
    struct io_uring_sqe *sqe = &queue->sqes[*tail & *queue->sq_mask];
    memset(sqe, 0, sizeof *sqe);
    return sqe;
}

static void publish_sqe(struct linea_completion *queue, unsigned tail) {
    queue->sq_array[tail & *queue->sq_mask] = tail & *queue->sq_mask;
    store_release(queue->sq_tail, advance(tail));
}

static uint64_t completion_submit(struct linea_completion *queue, struct linea_op *operation, void *pending) {
    if (queue == NULL) return 0;
    if (queue->active >= completion_slots) {
#if defined(LINEA_COMPLETION_CAPACITY_TEST)
        if (queue->active != 1 || queue->slots[0].pending == NULL || queue->slots[0].pending == pending)
            completion_fail();
        __atomic_store_n(&capacity_refused, 1U, __ATOMIC_RELEASE);
        const char message[] = "native completion: admission preserved its live original\n";
        report_bytes(message, sizeof message - 1);
#endif
        return 0;
    }
    unsigned opcode;
    if (operation->kind == LINEA_OP_READ) opcode = IORING_OP_RECV;
    else if (operation->kind == LINEA_OP_WRITE) opcode = IORING_OP_SEND;
    else if (operation->kind == LINEA_OP_ACCEPT) opcode = IORING_OP_ACCEPT;
    else if (operation->kind == LINEA_OP_CONNECT && operation->fd >= 0) opcode = IORING_OP_POLL_ADD;
    else return 0;
    if (!queue->supported[opcode]) return 0;
    unsigned index;
    for (index = 0; index < completion_slots; index += 1)
        if (queue->slots[index].pending == NULL && queue->slots[index].generation != UINT32_MAX) break;
    if (index == completion_slots) return 0;
    unsigned tail;
    struct io_uring_sqe *sqe = next_sqe(queue, &tail);
    if (sqe == NULL) return 0;
    struct completion_slot *slot = &queue->slots[index];
    uint32_t generation = slot->generation == 0 ? 1 : slot->generation;
    memset(slot, 0, sizeof *slot);
    slot->generation = generation;
    slot->pending = pending;
    slot->original_live = 1;
    queue->active += 1;
    const uint64_t cookie = slot_cookie(index, generation, 0);
    sqe->opcode = (uint8_t)opcode;
#if defined(LINEA_COMPLETION_UNSUPPORTED_TEST)
    sqe->opcode = UINT8_MAX;
#endif
    sqe->fd = operation->fd;
    if (operation->kind == LINEA_OP_READ || operation->kind == LINEA_OP_WRITE) {
        sqe->addr = operation->at;
        sqe->len = (uint32_t)(operation->len > INT_MAX ? INT_MAX : operation->len);
        if (operation->kind == LINEA_OP_WRITE) sqe->msg_flags = MSG_NOSIGNAL;
    } else if (operation->kind == LINEA_OP_ACCEPT) sqe->accept_flags = SOCK_NONBLOCK | SOCK_CLOEXEC;
    else sqe->poll32_events = POLLOUT | POLLERR | POLLHUP;
    sqe->user_data = cookie;
#if defined(LINEA_FIBER_RING_TEST)
    slot->opcode = sqe->opcode;
#endif
    publish_sqe(queue, tail);
    linea_completion_flush(queue);
    return cookie;
}

static void completion_cancel(struct linea_completion *queue, uint64_t cookie) {
    if (queue == NULL) completion_fail();
    const uint32_t index = (uint32_t)cookie >> 1;
    const uint32_t generation = (uint32_t)(cookie >> 32);
    if (index >= completion_slots) completion_fail();
    struct completion_slot *slot = &queue->slots[index];
    if (slot->pending == NULL || slot->generation != generation) completion_fail();
    slot->expired = 1;
    if (slot->original_live && !slot->cancel_submitted) slot->cancel_wanted = 1;
    linea_completion_flush(queue);
}

static long enter_queue(struct linea_completion *queue, unsigned count) {
#if defined(LINEA_COMPLETION_PARTIAL_TEST)
    if (queue->submission_probes == 0) {
        int cancellation = 0;
        for (unsigned i = 0; i < completion_slots; i += 1)
            if (queue->slots[i].cancel_submitted) cancellation = 1;
        /* Leave the original published until expiry queues its control, then
         * ask the real kernel to consume exactly one of the two SQEs. */
        if (!cancellation) return 0;
        if (count != 2) completion_fail();
        const long answer = syscall(SYS_io_uring_enter, queue->fd, 1U, 0U, 0U, NULL, 0U);
        if (answer == 1) {
            if (distance(load_acquire(queue->sq_tail), load_acquire(queue->sq_head)) != 1) completion_fail();
            queue->submission_probes = 1;
            const char message[] = "native completion: partial submission retained the unconsumed control\n";
            report_bytes(message, sizeof message - 1);
        }
        return answer;
    }
#elif defined(LINEA_COMPLETION_INTERRUPTED_TEST) || defined(LINEA_COMPLETION_SHORTAGE_TEST)
    /* Two consecutive failures span initial publication and the first poll.
     * Completion then requires the bounded retry wake rather than an unrelated
     * event or a peer writing a socket whose request was never submitted. */
    if (queue->submission_probes < 2) {
        queue->submission_probes += 1;
#if defined(LINEA_COMPLETION_INTERRUPTED_TEST)
        const char message[] = "native completion: interrupted submission retained its request\n";
        const int error = EINTR;
#else
        const char message[] = "native completion: submission shortage retained its request\n";
        const int error = EAGAIN;
#endif
        if (queue->submission_probes == 2) report_bytes(message, sizeof message - 1);
        errno = error;
        return -1;
    }
#endif
    return syscall(SYS_io_uring_enter, queue->fd, count, 0U, 0U, NULL, 0U);
}

static void completion_flush(struct linea_completion *queue) {
    if (queue == NULL) return;
    if (load_acquire(queue->cq_overflow) != 0) completion_fail();
    for (unsigned i = 0; i < completion_slots; i += 1) {
        struct completion_slot *slot = &queue->slots[i];
        if (slot->pending == NULL || !slot->original_live || !slot->cancel_wanted) continue;
        unsigned tail;
        struct io_uring_sqe *sqe = next_sqe(queue, &tail);
        if (sqe == NULL) break;
        sqe->opcode = IORING_OP_ASYNC_CANCEL;
        sqe->fd = -1;
        sqe->addr = slot_cookie(i, slot->generation, 0);
        sqe->user_data = slot_cookie(i, slot->generation, 1);
#if defined(LINEA_COMPLETION_CANCEL_RETRY_TEST)
        if (slot->cancel_attempts == 0) {
            /* A real NOP completion models an allocation refusal before any
             * cancellation took effect. The original socket read stays live. */
            sqe->opcode = IORING_OP_NOP;
            sqe->addr = 0;
        }
        slot->cancel_attempts += 1;
#endif
        slot->cancel_wanted = 0;
        slot->cancel_live = 1;
        slot->cancel_submitted = 1;
        publish_sqe(queue, tail);
    }
    const unsigned count = distance(load_acquire(queue->sq_tail), load_acquire(queue->sq_head));
    if (count == 0) return;
    const long answer = enter_queue(queue, count);
    if (answer < 0 && errno != EINTR && errno != EAGAIN && errno != EBUSY) completion_fail();
    /* Published but unconsumed SQEs keep their slots and are retried. Even a
     * failed syscall never proves that the kernel relinquished the buffers. */
}

#if defined(LINEA_COMPLETION_ACCEPT_TIE_TEST)
static int defer_accepted_result(struct linea_completion *queue) {
    for (unsigned i = 0; i < completion_slots; i += 1) {
        const struct completion_slot *slot = &queue->slots[i];
        if (slot->pending != NULL && slot->opcode == IORING_OP_ACCEPT && !slot->expired) return 1;
    }
    return 0;
}
#endif

static int completion_retry(struct linea_completion *queue) {
    if (queue == NULL) return 0;
#if defined(LINEA_COMPLETION_ACCEPT_TIE_TEST)
    if (defer_accepted_result(queue)) return 1;
#endif
#if defined(LINEA_COMPLETION_CAPACITY_TEST)
    if (queue->active != 0 && !__atomic_load_n(&capacity_refused, __ATOMIC_ACQUIRE)) return 1;
#endif
    if (load_acquire(queue->sq_tail) != load_acquire(queue->sq_head)) return 1;
    for (unsigned i = 0; i < completion_slots; i += 1)
        if (queue->slots[i].pending != NULL && queue->slots[i].cancel_wanted) return 1;
    return 0;
}

static int retire_event(struct linea_completion *queue, struct io_uring_cqe event,
                    struct linea_completion_result *result) {
    const uint32_t index = (uint32_t)event.user_data >> 1;
    const uint32_t generation = (uint32_t)(event.user_data >> 32);
    if (index >= completion_slots) return 0;
    struct completion_slot *slot = &queue->slots[index];
    if (slot->pending == NULL || slot->generation != generation) return 0;
    if (event.flags & IORING_CQE_F_MORE) completion_fail();
#if defined(LINEA_COMPLETION_OWN_FIRST_TEST) || defined(LINEA_COMPLETION_CANCEL_FIRST_TEST)
    const int cancellation = (event.user_data & 1U) != 0;
    if (slot->original_live && slot->cancel_live) {
#if defined(LINEA_COMPLETION_OWN_FIRST_TEST)
        const int defer = cancellation;
#else
        const int defer = !cancellation;
#endif
        if (defer) {
            if (queue->holding) completion_fail();
            queue->held.user_data = event.user_data;
            queue->held.res = event.res;
            queue->held.flags = event.flags;
            queue->holding = 1;
            return 0;
        }
        slot->first_retirement = cancellation ? 2 : 1;
    }
#endif
    if (event.user_data & 1U) {
        if (!slot->cancel_live) return 0;
#if defined(LINEA_COMPLETION_CANCEL_RETRY_TEST)
        if (slot->cancel_attempts == 1) {
            if (event.res != 0 || !slot->original_live) completion_fail();
            event.res = -ENOMEM;
        }
#endif
        slot->cancel_live = 0;
        if (slot->original_live && event.res < 0 && event.res != -ENOENT && event.res != -EALREADY) {
            if (event.res != -EINTR && event.res != -EAGAIN && event.res != -ENOMEM && event.res != -EBUSY)
                completion_fail();
            slot->cancel_wanted = 1;
#if defined(LINEA_COMPLETION_CANCEL_RETRY_TEST)
            const char message[] = "native completion: transient cancellation failure retained its original\n";
            report_bytes(message, sizeof message - 1);
#endif
        }
    } else {
        if (!slot->original_live) return 0;
        slot->original_live = 0;
        slot->cancel_wanted = 0;
        slot->result = event.res;
    }
    if (slot->original_live || slot->cancel_live) return 0;
#if defined(LINEA_COMPLETION_ACCEPT_TIE_TEST)
    if (slot->opcode == IORING_OP_ACCEPT) {
        if (slot->result < 0 || !slot->expired || !slot->cancel_submitted) completion_fail();
        const char message[] = "native completion: accepted descriptor won its expired deadline\n";
        report_bytes(message, sizeof message - 1);
    }
#endif
#if defined(LINEA_COMPLETION_STALE_COOKIE_TEST)
    if (!queue->recorded && !(event.user_data & 1U)) {
        queue->retired.user_data = event.user_data;
        queue->retired.res = event.res;
        queue->retired.flags = event.flags;
        queue->recorded = 1;
    }
#endif
#if defined(LINEA_FIBER_RING_TEST)
    if (slot->opcode == IORING_OP_RECV && slot->result >= 0) {
        const char received[] = "native completion: kernel receive completed\n";
        report_bytes(received, sizeof received - 1);
    }
    if (slot->opcode == IORING_OP_RECV && slot->result == -(long)ECONNRESET) {
        const char reset[] = "native completion: kernel receive reported reset\n";
        report_bytes(reset, sizeof reset - 1);
    }
    if (slot->opcode == IORING_OP_ACCEPT && slot->result >= 0) {
        const char accepted[] = "native completion: kernel accept retired\n";
        report_bytes(accepted, sizeof accepted - 1);
    }
    if (slot->opcode == IORING_OP_POLL_ADD && slot->result >= 0) {
        const char connected[] = "native completion: kernel connect readiness completed\n";
        report_bytes(connected, sizeof connected - 1);
    }
    if (slot->opcode == IORING_OP_POLL_ADD && slot->result == -(long)ECANCELED) {
        const char expired[] = "native completion: kernel connect readiness canceled\n";
        report_bytes(expired, sizeof expired - 1);
    }
    if (slot->opcode == IORING_OP_SEND && slot->result >= 0) {
        const char sent[] = "native completion: kernel send retired\n";
        report_bytes(sent, sizeof sent - 1);
    }
#endif
#if defined(LINEA_COMPLETION_OWN_FIRST_TEST) || defined(LINEA_COMPLETION_CANCEL_FIRST_TEST)
#if defined(LINEA_COMPLETION_OWN_FIRST_TEST)
    if (slot->first_retirement != 1 || !slot->cancel_submitted) completion_fail();
    const char message[] = "native completion: own CQE retired before cancel CQE\n";
#else
    if (slot->first_retirement != 2 || !slot->cancel_submitted) completion_fail();
    const char message[] = "native completion: cancel CQE retired before own CQE\n";
#endif
    report_bytes(message, sizeof message - 1);
#endif
    *result = (struct linea_completion_result){ slot->pending, slot->result, slot->expired, slot->cancel_submitted };
    slot->pending = NULL;
    if (slot->generation != UINT32_MAX) slot->generation += 1;
    queue->active -= 1;
#if defined(LINEA_COMPLETION_CAPACITY_TEST)
    if (__atomic_fetch_add(&capacity_retired, 1U, __ATOMIC_ACQ_REL) == 1) {
        const char drained[] = "native completion: both rings drained after overflow\n";
        report_bytes(drained, sizeof drained - 1);
    }
#endif
    return 1;
}

static int completion_next(struct linea_completion *queue, struct linea_completion_result *result) {
    if (queue == NULL) return 0;
#if defined(LINEA_COMPLETION_ACCEPT_TIE_TEST)
    /* The kernel has accepted a real connection, but source retirement waits
     * for the genuine timer to request cancellation. Its own successful CQE
     * must still win after the control request also relinquishes its lease. */
    if (defer_accepted_result(queue)) return 0;
#endif
#if defined(LINEA_COMPLETION_CAPACITY_TEST)
    /* Keep genuine request records live until the third Linea reader has
     * attempted admission. Nothing is fabricated or released during the hold. */
    if (!__atomic_load_n(&capacity_refused, __ATOMIC_ACQUIRE)) return 0;
#endif
    for (;;) {
        struct io_uring_cqe event;
        int use_held = 0;
#if defined(LINEA_COMPLETION_OWN_FIRST_TEST) || defined(LINEA_COMPLETION_CANCEL_FIRST_TEST)
        if (queue->holding) {
            struct completion_slot *held_slot = &queue->slots[(uint32_t)queue->held.user_data >> 1];
            use_held = (queue->held.user_data & 1U) ? !held_slot->original_live : !held_slot->cancel_live;
        }
        if (use_held) {
            event.user_data = queue->held.user_data;
            event.res = queue->held.res;
            event.flags = queue->held.flags;
            queue->holding = 0;
        } else
#endif
        {
            const unsigned head = load_acquire(queue->cq_head);
            if (head == load_acquire(queue->cq_tail)) return 0;
            event = queue->cqes[head & *queue->cq_mask];
            store_release(queue->cq_head, advance(head));
        }
        (void)use_held;
        if (retire_event(queue, event, result)) return 1;
    }
}

#endif

int linea_completion_replay_stale(struct linea_completion *queue, unsigned long cookie) {
#if defined(__linux__) && defined(LINEA_COMPLETION_STALE_COOKIE_TEST)
    if (queue == NULL || !queue->recorded || queue->retired.user_data != cookie) return 0;
    const uint32_t index = (uint32_t)cookie >> 1;
    if (index >= completion_slots) return 0;
    struct completion_slot *slot = &queue->slots[index];
    if (slot->pending == NULL) return -1;
    const struct completion_slot before = *slot;
    const unsigned active = queue->active;
    struct io_uring_cqe event = {
        .user_data = queue->retired.user_data,
        .res = queue->retired.res,
        .flags = queue->retired.flags,
    };
    struct linea_completion_result result;
    if (retire_event(queue, event, &result)) return 0;
    return queue->active == active && slot->pending == before.pending &&
        slot->generation == before.generation && slot->original_live == before.original_live &&
        slot->cancel_live == before.cancel_live && slot->cancel_wanted == before.cancel_wanted &&
        slot->cancel_submitted == before.cancel_submitted && slot->expired == before.expired &&
        slot->result == before.result;
#else
    (void)queue;
    (void)cookie;
    return 0;
#endif
}

/* These declarations have one platform-independent ABI. Only implementation
 * bodies select the kernel backend; unavailable targets keep readiness. */
struct linea_completion *linea_completion_open(int eventfd) {
#if defined(__linux__)
    return completion_open(eventfd);
#else
    (void)eventfd; return NULL;
#endif
}

void linea_completion_close(struct linea_completion *queue) {
#if defined(__linux__)
    completion_close(queue);
#else
    (void)queue;
#endif
}

unsigned long linea_completion_submit(struct linea_completion *queue, struct linea_op *operation, void *pending) {
#if defined(__linux__)
    return completion_submit(queue, operation, pending);
#else
    (void)queue; (void)operation; (void)pending; return 0;
#endif
}

void linea_completion_cancel(struct linea_completion *queue, unsigned long cookie) {
#if defined(__linux__)
    completion_cancel(queue, cookie);
#else
    (void)queue; (void)cookie; abort();
#endif
}

void linea_completion_flush(struct linea_completion *queue) {
#if defined(__linux__)
    completion_flush(queue);
#else
    (void)queue;
#endif
}

int linea_completion_retry(struct linea_completion *queue) {
#if defined(__linux__)
    return completion_retry(queue);
#else
    (void)queue; return 0;
#endif
}

int linea_completion_next(struct linea_completion *queue, struct linea_completion_result *result) {
#if defined(__linux__)
    return completion_next(queue, result);
#else
    (void)queue; (void)result; return 0;
#endif
}
