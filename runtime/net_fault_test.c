#define _GNU_SOURCE
/* Assertions execute test setup, checks, and cleanup in every build mode. */
#undef NDEBUG
#include "net.h"

#include <arpa/inet.h>
#include <assert.h>
#include <errno.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

/* Every fault flag starts disarmed; each test arms exactly the fault it
 * exercises immediately before the call meant to trip it, and every wrapper
 * clears its own flag on the one call it fires for. */
static int fail_socket_with_emfile = 0;
static int fail_setsockopt_with_enoprotoopt = 0;
static int fail_bind_with_addrinuse = 0;
static int fail_listen_with_enobufs = 0;
static int fail_close_on_exec_with_einval = 0;
static int interrupt_accept = 0;
static int interrupt_connect = 0;
static int fail_getpeername_with = 0;
static int fail_getsockname_with = 0;

/* setsockopt, bind, listen and fcntl each record the descriptor they were
 * asked to act on, so a test can confirm it was released after a fault. */
static int last_socket_fd = -1;

int linea_test_socket(int domain, int type, int protocol) {
    if (fail_socket_with_emfile) {
        fail_socket_with_emfile = 0;
        errno = EMFILE;
        return -1;
    }
    return socket(domain, type, protocol);
}

int linea_test_setsockopt(int fd, int level, int name, const void *value, socklen_t len) {
    last_socket_fd = fd;
    if (fail_setsockopt_with_enoprotoopt) {
        fail_setsockopt_with_enoprotoopt = 0;
        errno = ENOPROTOOPT;
        return -1;
    }
    return setsockopt(fd, level, name, value, len);
}

int linea_test_bind(int fd, const struct sockaddr *addr, socklen_t len) {
    last_socket_fd = fd;
    if (fail_bind_with_addrinuse) {
        fail_bind_with_addrinuse = 0;
        errno = EADDRINUSE;
        return -1;
    }
    return bind(fd, addr, len);
}

int linea_test_listen(int fd, int backlog) {
    last_socket_fd = fd;
    if (fail_listen_with_enobufs) {
        fail_listen_with_enobufs = 0;
        errno = ENOBUFS;
        return -1;
    }
    return listen(fd, backlog);
}

/* net.c's only fcntl call is the close-on-exec step shared by every socket it
 * creates or accepts; matching the header's variadic prototype (rather than
 * a fixed third parameter) keeps this definition compatible with however the
 * renamed declaration in <fcntl.h> is seen from net.c. */
int linea_test_fcntl(int fd, int cmd, ...) {
    va_list args;
    va_start(args, cmd);
    int arg = va_arg(args, int);
    va_end(args);
    last_socket_fd = fd;
    if (fail_close_on_exec_with_einval && cmd == F_SETFD) {
        fail_close_on_exec_with_einval = 0;
        errno = EINVAL;
        return -1;
    }
    return fcntl(fd, cmd, arg);
}

/* A real accept() is never attempted on the faked call, matching how a
 * signal interrupts accept() before a connection is taken off the queue: the
 * queued connection is still there for the retry. */
int linea_test_accept(int fd, struct sockaddr *addr, socklen_t *len) {
    if (interrupt_accept) {
        interrupt_accept = 0;
        errno = EINTR;
        return -1;
    }
    return accept(fd, addr, len);
}

/* A real signal-interrupted connect() still starts the handshake before
 * EINTR is reported: the connection attempt is not abandoned. The wrapper
 * reproduces a genuinely in-flight interruption rather than an already-
 * decided one: switch the socket to non-blocking, issue the real connect
 * (which reports success, EINPROGRESS, or a real error such as
 * ECONNREFUSED once the kernel already knows the peer refused), restore
 * blocking mode, then report EINTR regardless of that outcome. Only the
 * caller's poll+SO_ERROR completion discovers what actually happened. */
int linea_test_connect(int fd, const struct sockaddr *addr, socklen_t len) {
    if (interrupt_connect) {
        interrupt_connect = 0;
        const int flags = fcntl(fd, F_GETFL, 0);
        assert(flags != -1);
        assert(fcntl(fd, F_SETFL, flags | O_NONBLOCK) == 0);
        connect(fd, addr, len);
        assert(fcntl(fd, F_SETFL, flags) == 0);
        errno = EINTR;
        return -1;
    }
    return connect(fd, addr, len);
}

int linea_test_getpeername(int fd, struct sockaddr *addr, socklen_t *len) {
    if (fail_getpeername_with != 0) {
        errno = fail_getpeername_with;
        fail_getpeername_with = 0;
        return -1;
    }
    return getpeername(fd, addr, len);
}

int linea_test_getsockname(int fd, struct sockaddr *addr, socklen_t *len) {
    if (fail_getsockname_with != 0) {
        errno = fail_getsockname_with;
        fail_getsockname_with = 0;
        return -1;
    }
    return getsockname(fd, addr, len);
}

static unsigned long loopback(unsigned port) { return (0x7f000001UL << 16) | port; }

static int descriptor_is_closed(int fd) {
    return fcntl(fd, F_GETFD) == -1 && errno == EBADF;
}

static int raw_listener(unsigned long *bound_address) {
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    assert(fd >= 0);
    struct sockaddr_in a;
    memset(&a, 0, sizeof a);
    a.sin_family = AF_INET;
    a.sin_addr.s_addr = htonl(0x7f000001UL);
    a.sin_port = 0;
    assert(bind(fd, (struct sockaddr *)&a, sizeof a) == 0);
    assert(listen(fd, 4) == 0);
    socklen_t size = sizeof a;
    assert(getsockname(fd, (struct sockaddr *)&a, &size) == 0);
    *bound_address = ((unsigned long)ntohl(a.sin_addr.s_addr) << 16) | ntohs(a.sin_port);
    return fd;
}

/* Learns a free loopback port by binding and immediately closing, so nothing
 * is listening there when the caller connects to it. */
static unsigned long closed_port_address(void) {
    unsigned long bound_address;
    int fd = raw_listener(&bound_address);
    assert(close(fd) == 0);
    return bound_address;
}

static void listen_reports_emfile(void) {
    fail_socket_with_emfile = 1;
    assert(linea_net_listen(loopback(0), 4) == -EMFILE);
    assert(fail_socket_with_emfile == 0);
}

static void listen_reports_setsockopt_failure_and_releases_fd(void) {
    fail_setsockopt_with_enoprotoopt = 1;
    assert(linea_net_listen(loopback(0), 4) == -ENOPROTOOPT);
    assert(fail_setsockopt_with_enoprotoopt == 0);
    assert(descriptor_is_closed(last_socket_fd));
}

static void listen_reports_bind_failure_and_releases_fd(void) {
    fail_bind_with_addrinuse = 1;
    assert(linea_net_listen(loopback(0), 4) == -EADDRINUSE);
    assert(fail_bind_with_addrinuse == 0);
    assert(descriptor_is_closed(last_socket_fd));
}

static void listen_reports_listen_failure_and_releases_fd(void) {
    fail_listen_with_enobufs = 1;
    assert(linea_net_listen(loopback(0), 4) == -ENOBUFS);
    assert(fail_listen_with_enobufs == 0);
    assert(descriptor_is_closed(last_socket_fd));
}

static int connect_real_client(unsigned long bound) {
    int client = socket(AF_INET, SOCK_STREAM, 0);
    assert(client >= 0);
    struct sockaddr_in a;
    memset(&a, 0, sizeof a);
    a.sin_family = AF_INET;
    a.sin_addr.s_addr = htonl((uint32_t)(bound >> 16));
    a.sin_port = htons((uint16_t)(bound & 0xffff));
    assert(connect(client, (struct sockaddr *)&a, sizeof a) == 0);
    return client;
}

static void accept_releases_fd_on_close_on_exec_failure(void) {
    long listener = linea_net_listen(loopback(0), 4);
    assert(listener >= 0);
    long bound = linea_net_local_address((int)listener);
    assert(bound >= 0);
    int client = connect_real_client((unsigned long)bound);

    fail_close_on_exec_with_einval = 1;
    assert(linea_net_accept((int)listener) == -EINVAL);
    assert(fail_close_on_exec_with_einval == 0);
    assert(descriptor_is_closed(last_socket_fd));

    close(client);
    close((int)listener);
}

static void accept_retries_after_eintr(void) {
    long listener = linea_net_listen(loopback(0), 4);
    assert(listener >= 0);
    long bound = linea_net_local_address((int)listener);
    assert(bound >= 0);
    int client = connect_real_client((unsigned long)bound);

    interrupt_accept = 1;
    long server = linea_net_accept((int)listener);
    assert(interrupt_accept == 0);
    assert(server >= 0);

    close(client);
    close((int)server);
    close((int)listener);
}

static void connect_reports_success_after_eintr(void) {
    unsigned long bound_address;
    int listener = raw_listener(&bound_address);

    interrupt_connect = 1;
    long client = linea_net_connect(bound_address);
    assert(interrupt_connect == 0);
    assert(client >= 0);

    int server = accept(listener, NULL, NULL);
    assert(server >= 0);

    close(server);
    close((int)client);
    close(listener);
}

/* The interrupted call is genuinely in-flight (see linea_test_connect), so
 * only an implementation that actually waits on poll+SO_ERROR can tell this
 * apart from success: one that treated EINTR as completion would return the
 * fd here instead of -ECONNREFUSED. */
static void connect_reports_refused_after_eintr(void) {
    unsigned long bound_address = closed_port_address();

    interrupt_connect = 1;
    long client = linea_net_connect(bound_address);
    assert(interrupt_connect == 0);
    assert(client == -ECONNREFUSED);
}

static void reset_closes_the_descriptor_when_lingering_is_refused(void) {
    long listener = linea_net_listen(loopback(0), 4);
    assert(listener >= 0);
    long bound = linea_net_local_address((int)listener);
    assert(bound >= 0);
    long client = linea_net_connect((unsigned long)bound);
    assert(client >= 0);
    fail_setsockopt_with_enoprotoopt = 1;
    assert(linea_net_reset((int)client) == -ENOPROTOOPT);
    assert(fail_setsockopt_with_enoprotoopt == 0);
    assert(last_socket_fd == (int)client);
    assert(descriptor_is_closed((int)client));
    close((int)listener);
}

/* A connected socket without a peer was torn down: Linux reports ENOTCONN
 * and Darwin EINVAL. Any other failure is reported as it is. */
static void peer_address_reports_a_torn_down_connection_as_reset(void) {
    fail_getpeername_with = ENOTCONN;
    assert(linea_net_peer_address(3) == -ECONNRESET);
    fail_getpeername_with = EINVAL;
    assert(linea_net_peer_address(3) == -ECONNRESET);
    fail_getpeername_with = EBADF;
    assert(linea_net_peer_address(3) == -EBADF);
    assert(fail_getpeername_with == 0);
}

/* accept() hands every connection straight to peer_address (see
 * Listener.accept in std/net/listener.lin), so a signal interrupting
 * getpeername on that path must not surface as a failed accept: the
 * connection is already established and worth retrying for. */
static void peer_address_retries_after_eintr(void) {
    long listener = linea_net_listen(loopback(0), 4);
    assert(listener >= 0);
    long bound = linea_net_local_address((int)listener);
    assert(bound >= 0);
    int client = connect_real_client((unsigned long)bound);
    int server = accept((int)listener, NULL, NULL);
    assert(server >= 0);

    struct sockaddr_in expected;
    socklen_t expected_size = sizeof expected;
    assert(getpeername(server, (struct sockaddr *)&expected, &expected_size) == 0);
    unsigned long expected_packed =
        ((unsigned long)ntohl(expected.sin_addr.s_addr) << 16) | ntohs(expected.sin_port);

    fail_getpeername_with = EINTR;
    long peer = linea_net_peer_address(server);
    assert(fail_getpeername_with == 0);
    assert(peer == (long)expected_packed);

    close(client);
    close(server);
    close((int)listener);
}

/* getsockname shares getpeername's exposure to a signal landing mid-call;
 * the same retry keeps a bound address readable rather than reporting the
 * interruption as a lookup failure. */
static void local_address_retries_after_eintr(void) {
    long listener = linea_net_listen(loopback(0), 4);
    assert(listener >= 0);

    struct sockaddr_in expected;
    socklen_t expected_size = sizeof expected;
    assert(getsockname((int)listener, (struct sockaddr *)&expected, &expected_size) == 0);
    unsigned long expected_packed =
        ((unsigned long)ntohl(expected.sin_addr.s_addr) << 16) | ntohs(expected.sin_port);

    fail_getsockname_with = EINTR;
    long bound = linea_net_local_address((int)listener);
    assert(fail_getsockname_with == 0);
    assert(bound == (long)expected_packed);

    close((int)listener);
}

int main(void) {
    listen_reports_emfile();
    listen_reports_setsockopt_failure_and_releases_fd();
    listen_reports_bind_failure_and_releases_fd();
    listen_reports_listen_failure_and_releases_fd();
    accept_releases_fd_on_close_on_exec_failure();
    accept_retries_after_eintr();
    connect_reports_success_after_eintr();
    connect_reports_refused_after_eintr();
    reset_closes_the_descriptor_when_lingering_is_refused();
    peer_address_reports_a_torn_down_connection_as_reset();
    peer_address_retries_after_eintr();
    local_address_retries_after_eintr();
    puts("native net: injected socket, setsockopt, bind, listen, fcntl, accept, connect, getpeername and getsockname faults are retried or reported; a refused reset still closes");
    return 0;
}
