/* How the runtime writes to a pipe or socket whose reader has gone without
 * SIGPIPE ending the process, while changing nothing shared: not the
 * process's SIGPIPE disposition, which stays as the host set it, and not
 * the open file, which other threads and processes write through too. No
 * part of this changes the process-wide disposition.
 *
 * Linux raises a write's SIGPIPE on the writing thread. macOS raises it on
 * the process: the system hands it to a thread that does not block it, or,
 * where every thread blocks it, leaves it pending on one of them, not
 * necessarily the writer. Three cases follow.
 *
 * 1. A socket, and every ordinary Linea write, on either system. A socket is
 *    written with `send` and `MSG_NOSIGNAL`, which raises no SIGPIPE for that
 *    one call. Any other descriptor is written with SIGPIPE blocked on the
 *    writing thread, and a SIGPIPE the write left pending on that thread is
 *    taken with `sigwait` before the thread's mask is restored. One that was
 *    already pending before the write is left pending: a blocked signal does
 *    not queue, so a second SIGPIPE merges with it, and taking it would take
 *    the one that was there first. On Linux this is the whole of it.
 *
 * 2. A standalone Linea program on macOS. Its entry, `linea_set_args`,
 *    blocks SIGPIPE on the main thread, and threads created after it with
 *    `pthread_create`, by the runtime or by C code it calls, inherit the
 *    mask. A SIGPIPE a write raises then stays pending on a thread that
 *    never takes it, and the write answers EPIPE. Linea does not control the
 *    mask of threads it did not create from a thread holding the block:
 *    libdispatch (GCD) workqueue threads start with their own mask, not
 *    main's, and a thread a C constructor started before `linea_set_args`
 *    ran never inherited it. While such a thread is alive and does not block
 *    SIGPIPE, a write's SIGPIPE can reach it, under the process's
 *    disposition. A signal mask, and a pending signal, survive `exec`: a
 *    program a Linea program starts through C (`fork` and `exec`,
 *    `posix_spawn`, `system`) begins with SIGPIPE blocked unless the caller
 *    sets its mask, and a program the process becomes by `exec` in place
 *    keeps a SIGPIPE left pending on main and dies of it once it unblocks
 *    SIGPIPE; no path of the runtime or the standard library calls `exec`.
 *
 * 3. Linea embedded in a host process, which calls exported functions and
 *    runs no Linea entry. Threads the host creates keep the host's signal
 *    policy: the runtime blocks SIGPIPE only around its own writes, on the
 *    writing thread. On macOS a host thread that does not block SIGPIPE can
 *    take a Linea write's SIGPIPE, under the host's disposition, as it would
 *    take the host's own write's. An embedder that needs protection blocks
 *    SIGPIPE on its own threads. */

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
