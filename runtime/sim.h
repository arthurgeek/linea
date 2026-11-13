#ifndef LINEA_SIM_H
#define LINEA_SIM_H

#include "loop.h"
#include "op.h"

#include <stdint.h>

/* 2^30: Linux hands a process descriptors below fs.nr_open, 2^20 unless an
 * administrator raises it, and macOS below kern.maxfilesperproc. */
#define LINEA_SIM_FIRST_DESCRIPTOR 0x40000000

/* A simulation: a virtual monotonic and wall clock, an in-memory network and
 * a source of choices seeded by the program. While a thread runs a
 * simulation (`linea_io_switch` made it the thread's loop), its clock reads
 * and sleeps and its socket operations are answered here, and no system call
 * is made for them. Virtual time moves only when the program advances it or
 * when all its tasks are parked, which jumps it to the next event: a
 * delivery, a handshake, or a wait's deadline. Tasks share one carrier on
 * the calling thread, and runnable fibers are selected from the seed.
 *
 * A simulated descriptor is an entry of a table the runtime keeps for every
 * simulation, numbered from `LINEA_SIM_FIRST_DESCRIPTOR`. Its number is
 * positive, as every descriptor an operation answers is, and the in-place
 * backend refuses a real descriptor numbered that high, so no real
 * descriptor shares it. An entry knows its simulation until that simulation
 * ends, so an operation on it from any other loop traps. Releasing it outside
 * a run marks it, and the simulation's next operation closes it; releasing it
 * on another thread while a run is in progress traps; releasing it after the
 * simulation ended forgets the entry. A real socket used while a simulation runs traps too,
 * since it would wait on the kernel against a virtual clock.
 *
 * Every entry and every simulation is guarded by one lock, held across each
 * nonblocking attempt, with the lock released before a fiber switches, so
 * a descriptor released on another thread never meets an operation in progress. */

/* Open a simulation and answer its identity, or 0 when it cannot be
 * allocated or no loop slot is free. Latencies are nanoseconds. Each chunk of
 * a write arrives `latency_ns` plus a chosen 0 to `jitter_ns` later, in
 * order; `chunk_bytes`, when not 0, cuts each write into chunks of 1 to that
 * many bytes; `buffer_bytes` bounds what each direction holds in flight and
 * unread (0 is taken as 1); `short_writes`, when not 0, lets a write accept a
 * chosen prefix of what fits; `reset_one_in`, when not 0, resets a
 * connection in place of delivering a chunk once in that many chunks. */
unsigned long linea_sim_open(unsigned long seed, unsigned long latency_ns, unsigned long jitter_ns,
                             unsigned long chunk_bytes, unsigned long buffer_bytes, uint8_t short_writes,
                             unsigned long reset_one_in);
/* Move the simulation's clock `nanoseconds` forward, delivering what
 * arrives meanwhile. */
void linea_sim_advance(unsigned long identity, unsigned long nanoseconds);
/* A digest of every event the simulation has run, in order: two
 * simulations opened alike that run one program report the same. */
unsigned long linea_sim_fingerprint(unsigned long identity);
/* End the simulation: free its network, mark its descriptors as outside
 * every simulation, and retire its loop identity. */
void linea_sim_close(unsigned long identity);

/* Whether the calling thread runs a simulation. */
static inline int linea_sim_running(void) {
    return linea_io_is_simulated(linea_io_current()) != 0;
}

/* Whether the simulation answers an operation on `fd`. It traps for a
 * simulated descriptor outside its simulation, and for a real descriptor
 * while a simulation runs. */
int linea_sim_takes(int fd);
/* Whether `fd` is a simulated descriptor's number. */
static inline int linea_sim_descriptor(int fd) {
    return fd >= LINEA_SIM_FIRST_DESCRIPTOR;
}

/* The simulated backend: perform `op` against the running simulation. A
 * connect makes the client's descriptor, an accept answers the server's. */
long linea_sim_perform(struct linea_op *op);
long linea_sim_listen(unsigned long address, unsigned long backlog);
long linea_sim_local_address(int fd);
long linea_sim_peer_address(int fd);
long linea_sim_shutdown_write(int fd);
long linea_sim_reset(int fd);
/* Close a simulated descriptor: inside a run of its simulation as a socket
 * closes, outside one at the simulation's next operation, and after the
 * simulation ended by forgetting its entry. */
long linea_sim_release(int fd);
/* Read the running simulation's clock, as `linea_clock_read` does. */
long linea_sim_clock_read(uint8_t clock, long *seconds, unsigned long *nanoseconds);
/* The running simulation's monotonic clock, in nanoseconds. */
unsigned long linea_sim_now(void);
/* Whether the simulated descriptor `fd` is ready: readable, or writable when
 * `writable` is 1. */
int linea_sim_ready(int fd, uint8_t writable);
/* The earliest instant after now at which the network changes, 0 for none. */
unsigned long linea_sim_next_event(void);
/* Move the running simulation's clock to `instant`, delivering what arrives
 * by then, for a wait set waiting on it. */
void linea_sim_jump(unsigned long instant);
/* Wait `nanoseconds` on the running simulation's clock. */
long linea_sim_sleep(unsigned long nanoseconds);

void *linea_sim_carrier(unsigned long identity);
unsigned long linea_sim_choice(unsigned long bound);
long linea_sim_attempt(struct linea_op *operation);

#endif
