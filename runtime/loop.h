#ifndef LINEA_LOOP_H
#define LINEA_LOOP_H

#include <stdint.h>

/* The loop table. An `io.Io` is a loop's identity: 0 names the system, and
 * any other value names a slot of the table, its index plus one in the high
 * 32 bits and the slot's generation in the low 32. A slot's generation
 * changes when its loop ends, so an identity kept past the end of its loop
 * no longer matches and is refused rather than read. Slots live in pages
 * that are never freed. The only loops so far are simulations. */

/* Take a slot for `state` and answer its identity, or 0 when no slot can be
 * had: the table's pages cannot be allocated, or every slot is in use or
 * retired. */
unsigned long linea_loop_claim(void *state);

/* The state of the loop `identity` names. An identity whose loop has ended,
 * or that names no slot, traps. */
void *linea_loop_find(unsigned long identity);

/* End the loop `identity` names. Its slot's generation moves on; a slot
 * whose generation would wrap is retired and never handed out again, so no
 * identity can ever match a later loop of its slot. */
void linea_loop_retire(unsigned long identity);

/* How many threads have the loop `identity` names as their own; 0 for a
 * loop that has ended. */
unsigned long linea_loop_runs(unsigned long identity);

/* The state of the loop the calling thread runs on, or null on the system. */
void *linea_loop_running(void);

/* The identity of the loop the calling thread runs on, 0 for the system. */
unsigned long linea_io_current(void);

/* Make the loop `identity` names the calling thread's, after checking it as
 * `linea_loop_find` does, and answer the identity it replaced. */
unsigned long linea_io_switch(unsigned long identity);

/* 1 when `identity` names a simulation, 0 when it names the system; an
 * identity whose loop has ended traps. */
uint8_t linea_io_is_simulated(unsigned long identity);

#endif
