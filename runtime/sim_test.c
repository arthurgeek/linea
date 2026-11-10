#define _GNU_SOURCE
/* Assertions execute test setup, checks, and cleanup in every build mode. */
#undef NDEBUG
#include "clock.h"
#include "io.h"
#include "loop.h"
#include "net.h"
#include "sim.h"
#include "task.h"

#include <assert.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#define ADDRESS(p) ((unsigned long)(uintptr_t)(p))

static const unsigned long ms = 1000000UL;

static unsigned long loopback(unsigned port) { return (0x7f000001UL << 16) | port; }

/* A simulation with a fixed latency and none of the seed's faults. */
static unsigned long plain(unsigned long latency) {
    const unsigned long identity = linea_sim_open(7, latency, 0, 0, 65536, 0, 0);
    assert(identity != 0);
    return identity;
}

static unsigned long virtual_now(void) {
    long seconds;
    unsigned long nanoseconds;
    assert(linea_clock_read(LINEA_CLOCK_MONOTONIC, &seconds, &nanoseconds) == 0);
    return (unsigned long)seconds * 1000000000UL + nanoseconds;
}

static unsigned long real_now(void) {
    struct timespec now;
    assert(clock_gettime(CLOCK_MONOTONIC, &now) == 0);
    return (unsigned long)now.tv_sec * 1000000000UL + (unsigned long)now.tv_nsec;
}

/* Runs `body` in a child and checks that it aborted with standard error
 * beginning with `message`. */
static void traps_with(void (*body)(void), const char *message) {
    int pipe_ends[2];
    assert(pipe(pipe_ends) == 0);
    const pid_t pid = fork();
    assert(pid >= 0);
    if (pid == 0) {
        dup2(pipe_ends[1], 2);
        close(pipe_ends[0]);
        body();
        _exit(0);
    }
    close(pipe_ends[1]);
    char said[512];
    size_t len = 0;
    ssize_t got;
    while ((got = read(pipe_ends[0], said + len, sizeof said - 1 - len)) > 0) len += (size_t)got;
    said[len] = '\0';
    close(pipe_ends[0]);
    int status = 0;
    assert(waitpid(pid, &status, 0) == pid);
    assert(WIFSIGNALED(status) && WTERMSIG(status) == SIGABRT);
    assert(strncmp(said, message, strlen(message)) == 0);
}

/* A listener, a connected client and the connection accepted for it, in the
 * running simulation. */
struct pair { long listener, client, server; };

static struct pair connected_pair(void) {
    struct pair p;
    p.listener = linea_net_listen(loopback(80), 4);
    assert(p.listener >= LINEA_SIM_FIRST_DESCRIPTOR);
    p.client = linea_net_connect(loopback(80), 0);
    assert(p.client >= LINEA_SIM_FIRST_DESCRIPTOR);
    p.server = linea_net_accept((int)p.listener, 0);
    assert(p.server >= LINEA_SIM_FIRST_DESCRIPTOR);
    return p;
}

static void close_pair(struct pair p) {
    assert(linea_net_close((int)p.client) == 0);
    assert(linea_net_close((int)p.server) == 0);
    assert(linea_net_close((int)p.listener) == 0);
}

/* An identity names its loop until the loop ends; a later loop in the same
 * slot gets another generation, so the old identity never names it. */
static void a_slot_reused_after_its_loop_ends_has_a_new_identity(void) {
    int first_state = 1, second_state = 2;
    const unsigned long first = linea_loop_claim(&first_state);
    assert(first != 0 && linea_loop_find(first) == &first_state);
    linea_loop_retire(first);
    const unsigned long second = linea_loop_claim(&second_state);
    assert(second >> 32 == first >> 32);
    assert((uint32_t)second == (uint32_t)first + 1);
    assert(linea_loop_find(second) == &second_state);
    linea_loop_retire(second);
}

static unsigned long ended;

static void find_the_ended_loop(void) { (void)linea_loop_find(ended); }

static void ask_about_the_ended_loop(void) { (void)linea_io_is_simulated(ended); }

static void switch_to_the_ended_loop(void) { (void)linea_io_switch(ended); }

static void an_identity_of_an_ended_loop_traps(void) {
    int state = 0;
    ended = linea_loop_claim(&state);
    linea_loop_retire(ended);
    traps_with(find_the_ended_loop, "linea: an Io names a loop that has ended\n");
    traps_with(ask_about_the_ended_loop, "linea: an Io names a loop that has ended\n");
    traps_with(switch_to_the_ended_loop, "linea: an Io names a loop that has ended\n");
}

/* The system is identity 0; a running simulation is the thread's Io until
 * the switch back. */
static void running_a_simulation_makes_it_the_current_io(void) {
    assert(linea_io_current() == 0 && !linea_sim_running());
    assert(linea_io_is_simulated(0) == 0);
    const unsigned long sim = plain(ms);
    assert(linea_io_is_simulated(sim) == 1);
    assert(linea_io_switch(sim) == 0);
    assert(linea_io_current() == sim && linea_sim_running());
    assert(linea_io_switch(0) == sim);
    assert(linea_io_current() == 0);
    linea_sim_close(sim);
}

/* The virtual clocks start at fixed instants and move only when the
 * simulation is advanced or its task sleeps; neither waits in real time. */
static void virtual_time_moves_only_when_advanced_and_never_sleeps(void) {
    const unsigned long sim = plain(ms);
    (void)linea_io_switch(sim);
    long wall_seconds;
    unsigned long wall_nanoseconds;
    assert(linea_clock_read(LINEA_CLOCK_WALL, &wall_seconds, &wall_nanoseconds) == 0);
    assert(wall_seconds == 1767225600L && wall_nanoseconds == 0);
    const unsigned long start = virtual_now();
    assert(start == 1000000000UL);
    assert(virtual_now() == start);
    const unsigned long real_start = real_now();
    assert(linea_clock_sleep(3600UL * 1000000000UL) == 0);
    assert(virtual_now() == start + 3600UL * 1000000000UL);
    linea_sim_advance(sim, 5 * ms);
    assert(virtual_now() == start + 3600UL * 1000000000UL + 5 * ms);
    assert(real_now() - real_start < 1000000000UL);
    (void)linea_io_switch(0);
    linea_sim_close(sim);
}

/* §1's tie rules, with readiness and expiry at one virtual instant: progress
 * observed at the deadline answers it; a deadline one nanosecond earlier
 * times out. */
static void a_read_whose_bytes_arrive_at_its_deadline_reads_them(void) {
    const unsigned long sim = plain(200 * ms);
    (void)linea_io_switch(sim);
    struct pair p = connected_pair();
    char bytes[8] = "x";
    assert(linea_net_write((int)p.client, ADDRESS(bytes), 1, 0) == 1);
    const unsigned long arrival = virtual_now() + 200 * ms;
    char got[8];
    assert(linea_net_read((int)p.server, ADDRESS(got), 8, arrival - 1) == -(long)ETIMEDOUT);
    assert(virtual_now() == arrival - 1);
    assert(linea_net_read((int)p.server, ADDRESS(got), 8, arrival) == 1 && got[0] == 'x');
    assert(virtual_now() == arrival);
    close_pair(p);
    (void)linea_io_switch(0);
    linea_sim_close(sim);
}

/* The client is connected after two deliveries, SYN and SYN-ACK, and the
 * server's end is ready to accept after a third, the ACK. */
static void an_accept_whose_handshake_completes_at_its_deadline_accepts(void) {
    const unsigned long sim = plain(10 * ms);
    (void)linea_io_switch(sim);
    const long listener = linea_net_listen(loopback(80), 4);
    const unsigned long start = virtual_now();
    const long client = linea_net_connect(loopback(80), 0);
    assert(client >= LINEA_SIM_FIRST_DESCRIPTOR && virtual_now() == start + 20 * ms);
    const unsigned long ready = start + 30 * ms;
    assert(linea_net_accept((int)listener, ready - 1) == -(long)ETIMEDOUT);
    assert(virtual_now() == ready - 1);
    const long served = linea_net_accept((int)listener, ready);
    assert(served >= LINEA_SIM_FIRST_DESCRIPTOR && virtual_now() == ready);
    assert(linea_net_close((int)served) == 0);
    assert(linea_net_close((int)client) == 0);
    assert(linea_net_close((int)listener) == 0);
    (void)linea_io_switch(0);
    linea_sim_close(sim);
}

/* A connect whose handshake completes at its deadline is connected; one
 * whose deadline comes a nanosecond earlier times out, and the handshake it
 * started leaves nothing in the listener's queue. */
static void a_connect_whose_handshake_completes_at_its_deadline_connects(void) {
    const unsigned long sim = plain(15 * ms);
    (void)linea_io_switch(sim);
    const long listener = linea_net_listen(loopback(80), 4);
    assert(linea_net_connect(loopback(80), virtual_now() + 30 * ms - 1) == -(long)ETIMEDOUT);
    assert(linea_net_accept((int)listener, virtual_now() + 100 * ms) == -(long)ETIMEDOUT);
    const unsigned long deadline = virtual_now() + 30 * ms;
    const long client = linea_net_connect(loopback(80), deadline);
    assert(client >= LINEA_SIM_FIRST_DESCRIPTOR && virtual_now() == deadline);
    const long served = linea_net_accept((int)listener, 0);
    assert(served >= LINEA_SIM_FIRST_DESCRIPTOR);
    assert(linea_net_close((int)served) == 0);
    assert(linea_net_close((int)client) == 0);
    assert(linea_net_close((int)listener) == 0);
    (void)linea_io_switch(0);
    linea_sim_close(sim);
}

/* A write that finds the peer's share of the network full waits, and with
 * the peer never reading, ends at its deadline. */
static void a_write_to_a_peer_that_reads_nothing_times_out(void) {
    const unsigned long sim = linea_sim_open(7, ms, 0, 0, 16, 0, 0);
    (void)linea_io_switch(sim);
    struct pair p = connected_pair();
    char bytes[32];
    memset(bytes, 'y', sizeof bytes);
    assert(linea_net_write((int)p.client, ADDRESS(bytes), 32, 0) == 16);
    const unsigned long deadline = virtual_now() + 75 * ms;
    assert(linea_net_write((int)p.client, ADDRESS(bytes), 32, deadline) == -(long)ETIMEDOUT);
    assert(virtual_now() == deadline);
    close_pair(p);
    (void)linea_io_switch(0);
    linea_sim_close(sim);
}

/* A deadline already past answers before anything is consumed. */
static void a_deadline_already_past_consumes_nothing(void) {
    const unsigned long sim = plain(ms);
    (void)linea_io_switch(sim);
    struct pair p = connected_pair();
    char bytes[4] = "abc";
    assert(linea_net_write((int)p.client, ADDRESS(bytes), 3, 0) == 3);
    linea_sim_advance(sim, 5 * ms);
    char got[4];
    assert(linea_net_read((int)p.server, ADDRESS(got), 4, virtual_now()) == -(long)ETIMEDOUT);
    assert(linea_net_read((int)p.server, ADDRESS(got), 4, 0) == 3);
    close_pair(p);
    (void)linea_io_switch(0);
    linea_sim_close(sim);
}

/* Chunks of one byte make reads short; a half-close then ends the
 * input, while the other direction still carries bytes. */
static void chunks_make_short_reads_and_a_half_close_ends_input(void) {
    const unsigned long sim = linea_sim_open(3, ms, 4 * ms, 1, 65536, 0, 0);
    (void)linea_io_switch(sim);
    struct pair p = connected_pair();
    char bytes[6] = "hello";
    assert(linea_net_write((int)p.client, ADDRESS(bytes), 5, 0) == 5);
    assert(linea_net_shutdown_write((int)p.client) == 0);
    char got[8];
    size_t total = 0;
    int reads = 0;
    long count;
    while ((count = linea_net_read((int)p.server, ADDRESS(got) + total, 8 - total, 0)) > 0) {
        reads += 1;
        total += (size_t)count;
    }
    assert(count == 0 && total == 5 && memcmp(got, "hello", 5) == 0);
    /* One-byte chunks with jitter reach the reader at several instants. */
    assert(reads > 1);
    assert(linea_net_write((int)p.server, ADDRESS(bytes), 2, 0) == 2);
    assert(linea_net_read((int)p.client, ADDRESS(got), 8, 0) >= 1);
    close_pair(p);
    (void)linea_io_switch(0);
    linea_sim_close(sim);
}

/* Short writes accept a prefix; a reset chosen for every chunk reaches the
 * reader as a reset. */
static void short_writes_and_chosen_resets_reach_the_program(void) {
    unsigned long sim = linea_sim_open(11, ms, 0, 0, 65536, 1, 0);
    (void)linea_io_switch(sim);
    struct pair p = connected_pair();
    char bytes[64];
    memset(bytes, 'z', sizeof bytes);
    int short_seen = 0;
    for (int i = 0; i < 16; i++) {
        const long sent = linea_net_write((int)p.client, ADDRESS(bytes), 64, 0);
        assert(sent >= 1 && sent <= 64);
        if (sent < 64) short_seen = 1;
    }
    assert(short_seen);
    close_pair(p);
    (void)linea_io_switch(0);
    linea_sim_close(sim);

    sim = linea_sim_open(11, ms, 0, 0, 65536, 0, 1);
    (void)linea_io_switch(sim);
    p = connected_pair();
    assert(linea_net_write((int)p.client, ADDRESS(bytes), 8, 0) == 8);
    char got[8];
    assert(linea_net_read((int)p.server, ADDRESS(got), 8, 0) == -(long)ECONNRESET);
    assert(linea_net_peer_address((int)p.server) == -(long)ECONNRESET);
    close_pair(p);
    (void)linea_io_switch(0);
    linea_sim_close(sim);
}

/* A connection to a port no listener holds is refused, and a second
 * listener on a port is refused as in use. Closing a connection with bytes
 * it never read resets its peer. */
static void refusals_and_resets_follow_the_kernels(void) {
    const unsigned long sim = plain(ms);
    (void)linea_io_switch(sim);
    assert(linea_net_connect(loopback(81), 0) == -(long)ECONNREFUSED);
    struct pair p = connected_pair();
    assert(linea_net_listen(loopback(80), 4) == -(long)EADDRINUSE);
    const long any = linea_net_listen(loopback(0), 4);
    assert(any >= LINEA_SIM_FIRST_DESCRIPTOR);
    assert((linea_net_local_address((int)any) & 0xffff) >= 49152);
    assert(linea_net_close((int)any) == 0);
    char bytes[4] = "abc";
    assert(linea_net_write((int)p.client, ADDRESS(bytes), 3, 0) == 3);
    linea_sim_advance(sim, 5 * ms);
    assert(linea_net_close((int)p.server) == 0);
    char got[4];
    assert(linea_net_read((int)p.client, ADDRESS(got), 4, 0) == -(long)ECONNRESET);
    assert(linea_net_close((int)p.client) == 0);
    assert(linea_net_close((int)p.listener) == 0);
    (void)linea_io_switch(0);
    linea_sim_close(sim);
}

/* Two simulations opened with one seed that run one program report one
 * fingerprint; another seed chooses other latencies. */
static unsigned long run_exchange(unsigned long seed) {
    const unsigned long sim = linea_sim_open(seed, ms, 20 * ms, 3, 65536, 1, 0);
    (void)linea_io_switch(sim);
    struct pair p = connected_pair();
    char bytes[32];
    memset(bytes, 'q', sizeof bytes);
    size_t sent = 0;
    while (sent < sizeof bytes) {
        const long count = linea_net_write((int)p.client, ADDRESS(bytes) + sent, sizeof bytes - sent, 0);
        assert(count > 0);
        sent += (size_t)count;
    }
    char got[32];
    size_t received = 0;
    while (received < sizeof got) {
        const long count = linea_net_read((int)p.server, ADDRESS(got) + received, sizeof got - received, 0);
        assert(count > 0);
        received += (size_t)count;
    }
    close_pair(p);
    (void)linea_io_switch(0);
    const unsigned long fingerprint = linea_sim_fingerprint(sim);
    linea_sim_close(sim);
    return fingerprint;
}

static void one_seed_gives_one_trace(void) {
    const unsigned long first = run_exchange(42);
    /* A descriptor of another simulation, held across the second run,
     * changes the numbers descriptors get but not the trace. */
    const unsigned long other = plain(ms);
    (void)linea_io_switch(other);
    const long held = linea_net_listen(loopback(80), 4);
    (void)linea_io_switch(0);
    assert(run_exchange(42) == first);
    assert(run_exchange(43) != first);
    (void)linea_io_switch(other);
    assert(linea_net_close((int)held) == 0);
    (void)linea_io_switch(0);
    linea_sim_close(other);
}

static long escaped;

static void write_to_the_escaped_descriptor(void) {
    char bytes[1] = { 'e' };
    (void)linea_net_write((int)escaped, ADDRESS(bytes), 1, 0);
}

static void accept_on_a_real_listener_inside(void) {
    const long real = linea_net_listen(loopback(0), 4);
    assert(real >= 0 && real < LINEA_SIM_FIRST_DESCRIPTOR);
    (void)linea_io_switch(plain(ms));
    (void)linea_net_accept((int)real, 0);
}

static void start_a_task_inside(void) {
    const long task = linea_task_prepare(1UL << 16);
    assert(task > 0);
    (void)linea_io_switch(plain(ms));
    (void)linea_task_start((unsigned long)task, NULL, NULL, 0, 0, 0);
}

static void read_with_nothing_on_the_way(void) {
    (void)linea_io_switch(plain(ms));
    struct pair p = connected_pair();
    char got[1];
    (void)linea_net_read((int)p.server, ADDRESS(got), 1, 0);
}

/* A simulated descriptor names nothing outside its simulation, so using it
 * there traps, while releasing it forgets it. A real socket used inside
 * traps; so does a second task, and a wait for what can never arrive. */
static void each_side_traps_on_the_others_descriptors(void) {
    const unsigned long sim = plain(ms);
    (void)linea_io_switch(sim);
    struct pair p = connected_pair();
    (void)linea_io_switch(0);
    escaped = p.client;
    traps_with(write_to_the_escaped_descriptor, "linea: a simulated descriptor was used outside its simulation\n");
    linea_sim_close(sim);
    traps_with(write_to_the_escaped_descriptor, "linea: a simulated descriptor was used outside its simulation\n");
    assert(linea_net_close((int)p.client) == 0);
    assert(linea_net_close((int)p.server) == 0);
    assert(linea_net_close((int)p.listener) == 0);
    traps_with(accept_on_a_real_listener_inside, "linea: a real socket was used inside a simulation\n");
    traps_with(start_a_task_inside, "linea: a simulation runs one task until fibers\n");
    traps_with(read_with_nothing_on_the_way, "linea: a simulation's one task waits forever\n");
}

/* The fingerprint digests the bytes delivered, not only how many. */
static unsigned long fingerprint_of_sending(const char *text) {
    const unsigned long sim = plain(ms);
    (void)linea_io_switch(sim);
    struct pair p = connected_pair();
    assert(linea_net_write((int)p.client, ADDRESS(text), 3, 0) == 3);
    char got[3];
    assert(linea_net_read((int)p.server, ADDRESS(got), 3, 0) == 3);
    close_pair(p);
    (void)linea_io_switch(0);
    const unsigned long fingerprint = linea_sim_fingerprint(sim);
    linea_sim_close(sim);
    return fingerprint;
}

static void different_bytes_of_one_length_give_different_fingerprints(void) {
    assert(fingerprint_of_sending("abc") == fingerprint_of_sending("abc"));
    assert(fingerprint_of_sending("abc") != fingerprint_of_sending("abd"));
}

/* Closing a simulated descriptor outside a run of its open simulation only
 * forgets its number: the peer, in a later run, hears neither an end nor a
 * reset, so the run does not depend on when the number was let go. */
static void a_descriptor_closed_between_runs_is_only_forgotten(void) {
    const unsigned long sim = plain(ms);
    (void)linea_io_switch(sim);
    struct pair p = connected_pair();
    (void)linea_io_switch(0);
    assert(linea_net_close((int)p.client) == 0);
    (void)linea_io_switch(sim);
    char bytes[2] = { 'o', 'k' };
    assert(linea_net_write((int)p.server, ADDRESS(bytes), 2, 0) == 2);
    char got[2];
    assert(linea_net_read((int)p.server, ADDRESS(got), 2, virtual_now() + 50 * ms) == -(long)ETIMEDOUT);
    assert(linea_net_write((int)p.server, ADDRESS(bytes), 2, 0) == 2);
    assert(linea_net_close((int)p.server) == 0);
    assert(linea_net_close((int)p.listener) == 0);
    (void)linea_io_switch(0);
    linea_sim_close(sim);
}

static unsigned long other_world;

static void receive_from_a_task_inside(void) {
    const long task = linea_task_prepare(1UL << 16);
    assert(task > 0);
    (void)linea_io_switch(plain(ms));
    unsigned long word = 0;
    linea_chan_recv((unsigned long)task, ADDRESS(&word), sizeof word);
}

static void advance_another_simulation_inside(void) {
    other_world = plain(ms);
    (void)linea_io_switch(plain(ms));
    linea_sim_advance(other_world, ms);
}

/* A run waits on no other task, and its world moves only its own clock. */
static void a_session_wait_and_a_foreign_world_trap_inside(void) {
    traps_with(receive_from_a_task_inside, "linea: a simulation runs one task until fibers\n");
    traps_with(advance_another_simulation_inside, "linea: a simulation's world was used outside its run\n");
}

/* A real socket may be closed inside a simulation, since closing waits on
 * nothing. */
static void a_real_socket_closes_inside_a_simulation(void) {
    const long real = linea_net_listen(loopback(0), 4);
    assert(real >= 0);
    const unsigned long sim = plain(ms);
    (void)linea_io_switch(sim);
    assert(linea_net_close((int)real) == 0);
    (void)linea_io_switch(0);
    linea_sim_close(sim);
}

int main(void) {
    a_slot_reused_after_its_loop_ends_has_a_new_identity();
    an_identity_of_an_ended_loop_traps();
    running_a_simulation_makes_it_the_current_io();
    virtual_time_moves_only_when_advanced_and_never_sleeps();
    a_read_whose_bytes_arrive_at_its_deadline_reads_them();
    an_accept_whose_handshake_completes_at_its_deadline_accepts();
    a_connect_whose_handshake_completes_at_its_deadline_connects();
    a_write_to_a_peer_that_reads_nothing_times_out();
    a_deadline_already_past_consumes_nothing();
    chunks_make_short_reads_and_a_half_close_ends_input();
    short_writes_and_chosen_resets_reach_the_program();
    refusals_and_resets_follow_the_kernels();
    one_seed_gives_one_trace();
    each_side_traps_on_the_others_descriptors();
    a_real_socket_closes_inside_a_simulation();
    different_bytes_of_one_length_give_different_fingerprints();
    a_descriptor_closed_between_runs_is_only_forgotten();
    a_session_wait_and_a_foreign_world_trap_inside();
    puts("native sim: loop identities, virtual clocks, tie rules, deadlines, chunks, resets, seeds, forgetting and traps passed");
    return 0;
}
