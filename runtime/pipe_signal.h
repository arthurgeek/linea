/* How the runtime writes to a pipe whose reader has gone without SIGPIPE
 * ending the process, while leaving the process's SIGPIPE disposition as the
 * host set it.
 *
 * Linux raises the SIGPIPE of such a write on the writing thread, so blocking
 * it on that thread keeps it from any other. macOS raises it on the process,
 * which hands it to any thread that does not block it, so blocking it on the
 * writing thread does not stop it ending the process. There the write is kept
 * from raising it at all: `F_SETNOSIGPIPE` makes every write on that open file
 * answer EPIPE without the signal. The setting belongs to the open file, so it
 * stays set after the write, for every descriptor that shares the file,
 * including ones another process inherited; clearing it again would race
 * with another thread writing to the same file. */

#ifndef LINEA_PIPE_SIGNAL_H
#define LINEA_PIPE_SIGNAL_H

#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <signal.h>

#if defined(F_SETNOSIGPIPE)
/* Makes a write to `fd` answer EPIPE without raising SIGPIPE. Answers zero,
 * or the errno that kept the setting from taking. The setting is read before
 * it is written: a socket whose peer reset the connection refuses
 * `F_SETNOSIGPIPE` with EINVAL, while it reports the `SO_NOSIGPIPE` the
 * runtime set when it opened the socket. */
static inline int write_without_pipe_signal(int fd) {
    const int set = fcntl(fd, F_GETNOSIGPIPE);
    if (set < 0) return errno;
    if (set != 0) return 0;
    return fcntl(fd, F_SETNOSIGPIPE, 1) == 0 ? 0 : errno;
}
#endif

/* Keeps a failure report written to standard error from raising SIGPIPE, so
 * a process whose standard error has no reader still ends by the abort that
 * follows the report. Uses only async-signal-safe calls, since the fault
 * handler reports through it. Where it cannot take, the report goes ahead
 * anyway: nothing better is left to do on the way to an abort. */
static inline void report_without_pipe_signal(void) {
#if defined(F_SETNOSIGPIPE)
    (void)write_without_pipe_signal(2);
#else
    sigset_t pipe_signal;
    if (sigemptyset(&pipe_signal) == 0 && sigaddset(&pipe_signal, SIGPIPE) == 0) {
        (void)pthread_sigmask(SIG_BLOCK, &pipe_signal, 0);
    }
#endif
}

#endif
