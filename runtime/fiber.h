#ifndef LINEA_FIBER_H
#define LINEA_FIBER_H

#include <stdint.h>

struct linea_park;
struct linea_fiber;
struct linea_fiber_waiter;
struct linea_op;

typedef void (*linea_fiber_entry)(void *argument);
typedef long (*linea_fiber_attempt)(struct linea_op *operation);

/* A prepared fiber owns its fixed stack and is pinned to one carrier. It is
 * not runnable until started. finished runs on the scheduler stack, after
 * the fiber's final context has been saved. */
struct linea_fiber *linea_fiber_create(unsigned long identity, unsigned long stack_bytes,
                                      linea_fiber_entry entry, linea_fiber_entry finished, void *argument, int *error);
void linea_fiber_start(struct linea_fiber *fiber);
void linea_fiber_destroy(struct linea_fiber *fiber);
int linea_fiber_active(void);

/* These are called holding the record's lock. The waiter is published before
 * that lock is released, and the lock is reacquired before park answers. */
int linea_fiber_park(struct linea_park *park, unsigned long deadline);
void linea_fiber_unpark(struct linea_park *park);
void linea_fiber_yield(void);

/* Complete one operation on the executing fiber's carrier. The callback
 * attempts a nonblocking call and answers -EAGAIN when it would wait. */
long linea_fiber_perform(struct linea_op *operation, linea_fiber_attempt attempt);
long linea_fiber_wait_descriptor(int fd, uint8_t writable, unsigned long deadline);
long linea_fiber_sleep(unsigned long nanoseconds);

/* Process-lifetime loops. Failure leaves no carrier or mapping behind. */
long linea_loop_open(unsigned long carriers);

void *linea_fiber_sim_create(unsigned long identity);
void linea_fiber_sim_switch(unsigned long previous, unsigned long identity);
void linea_fiber_sim_destroy(void *carrier);
int linea_fiber_sim_step(unsigned long deadline);
int linea_fiber_sim_park(struct linea_park *park, unsigned long deadline);

#endif
