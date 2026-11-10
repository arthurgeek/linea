#ifndef LINEA_WAITSET_H
#define LINEA_WAITSET_H

#include <stdint.h>

/* A wait set: one task waits in it for the first of several sources, and
 * keeps the ones that did not fire. The runtime keeps a registration per
 * source and decides which is ready; the values registered stay in bytes the
 * program owns, so a registration here is only a slot, a generation and a
 * state.
 *
 * A registration's state moves by compare-and-swap, each swap made by one
 * party: `registered` to `signalled` by its source (a session's peer, a
 * body's return, a descriptor event, a timer's expiry, a signal's count), and
 * `registered` or `signalled` to `taken` by the set's owner, through `next`,
 * `take` or `close`. A source that wins its swap then queues the
 * registration on the set and wakes it; a source that loses does nothing. A
 * registration taken is disarmed before its slot is released: an endpoint's
 * mark is cleared under its session's lock, a descriptor is removed from the
 * kernel queue, a signal's registration leaves the router, a timer leaves the
 * heap. Only then does the slot's generation move on, so a key kept past
 * that point, or an event the kernel still delivers, names an older
 * generation and is refused.
 *
 * Every set belongs to the loop it was opened on (`linea_io_current`), and
 * every operation on it from another loop traps. Inside a simulation a set
 * waits on the simulation's clock and descriptors and on signals the program
 * delivers with `world.deliver`; a session's endpoint or a task's handle
 * cannot be registered there, since a simulation runs one task.
 *
 * Lock order: a session's lock, then the signal router's, then a set's. */

/* A set's state, reached from the sources that signal it. */
struct linea_registration;

/* Open a set, owned by the calling thread's loop. It answers the set, or 0
 * when its record cannot be allocated. */
unsigned long linea_waitset_open(void);

/* The set's identity: a number no other set is ever given, which a key
 * names its set by. */
unsigned long linea_waitset_identity(unsigned long set);

/* Reserve a slot for a registration and answer its index in the high 32
 * bits and its generation in the low 32. No source sees it until one of the
 * registering calls below names it. Running out of memory traps. */
unsigned long linea_waitset_reserve(unsigned long set);

/* Give back a slot `linea_waitset_reserve` answered that was never
 * registered. */
void linea_waitset_unreserve(unsigned long set, unsigned long slot);

/* Register the endpoint `endpoint`, whose next operation is `recv` or
 * `offer`: it is signalled once the peer's `send` or `choose` waits. */
void linea_waitset_received(unsigned long set, unsigned long slot, unsigned long endpoint);

/* Register the handle `handle`, at its end state: it is signalled once the
 * task's body has returned. */
void linea_waitset_returned(unsigned long set, unsigned long slot, unsigned long handle);

/* Register a descriptor: signalled once it is readable (`writable` 0) or
 * writable (1). Answers zero, or a negated errno when the set's kernel queue
 * cannot be made or cannot watch it; the slot stays reserved then. */
long linea_waitset_descriptor(unsigned long set, unsigned long slot, int fd, uint8_t writable);

/* Register a source that is ready already: it is signalled at once. */
void linea_waitset_ready(unsigned long set, unsigned long slot);

/* Register a timer that expires `after_ns` from now on the set's loop's
 * monotonic clock. */
void linea_waitset_timer(unsigned long set, unsigned long slot, unsigned long after_ns);

/* Register signal `signal` (an `io.Signal`'s number), signalled by the first
 * delivery after this call. Answers zero, or a negated errno when the set's
 * kernel queue cannot be made or cannot watch the router; the slot stays
 * reserved then. The caller holds a share of the signal's disposition, taken
 * on the loop `home` (0 for the system); a share taken on another loop than
 * the set's traps, since a simulation's share holds none of the process's
 * disposition and a real one is not delivered inside a simulation. */
long linea_waitset_signal(unsigned long set, unsigned long slot, uint8_t signal, unsigned long home);

/* Wait until a registration is signalled, take the earliest signalled, and
 * answer its slot, whose generation has moved on. An empty set answers -1 at
 * once. */
long linea_waitset_next(unsigned long set);

/* Withdraw the registration at `slot` if it has generation `generation` and
 * has not been taken, answering 1, or 0 for a slot that has moved on. With
 * `only_registered` set, a registration already signalled is left alone and
 * 0 answered. */
uint8_t linea_waitset_take(unsigned long set, unsigned long slot, unsigned long generation, uint8_t only_registered);

/* Withdraw any registration still held and answer its slot, or -1 for an
 * empty set. */
long linea_waitset_withdraw(unsigned long set);

/* Free an empty set. A set still holding a registration traps. */
void linea_waitset_close(unsigned long set);

/* Called by a source, under the lock that guards its mark of `r`, when what
 * `r` waits for has happened. */
void linea_registration_signal(struct linea_registration *r);

#endif
