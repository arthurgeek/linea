#ifndef LINEA_PARK_H
#define LINEA_PARK_H

#include <pthread.h>

/* The one place the runtime stops a task until another party wakes it, and
 * the one place it wakes one. A session's rendezvous, a handle's join, a
 * task's start latch and an owning task's call queue each keep a park in
 * the record they wait on, and every wait on that record is a park on it.
 *
 * On a thread a park is a condition variable and the lock of the record it
 * belongs to. A parker holds the lock, checks the condition it waits for,
 * and parks while the condition does not hold; whoever makes the condition
 * hold does so with the lock held and unparks. Since the condition is
 * checked and the park entered under one lock, and the change and the
 * unpark are made under the same lock, no wake is lost; a park may still
 * return without one, so a parker checks its condition again each time it
 * returns. The lock's release by one party and its acquire by the other
 * order everything either did before. */
struct linea_fiber_waiter;

struct linea_park {
    pthread_mutex_t lock;
    pthread_cond_t changed;
    struct linea_fiber_waiter *fibers;
};

/* Initialise a park, answering zero or the errno that kept its lock or its
 * condition variable from being made; a failure leaves nothing to destroy.
 * On Linux its timed waits read the monotonic clock, which a change to the
 * system's time does not move. */
int linea_park_init(struct linea_park *p);
void linea_park_destroy(struct linea_park *p);

void linea_park_lock(struct linea_park *p);
void linea_park_unlock(struct linea_park *p);

/* Wait, holding `p`'s lock, until `p` is unparked or the monotonic clock
 * reaches `deadline_ns`, 0 for no deadline. Answers 1 once the deadline has
 * passed and 0 otherwise; a wait that ends at its deadline may answer 0, and
 * a later park then answers 1. Either answer may come without a wake, and
 * the lock is held again when it returns. */
int linea_park(struct linea_park *p, unsigned long deadline_ns);

/* Wake every party parked on `p`, holding `p`'s lock. */
void linea_unpark(struct linea_park *p);

/* The monotonic clock, in nanoseconds, plus `after_ns`: a deadline for
 * `linea_park`. A time past what 64 bits of nanoseconds count, about 584
 * years after the clock's start, answers 0, no deadline, since no clock
 * reaches it. */
unsigned long linea_park_deadline_after(unsigned long after_ns);

#endif
