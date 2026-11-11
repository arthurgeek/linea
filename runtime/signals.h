#ifndef LINEA_SIGNALS_H
#define LINEA_SIGNALS_H

#include <stdint.h>

/* Operating-system signals as wait-set sources. The signals offered are
 * `io.Signal`'s, numbered as it declares them: 0 SIGTERM, 1 SIGINT, 2 SIGHUP,
 * 3 SIGUSR1 and 4 SIGUSR2.
 *
 * While a share of a signal exists, the router's handler is installed for
 * it. The handler counts the delivery with an atomic increment, writes a
 * byte to the router's wake descriptor, calls the handler a host installed
 * before the first share, if any, and restores `errno`. Every wait set
 * holding a signal registration watches the wake descriptor; the first to
 * see it readable drains it, reads each signal's count, and signals every
 * registration whose signal was delivered after it was made. When the last
 * share of a signal is released, the action saved by the first share is
 * restored.
 *
 * Inside a simulation a share installs nothing, and a signal is delivered
 * only by `linea_signal_deliver_simulated`, which signals the registrations
 * made inside that simulation. */

struct linea_registration;

enum { linea_signal_kinds = 5 };

/* Acquire one share of `signal`'s disposition on the calling thread's loop.
 * Answers 0, 1 when the signal is ignored (its action is `SIG_IGN`) and no
 * share was taken, or a negated errno when the wake descriptor or the
 * handler cannot be installed. */
long linea_signal_acquire(uint8_t signal);

/* Release a share acquired on loop `loop`; the last share of a signal on
 * the system restores the action saved by its first. */
void linea_signal_release(uint8_t signal, unsigned long loop);

/* Deliver `signal` inside the simulation `loop`, which must be running on
 * the calling thread. */
void linea_signal_deliver_simulated(unsigned long loop, uint8_t signal);

/* A registration's place in the router's list. */
struct linea_signal_watch {
    struct linea_registration *registration;
    struct linea_signal_watch *previous, *next;
    unsigned long loop;
    unsigned long recorded;
    uint8_t signal;
    uint8_t listed;
};

/* The descriptor the router writes a byte to on each delivery; -1 before the
 * first share. */
int linea_signal_wake_descriptor(void);

/* Add `watch` to the router: it is signalled by the first delivery of its
 * signal on `loop` after this call. */
void linea_signal_watch(struct linea_signal_watch *watch, struct linea_registration *r, unsigned long loop, uint8_t signal);

/* Take `watch` out of the router. Once this returns, the router signals it
 * no more. */
void linea_signal_unwatch(struct linea_signal_watch *watch);

/* Drain the wake descriptor and signal every registration whose signal was
 * delivered after it was made. */
void linea_signal_drain(void);

#endif
