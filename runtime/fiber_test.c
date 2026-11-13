#define _GNU_SOURCE
#undef NDEBUG
#include "loop.h"
#include "clock.h"
#include "net.h"
#include "park.h"
#include "task.h"
#include "signals.h"
#include "waitset.h"

#include <assert.h>
#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <signal.h>
#include <stdio.h>
#include <sys/socket.h>
#include <unistd.h>

long linea_loop_open(unsigned long carriers);
long linea_task_prepare_on(unsigned long stack_bytes, unsigned long identity);

static const unsigned long stack_bytes = 2097152;
static pthread_t parent_thread, child_thread;
static unsigned long released;
static int sockets[2];
static unsigned long peer_ran;

static void release_body(unsigned long at, unsigned long len) {
    assert(at == 0 && len == 0);
    released += 1;
}

static void child(unsigned long endpoint, unsigned long at, unsigned long len) {
    assert(at == 0 && len == 0);
    child_thread = pthread_self();
    unsigned long answer = 42;
    linea_chan_send(endpoint, (unsigned long)&answer, sizeof answer);
    linea_chan_close(endpoint);
}

static void parent(unsigned long endpoint, unsigned long at, unsigned long len) {
    assert(at == 0 && len == 0);
    parent_thread = pthread_self();
    const unsigned long home = linea_io_current();
    assert(home != 0 && !linea_io_is_simulated(home));
    const long prepared = linea_task_prepare_on(stack_bytes, home);
    assert(prepared > 0);
    const unsigned long handle = linea_task_start((unsigned long)prepared, child, release_body, 0, 0, 0);
    unsigned long answer = 0;
    linea_chan_recv(handle, (unsigned long)&answer, sizeof answer);
    assert(answer == 42);
    linea_chan_close(handle);
    linea_chan_send(endpoint, (unsigned long)&answer, sizeof answer);
    linea_chan_close(endpoint);
}

static void sessions_progress_on(unsigned long carriers) {
    const long opened = linea_loop_open(carriers);
    assert(opened > 0);
    assert(!linea_io_is_simulated((unsigned long)opened));
    const long cancelled = linea_task_prepare_on(stack_bytes, (unsigned long)opened);
    assert(cancelled > 0);
    linea_task_cancel((unsigned long)cancelled);
    assert(linea_task_prepare_on(1UL << 62, (unsigned long)opened) < 0);
    const long prepared = linea_task_prepare_on(stack_bytes, (unsigned long)opened);
    assert(prepared > 0);
    const unsigned long handle = linea_task_start((unsigned long)prepared, parent, release_body, 0, 0, 0);
    unsigned long answer = 0;
    linea_chan_recv(handle, (unsigned long)&answer, sizeof answer);
    assert(answer == 42);
    linea_chan_close(handle);
    assert((pthread_equal(parent_thread, child_thread) != 0) == (carriers == 1));
    assert(linea_io_current() == 0);
}

static void write_one(unsigned long endpoint, unsigned long at, unsigned long len) {
    assert(at == 0 && len == 0);
    const unsigned char byte = 77;
    assert(linea_net_write(sockets[1], (unsigned long)&byte, 1, 0) == 1);
    linea_chan_close(endpoint);
}

static void read_one(unsigned long endpoint, unsigned long at, unsigned long len) {
    assert(at == 0 && len == 0);
    const long prepared = linea_task_prepare_on(stack_bytes, linea_io_current());
    assert(prepared > 0);
    const unsigned long writer = linea_task_start((unsigned long)prepared, write_one, release_body, 0, 0, 0);
    unsigned char byte = 0;
    assert(linea_net_read(sockets[0], (unsigned long)&byte, 1, linea_park_deadline_after(1000000000UL)) == 1);
    assert(byte == 77);
    linea_chan_close(writer);
    linea_chan_close(endpoint);
}

static void a_socket_read_releases_its_carrier(void) {
    assert(socketpair(AF_UNIX, SOCK_STREAM, 0, sockets) == 0);
    assert(fcntl(sockets[0], F_SETFL, O_NONBLOCK) == 0);
    assert(fcntl(sockets[1], F_SETFL, O_NONBLOCK) == 0);
    const long loop = linea_loop_open(1);
    assert(loop > 0);
    const long prepared = linea_task_prepare_on(stack_bytes, (unsigned long)loop);
    assert(prepared > 0);
    linea_chan_close(linea_task_start((unsigned long)prepared, read_one, release_body, 0, 0, 0));
    assert(close(sockets[0]) == 0 && close(sockets[1]) == 0);
}

static void signal_is_ignored(unsigned long endpoint, unsigned long at, unsigned long len) {
    assert(at == 0 && len == 0);
    assert(linea_signal_acquire(3) == 1);
    linea_chan_close(endpoint);
}

static void signal_policy_applies_on_fibers(void) {
    void (*previous)(int) = signal(SIGUSR1, SIG_IGN);
    assert(previous != SIG_ERR);
    const long loop = linea_loop_open(1);
    assert(loop > 0);
    const long prepared = linea_task_prepare_on(stack_bytes, (unsigned long)loop);
    assert(prepared > 0);
    linea_chan_close(linea_task_start((unsigned long)prepared, signal_is_ignored, release_body, 0, 0, 0));
    assert(signal(SIGUSR1, previous) != SIG_ERR);
}

static void zero_poll_and_waitset(unsigned long endpoint, unsigned long at, unsigned long len) {
    assert(at == 0 && len == 0);
    long prepared = linea_task_prepare_on(stack_bytes, linea_io_current());
    assert(prepared > 0);
    unsigned long handle = linea_task_start((unsigned long)prepared, child, release_body, 0, 0, 0);
    unsigned long answer = 0;
    assert(linea_chan_recv_until(handle, (unsigned long)&answer, sizeof answer, 0) == 1);
    assert(answer == 42);
    linea_chan_close(handle);

    prepared = linea_task_prepare_on(stack_bytes, linea_io_current());
    assert(prepared > 0);
    handle = linea_task_start((unsigned long)prepared, write_one, release_body, 0, 0, 0);
    const unsigned long set = linea_waitset_open();
    assert(set != 0);
    const unsigned long key = linea_waitset_reserve(set);
    const unsigned long slot = key >> 32;
    assert(linea_waitset_descriptor(set, slot, sockets[0], 0) == 0);
    assert(linea_waitset_next(set) == (long)slot);
    linea_waitset_close(set);
    unsigned char byte = 0;
    assert(linea_net_read(sockets[0], (unsigned long)&byte, 1, 0) == 1 && byte == 77);
    linea_chan_close(handle);

    byte = 99;
    assert(linea_net_read(sockets[0], (unsigned long)&byte, 1, linea_park_deadline_after(1000000UL)) == -ETIMEDOUT);
    assert(byte == 99);
    /* Repeated timeout/disarm/rearm cycles reuse registration slots while
     * every expired input frame remains unmodified. */
    for (unsigned i = 0; i < 64; i += 1) {
        assert(linea_net_read(sockets[0], (unsigned long)&byte, 1, linea_park_deadline_after(100000UL)) == -ETIMEDOUT);
        assert(byte == 99);
    }
    linea_chan_close(endpoint);
}

static void set_peer_flag(unsigned long endpoint, unsigned long at, unsigned long len) {
    assert(at == 0 && len == 0);
    peer_ran = 1;
    linea_chan_close(endpoint);
}

static void sleep_releases_carrier(unsigned long endpoint, unsigned long at, unsigned long len) {
    assert(at == 0 && len == 0);
    const long prepared = linea_task_prepare_on(stack_bytes, linea_io_current());
    assert(prepared > 0);
    const unsigned long handle = linea_task_start((unsigned long)prepared, set_peer_flag, release_body, 0, 0, 0);
    assert(linea_clock_sleep(1000000UL) == 0);
    assert(peer_ran == 1);
    linea_chan_close(handle);
    linea_chan_close(endpoint);
}

static void descriptor_timer_and_poll_progress(void) {
    assert(socketpair(AF_UNIX, SOCK_STREAM, 0, sockets) == 0);
    assert(fcntl(sockets[0], F_SETFL, O_NONBLOCK) == 0);
    assert(fcntl(sockets[1], F_SETFL, O_NONBLOCK) == 0);
    const long loop = linea_loop_open(1);
    assert(loop > 0);
    long prepared = linea_task_prepare_on(stack_bytes, (unsigned long)loop);
    assert(prepared > 0);
    linea_chan_close(linea_task_start((unsigned long)prepared, zero_poll_and_waitset, release_body, 0, 0, 0));
    assert(close(sockets[0]) == 0 && close(sockets[1]) == 0);
    prepared = linea_task_prepare_on(stack_bytes, (unsigned long)loop);
    assert(prepared > 0);
    linea_chan_close(linea_task_start((unsigned long)prepared, sleep_releases_carrier, release_body, 0, 0, 0));
}

static void hot_reads_keep_the_carrier(unsigned long endpoint, unsigned long at, unsigned long len) {
    assert(at == 0 && len == 0);
    peer_ran = 0;
    const long prepared = linea_task_prepare_on(stack_bytes, linea_io_current());
    assert(prepared > 0);
    const unsigned long peer = linea_task_start((unsigned long)prepared, set_peer_flag, release_body, 0, 0, 0);
    unsigned char byte = 0;
    for (unsigned i = 0; i < 8; i += 1) {
        assert(linea_net_read(sockets[0], (unsigned long)&byte, 1, 0) == 1);
        assert(byte == i && peer_ran == 0);
    }
    linea_chan_close(peer);
    assert(peer_ran == 1);
    linea_chan_close(endpoint);
}

static void descriptors_move_between_execution_contexts(void) {
    assert(socketpair(AF_UNIX, SOCK_STREAM, 0, sockets) == 0);
    assert(fcntl(sockets[0], F_SETFL, O_NONBLOCK) == 0);
    assert(fcntl(sockets[1], F_SETFL, O_NONBLOCK) == 0);
    for (unsigned carriers = 1; carriers <= 2; carriers += 1) {
        const long loop = linea_loop_open(carriers);
        assert(loop > 0);
        const long prepared = linea_task_prepare_on(stack_bytes, (unsigned long)loop);
        assert(prepared > 0);
        linea_chan_close(linea_task_start((unsigned long)prepared, read_one, release_body, 0, 0, 0));
    }
    /* Both carrier registrations have retired before the descriptor returns
     * to the system thread and then to another single-carrier loop. */
    const unsigned char bytes[8] = {0, 1, 2, 3, 4, 5, 6, 7};
    assert(linea_net_write(sockets[1], (unsigned long)bytes, sizeof bytes, 0) == sizeof bytes);
    const long loop = linea_loop_open(1);
    assert(loop > 0);
    const long prepared = linea_task_prepare_on(stack_bytes, (unsigned long)loop);
    assert(prepared > 0);
    linea_chan_close(linea_task_start((unsigned long)prepared, hot_reads_keep_the_carrier, release_body, 0, 0, 0));
    const unsigned char last = 19;
    assert(linea_net_write(sockets[1], (unsigned long)&last, 1, 0) == 1);
    unsigned char read = 0;
    assert(linea_net_read(sockets[0], (unsigned long)&read, 1, 0) == 1 && read == last);
    assert(close(sockets[0]) == 0 && close(sockets[1]) == 0);
}

/* Two output views of one connection may each have an operation waiting on
 * the same carrier. Completing one must not replace the other's watch. */
static void blocked_writer(unsigned long endpoint, unsigned long at, unsigned long len) {
    assert(at == 0 && len == 0);
    const unsigned char byte = 23;
    assert(linea_net_write(sockets[0], (unsigned long)&byte, 1, 0) == 1);
    linea_chan_close(endpoint);
}

static void simultaneous_writes_keep_both_waiters(void) {
    assert(socketpair(AF_UNIX, SOCK_STREAM, 0, sockets) == 0);
    assert(fcntl(sockets[0], F_SETFL, O_NONBLOCK) == 0);
    assert(fcntl(sockets[1], F_SETFL, O_NONBLOCK) == 0);
    unsigned char bytes[8192] = {0};
    while (write(sockets[0], bytes, sizeof bytes) > 0) {}
    assert(errno == EAGAIN || errno == EWOULDBLOCK);
    const long loop = linea_loop_open(1);
    assert(loop > 0);
    unsigned long writers[2];
    for (unsigned i = 0; i < 2; i += 1) {
        const long prepared = linea_task_prepare_on(stack_bytes, (unsigned long)loop);
        assert(prepared > 0);
        writers[i] = linea_task_start((unsigned long)prepared, blocked_writer, release_body, 0, 0, 0);
    }
    /* The FIFO carrier reaches this task only after both writers have
     * submitted their blocked operations. No timing pause is needed. */
    const long sentinel = linea_task_prepare_on(stack_bytes, (unsigned long)loop);
    assert(sentinel > 0);
    linea_chan_close(linea_task_start((unsigned long)sentinel, set_peer_flag, release_body, 0, 0, 0));
    while (read(sockets[1], bytes, sizeof bytes) > 0) {}
    assert(errno == EAGAIN || errno == EWOULDBLOCK);
    for (unsigned i = 0; i < 2; i += 1) linea_chan_close(writers[i]);
    assert(close(sockets[0]) == 0 && close(sockets[1]) == 0);
}

int main(void) {
    (void)alarm(30);
    assert(linea_loop_open(0) == -EINVAL);
    sessions_progress_on(1);
    sessions_progress_on(2);
    assert(released == 4);
    a_socket_read_releases_its_carrier();
    assert(released == 6);
    signal_policy_applies_on_fibers();
    descriptor_timer_and_poll_progress();
    assert(released == 12);
    descriptors_move_between_execution_contexts();
    assert(released == 18);
    simultaneous_writes_keep_both_waiters();
    assert(released == 21);
    (void)alarm(0);
    puts("native fibers: same-carrier sessions, cross-carrier wakes, joins and cancelled preparations passed");
    return 0;
}
