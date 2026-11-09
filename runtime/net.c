#define _GNU_SOURCE
#include "net.h"

#include "clock.h"
#include "io.h"
#include "pipe_signal.h"

#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <netinet/in.h>
#include <poll.h>
#include <stdint.h>
#include <string.h>
#include <sys/socket.h>
#include <time.h>
#include <unistd.h>

static struct sockaddr_in unpack(unsigned long packed) {
    struct sockaddr_in a;
    memset(&a, 0, sizeof a);
    a.sin_family = AF_INET;
    a.sin_port = htons((uint16_t)(packed & 0xffffUL));
    a.sin_addr.s_addr = htonl((uint32_t)(packed >> 16));
    return a;
}

static long pack(const struct sockaddr_in *a) {
    return (long)(((unsigned long)ntohl(a->sin_addr.s_addr) << 16) | ntohs(a->sin_port));
}

/* The socket options every socket carries. Neither F_SETFD nor F_SETFL blocks;
 * Linux and macOS document EINTR only for the blocking lock commands. An
 * accepted socket inherits O_NONBLOCK from its listener on macOS and not on
 * Linux, so it is set on every socket. */
static int configure(int fd) {
#if defined(SO_NOSIGPIPE)
    int nosigpipe = 1;
    (void)setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &nosigpipe, sizeof nosigpipe);
#endif
    if (fcntl(fd, F_SETFD, FD_CLOEXEC) != 0) return errno;
    const int flags = fcntl(fd, F_GETFL, 0);
    if (flags == -1) return errno;
    return fcntl(fd, F_SETFL, flags | O_NONBLOCK) == 0 ? 0 : errno;
}

static long stream_socket(void) {
    /* socket does not block; Linux and macOS document no EINTR for it. */
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) return -(long)errno;
    int failed = configure(fd);
    if (failed != 0) { close(fd); return -(long)failed; }
    return fd;
}

long linea_net_listen(unsigned long address, unsigned long backlog) {
    if (backlog > 4096) return -(long)EINVAL;
    long fd = stream_socket();
    if (fd < 0) return fd;
    int on = 1;
    struct sockaddr_in a = unpack(address);
    /* setsockopt, bind and listen configure an already-open socket without
     * blocking; neither Linux nor macOS documents EINTR for any of the three. */
    if (setsockopt((int)fd, SOL_SOCKET, SO_REUSEADDR, &on, sizeof on) != 0 ||
        bind((int)fd, (struct sockaddr *)&a, sizeof a) != 0 ||
        listen((int)fd, (int)backlog) != 0) {
        int error = errno;
        close((int)fd);
        return -(long)error;
    }
    return fd;
}

/* One operation on a descriptor. The operation's bytes stay lent by the caller
 * until `linea_io_perform` returns. */
enum op_kind { OP_ACCEPT, OP_CONNECT, OP_READ, OP_WRITE };

struct linea_op {
    enum op_kind kind;
    int fd;                     /* the socket; -1 for a connect not yet started */
    unsigned long at, len;      /* the bytes a read fills or a write sends */
    unsigned long address;      /* connect's packed address */
    unsigned long deadline_ns;  /* monotonic; 0 for none */
};

/* -EAGAIN and -EWOULDBLOCK are one answer: the operation would wait. */
static long failed(void) {
    return errno == EAGAIN || errno == EWOULDBLOCK ? -(long)EAGAIN : -(long)errno;
}

static long attempt_accept(const struct linea_op *op) {
    int fd;
    do { fd = accept(op->fd, NULL, NULL); } while (fd < 0 && errno == EINTR);
    if (fd < 0) return failed();
    const int error = configure(fd);
    if (error != 0) { close(fd); return -(long)error; }
    return fd;
}

/* A connecting socket is finished when it is writable: SO_ERROR then says how.
 * A socket that is not yet writable has SO_ERROR 0 too, so writability is read
 * first. Linux reports a failed handshake as POLLERR or POLLHUP with POLLOUT;
 * any reported condition ends the wait. */
static long connect_finished(int fd) {
    struct pollfd entry = { fd, POLLOUT, 0 };
    int ready;
    do { ready = poll(&entry, 1, 0); } while (ready < 0 && errno == EINTR);
    if (ready < 0) return -(long)errno;
    if (ready == 0) return -(long)EAGAIN;
    int pending = 0;
    socklen_t pending_size = sizeof pending;
    /* getsockopt does not block; Linux and macOS document no EINTR for it. */
    if (getsockopt(fd, SOL_SOCKET, SO_ERROR, &pending, &pending_size) != 0) return -(long)errno;
    return pending == 0 ? fd : -(long)pending;
}

/* The first attempt makes the socket and starts the handshake; a later one
 * checks whether it finished. An interrupted connect keeps running in the
 * kernel, so EINTR is the same as EINPROGRESS. Only EAGAIN from connect means
 * something else, that no local port is free, and retrying the poll would
 * read an unconnected socket as connected, so it is reported as the shortage
 * it is. */
static long attempt_connect(struct linea_op *op) {
    if (op->fd >= 0) return connect_finished(op->fd);
    const long socket_fd = stream_socket();
    if (socket_fd < 0) return socket_fd;
    op->fd = (int)socket_fd;
    struct sockaddr_in a = unpack(op->address);
    if (connect(op->fd, (struct sockaddr *)&a, sizeof a) == 0) return op->fd;
    if (errno == EAGAIN) return -(long)EADDRNOTAVAIL;
    if (errno != EINPROGRESS && errno != EINTR) return -(long)errno;
    return connect_finished(op->fd);
}

static long attempt_read(const struct linea_op *op) {
    ssize_t count;
    do {
        count = read(op->fd, (void *)(uintptr_t)op->at, (size_t)op->len);
    } while (count < 0 && errno == EINTR);
    return count < 0 ? failed() : (long)count;
}

static long attempt_write(const struct linea_op *op) {
    ssize_t count;
    do {
        count = send_without_signal(op->fd, (const void *)(uintptr_t)op->at, (size_t)op->len);
    } while (count < 0 && errno == EINTR);
    return count < 0 ? failed() : (long)count;
}

static long attempt(struct linea_op *op) {
    if (op->kind == OP_ACCEPT) return attempt_accept(op);
    if (op->kind == OP_CONNECT) return attempt_connect(op);
    if (op->kind == OP_READ) return attempt_read(op);
    return attempt_write(op);
}

static long monotonic_now(unsigned long *now) {
    long seconds;
    unsigned long nanoseconds;
    const long error = linea_clock_read(LINEA_CLOCK_MONOTONIC, &seconds, &nanoseconds);
    if (error != 0) return error;
    *now = (unsigned long)seconds * 1000000000UL + nanoseconds;
    return 0;
}

/* Wait for the descriptor until the deadline at most. poll counts whole
 * milliseconds, so what remains is rounded down and a wait ends by the deadline
 * rather than after it; the last fraction of a millisecond is slept, and the
 * attempt that follows finds whatever became ready meanwhile. An interrupted
 * wait returns, and the caller computes what remains from the clock again. */
static long wait_ready(const struct linea_op *op, unsigned long remaining_ns, int unbounded) {
    struct pollfd entry;
    entry.fd = op->fd;
    entry.events = (op->kind == OP_READ || op->kind == OP_ACCEPT) ? POLLIN : POLLOUT;
    entry.revents = 0;
    int timeout_ms = -1;
    if (!unbounded) {
        const unsigned long whole_ms = remaining_ns / 1000000UL;
        if (whole_ms == 0) {
            struct timespec remainder;
            remainder.tv_sec = 0;
            remainder.tv_nsec = (long)remaining_ns;
            (void)nanosleep(&remainder, NULL);
            return 0;
        }
        timeout_ms = whole_ms > (unsigned long)INT_MAX ? INT_MAX : (int)whole_ms;
    }
    if (poll(&entry, 1, timeout_ms) < 0 && errno != EINTR) return -(long)errno;
    return 0;
}

/* Perform `op` on the calling thread and answer its one result. A descriptor
 * that is not ready is polled for what remains of the deadline, and EINTR never
 * reaches the caller.
 *
 * The deadline is checked once on entry, so an operation whose deadline has
 * already passed answers -ETIMEDOUT before anything is consumed. After that
 * the check follows each attempt: an attempt made as the wait ended, whether
 * by readiness or by expiry, is the claimant's last, and it decides the result
 * by the operation's own rule. Progress wins, since dropping bytes or a
 * connection taken off the backlog would lose them, and an attempt that would
 * still wait answers -ETIMEDOUT. A connect's attempt reads SO_ERROR when the
 * socket is writable, and a socket still connecting at the deadline times out
 * and is closed here, since the caller never received it. */
static long linea_io_perform(struct linea_op *op) {
    unsigned long now = 0;
    const int has_deadline = op->deadline_ns != 0;
    if (has_deadline) {
        const long clock_error = monotonic_now(&now);
        if (clock_error != 0) return clock_error;
        if (now >= op->deadline_ns) return -(long)ETIMEDOUT;
    }
    long answer;
    for (;;) {
        answer = attempt(op);
        if (answer != -(long)EAGAIN) break;
        unsigned long remaining_ns = 0;
        if (has_deadline) {
            const long clock_error = monotonic_now(&now);
            if (clock_error != 0) { answer = clock_error; break; }
            if (now >= op->deadline_ns) { answer = -(long)ETIMEDOUT; break; }
            remaining_ns = op->deadline_ns - now;
        }
        const long wait_error = wait_ready(op, remaining_ns, !has_deadline);
        if (wait_error != 0) { answer = wait_error; break; }
    }
    if (op->kind == OP_CONNECT && answer < 0 && op->fd >= 0) close(op->fd);
    return answer;
}

long linea_net_accept(int listener, unsigned long deadline_ns) {
    struct linea_op op = { OP_ACCEPT, listener, 0, 0, 0, deadline_ns };
    return linea_io_perform(&op);
}

long linea_net_connect(unsigned long address, unsigned long deadline_ns) {
    struct linea_op op = { OP_CONNECT, -1, 0, 0, address, deadline_ns };
    return linea_io_perform(&op);
}

long linea_net_read(int fd, unsigned long at, unsigned long len, unsigned long deadline_ns) {
    const int invalid = linea_io_byte_range(at, len);
    if (invalid != 0) return -(long)invalid;
    if (len == 0) return 0;
    struct linea_op op = { OP_READ, fd, at, len, 0, deadline_ns };
    return linea_io_perform(&op);
}

long linea_net_write(int fd, unsigned long at, unsigned long len, unsigned long deadline_ns) {
    const int invalid = linea_io_byte_range(at, len);
    if (invalid != 0) return -(long)invalid;
    if (len == 0) return 0;
    struct linea_op op = { OP_WRITE, fd, at, len, 0, deadline_ns };
    return linea_io_perform(&op);
}

/* Neither POSIX nor Linux documents EINTR for getsockname, but it shares
 * getpeername's observed exposure on macOS below, and Listener.local_address
 * reads a real caller's bound address, so the same retry applies here. */
long linea_net_local_address(int fd) {
    struct sockaddr_in a;
    socklen_t size;
    int result;
    do {
        size = sizeof a;
        result = getsockname(fd, (struct sockaddr *)&a, &size);
    } while (result != 0 && errno == EINTR);
    if (result != 0) return -(long)errno;
    return pack(&a);
}

/* Neither POSIX nor Linux documents EINTR for getpeername, but it was
 * observed on macOS under real signal load. accept() calls this immediately
 * for every accepted connection (see Listener.accept in
 * std/net/listener.lin), so a signal landing during getpeername must not
 * turn an already-established connection into a reported accept failure;
 * the retry is what accept()'s own EINTR loop above provides for the
 * connection itself. */
long linea_net_peer_address(int fd) {
    struct sockaddr_in a;
    socklen_t size;
    int result;
    do {
        size = sizeof a;
        result = getpeername(fd, (struct sockaddr *)&a, &size);
    } while (result != 0 && errno == EINTR);
    if (result != 0) {
        /* A connected socket has no peer only once the connection was torn
         * down, which Linux reports as ENOTCONN and Darwin as EINVAL. */
        if (errno == ENOTCONN || errno == EINVAL) return -(long)ECONNRESET;
        return -(long)errno;
    }
    return pack(&a);
}

long linea_net_shutdown_write(int fd) {
    /* shutdown does not block; Linux and macOS document no EINTR for it. */
    return shutdown(fd, SHUT_WR) == 0 ? 0 : -(long)errno;
}

long linea_net_reset(int fd) {
    struct linger abort_on_close;
    abort_on_close.l_onoff = 1;
    abort_on_close.l_linger = 0;
    /* setsockopt does not block; Linux and macOS document no EINTR for it. */
    const int configured = setsockopt(fd, SOL_SOCKET, SO_LINGER, &abort_on_close, sizeof abort_on_close);
    const int error = configured == 0 ? 0 : errno;
    /* close is not retried after EINTR: POSIX leaves the descriptor's fate
     * unspecified in that case, and this runtime's supported kernels remove
     * it before reporting the error either way, so a retry could close an
     * unrelated descriptor that already reused the number. */
    const int closed = close(fd);
    if (error != 0) return -(long)error;
    return closed == 0 ? 0 : -(long)errno;
}
