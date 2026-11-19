#define _GNU_SOURCE
#include "process.h"

#include "fiber.h"
#include "io.h"
#include "pipe_signal.h"
#include "sim.h"

#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <poll.h>
#include <signal.h>
#include <spawn.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>
#if defined(__linux__)
#include <sys/syscall.h>
#endif
#if defined(__APPLE__)
#include <sys/event.h>
#endif

extern char **environ;

#if defined(__linux__)
/* glibc gained these in 2.29 and 2.34, after the oldest glibc the runtime is
 * compiled against. They are declared weak, so a program linked against a
 * glibc that has them calls them and one linked against an older glibc finds
 * them null and falls back. */
extern int posix_spawn_file_actions_addchdir_np(posix_spawn_file_actions_t *actions, const char *path) __attribute__((weak));
extern int posix_spawn_file_actions_addclosefrom_np(posix_spawn_file_actions_t *actions, int from) __attribute__((weak));
/* The system call number is the same on every Linux architecture. */
#if !defined(SYS_pidfd_open)
#define SYS_pidfd_open 434
#endif
#endif

static void fail(const char *message) {
    report_bytes(message, strlen(message));
    abort();
}

/* A child process exists outside any simulation, so one used inside a
 * simulation would make its run depend on the real system. */
static void refuse_simulated(void) {
    if (linea_sim_running()) fail("linea: a child process was used inside a simulation\n");
}

/* Whether the kernel reaps this process's children itself: SIGCHLD ignored,
 * or caught with SA_NOCLDWAIT. A child then leaves no zombie to wait for, and
 * once it ends its process ID may name another process, so no child is
 * started and none is signalled. */
static int children_reaped_by_kernel(void) {
    struct sigaction action;
    if (sigaction(SIGCHLD, NULL, &action) != 0) return 0;
    return action.sa_handler == SIG_IGN || (action.sa_flags & SA_NOCLDWAIT) != 0;
}

/* Fill `table` with a pointer to each of the `count` NUL-terminated strings
 * that fill exactly the `extent` bytes at `at`, then a null pointer. */
static int split(unsigned long at, unsigned long extent, unsigned long count, char **table) {
    if (count == 0 || extent == 0) return EINVAL;
    char *bytes = (char *)(uintptr_t)at;
    if (bytes[extent - 1] != '\0') return EINVAL;
    unsigned long found = 0;
    unsigned long start = 0;
    for (unsigned long i = 0; i < extent; i++) {
        if (bytes[i] != '\0') continue;
        if (found == count) return EINVAL;
        table[found] = bytes + start;
        found++;
        start = i + 1;
    }
    if (found != count) return EINVAL;
    table[count] = NULL;
    return 0;
}

/* Move `fd` to a number above the standard streams, so a dup2 onto 0, 1 or 2
 * never names its own source, which would leave close-on-exec set. */
static int above_standard(int *fd) {
    if (*fd > 2) return 0;
    const int moved = fcntl(*fd, F_DUPFD_CLOEXEC, 3);
    if (moved < 0) return errno;
    close(*fd);
    *fd = moved;
    return 0;
}

/* A pipe whose ends are both close-on-exec and above the standard streams;
 * `parent` is made nonblocking. `parent_reads` says which end is the
 * parent's. fcntl's F_SETFD and F_SETFL do not block; Linux and macOS
 * document EINTR only for the blocking lock commands. */
static int open_pipe(int parent_reads, int *parent, int *child) {
    int ends[2];
#if defined(__linux__)
    if (pipe2(ends, O_CLOEXEC) != 0) return errno;
#else
    /* posix_spawn below closes every descriptor not named for the child, so
     * the instant before close-on-exec is set leaks nothing into it; another
     * thread's fork in that instant could inherit an end, as it could any
     * descriptor C code opens. */
    if (pipe(ends) != 0) return errno;
    if (fcntl(ends[0], F_SETFD, FD_CLOEXEC) != 0 || fcntl(ends[1], F_SETFD, FD_CLOEXEC) != 0) {
        const int error = errno;
        close(ends[0]);
        close(ends[1]);
        return error;
    }
#endif
    int error = above_standard(&ends[0]);
    if (error == 0) error = above_standard(&ends[1]);
    *parent = parent_reads ? ends[0] : ends[1];
    *child = parent_reads ? ends[1] : ends[0];
    if (error == 0) {
        const int flags = fcntl(*parent, F_GETFL, 0);
        if (flags == -1 || fcntl(*parent, F_SETFL, flags | O_NONBLOCK) != 0) error = errno;
    }
    if (error != 0) {
        close(ends[0]);
        close(ends[1]);
        *parent = -1;
        *child = -1;
    }
    return error;
}

#if defined(__linux__)
/* Close in the child every descriptor above the standard streams that is not
 * close-on-exec, read from /proc/self/fd, where glibc offers no
 * `addclosefrom`. A descriptor another thread opens after the walk without
 * close-on-exec can still reach the child. */
static int close_inherited(posix_spawn_file_actions_t *actions) {
    if (posix_spawn_file_actions_addclosefrom_np != NULL) return posix_spawn_file_actions_addclosefrom_np(actions, 3);
    int listing;
    do {
        listing = open("/proc/self/fd", O_RDONLY | O_DIRECTORY | O_CLOEXEC);
    } while (listing < 0 && errno == EINTR);
    if (listing < 0) return errno;
    DIR *entries = fdopendir(listing);
    if (entries == NULL) {
        const int error = errno;
        close(listing);
        return error;
    }
    int error = 0;
    struct dirent *entry;
    while (error == 0 && (entry = readdir(entries)) != NULL) {
        char *end;
        const long fd = strtol(entry->d_name, &end, 10);
        if (end == entry->d_name || *end != '\0' || fd < 3 || fd > INT_MAX || fd == listing) continue;
        const int flags = fcntl((int)fd, F_GETFD);
        if (flags >= 0 && (flags & FD_CLOEXEC) == 0) error = posix_spawn_file_actions_addclose(actions, (int)fd);
    }
    closedir(entries);
    return error;
}
#endif

/* Set up the child's stream `target` (0, 1 or 2) as `mode` says. A pipe's
 * child end is `child`. */
static int stream_action(posix_spawn_file_actions_t *actions, int target, unsigned mode, int child) {
    switch (mode) {
    case LINEA_PROCESS_INHERIT: {
#if defined(__APPLE__)
        /* POSIX_SPAWN_CLOEXEC_DEFAULT closes every descriptor not named. A
         * stream this process has closed stays closed in the child, as it
         * does on Linux; naming it would fail the whole spawn with EBADF. A
         * close-on-exec descriptor in a stream's place is one the runtime
         * opened there after the stream was closed, such as a loop's kqueue,
         * which macOS also refuses to pass on; it stays closed too, as exec
         * closes it on Linux. */
        const int flags = fcntl(target, F_GETFD);
        if (flags == -1 || (flags & FD_CLOEXEC) != 0) return 0;
        return posix_spawn_file_actions_addinherit_np(actions, target);
#else
        return 0;
#endif
    }
    case LINEA_PROCESS_NULL:
        return posix_spawn_file_actions_addopen(actions, target, "/dev/null", target == 0 ? O_RDONLY : O_WRONLY, 0);
    case LINEA_PROCESS_PIPE:
        return posix_spawn_file_actions_adddup2(actions, child, target);
    default:
        return EINVAL;
    }
}

long linea_process_spawn(unsigned long arguments_at, unsigned long arguments_extent, unsigned long argument_count,
                         unsigned long environment_at, unsigned long environment_extent, unsigned long environment_count,
                         unsigned long directory_at, unsigned long directory_extent,
                         unsigned long table_at, unsigned long table_extent,
                         uint8_t setup, int *stdin_fd, int *stdout_fd, int *stderr_fd) {
    int *parents[3] = { stdin_fd, stdout_fd, stderr_fd };
    for (int i = 0; i < 3; i++) *parents[i] = -1;
    if (linea_sim_running()) return -(long)ENOTSUP;
    if (children_reaped_by_kernel()) return -(long)ECHILD;

    int invalid = linea_io_byte_range(arguments_at, arguments_extent);
    if (invalid == 0) invalid = linea_io_byte_range(environment_at, environment_extent);
    if (invalid == 0) invalid = linea_io_byte_range(directory_at, directory_extent);
    if (invalid == 0) invalid = linea_io_byte_range(table_at, table_extent);
    if (invalid != 0) return -(long)invalid;
    if (setup > 0x7f) return -(long)EINVAL;
    const int inherit_environment = (setup & LINEA_PROCESS_ENVIRONMENT) == 0;
    if (inherit_environment && (environment_extent != 0 || environment_count != 0)) return -(long)EINVAL;
    const unsigned long pointer_size = sizeof(char *);
    const unsigned long limit = ULONG_MAX / pointer_size - 2;
    if (argument_count > limit || (!inherit_environment && environment_count > limit - argument_count)) return -(long)EINVAL;
    const unsigned long pointers = argument_count + 1 + (inherit_environment ? 0 : environment_count + 1);
    if (table_at % pointer_size != 0 || table_extent < pointers * pointer_size) return -(long)EINVAL;
    if (directory_extent != 0) {
        const char *path = (const char *)(uintptr_t)directory_at;
        if (directory_extent < 2 || path[directory_extent - 1] != '\0' ||
            (memchr)(path, '\0', (size_t)(directory_extent - 1)) != NULL) return -(long)EINVAL;
    }

    char **argv = (char **)(uintptr_t)table_at;
    char **envp = inherit_environment ? environ : argv + argument_count + 1;
    int error = split(arguments_at, arguments_extent, argument_count, argv);
    if (error == 0 && !inherit_environment) {
        if (environment_count != 0) {
            error = split(environment_at, environment_extent, environment_count, envp);
        } else if (environment_extent != 0) {
            error = EINVAL;
        } else {
            envp[0] = NULL;
        }
    }
    if (error != 0) return -(long)error;

    unsigned modes[3];
    int children[3] = { -1, -1, -1 };
    for (int i = 0; i < 3; i++) {
        modes[i] = (unsigned)(setup >> (2 * i)) & 3U;
        if (modes[i] > LINEA_PROCESS_PIPE) return -(long)EINVAL;
    }
    for (int i = 0; i < 3 && error == 0; i++) {
        if (modes[i] == LINEA_PROCESS_PIPE) error = open_pipe(i != 0, parents[i], &children[i]);
    }

    posix_spawn_file_actions_t actions;
    posix_spawnattr_t attributes;
    int actions_made = 0, attributes_made = 0;
    if (error == 0) {
        error = posix_spawn_file_actions_init(&actions);
        actions_made = error == 0;
    }
    if (error == 0) {
        error = posix_spawnattr_init(&attributes);
        attributes_made = error == 0;
    }
    for (int i = 0; i < 3 && error == 0; i++) error = stream_action(&actions, i, modes[i], children[i]);
    if (error == 0 && directory_extent != 0) {
        const char *path = (const char *)(uintptr_t)directory_at;
#if defined(__linux__)
        error = posix_spawn_file_actions_addchdir_np == NULL ? ENOTSUP : posix_spawn_file_actions_addchdir_np(&actions, path);
#else
        error = posix_spawn_file_actions_addchdir_np(&actions, path);
#endif
    }
#if defined(__linux__)
    if (error == 0) error = close_inherited(&actions);
#endif
    if (error == 0) {
        /* The child starts with no signal blocked: the runtime blocks SIGPIPE
         * on its threads, and a blocked signal survives exec. Dispositions are
         * left as the system sets them across exec, so a signal this process
         * was started ignoring stays ignored in the child. */
        sigset_t empty;
        sigemptyset(&empty);
        error = posix_spawnattr_setsigmask(&attributes, &empty);
    }
    if (error == 0) {
        short flags = POSIX_SPAWN_SETSIGMASK;
#if defined(__APPLE__)
        flags = (short)(flags | POSIX_SPAWN_CLOEXEC_DEFAULT);
#endif
        error = posix_spawnattr_setflags(&attributes, flags);
    }
    pid_t pid = -1;
    if (error == 0) {
        /* posix_spawn reports a program that cannot be executed as its
         * error, on glibc and on macOS alike, and is not interrupted by
         * signals. `(strchr)` names the function rather than the macro newer
         * glibc headers define with C11's `_Generic`. */
        error = (strchr)(argv[0], '/') != NULL
            ? posix_spawn(&pid, argv[0], &actions, &attributes, argv, envp)
            : posix_spawnp(&pid, argv[0], &actions, &attributes, argv, envp);
    }
    if (actions_made) posix_spawn_file_actions_destroy(&actions);
    if (attributes_made) posix_spawnattr_destroy(&attributes);
    for (int i = 0; i < 3; i++) {
        if (children[i] >= 0) close(children[i]);
        if (error != 0 && *parents[i] >= 0) {
            close(*parents[i]);
            *parents[i] = -1;
        }
    }
    return error != 0 ? -(long)error : (long)pid;
}

/* 0 with the exit code, or 1 with the signal's number, from a status
 * waitpid wrote, or 2 for a child that only stopped or continued, as a
 * traced child is reported even to a wait that did not ask, and has not
 * ended. */
static long decode(int raw, unsigned long *status) {
    if (WIFEXITED(raw)) {
        *status = (unsigned long)WEXITSTATUS(raw);
        return 0;
    }
    if (WIFSIGNALED(raw)) {
        *status = (unsigned long)WTERMSIG(raw);
        return 1;
    }
    return 2;
}

/* Block the calling thread until `pid` ends, and reap it. */
static long wait_in_place(int pid, unsigned long *status) {
    for (;;) {
        int raw = 0;
        pid_t answered;
        do {
            answered = waitpid((pid_t)pid, &raw, 0);
        } while (answered < 0 && errno == EINTR);
        if (answered < 0) return -(long)errno;
        const long ended = decode(raw, status);
        if (ended != 2) return ended;
    }
}

/* A descriptor that becomes readable once `pid` ends: a pidfd on Linux, a
 * kqueue watching the process on macOS. -ESRCH means the child has already
 * ended; -ENOSYS that the kernel offers no such descriptor. */
static long exit_descriptor(int pid) {
#if defined(__linux__)
    /* pidfd_open answers a close-on-exec descriptor. */
    const long fd = syscall(SYS_pidfd_open, pid, 0);
    return fd < 0 ? -(long)errno : fd;
#elif defined(__APPLE__)
    const int queue = kqueue();
    if (queue < 0) return -(long)errno;
    if (fcntl(queue, F_SETFD, FD_CLOEXEC) != 0) {
        const int error = errno;
        close(queue);
        return -(long)error;
    }
    struct kevent change;
    EV_SET(&change, (uintptr_t)pid, EVFILT_PROC, EV_ADD | EV_ONESHOT, NOTE_EXIT, 0, NULL);
    int registered;
    do {
        registered = kevent(queue, &change, 1, NULL, 0, NULL);
    } while (registered < 0 && errno == EINTR);
    if (registered < 0) {
        const int error = errno;
        close(queue);
        return -(long)error;
    }
    return queue;
#else
#error "waiting for a child on a fiber requires Linux pidfds or macOS kqueue"
#endif
}

/* A wait fails only where waitpid itself does, when the child is not this
 * process's to reap (ECHILD): every other failure on the way, such as no
 * descriptor left for a pidfd or a kqueue, or a parking that could not be
 * armed, falls back to the blocking wait, which holds the carrier but still
 * reaps the child. */
long linea_process_wait(int pid, unsigned long *status) {
    if (pid <= 0) return -(long)EINVAL;
    refuse_simulated();
    if (!linea_fiber_active()) return wait_in_place(pid, status);
    for (;;) {
        int raw = 0;
        pid_t answered;
        do {
            answered = waitpid((pid_t)pid, &raw, WNOHANG);
        } while (answered < 0 && errno == EINTR);
        if (answered < 0) return -(long)errno;
        if (answered == (pid_t)pid) {
            const long ended = decode(raw, status);
            if (ended != 2) return ended;
            continue;
        }
        const long fd = exit_descriptor(pid);
        if (fd == -(long)ESRCH) {
            /* macOS reports the exit before the zombie can be reaped; sleep
             * a millisecond, parked, rather than spin on the carrier. */
            const long slept = linea_fiber_sleep(1000000UL);
            if (slept < 0) return wait_in_place(pid, status);
            continue;
        }
        if (fd < 0) return wait_in_place(pid, status);
        const long woke = linea_fiber_wait_descriptor((int)fd, 0, 0);
        close((int)fd);
        if (woke < 0) return wait_in_place(pid, status);
    }
}

long linea_process_kill(int pid) {
    if (pid <= 0) return -(long)EINVAL;
    refuse_simulated();
    if (children_reaped_by_kernel()) return -(long)ECHILD;
    /* kill does not block; Linux and macOS document no EINTR for it. */
    return kill((pid_t)pid, SIGKILL) == 0 ? 0 : -(long)errno;
}

/* Wait until `fd` is ready to read, or to write when `writable` is set. */
static long wait_ready(int fd, int writable) {
    if (linea_fiber_active()) {
        const long woke = linea_fiber_wait_descriptor(fd, (uint8_t)writable, 0);
        return woke < 0 ? woke : 0;
    }
    struct pollfd entry = { fd, (short)(writable ? POLLOUT : POLLIN), 0 };
    int ready;
    do {
        ready = poll(&entry, 1, -1);
    } while (ready < 0 && (errno == EINTR || errno == EAGAIN));
    return ready < 0 ? -(long)errno : 0;
}

/* Read or write once the pipe is ready. The transfer itself is the ordinary
 * descriptor transfer, which retries EINTR and turns a write's SIGPIPE into
 * -EPIPE; on the nonblocking end it answers -EAGAIN until the pipe is ready. */
static long transfer(int fd, unsigned long at, unsigned long len, int writing) {
    refuse_simulated();
    const int invalid = linea_io_byte_range(at, len);
    if (invalid != 0) return -(long)invalid;
    if (len == 0) return 0;
    for (;;) {
        long answer = writing ? linea_write_some(fd, at, len) : linea_read_some(fd, at, len);
#if EWOULDBLOCK != EAGAIN
        if (answer == -(long)EWOULDBLOCK) answer = -(long)EAGAIN;
#endif
        if (answer != -(long)EAGAIN) return answer;
        const long waited = wait_ready(fd, writing);
        if (waited < 0) return waited;
    }
}

long linea_pipe_read(int fd, unsigned long at, unsigned long len) {
    return transfer(fd, at, len, 0);
}

long linea_pipe_write(int fd, unsigned long at, unsigned long len) {
    return transfer(fd, at, len, 1);
}
