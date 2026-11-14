#define _GNU_SOURCE
/* Assertions execute test setup, checks, and cleanup in every build mode. */
#undef NDEBUG
#include "clock.h"
#include "io.h"
#include "net.h"
#include "sim.h"

#include <assert.h>
#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

#define ADDRESS(p) ((unsigned long)(uintptr_t)(p))

static const unsigned long ms = 1000000UL;

/* The simulation's next `refusals` allocations fail, as an allocator out of
 * memory fails them; every one after that succeeds. */
static int refusals = 0;

void *linea_test_malloc(size_t size) {
    if (refusals > 0) {
        refusals -= 1;
        return NULL;
    }
    return malloc(size);
}

static unsigned long loopback(unsigned port) { return (0x7f000001UL << 16) | port; }

static unsigned long virtual_now(void) {
    long seconds;
    unsigned long nanoseconds;
    assert(linea_clock_read(LINEA_CLOCK_MONOTONIC, &seconds, &nanoseconds) == 0);
    return (unsigned long)seconds * 1000000000UL + nanoseconds;
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

/* A half-close that cannot allocate the end of input it sends has shut
 * nothing: asked again it sends the end, and the peer reads it. */
static void a_half_close_refused_for_memory_is_asked_again(void) {
    const unsigned long sim = linea_sim_open(7, ms, 0, 0, 65536, 0, 0);
    assert(sim != 0);
    (void)linea_io_switch(sim);
    struct pair p = connected_pair();
    refusals = 1;
    assert(linea_net_shutdown_write((int)p.client) == -(long)ENOMEM);
    assert(linea_net_shutdown_write((int)p.client) == 0);
    char got[2];
    assert(linea_net_read((int)p.server, ADDRESS(got), 2, virtual_now() + 10 * ms) == 0);
    assert(linea_net_close((int)p.client) == 0);
    assert(linea_net_close((int)p.server) == 0);
    assert(linea_net_close((int)p.listener) == 0);
    (void)linea_io_switch(0);
    linea_sim_close(sim);
}

/* Closing a connection whose half-close was refused still ends the peer's
 * input, since nothing was shut. */
static void a_close_after_a_refused_half_close_ends_the_peers_input(void) {
    const unsigned long sim = linea_sim_open(7, ms, 0, 0, 65536, 0, 0);
    assert(sim != 0);
    (void)linea_io_switch(sim);
    struct pair p = connected_pair();
    refusals = 1;
    assert(linea_net_shutdown_write((int)p.client) == -(long)ENOMEM);
    assert(linea_net_close((int)p.client) == 0);
    char got[2];
    assert(linea_net_read((int)p.server, ADDRESS(got), 2, virtual_now() + 10 * ms) == 0);
    assert(linea_net_close((int)p.server) == 0);
    assert(linea_net_close((int)p.listener) == 0);
    (void)linea_io_switch(0);
    linea_sim_close(sim);
}

/* A close that cannot allocate the end of input it sends resets its peer at
 * once: the peer's read answers and does not wait for an end that was never
 * sent. */
static void a_close_refused_for_memory_resets_the_peer(void) {
    const unsigned long sim = linea_sim_open(7, ms, 0, 0, 65536, 0, 0);
    assert(sim != 0);
    (void)linea_io_switch(sim);
    struct pair p = connected_pair();
    refusals = 1;
    assert(linea_net_close((int)p.client) == 0);
    char got[2];
    assert(linea_net_read((int)p.server, ADDRESS(got), 2, virtual_now() + 10 * ms) == -(long)ECONNRESET);
    assert(linea_net_close((int)p.server) == 0);
    assert(linea_net_close((int)p.listener) == 0);
    (void)linea_io_switch(0);
    linea_sim_close(sim);
}

/* A write to a peer that has closed sends the writer a reset. A write that
 * cannot allocate it has sent none: the next write sends it, and the writer
 * then reads the reset. */
static void a_write_to_a_closed_peer_refused_for_memory_is_asked_again(void) {
    const unsigned long sim = linea_sim_open(7, ms, 0, 0, 65536, 0, 0);
    assert(sim != 0);
    (void)linea_io_switch(sim);
    struct pair p = connected_pair();
    assert(linea_net_close((int)p.server) == 0);
    const char sent[2] = { 'o', 'k' };
    refusals = 1;
    assert(linea_net_write((int)p.client, ADDRESS(sent), 2, virtual_now() + 10 * ms) == -(long)ENOMEM);
    assert(linea_net_write((int)p.client, ADDRESS(sent), 2, virtual_now() + 10 * ms) == 2);
    char got[2];
    assert(linea_net_read((int)p.client, ADDRESS(got), 2, virtual_now() + 10 * ms) == -(long)ECONNRESET);
    assert(linea_net_close((int)p.client) == 0);
    assert(linea_net_close((int)p.listener) == 0);
    (void)linea_io_switch(0);
    linea_sim_close(sim);
}

int main(void) {
    a_half_close_refused_for_memory_is_asked_again();
    a_close_after_a_refused_half_close_ends_the_peers_input();
    a_close_refused_for_memory_resets_the_peer();
    a_write_to_a_closed_peer_refused_for_memory_is_asked_again();
    puts("native sim: an end or a reset refused for memory is sent when asked again, and a close resets its peer at once");
    return 0;
}
