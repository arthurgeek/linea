/* How the runtime writes to a pipe or socket whose reader has gone without
 * SIGPIPE ending the process, while changing nothing shared: not the
 * process's SIGPIPE disposition, which stays as the host set it, and not
 * the open file, which other threads and processes write through too.
 *
 * A socket is written with `send` and `MSG_NOSIGNAL`, which raises no
 * SIGPIPE for that one call. Any other descriptor is written with SIGPIPE
 * blocked on the writing thread, and a SIGPIPE the write left pending on that
 * thread is taken with `sigwait` before the thread's mask is restored. One
 * that was already pending before the write is left pending: a blocked
 * signal does not queue, so a second SIGPIPE merges with it, and taking it
 * would take the one that was there first.
 *
 * Linux raises a write's SIGPIPE on the writing thread, so that is the whole
 * of it there. macOS raises it on the process: the system hands it to a
 * thread that does not block it, or, where every thread blocks it, leaves it
 * pending on one of them, not necessarily the writer. So in a Linea program
 * the entry blocks SIGPIPE on the main thread before any other thread exists
 * (`linea_set_args`), and every thread started after it, by the runtime or by
 * C code it calls, inherits the block. A SIGPIPE raised on macOS then stays
 * pending on a thread that never takes it, and the write answers EPIPE. A
 * signal mask is inherited across `fork` and `exec`, so a program a Linea
 * program starts through C (`fork` and `exec`, `posix_spawn`, `system`)
 * starts with SIGPIPE blocked unless the caller sets its mask, as with any
 * program that blocks a signal; undoing the block in a `fork` child would
 * leave a child that goes on running Linea code on several threads open to
 * the signal.
 *
 * What this cannot cover, on macOS only: a process that runs Linea code
 * without a Linea entry, as a host calling exported functions does, where a
 * thread of the host's does not block SIGPIPE. A write to a pipe with no
 * reader then raises a SIGPIPE that thread takes, under the host's
 * disposition, exactly as the host's own write would. */

#ifndef LINEA_PIPE_SIGNAL_H
#define LINEA_PIPE_SIGNAL_H

#include <errno.h>
#include <pthread.h>
#include <signal.h>
#include <stddef.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <unistd.h>

/* One write of the `len` bytes at `bytes` to `fd` where `fd` is a socket,
 * with `send` and `MSG_NOSIGNAL`, answering as `write` does; where `fd` is
 * not a socket it writes nothing and fails with ENOTSOCK. Async-signal-safe. */
static inline ssize_t send_without_signal(int fd, const void *bytes, size_t len) {
    return send(fd, bytes, len, MSG_NOSIGNAL);
}

/* Writes the `len` bytes at `bytes` to standard error for a failure report,
 * so a process whose standard error has no reader still ends by the abort
 * that follows the report. SIGPIPE is blocked on the reporting thread and
 * left blocked, since the process ends next; nothing else changes. A write
 * that fails ends the report: nothing better is left to do on the way to an
 * abort. Uses only async-signal-safe calls (`sigemptyset`, `sigaddset`,
 * `pthread_sigmask`, `send` and `write`), since the fault handler reports
 * through it. */
static inline void report_bytes(const char *bytes, size_t len) {
    sigset_t pipe_signal;
    if (sigemptyset(&pipe_signal) == 0 && sigaddset(&pipe_signal, SIGPIPE) == 0) {
        (void)pthread_sigmask(SIG_BLOCK, &pipe_signal, 0);
    }
    while (len > 0) {
        ssize_t written = send_without_signal(2, bytes, len);
        if (written < 0 && errno == ENOTSOCK) written = write(2, bytes, len);
        if (written < 0 && errno == EINTR) continue;
        if (written <= 0) return;
        bytes += written;
        len -= (size_t)written;
    }
}

#endif
