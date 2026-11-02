/* How the runtime writes to a pipe or socket whose reader has gone without
 * SIGPIPE ending the process, while leaving the process's SIGPIPE disposition
 * as the host set it.
 *
 * Linux raises the SIGPIPE of such a write on the writing thread, so blocking
 * it on that thread keeps it from any other. macOS raises it on the process,
 * which hands it to any thread that does not block it, so there the write is
 * kept from raising it at all: `F_SETNOSIGPIPE` makes every write on an open
 * file answer EPIPE without the signal. A socket whose peer has gone refuses
 * the setting with EINVAL, and is written with `send` and `MSG_NOSIGNAL`.
 *
 * The setting belongs to the open file, not to the descriptor or the process,
 * and it stays set after the write. Every holder of that open file, another
 * process that inherited it included, then gets EPIPE from a write with no
 * reader instead of SIGPIPE. Restoring the setting after the write is not
 * sound: a process forked from this one shares the open file and keeps its
 * own record of writes in progress, so one process's restore can clear the
 * setting under another's write that is still waiting, which then raises
 * SIGPIPE; and a pipe opened twice by name is two open files with one inode,
 * so no record kept by inode can tell whose setting it would clear. */

#ifndef LINEA_PIPE_SIGNAL_H
#define LINEA_PIPE_SIGNAL_H

#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <signal.h>
#include <stddef.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <unistd.h>

#if defined(__APPLE__)
/* One write of the `len` bytes at `bytes` to `fd` that raises no SIGPIPE,
 * answering as `write` does. The open file gets `F_SETNOSIGPIPE` before the
 * write and keeps it; a socket whose peer has gone refuses the setting with
 * EINVAL and is written with `send` and `MSG_NOSIGNAL` instead. Uses only
 * async-signal-safe calls. */
static inline ssize_t write_without_pipe_signal(int fd, const void *bytes, size_t len) {
    const int set = fcntl(fd, F_GETNOSIGPIPE);
    if (set < 0) return -1;
    if (set == 0 && fcntl(fd, F_SETNOSIGPIPE, 1) != 0) {
        if (errno != EINVAL) return -1;
        const ssize_t sent = send(fd, bytes, len, MSG_NOSIGNAL);
        if (sent < 0 && errno == ENOTSOCK) errno = EINVAL;
        return sent;
    }
    return write(fd, bytes, len);
}
#endif

/* Writes the `len` bytes at `bytes` to standard error for a failure report,
 * without raising SIGPIPE, so a process whose standard error has no reader
 * still ends by the abort that follows the report. A write that fails ends
 * the report: nothing better is left to do on the way to an abort. Uses only
 * async-signal-safe calls (`write_without_pipe_signal` on macOS;
 * `sigemptyset`, `sigaddset`, `pthread_sigmask` and `write` elsewhere), since
 * the fault handler reports through it. */
static inline void report_bytes(const char *bytes, size_t len) {
#if !defined(__APPLE__)
    sigset_t pipe_signal;
    if (sigemptyset(&pipe_signal) == 0 && sigaddset(&pipe_signal, SIGPIPE) == 0) {
        (void)pthread_sigmask(SIG_BLOCK, &pipe_signal, 0);
    }
#endif
    while (len > 0) {
#if defined(__APPLE__)
        const ssize_t written = write_without_pipe_signal(2, bytes, len);
#else
        const ssize_t written = write(2, bytes, len);
#endif
        if (written < 0 && errno == EINTR) continue;
        if (written <= 0) return;
        bytes += written;
        len -= (size_t)written;
    }
}

#endif
