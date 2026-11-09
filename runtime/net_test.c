#define _GNU_SOURCE
/* Assertions execute test setup, checks, and cleanup in every build mode. */
#undef NDEBUG
#include "io.h"
#include "net.h"

#include "clock.h"

#include <assert.h>
#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <time.h>
#include <unistd.h>

#define ADDRESS(p) ((unsigned long)(uintptr_t)(p))

static unsigned long loopback(unsigned port) { return (0x7f000001UL << 16) | port; }

static unsigned long now_ns(void) {
    long seconds;
    unsigned long nanoseconds;
    assert(linea_clock_read(LINEA_CLOCK_MONOTONIC, &seconds, &nanoseconds) == 0);
    return (unsigned long)seconds * 1000000000UL + nanoseconds;
}

static unsigned long in_ms(unsigned long ms) { return now_ns() + ms * 1000000UL; }

/* A listener, a connected client and the connection accepted for it. */
struct pair { long listener, client, server; };

static struct pair connected_pair(void) {
    struct pair p;
    p.listener = linea_net_listen(loopback(0), 4);
    assert(p.listener >= 0);
    long bound = linea_net_local_address((int)p.listener);
    assert(bound >= 0);
    p.client = linea_net_connect((unsigned long)bound, 0);
    assert(p.client >= 0);
    p.server = linea_net_accept((int)p.listener, 0);
    assert(p.server >= 0);
    return p;
}

static void close_pair(struct pair p) {
    close((int)p.client); close((int)p.server); close((int)p.listener);
}

static int is_nonblocking(long fd) {
    int flags = fcntl((int)fd, F_GETFL, 0);
    assert(flags != -1);
    return (flags & O_NONBLOCK) != 0;
}

/* Every socket the runtime makes is nonblocking, on Linux too, where an
 * accepted socket does not inherit the listener's mode. */
static void every_socket_is_nonblocking(void) {
    struct pair p = connected_pair();
    assert(is_nonblocking(p.listener));
    assert(is_nonblocking(p.client));
    assert(is_nonblocking(p.server));
    close_pair(p);
}

static void short_read_answers_what_arrived(void) {
    struct pair p = connected_pair();
    assert(linea_net_write((int)p.client, ADDRESS("abc"), 3, 0) == 3);
    char got[8];
    assert(linea_net_read((int)p.server, ADDRESS(got), sizeof got, 0) == 3);
    assert(memcmp(got, "abc", 3) == 0);
    close_pair(p);
}

struct delayed_write { int fd; };

static void *write_after_a_pause(void *argument) {
    const struct delayed_write *job = argument;
    struct timespec pause = { 0, 30 * 1000000L };
    nanosleep(&pause, NULL);
    assert(linea_net_write(job->fd, ADDRESS("z"), 1, 0) == 1);
    return NULL;
}

/* With nothing to read the socket answers EAGAIN inside the runtime, and with
 * no deadline the read waits until the byte comes. */
static void read_without_a_deadline_waits_past_eagain(void) {
    struct pair p = connected_pair();
    struct delayed_write job = { (int)p.client };
    pthread_t writer;
    assert(pthread_create(&writer, NULL, write_after_a_pause, &job) == 0);
    char got;
    assert(linea_net_read((int)p.server, ADDRESS(&got), 1, 0) == 1);
    assert(got == 'z');
    assert(pthread_join(writer, NULL) == 0);
    close_pair(p);
}

static void read_deadline_times_out(void) {
    struct pair p = connected_pair();
    const unsigned long started = now_ns();
    char got[4];
    assert(linea_net_read((int)p.server, ADDRESS(got), sizeof got, in_ms(50)) == -ETIMEDOUT);
    assert(now_ns() - started >= 50 * 1000000UL);
    /* A timed-out read leaves the connection usable. */
    assert(linea_net_write((int)p.client, ADDRESS("k"), 1, 0) == 1);
    assert(linea_net_read((int)p.server, ADDRESS(got), sizeof got, in_ms(1000)) == 1);
    close_pair(p);
}

/* A deadline already past answers before any attempt, so bytes waiting stay in
 * the socket for the next read. */
static void read_past_its_deadline_leaves_the_bytes(void) {
    struct pair p = connected_pair();
    assert(linea_net_write((int)p.client, ADDRESS("q"), 1, 0) == 1);
    /* Loopback delivery can trail the write by a moment. */
    struct timespec settle = { 0, 5 * 1000000L };
    nanosleep(&settle, NULL);
    char got;
    assert(linea_net_read((int)p.server, ADDRESS(&got), 1, now_ns() - 1) == -ETIMEDOUT);
    assert(linea_net_read((int)p.server, ADDRESS(&got), 1, 0) == 1);
    assert(got == 'q');
    close_pair(p);
}

static void empty_read_and_write_touch_nothing(void) {
    char byte;
    assert(linea_net_read(-1, ADDRESS(&byte), 0, 0) == 0);
    assert(linea_net_write(-1, ADDRESS(&byte), 0, 0) == 0);
}

static void accept_deadline_times_out_and_the_listener_still_serves(void) {
    long listener = linea_net_listen(loopback(0), 4);
    assert(listener >= 0);
    long bound = linea_net_local_address((int)listener);
    assert(bound >= 0);
    const unsigned long started = now_ns();
    assert(linea_net_accept((int)listener, in_ms(50)) == -ETIMEDOUT);
    assert(now_ns() - started >= 50 * 1000000UL);
    long client = linea_net_connect((unsigned long)bound, 0);
    assert(client >= 0);
    long served = linea_net_accept((int)listener, 0);
    assert(served >= 0);
    close((int)client); close((int)served); close((int)listener);
}

/* A deadline already past takes nothing off the backlog. */
static void accept_past_its_deadline_leaves_the_connection_queued(void) {
    long listener = linea_net_listen(loopback(0), 4);
    assert(listener >= 0);
    long bound = linea_net_local_address((int)listener);
    assert(bound >= 0);
    long client = linea_net_connect((unsigned long)bound, 0);
    assert(client >= 0);
    assert(linea_net_accept((int)listener, now_ns() - 1) == -ETIMEDOUT);
    long served = linea_net_accept((int)listener, 0);
    assert(served >= 0);
    close((int)client); close((int)served); close((int)listener);
}

static void connect_past_its_deadline_makes_no_socket(void) {
    long listener = linea_net_listen(loopback(0), 4);
    assert(listener >= 0);
    long bound = linea_net_local_address((int)listener);
    assert(bound >= 0);
    /* The lowest free descriptor stays free: nothing was opened and leaked. */
    int probe = open("/dev/null", O_RDONLY);
    assert(probe >= 0);
    close(probe);
    assert(linea_net_connect((unsigned long)bound, now_ns() - 1) == -ETIMEDOUT);
    int next = open("/dev/null", O_RDONLY);
    assert(next == probe);
    close(next);
    close((int)listener);
}

/* 192.0.2.0/24 is reserved for documentation and is not routed, so a handshake
 * there stays in progress and answers -ETIMEDOUT at its deadline with the
 * socket closed. A host with no route answers unreachable at once. */
static void connect_deadline_ends_a_pending_handshake(void) {
    const unsigned long documentation_address = (0xc0000201UL << 16) | 9;
    const unsigned long started = now_ns();
    const long client = linea_net_connect(documentation_address, in_ms(100));
    assert(client == -ETIMEDOUT || client == -ENETUNREACH || client == -EHOSTUNREACH);
    if (client == -ETIMEDOUT) assert(now_ns() - started >= 100 * 1000000UL);
    assert(now_ns() - started < 10UL * 1000000000UL);
}

/* A send buffer fills with short counts, then a write that cannot progress
 * answers -ETIMEDOUT at its deadline. */
static void write_deadline_times_out_on_a_full_buffer(void) {
    struct pair p = connected_pair();
    static char bytes[1 << 16];
    memset(bytes, 'x', sizeof bytes);
    int sent_some = 0;
    long result = 0;
    for (int round = 0; round < 100000; round += 1) {
        result = linea_net_write((int)p.server, ADDRESS(bytes), sizeof bytes, in_ms(50));
        if (result < 0) break;
        assert(result > 0);
        sent_some = 1;
    }
    assert(sent_some);
    assert(result == -ETIMEDOUT);
    close_pair(p);
}

/* One side's shutdown ends the peer's input; the other direction stays open. */
static void half_close_ends_input_and_keeps_the_other_direction(void) {
    struct pair p = connected_pair();
    assert(linea_net_shutdown_write((int)p.client) == 0);
    char got[4];
    assert(linea_net_read((int)p.server, ADDRESS(got), sizeof got, in_ms(1000)) == 0);
    assert(linea_net_write((int)p.server, ADDRESS("ok"), 2, 0) == 2);
    assert(linea_net_read((int)p.client, ADDRESS(got), sizeof got, in_ms(1000)) == 2);
    assert(memcmp(got, "ok", 2) == 0);
    close_pair(p);
}

static void round_trip(void) {
    long listener = linea_net_listen(loopback(0), 4);
    assert(listener >= 0);
    long bound = linea_net_local_address((int)listener);
    assert(bound >= 0 && (bound >> 16) == 0x7f000001 && (bound & 0xffff) != 0);
    long client = linea_net_connect((unsigned long)bound, 0);   /* before accept: kernel queues it */
    assert(client >= 0);
    long server = linea_net_accept((int)listener, 0);
    assert(server >= 0);
    assert(linea_net_write((int)client, ADDRESS("ping"), 4, 0) == 4);
    char got[4];
    assert(linea_net_read((int)server, ADDRESS(got), 4, 0) == 4 && memcmp(got, "ping", 4) == 0);
    long peer = linea_net_peer_address((int)server);
    assert((peer >> 16) == 0x7f000001);
    close((int)client); close((int)server); close((int)listener);
}

static void broken_pipe_without_signal(void) {
    long listener = linea_net_listen(loopback(0), 4);
    assert(listener >= 0);
    long bound = linea_net_local_address((int)listener);
    assert(bound >= 0);
    long client = linea_net_connect((unsigned long)bound, 0);
    assert(client >= 0);
    long server = linea_net_accept((int)listener, 0);
    assert(server >= 0);
    close((int)client);

    char bytes[64];
    memset(bytes, 'x', sizeof bytes);
    /* The kernel notices the closed peer once the writing process is the
     * only reference left to the half-closed connection; earlier writes can
     * still succeed, and one may even report -ECONNRESET before the socket
     * settles into reporting -EPIPE on every later write. */
    long result;
    int attempts = 0;
    do {
        result = linea_net_write((int)server, ADDRESS(bytes), sizeof bytes, 0);
        attempts += 1;
    } while (result != -EPIPE && attempts < 100000);
    assert(result == -EPIPE);
    close((int)server); close((int)listener);
}

static void address_in_use(void) {
    long listener = linea_net_listen(loopback(0), 4);
    assert(listener >= 0);
    long bound = linea_net_local_address((int)listener);
    assert(bound >= 0);
    long second = linea_net_listen((unsigned long)bound, 4);
    assert(second == -EADDRINUSE);
    close((int)listener);
}

static void refused(void) {
    long listener = linea_net_listen(loopback(0), 4);
    assert(listener >= 0);
    long bound = linea_net_local_address((int)listener);
    assert(bound >= 0);
    close((int)listener);
    long client = linea_net_connect((unsigned long)bound, 0);
    assert(client == -ECONNREFUSED);
}

static void reset(void) {
    long listener = linea_net_listen(loopback(0), 4);
    assert(listener >= 0);
    long bound = linea_net_local_address((int)listener);
    assert(bound >= 0);
    long client = linea_net_connect((unsigned long)bound, 0);
    assert(client >= 0);
    long server = linea_net_accept((int)listener, 0);
    assert(server >= 0);
    assert(linea_net_write((int)client, ADDRESS("GET"), 3, 0) == 3);
    assert(linea_net_reset((int)client) == 0);
    /* The reset discards the connection, so the peer's read reports it
     * rather than an orderly end of input. */
    char got[8];
    long result = linea_net_read((int)server, ADDRESS(got), sizeof got, 0);
    while (result > 0) result = linea_net_read((int)server, ADDRESS(got), sizeof got, 0);
    assert(result == -ECONNRESET);
    close((int)server); close((int)listener);
}

static void accepted_after_reset(void) {
    long listener = linea_net_listen(loopback(0), 4);
    assert(listener >= 0);
    long bound = linea_net_local_address((int)listener);
    assert(bound >= 0);
    long client = linea_net_connect((unsigned long)bound, 0);
    assert(client >= 0);
    assert(linea_net_reset((int)client) == 0);
    /* The reset reaches the listener before or after the queued connection
     * is handed out: accepting it fails, it is accepted with no peer left to
     * name, or it is accepted intact and its first read reports the reset.
     * Which of the three happens is the kernel's timing, not the runtime's
     * contract. */
    long server = linea_net_accept((int)listener, 0);
    if (server < 0) {
        assert(server == -ECONNABORTED || server == -ECONNRESET);
    } else {
        long peer = linea_net_peer_address((int)server);
        if (peer >= 0) {
            char got[8];
            assert(linea_net_read((int)server, ADDRESS(got), sizeof got, 0) == -ECONNRESET);
        } else {
            assert(peer == -ECONNRESET);
        }
        close((int)server);
    }
    /* Whichever way the reset showed, the listener still serves the next
     * client. */
    long next = linea_net_connect((unsigned long)bound, 0);
    assert(next >= 0);
    long served = linea_net_accept((int)listener, 0);
    assert(served >= 0);
    assert(linea_net_peer_address((int)served) >= 0);
    close((int)next); close((int)served); close((int)listener);
}

int main(void) {
    round_trip();
    every_socket_is_nonblocking();
    short_read_answers_what_arrived();
    read_without_a_deadline_waits_past_eagain();
    read_deadline_times_out();
    read_past_its_deadline_leaves_the_bytes();
    empty_read_and_write_touch_nothing();
    accept_deadline_times_out_and_the_listener_still_serves();
    accept_past_its_deadline_leaves_the_connection_queued();
    connect_past_its_deadline_makes_no_socket();
    connect_deadline_ends_a_pending_handshake();
    write_deadline_times_out_on_a_full_buffer();
    half_close_ends_input_and_keeps_the_other_direction();
    broken_pipe_without_signal();
    address_in_use();
    refused();
    reset();
    accepted_after_reset();
    puts("native net: loopback round trips, deadlines on every operation, short counts, half-close, connection errors and resets passed");
    return 0;
}
