#ifndef LINEA_PROCESS_H
#define LINEA_PROCESS_H

#include <stdint.h>

/* How a child is set up, in the bits of `setup`: two bits per standard
 * stream, input in bits 0-1, output in 2-3 and error in 4-5, each one of the
 * three stream values; and bit 6, set when `environment_at`'s strings replace this
 * process's environment. */
enum linea_process_setup {
    LINEA_PROCESS_INHERIT = 0,
    LINEA_PROCESS_NULL = 1,
    LINEA_PROCESS_PIPE = 2,
    LINEA_PROCESS_ENVIRONMENT = 0x40
};

/* Start a child process and answer its process ID, or a negated errno.
 *
 * `arguments_at` holds `argument_count` NUL-terminated strings, the program
 * first, filling exactly `arguments_extent` bytes. `environment_at` holds
 * `environment_count` NUL-terminated `NAME=value` strings the same way, none
 * at all for an empty environment; without bit 6 of `setup` the child gets
 * this process's environment, and both are zero. `directory_at` is
 * one NUL-terminated path the child starts in, or an extent of zero for this
 * process's own. `table_at` is caller-owned scratch, aligned for pointers, with
 * room for `argument_count + 1` pointers and, when an environment is given,
 * `environment_count + 1` more; the call writes the pointer arrays the system
 * takes there.
 *
 * A program name holding no `/` is searched for in this process's PATH. The
 * child inherits only its three standard streams: every other descriptor is
 * closed in it. It starts with an empty signal mask.
 *
 * For each stream set to a pipe, `*stdin_fd`, `*stdout_fd` or `*stderr_fd`
 * receives the parent's end, nonblocking and close-on-exec; every other one
 * receives -1. On failure nothing is left open. Inside a simulation no
 * process starts and the answer is -ENOTSUP. */
long linea_process_spawn(unsigned long arguments_at, unsigned long arguments_extent, unsigned long argument_count,
                         unsigned long environment_at, unsigned long environment_extent, unsigned long environment_count,
                         unsigned long directory_at, unsigned long directory_extent,
                         unsigned long table_at, unsigned long table_extent,
                         uint8_t setup, int *stdin_fd, int *stdout_fd, int *stderr_fd);

/* Wait for the child `pid` to end and reap it. Answers 0 with its exit code
 * in `*status` when it exited, 1 with the signal's number when a signal ended
 * it, or a negated errno. A fiber parks until the child ends, leaving its
 * carrier to other fibers; a task on its own thread blocks in `waitpid`. */
long linea_process_wait(int pid, unsigned long *status);

/* Send SIGKILL to the child `pid`, which has not been reaped, so the number
 * still names it. Answers 0 or a negated errno. */
long linea_process_kill(int pid);

/* Read from or write to the parent's nonblocking end of a child's pipe,
 * waiting until the pipe is ready: a fiber parks, a thread polls. A read
 * answers its count, 0 at end of input; a write answers how many bytes it
 * wrote, -EPIPE once the child closed its end, with no SIGPIPE raised. */
long linea_pipe_read(int fd, unsigned long at, unsigned long len);
long linea_pipe_write(int fd, unsigned long at, unsigned long len);

#endif
