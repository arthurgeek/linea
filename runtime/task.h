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

/* Mailbox: many children / senders, one receiver. */
unsigned long linea_mailbox_open(void);
void linea_mailbox_close(unsigned long mb);
void linea_mailbox_send(unsigned long mb, unsigned long at, unsigned long len);
uint8_t linea_mailbox_recv(unsigned long mb, unsigned long at, unsigned long len);
void linea_mailbox_add_child(unsigned long mb);
void linea_mailbox_remove_child(unsigned long mb);
unsigned long linea_mailbox_timer(unsigned long mb, unsigned long nanoseconds, unsigned long at, unsigned long len);
uint8_t linea_mailbox_timer_cancel(unsigned long timer_handle, unsigned long at, unsigned long len);

/* Dispatch `worker(ctx)` on a background worker thread bounded by `max_workers`. */
typedef void (*linea_task_worker)(unsigned long ctx);
void linea_task_dispatch_worker(linea_task_worker worker, unsigned long ctx, unsigned long max_workers);

/* Wait until all active background worker threads have completed. */
void linea_task_drain_workers(void);

/* Worker identity (1-based on pool workers, 0 on non-pool threads) and
 * separate thread-local storage slot (initialized to 0 on every thread). */
unsigned long linea_task_worker_id(void);
void linea_task_set_worker_id(unsigned long wid);
unsigned long linea_task_worker_slot(void);
void linea_task_set_worker_slot(unsigned long slot);

/* Bounded FIFO connection queue for persistent worker tasks. */
unsigned long linea_conn_queue_open(void);
void linea_conn_queue_push(unsigned long handle, int fd);
int linea_conn_queue_pop(unsigned long handle);
void linea_conn_queue_close(unsigned long handle);
void linea_conn_queue_free(unsigned long handle);

/* Serialization lock for concurrent handler mutations (path-parameter buffers and observer callbacks). */
void linea_handler_lock(void);
void linea_handler_unlock(void);

/* Latch synchronization primitives */
unsigned long linea_latch_open(unsigned long count);
void linea_latch_count_down(unsigned long handle);
void linea_latch_wait(unsigned long handle);
uint8_t linea_latch_arrive_and_wait(unsigned long handle);
uint8_t linea_latch_arrive_and_wait_timeout(unsigned long handle, unsigned long timeout_ms);
void linea_latch_free(unsigned long handle);

/* Test synchronization latches for cross-server concurrency tests */
void linea_test_net_latch_init(void);
void linea_test_net_latch_signal_started(void);
void linea_test_net_latch_wait_started(void);
void linea_test_net_latch_wait_hold(void);
void linea_test_net_latch_release_hold(void);
void linea_test_net_latch_cleanup(void);

#endif
