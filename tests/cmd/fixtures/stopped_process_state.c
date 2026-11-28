#define _POSIX_C_SOURCE 200809L
#include <errno.h>
#include <signal.h>
#include <stdio.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

/* Keep an exited child unreaped until the transcript ends this helper. This
 * separates process existence from running: kill(pid, 0) succeeds on both. */
int main(void) {
    sigset_t stop;
    if (sigemptyset(&stop) != 0 || sigaddset(&stop, SIGTERM) != 0 ||
        sigprocmask(SIG_BLOCK, &stop, NULL) != 0) return 1;
    const pid_t child = fork();
    if (child < 0) return 2;
    if (child == 0) _exit(0);
    siginfo_t info = {0};
    int ready;
    do {
        ready = waitid(P_PID, (id_t)child, &info, WEXITED | WNOWAIT);
    } while (ready != 0 && errno == EINTR);
    if (ready != 0) return 3;
    if (printf("%ld\n", (long)child) < 0 || fflush(stdout) != 0) return 4;
    int signal;
    if (sigwait(&stop, &signal) != 0 || signal != SIGTERM) return 5;
    int status;
    pid_t waited;
    do {
        waited = waitpid(child, &status, 0);
    } while (waited < 0 && errno == EINTR);
    return waited == child && WIFEXITED(status) && WEXITSTATUS(status) == 0 ? 0 : 6;
}
