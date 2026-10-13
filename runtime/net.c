#define _GNU_SOURCE
#include "net.h"

#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <poll.h>
#include <stdint.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/time.h>
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

static int close_on_exec(int fd) {
    /* F_SETFD does not block; Linux and macOS document EINTR only for the
     * blocking lock commands F_SETLKW and F_OFD_SETLKW, not for it. */
    return fcntl(fd, F_SETFD, FD_CLOEXEC) == 0 ? 0 : errno;
}

static long stream_socket(void) {
    /* socket does not block; Linux and macOS document no EINTR for it. */
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) return -(long)errno;
    int failed = close_on_exec(fd);
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

long linea_net_accept(int listener) {
    int fd;
    do { fd = accept(listener, NULL, NULL); } while (fd < 0 && errno == EINTR);
    if (fd < 0) return -(long)errno;
    int failed = close_on_exec(fd);
    if (failed != 0) { close(fd); return -(long)failed; }
    return fd;
}

/* A signal restarts `connect` as EALREADY rather than reattempting the
 * three-way handshake, so an interrupted attempt is resumed by waiting for
 * the socket to become writable and then reading SO_ERROR, not by looping
 * on connect itself. */
static long await_connect(int fd) {
    struct pollfd entry;
    entry.fd = fd;
    entry.events = POLLOUT;
    int ready;
    do { ready = poll(&entry, 1, -1); } while (ready < 0 && errno == EINTR);
    if (ready < 0) return -(long)errno;
    int pending = 0;
    socklen_t pending_size = sizeof pending;
    /* getsockopt does not block; Linux and macOS document no EINTR for it. */
    if (getsockopt(fd, SOL_SOCKET, SO_ERROR, &pending, &pending_size) != 0) return -(long)errno;
    return pending == 0 ? 0 : -(long)pending;
}

long linea_net_connect(unsigned long address) {
    long fd = stream_socket();
    if (fd < 0) return fd;
    struct sockaddr_in a = unpack(address);
    if (connect((int)fd, (struct sockaddr *)&a, sizeof a) != 0) {
        int error = errno;
        if (error == EINTR) {
            long waited = await_connect((int)fd);
            if (waited != 0) { close((int)fd); return waited; }
        } else {
            close((int)fd);
            return -(long)error;
        }
    }
    return fd;
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

static struct timeval to_timeval(unsigned long ms) {
    struct timeval t;
    t.tv_sec = (time_t)(ms / 1000UL);
    t.tv_usec = (suseconds_t)((ms % 1000UL) * 1000UL);
    return t;
}

long linea_net_set_timeouts(int fd, unsigned long read_ms, unsigned long write_ms) {
    struct timeval read_timeout = to_timeval(read_ms);
    struct timeval write_timeout = to_timeval(write_ms);
    /* setsockopt does not block; Linux and macOS document no EINTR for it. */
    if (setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &read_timeout, sizeof read_timeout) != 0) return -(long)errno;
    if (setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &write_timeout, sizeof write_timeout) != 0) return -(long)errno;
    return 0;
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
