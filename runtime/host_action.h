/* How the runtime calls a handler a host installed before the runtime's own,
 * from inside the runtime's handler for the same signal. The fault handler
 * hands on a fault that is not Linea's this way, and the signal router chains
 * each signal it counts to the host's handler.
 *
 * The call reproduces the system's own call in these respects: the handler
 * gets the same arguments, and runs with the thread's signal mask extended by
 * its `sa_mask` and, unless it set `SA_NODEFER`, by its own signal; with
 * `SA_NODEFER` and the signal outside its `sa_mask`, the signal is unblocked
 * during the call. The runtime's own handler is installed without
 * `SA_NODEFER`, so its signal is already blocked when the call begins.
 * `SA_RESETHAND` is answered by each caller, since what follows a spent
 * one-shot handler differs: a fault takes the default action, and a counted
 * signal is counted alone while the router is installed.
 *
 * Everything here is async-signal-safe. */

#ifndef LINEA_HOST_ACTION_H
#define LINEA_HOST_ACTION_H

#include <pthread.h>
#include <signal.h>

/* Whether `action` calls a handler, and neither ignores its signal nor
 * leaves it its default. `SIG_DFL` and `SIG_IGN` are read first: the two
 * handler fields share their storage, and a process can carry `SA_SIGINFO`
 * beside either. */
static inline int host_action_calls_handler(const struct sigaction *action) {
    return action->sa_handler != SIG_DFL && action->sa_handler != SIG_IGN;
}

/* `action`'s flags, read unsigned: `SA_RESETHAND` and `SA_NODEFER` do not fit
 * an `int` on every system. */
static inline unsigned host_action_flags(const struct sigaction *action) {
    return (unsigned)action->sa_flags;
}

/* Call the handler `action` names for `signal`, under the mask described
 * above, and restore the thread's mask. `action` must name a handler. Answers
 * 0, or -1 when the thread's mask cannot be changed, before or after the call. */
static inline int host_action_call(const struct sigaction *action, int signal, siginfo_t *info, void *context) {
    const unsigned flags = host_action_flags(action);
    sigset_t before;
    if (pthread_sigmask(SIG_BLOCK, &action->sa_mask, &before) != 0) return -1;
    if ((flags & (unsigned)SA_NODEFER) != 0 && sigismember(&action->sa_mask, signal) != 1) {
        sigset_t own;
        if (sigemptyset(&own) != 0 || sigaddset(&own, signal) != 0 || pthread_sigmask(SIG_UNBLOCK, &own, 0) != 0) {
            (void)pthread_sigmask(SIG_SETMASK, &before, 0);
            return -1;
        }
    }
    if ((flags & (unsigned)SA_SIGINFO) != 0) {
        action->sa_sigaction(signal, info, context);
    } else {
        action->sa_handler(signal);
    }
    return pthread_sigmask(SIG_SETMASK, &before, 0) == 0 ? 0 : -1;
}

#endif
