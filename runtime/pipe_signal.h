/* How a failure report reaches standard error without SIGPIPE ending the
 * process first, while leaving the process's SIGPIPE disposition as the host
 * set it, so a process whose standard error has no reader still ends by the
 * abort that follows the report.
 *
 * Linux raises the SIGPIPE of a write to a pipe or socket with no reader on
 * the writing thread, so blocking it on that thread keeps it from any other.
 * macOS raises it on the process, which hands it to any thread that does not
 * block it. There a socket is written with `send` and `MSG_NOSIGNAL`, which
 * raises nothing, and a pipe's open file gets `F_SETNOSIGPIPE`. The report
 * leaves that setting in place, for every descriptor that shares the open
 * file, other processes' included: the process aborts right after, and
 * clearing it could let another thread's write that relies on it raise
 * SIGPIPE first. `linea_write_some` restores the setting after an ordinary
 * write. */

#ifndef LINEA_PIPE_SIGNAL_H
#define LINEA_PIPE_SIGNAL_H

#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <signal.h>
#include <stddef.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

/* Writes the `len` bytes at `bytes` to standard error for a failure report,
 * without raising SIGPIPE. A write that fails ends the report: nothing
 * better is left to do on the way to an abort. Uses only async-signal-safe
 * calls (`fstat`, `fcntl`, `send` and `write` on macOS; `sigemptyset`,
 * `sigaddset`, `pthread_sigmask` and `write` elsewhere), since the fault
 * handler reports through it. */
static inline void report_bytes(const char *bytes, size_t len) {
#if defined(F_SETNOSIGPIPE)
    struct stat status;
    const int socket = fstat(2, &status) == 0 && S_ISSOCK(status.st_mode);
    if (!socket && fcntl(2, F_GETNOSIGPIPE) == 0) (void)fcntl(2, F_SETNOSIGPIPE, 1);
#else
    sigset_t pipe_signal;
    if (sigemptyset(&pipe_signal) == 0 && sigaddset(&pipe_signal, SIGPIPE) == 0) {
        (void)pthread_sigmask(SIG_BLOCK, &pipe_signal, 0);
    }
#endif
    while (len > 0) {
#if defined(F_SETNOSIGPIPE)
        const ssize_t written = socket ? send(2, bytes, len, MSG_NOSIGNAL) : write(2, bytes, len);
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
