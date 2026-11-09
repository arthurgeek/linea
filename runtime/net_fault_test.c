#define _GNU_SOURCE
/* Assertions execute test setup, checks, and cleanup in every build mode. */
#undef NDEBUG
#include "net.h"
#include "clock.h"

#include <arpa/inet.h>
#include <assert.h>
#include <errno.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <poll.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <time.h>
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
static int fail_nonblocking_with_einval = 0;

/* The clock, the poll results and the system calls a deadline meets are
 * scripted, so a readiness and an expiry can coincide exactly. A poll step
 * either fails with `error`, or moves the clock by `advance_ns` and reports
 * `ready`; an empty script calls the real poll. */
struct poll_step { int error; int ready; unsigned long advance_ns; };
static struct poll_step poll_steps[8];
static unsigned poll_step_count = 0;
static unsigned poll_step_taken = 0;
static int last_poll_timeout_ms = 0;
static int nanosleep_calls = 0;
static unsigned long fake_now_ns = 1000000000UL;
static long fail_clock_with = 0;
static int read_eintr = 0, read_eagain = 0;
static int send_eintr = 0, send_eagain = 0;
static size_t send_at_most = 0;
static int accept_eagain = 0;
static int connect_in_progress = 0;
static int connect_eagain = 0;
static int scripted_so_error = -1;

/* setsockopt, bind, listen and fcntl each record the descriptor they were
 * asked to act on, so a test can confirm it was released after a fault. */
static int last_socket_fd = -1;

long linea_test_clock_read(uint8_t clock, long *seconds, unsigned long *nanoseconds) {
    assert(clock == LINEA_CLOCK_MONOTONIC);
    if (fail_clock_with != 0) {
        const long failure = fail_clock_with;
        fail_clock_with = 0;
        return failure;
    }
    *seconds = (long)(fake_now_ns / 1000000000UL);
    *nanoseconds = fake_now_ns % 1000000000UL;
    return 0;
}

int linea_test_poll(struct pollfd *entries, nfds_t count, int timeout_ms) {
    if (poll_step_taken == poll_step_count) return poll(entries, count, timeout_ms);
    if (timeout_ms != 0) last_poll_timeout_ms = timeout_ms;
    const struct poll_step step = poll_steps[poll_step_taken++];
    if (step.error != 0) {
        fake_now_ns += step.advance_ns;
        errno = step.error;
        return -1;
    }
    fake_now_ns += step.advance_ns;
    entries[0].revents = step.ready ? entries[0].events : 0;
    return step.ready;
}

int linea_test_nanosleep(const struct timespec *requested, struct timespec *remaining) {
    (void)remaining;
    nanosleep_calls += 1;
    fake_now_ns += (unsigned long)requested->tv_sec * 1000000000UL + (unsigned long)requested->tv_nsec;
    return 0;
}

ssize_t linea_test_read(int fd, void *bytes, size_t len) {
    if (read_eintr > 0) { read_eintr -= 1; errno = EINTR; return -1; }
    if (read_eagain > 0) { read_eagain -= 1; errno = EAGAIN; return -1; }
    return read(fd, bytes, len);
}

ssize_t linea_test_send(int fd, const void *bytes, size_t len, int flags) {
    if (send_eintr > 0) { send_eintr -= 1; errno = EINTR; return -1; }
    if (send_eagain > 0) { send_eagain -= 1; errno = EAGAIN; return -1; }
    if (send_at_most != 0 && len > send_at_most) len = send_at_most;
    return send(fd, bytes, len, flags);
}

int linea_test_getsockopt(int fd, int level, int name, void *value, socklen_t *len) {
    if (level == SOL_SOCKET && name == SO_ERROR && scripted_so_error >= 0) {
        *(int *)value = scripted_so_error;
        scripted_so_error = -1;
        return 0;
    }
    return getsockopt(fd, level, name, value, len);
}

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
#if defined(SO_NOSIGPIPE)
    if (name == SO_NOSIGPIPE) return setsockopt(fd, level, name, value, len);
#endif
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

/* net.c configures every socket it creates or accepts through fcntl, for
 * close-on-exec and for O_NONBLOCK; matching the header's variadic prototype (rather than
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
    if (fail_nonblocking_with_einval && cmd == F_SETFL) {
        fail_nonblocking_with_einval = 0;
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
    if (accept_eagain > 0) {
        accept_eagain -= 1;
        errno = EAGAIN;
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
 * the socket's mode, then report EINTR regardless of that outcome. Only the
 * caller's poll+SO_ERROR completion discovers what actually happened. */
int linea_test_connect(int fd, const struct sockaddr *addr, socklen_t len) {
    last_socket_fd = fd;
    if (connect_in_progress) {
        connect_in_progress = 0;
        errno = EINPROGRESS;
        return -1;
    }
    if (connect_eagain) {
        connect_eagain = 0;
        errno = EAGAIN;
        return -1;
    }
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
    assert(linea_net_accept((int)listener, 0) == -EINVAL);
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
    long server = linea_net_accept((int)listener, 0);
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
    long client = linea_net_connect(bound_address, 0);
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
    long client = linea_net_connect(bound_address, 0);
    assert(interrupt_connect == 0);
    assert(client == -ECONNREFUSED);
}

static void reset_closes_the_descriptor_when_lingering_is_refused(void) {
    long listener = linea_net_listen(loopback(0), 4);
    assert(listener >= 0);
    long bound = linea_net_local_address((int)listener);
    assert(bound >= 0);
    long client = linea_net_connect((unsigned long)bound, 0);
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
    long accepted = linea_net_accept((int)listener, 0);
    assert(accepted >= 0);
    int server = (int)accepted;

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

#define ADDRESS(p) ((unsigned long)(uintptr_t)(p))

static void script_polls(const struct poll_step *steps, unsigned count) {
    assert(count <= 8);
    memcpy(poll_steps, steps, count * sizeof steps[0]);
    poll_step_count = count;
    poll_step_taken = 0;
}

static void assert_script_finished(void) {
    assert(poll_step_taken == poll_step_count);
    poll_step_count = 0;
    poll_step_taken = 0;
}

/* A listener, a blocking client connected to it and the accepted descriptor. */
struct pair { long listener; int client; long server; };

static struct pair scripted_pair(void) {
    struct pair p;
    p.listener = linea_net_listen(loopback(0), 4);
    assert(p.listener >= 0);
    long bound = linea_net_local_address((int)p.listener);
    assert(bound >= 0);
    p.client = connect_real_client((unsigned long)bound);
    p.server = linea_net_accept((int)p.listener, 0);
    assert(p.server >= 0);
    return p;
}

static void close_pair(struct pair p) {
    close(p.client); close((int)p.server); close((int)p.listener);
}

/* Lets bytes written to the peer reach the socket before a scripted read. */
static void settle(int fd) {
    struct pollfd entry = { fd, POLLIN, 0 };
    assert(poll(&entry, 1, 5000) == 1);
}

/* The tie rules of a read: progress at the deadline answers its count, and a
 * last attempt that finds nothing answers -ETIMEDOUT. */
static void read_at_its_deadline_answers_progress(void) {
    struct pair p = scripted_pair();
    assert(write(p.client, "hi", 2) == 2);
    settle((int)p.server);
    const struct poll_step ties[] = { { 0, 1, 5000000 } };
    script_polls(ties, 1);
    read_eagain = 1;
    char got[8];
    assert(linea_net_read((int)p.server, ADDRESS(got), sizeof got, fake_now_ns + 5000000) == 2);
    assert_script_finished();
    close_pair(p);
}

static void read_at_its_deadline_without_progress_times_out(void) {
    struct pair p = scripted_pair();
    const struct poll_step ties[] = { { 0, 1, 5000000 } };
    script_polls(ties, 1);
    read_eagain = 2;
    char got[8];
    assert(linea_net_read((int)p.server, ADDRESS(got), sizeof got, fake_now_ns + 5000000) == -ETIMEDOUT);
    assert_script_finished();
    close_pair(p);
}

/* A readiness before the deadline that turns out spurious waits again. */
static void spurious_readiness_waits_again(void) {
    struct pair p = scripted_pair();
    assert(write(p.client, "s", 1) == 1);
    settle((int)p.server);
    const struct poll_step steps[] = { { 0, 1, 0 }, { 0, 1, 0 } };
    script_polls(steps, 2);
    read_eagain = 2;
    char got[8];
    assert(linea_net_read((int)p.server, ADDRESS(got), sizeof got, fake_now_ns + 2000000000UL) == 1);
    assert_script_finished();
    close_pair(p);
}

/* An interrupted read is attempted again and an interrupted wait recomputes
 * what remains, so a signal cannot stretch a deadline. */
static void interruptions_do_not_extend_a_deadline(void) {
    struct pair p = scripted_pair();
    assert(write(p.client, "i", 1) == 1);
    settle((int)p.server);
    read_eintr = 2;
    char got[8];
    assert(linea_net_read((int)p.server, ADDRESS(got), sizeof got, 0) == 1);

    const struct poll_step interrupted[] = { { EINTR, 0, 6000000 } };
    script_polls(interrupted, 1);
    read_eagain = 2;
    assert(linea_net_read((int)p.server, ADDRESS(got), sizeof got, fake_now_ns + 5000000) == -ETIMEDOUT);
    assert_script_finished();
    close_pair(p);
}

static void a_failed_poll_is_reported(void) {
    struct pair p = scripted_pair();
    const struct poll_step failing[] = { { ENOMEM, 0, 0 } };
    script_polls(failing, 1);
    read_eagain = 1;
    char got[8];
    assert(linea_net_read((int)p.server, ADDRESS(got), sizeof got, 0) == -ENOMEM);
    assert_script_finished();
    close_pair(p);
}

/* POSIX lets poll fail with EAGAIN when it is briefly short of memory. That is
 * a wait to retry, not an answer for the caller. */
static void a_poll_short_of_resources_is_retried(void) {
    struct pair p = scripted_pair();
    assert(write(p.client, "r", 1) == 1);
    settle((int)p.server);
    const struct poll_step busy[] = { { EAGAIN, 0, 0 } };
    script_polls(busy, 1);
    read_eagain = 1;
    char got[8];
    assert(linea_net_read((int)p.server, ADDRESS(got), sizeof got, 0) == 1);
    assert_script_finished();
    close_pair(p);
}

/* poll takes milliseconds: what remains is rounded down so the wait ends by
 * the deadline, never after it, and the last fraction is slept. */
static void a_wait_never_outlasts_its_deadline(void) {
    struct pair p = scripted_pair();
    const struct poll_step steps[] = { { 0, 0, 2000000 } };
    script_polls(steps, 1);
    read_eagain = 3;
    const int sleeps = nanosleep_calls;
    char got[8];
    const unsigned long deadline = fake_now_ns + 2500000;
    assert(linea_net_read((int)p.server, ADDRESS(got), sizeof got, deadline) == -ETIMEDOUT);
    assert(last_poll_timeout_ms == 2);
    assert(nanosleep_calls == sleeps + 1);
    assert(fake_now_ns == deadline);
    assert_script_finished();
    close_pair(p);
}

static void a_clock_failure_is_reported(void) {
    struct pair p = scripted_pair();
    char got[8];
    fail_clock_with = -EPERM;
    assert(linea_net_read((int)p.server, ADDRESS(got), sizeof got, fake_now_ns + 5000000) == -EPERM);
    close_pair(p);
}

static void write_at_its_deadline_answers_progress(void) {
    struct pair p = scripted_pair();
    const struct poll_step ties[] = { { 0, 1, 5000000 } };
    script_polls(ties, 1);
    send_eagain = 1;
    assert(linea_net_write((int)p.server, ADDRESS("hey"), 3, fake_now_ns + 5000000) == 3);
    assert_script_finished();
    close_pair(p);
}

static void write_at_its_deadline_without_progress_times_out(void) {
    struct pair p = scripted_pair();
    const struct poll_step ties[] = { { 0, 1, 5000000 } };
    script_polls(ties, 1);
    send_eagain = 2;
    assert(linea_net_write((int)p.server, ADDRESS("hey"), 3, fake_now_ns + 5000000) == -ETIMEDOUT);
    assert_script_finished();
    close_pair(p);
}

static void write_answers_a_short_count_and_retries_an_interruption(void) {
    struct pair p = scripted_pair();
    send_eintr = 1;
    send_at_most = 2;
    assert(linea_net_write((int)p.server, ADDRESS("hello"), 5, 0) == 2);
    send_at_most = 0;
    close_pair(p);
}

/* A connection accepted as the deadline passes is the caller's: the kernel
 * has already taken it off the backlog. */
static void accept_at_its_deadline_answers_the_connection(void) {
    long listener = linea_net_listen(loopback(0), 4);
    assert(listener >= 0);
    long bound = linea_net_local_address((int)listener);
    assert(bound >= 0);
    int client = connect_real_client((unsigned long)bound);
    const struct poll_step ties[] = { { 0, 1, 5000000 } };
    script_polls(ties, 1);
    accept_eagain = 1;
    long server = linea_net_accept((int)listener, fake_now_ns + 5000000);
    assert(server >= 0);
    assert_script_finished();
    close(client); close((int)server); close((int)listener);
}

static void accept_at_its_deadline_finding_nothing_times_out(void) {
    long listener = linea_net_listen(loopback(0), 4);
    assert(listener >= 0);
    long bound = linea_net_local_address((int)listener);
    assert(bound >= 0);
    int client = connect_real_client((unsigned long)bound);
    const struct poll_step ties[] = { { 0, 1, 5000000 } };
    script_polls(ties, 1);
    accept_eagain = 2;
    assert(linea_net_accept((int)listener, fake_now_ns + 5000000) == -ETIMEDOUT);
    assert_script_finished();
    /* The queued connection was not touched. */
    long server = linea_net_accept((int)listener, 0);
    assert(server >= 0);
    close(client); close((int)server); close((int)listener);
}

/* Writability is not success: at the deadline SO_ERROR decides, and only a
 * socket still not writable is a timeout. The first scripted poll is the
 * check made straight after connect, the second the wait that ends at the
 * deadline, the third the check at the deadline. */
static const struct poll_step connect_at_deadline[] = { { 0, 0, 0 }, { 0, 0, 5000000 }, { 0, 1, 0 } };
static const struct poll_step connect_past_deadline[] = { { 0, 0, 0 }, { 0, 0, 5000000 }, { 0, 0, 0 } };

static void connect_at_its_deadline_reads_so_error(void) {
    script_polls(connect_at_deadline, 3);
    connect_in_progress = 1;
    scripted_so_error = 0;
    long client = linea_net_connect(loopback(1), fake_now_ns + 5000000);
    assert(client >= 0);
    assert_script_finished();
    close((int)client);

    script_polls(connect_at_deadline, 3);
    connect_in_progress = 1;
    scripted_so_error = ECONNREFUSED;
    assert(linea_net_connect(loopback(1), fake_now_ns + 5000000) == -ECONNREFUSED);
    assert_script_finished();
    assert(descriptor_is_closed(last_socket_fd));
}

static void connect_still_in_progress_at_its_deadline_times_out(void) {
    script_polls(connect_past_deadline, 3);
    connect_in_progress = 1;
    assert(linea_net_connect(loopback(1), fake_now_ns + 5000000) == -ETIMEDOUT);
    assert_script_finished();
    assert(descriptor_is_closed(last_socket_fd));
}

static void a_failed_wait_closes_the_connecting_socket(void) {
    const struct poll_step failing[] = { { 0, 0, 0 }, { ENOMEM, 0, 0 } };
    script_polls(failing, 2);
    connect_in_progress = 1;
    assert(linea_net_connect(loopback(1), 0) == -ENOMEM);
    assert_script_finished();
    assert(descriptor_is_closed(last_socket_fd));
}

/* EAGAIN from connect means no local port, not a handshake in progress. */
static void connect_reports_eagain_as_no_address(void) {
    connect_eagain = 1;
    assert(linea_net_connect(loopback(1), 0) == -EADDRNOTAVAIL);
    assert(descriptor_is_closed(last_socket_fd));
}

static void making_a_socket_nonblocking_failure_releases_it(void) {
    fail_nonblocking_with_einval = 1;
    assert(linea_net_listen(loopback(0), 4) == -EINVAL);
    assert(fail_nonblocking_with_einval == 0);
    assert(descriptor_is_closed(last_socket_fd));

    long listener = linea_net_listen(loopback(0), 4);
    assert(listener >= 0);
    long bound = linea_net_local_address((int)listener);
    assert(bound >= 0);
    int client = connect_real_client((unsigned long)bound);
    fail_nonblocking_with_einval = 1;
    assert(linea_net_accept((int)listener, 0) == -EINVAL);
    assert(descriptor_is_closed(last_socket_fd));
    close(client);
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
    read_at_its_deadline_answers_progress();
    read_at_its_deadline_without_progress_times_out();
    spurious_readiness_waits_again();
    interruptions_do_not_extend_a_deadline();
    a_failed_poll_is_reported();
    a_poll_short_of_resources_is_retried();
    a_wait_never_outlasts_its_deadline();
    a_clock_failure_is_reported();
    write_at_its_deadline_answers_progress();
    write_at_its_deadline_without_progress_times_out();
    write_answers_a_short_count_and_retries_an_interruption();
    accept_at_its_deadline_answers_the_connection();
    accept_at_its_deadline_finding_nothing_times_out();
    connect_at_its_deadline_reads_so_error();
    connect_still_in_progress_at_its_deadline_times_out();
    a_failed_wait_closes_the_connecting_socket();
    connect_reports_eagain_as_no_address();
    making_a_socket_nonblocking_failure_releases_it();
    puts("native net: injected socket, setsockopt, bind, listen, fcntl, accept, connect, getpeername, getsockname, read, send and poll faults are retried or reported; ties between readiness and expiry follow each operation's rule; a refused reset still closes");
    return 0;
}
