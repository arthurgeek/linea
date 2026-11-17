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
#include <sys/mman.h>
#include <sys/syscall.h>
#include <unistd.h>

enum { completion_slots = 64, submission_entries = completion_slots * 2 };

struct completion_slot {
    void *pending;
    uint32_t generation;
    int original_live, cancel_live, cancel_wanted, cancel_submitted, expired;
    long result;
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

static int supported(int fd) {
    const size_t bytes = sizeof(struct io_uring_probe) + 256 * sizeof(struct io_uring_probe_op);
    struct io_uring_probe *probe = calloc(1, bytes);
    if (probe == NULL) return 0;
    const long answer = syscall(SYS_io_uring_register, fd, IORING_REGISTER_PROBE, probe, 256U);
    int read_supported = 0, cancel_supported = 0;
    if (answer == 0) for (unsigned i = 0; i < probe->ops_len; i += 1) {
        if (!(probe->ops[i].flags & IO_URING_OP_SUPPORTED)) continue;
        if (probe->ops[i].op == IORING_OP_RECV) read_supported = 1;
        if (probe->ops[i].op == IORING_OP_ASYNC_CANCEL) cancel_supported = 1;
    }
    free(probe);
    return read_supported && cancel_supported;
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
        parameters.cq_entries > 8192 || !supported(fd)) {
        close(fd);
        return NULL;
    }
    struct linea_completion *queue = calloc(1, sizeof *queue);
    if (queue == NULL) { close(fd); return NULL; }
    queue->fd = fd;
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
    if (queue == NULL || operation->kind != LINEA_OP_READ || queue->active >= completion_slots) return 0;
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
    sqe->opcode = IORING_OP_RECV;
#if defined(LINEA_COMPLETION_UNSUPPORTED_TEST)
    sqe->opcode = UINT8_MAX;
#endif
    sqe->fd = operation->fd;
    sqe->addr = operation->at;
    sqe->len = (uint32_t)(operation->len > INT_MAX ? INT_MAX : operation->len);
    sqe->user_data = cookie;
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

static int completion_retry(struct linea_completion *queue) {
    if (queue == NULL) return 0;
    if (load_acquire(queue->sq_tail) != load_acquire(queue->sq_head)) return 1;
    for (unsigned i = 0; i < completion_slots; i += 1)
        if (queue->slots[i].pending != NULL && queue->slots[i].cancel_wanted) return 1;
    return 0;
}

static int completion_next(struct linea_completion *queue, struct linea_completion_result *result) {
    if (queue == NULL) return 0;
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
        const uint32_t index = (uint32_t)event.user_data >> 1;
        const uint32_t generation = (uint32_t)(event.user_data >> 32);
        if (index >= completion_slots) continue;
        struct completion_slot *slot = &queue->slots[index];
        if (slot->pending == NULL || slot->generation != generation) continue;
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
                continue;
            }
            slot->first_retirement = cancellation ? 2 : 1;
        }
#endif
        if (event.user_data & 1U) {
            if (!slot->cancel_live) continue;
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
            if (!slot->original_live) continue;
            slot->original_live = 0;
            slot->cancel_wanted = 0;
            slot->result = event.res;
        }
        if (slot->original_live || slot->cancel_live) continue;
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
        return 1;
    }
}

#endif

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
