#ifndef LINEA_TASK_H
#define LINEA_TASK_H

#include <stdint.h>

/* A task is a thread with one session to the task that started it. A task
 * and an endpoint are named by an unsigned long the runtime hands out. Each
 * session holds one slot, so a send returns only once its peer has taken
 * the value, and a choice is a send of its branch number.
 *
 * Happens-before: everything the creator did before `linea_task_start` is
 * visible to the body; everything a task did before a send is visible to its
 * peer once the matching receive returns; everything the body did is visible
 * once `linea_chan_close` on the handle returns. Each edge is a release and
 * an acquire of the session's mutex, or `pthread_create` and `pthread_join`. */

/* What a started task's thread calls: the task's own endpoint, then the
 * address and length of the bytes its body is kept in. */
typedef void (*linea_task_entry)(unsigned long endpoint, unsigned long at, unsigned long len);

/* What the thread that joins a task calls with the same address and length,
 * to release those bytes. */
typedef void (*linea_task_release)(unsigned long at, unsigned long len);

/* Create a thread with a stack of `stack_bytes`, parked on a start latch
 * before it runs any code. The result is the task, or a negated errno when
 * its record, its stack or its thread cannot be made; a failure leaves
 * nothing behind. */
long linea_task_prepare(unsigned long stack_bytes);

/* Release a parked task's latch: its thread calls `entry` and returns. The
 * call cannot fail. The result is the creator's endpoint, the task's handle. */
unsigned long linea_task_start(unsigned long task, linea_task_entry entry, linea_task_release release, unsigned long at,
                               unsigned long len);

/* Release a parked task's latch with nothing to run, join its thread and
 * free what `linea_task_prepare` made. */
void linea_task_cancel(unsigned long task);

/* Hand the `len` bytes at `at` to the peer of `endpoint`, and return once
 * the peer has copied them. */
void linea_chan_send(unsigned long endpoint, unsigned long at, unsigned long len);

/* Wait until the peer of `endpoint` sends, and copy the `len` bytes it sent
 * to `at`. */
void linea_chan_recv(unsigned long endpoint, unsigned long at, unsigned long len);

/* Send the branch a choice takes, 0 for the left one and 1 for the right
 * one, and return once the peer has read it. */
void linea_chan_choose(unsigned long endpoint, uint8_t branch);

/* Wait until the peer of `endpoint` chooses, and return its branch. */
uint8_t linea_chan_offer(unsigned long endpoint);

/* Finish one end of a session at its end state. The task's own end returns
 * at once. The handle's returns only once the body has returned and the
 * thread has been joined, and it then releases the bytes the body was kept
 * in, on the calling thread, before freeing the session. */
void linea_chan_close(unsigned long endpoint);

/* Wait until the peer of `endpoint` sends or timeout elapses. Returns 1 if received, 0 on timeout. */
uint8_t linea_chan_recv_until(unsigned long endpoint, unsigned long at, unsigned long len, unsigned long timeout_ns);

/* An owning task's call queue: many callers, one owner. A call hands the
 * owner the `len` bytes at `at` and returns once the owner has finished with
 * them, so everything the caller did before the call happens before the
 * owner's work on it, and that work happens before the call returns. Calls
 * are served one at a time. */
unsigned long linea_owner_open(void);
void linea_owner_call(unsigned long queue, unsigned long at, unsigned long len);
/* Wait for the next call and copy its `len` bytes to `at`, answering 1, or
 * answer 0 once the queue is closed and no call waits. */
uint8_t linea_owner_next(unsigned long queue, unsigned long at, unsigned long len);
/* Finish the call `linea_owner_next` answered, releasing its caller. */
void linea_owner_done(unsigned long queue);
/* Accept no further calls; the owner's next wait answers 0. */
void linea_owner_close(unsigned long queue);
void linea_owner_free(unsigned long queue);

#endif
