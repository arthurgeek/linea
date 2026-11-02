#define _GNU_SOURCE
#include "io.h"

#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <pthread.h>
#include <signal.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/random.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <unistd.h>
#if defined(__linux__)
#include <sys/syscall.h>
#endif

/* The runtime's scalar address ABI targets LP64 Linux and macOS. */
typedef char linea_address_fits_pointer[(sizeof(unsigned long) == sizeof(void *)) ? 1 : -1];
typedef char linea_count_fits_long[(sizeof(long) == 8) ? 1 : -1];

uint8_t linea_io_category(int code) {
    switch (code) {
    case ENOENT: return LINEA_IO_NOT_FOUND;
    case EPERM: case EACCES: return LINEA_IO_PERMISSION_DENIED;
    case EEXIST: return LINEA_IO_ALREADY_EXISTS;
    case EAGAIN: return LINEA_IO_WOULD_BLOCK;
#if EWOULDBLOCK != EAGAIN
    case EWOULDBLOCK: return LINEA_IO_WOULD_BLOCK;
#endif
    case EPIPE: return LINEA_IO_BROKEN_PIPE;
    case EINTR: return LINEA_IO_INTERRUPTED;
    case EINVAL: case EFAULT: case EOVERFLOW: return LINEA_IO_INVALID_INPUT;
    case ENOTDIR: return LINEA_IO_NOT_DIRECTORY;
    case EISDIR: return LINEA_IO_IS_DIRECTORY;
    case ENOSYS: case ENOTSUP: return LINEA_IO_UNSUPPORTED;
    case ENOSPC: return LINEA_IO_NO_SPACE;
    case ENOMEM: case EMFILE: case ENFILE: return LINEA_IO_RESOURCE_EXHAUSTED;
    case ELOOP: return LINEA_IO_SYMLINK;
    case EBADF: return LINEA_IO_INVALID_DESCRIPTOR;
    case ETIMEDOUT: return LINEA_IO_TIMED_OUT;
    /* The connection was torn down before the operation finished, by the
     * peer or by the local stack; accept reports a queued connection that
     * went away before it was taken as ECONNABORTED. */
    case ECONNRESET: case ECONNABORTED: return LINEA_IO_CONNECTION_RESET;
    case ECONNREFUSED: return LINEA_IO_CONNECTION_REFUSED;
    case EADDRINUSE: return LINEA_IO_ADDRESS_IN_USE;
    default: return LINEA_IO_OTHER;
    }
}

int linea_errno(void) {
    return errno;
}

/* Defined with the allocator. Under the checking allocator it aborts where
 * the bytes were freed or reach outside their allocation; otherwise it
 * returns. */
void linea_storage_extent(unsigned long at, unsigned long len);

/* Validates the bytes a program hands a system call, and hands them to the
 * allocator first, so the call never meets storage the program does not own. */
static int byte_range(unsigned long at, unsigned long len) {
    if (len == 0) return 0;
    if (at == 0) return EFAULT;
    if (len > (unsigned long)LONG_MAX || len > ULONG_MAX - at) return EOVERFLOW;
    linea_storage_extent(at, len);
    return 0;
}

long linea_read_some(int fd, unsigned long at, unsigned long len) {
    const int invalid = byte_range(at, len);
    if (invalid != 0) return -(long)invalid;
    if (len == 0) return 0;
    ssize_t count;
    do {
        count = read(fd, (void *)(uintptr_t)at, (size_t)len);
    } while (count < 0 && errno == EINTR);
    return count < 0 ? -(long)errno : (long)count;
}

#if defined(F_SETNOSIGPIPE)
/* macOS raises the SIGPIPE of a write to a pipe or socket with no reader on
 * the process, which hands it to any thread that does not block it, so
 * blocking it on the writing thread, as Linux allows, does not keep it from
 * ending the process. A write there raises nothing in the first place.
 *
 * A socket is written with `send` and `MSG_NOSIGNAL`, which changes nothing
 * another writer sees. A pipe has no such call: its open file's
 * `F_SETNOSIGPIPE` setting is set for the write, if it was clear, and cleared
 * again after. The setting belongs to the open file, so while the write runs
 * a write by another process sharing the file, or by host code on another
 * thread, answers EPIPE without SIGPIPE too.
 *
 * Writes this runtime has in progress on a pipe are recorded below, by the
 * pipe's device and inode, so overlapping writes to one pipe, through one
 * descriptor or several sharing its open file, leave the setting set until
 * the last of them ends; clearing it after the first would let another's
 * write raise SIGPIPE. A pipe opened twice by name, as two open files with one
 * inode, is taken as one: the last write to end clears the setting through
 * its own descriptor. The table holds one entry per write in progress, so
 * its length is bounded by the threads writing at once.
 *
 * The cost is an `fstat` per write, and on a pipe three `fcntl` calls and
 * two lock operations: a 64-byte pipe write takes about 1.4 us this way
 * against 0.3 us for `write` alone on an Apple M-series machine. */
struct pipe_write {
    dev_t device;
    ino_t inode;
    /* Whether this write is one of those that keep the setting this runtime
     * made, rather than one that found it set by someone else. */
    int keeps_setting;
};

static pthread_mutex_t pipe_writes_lock = PTHREAD_MUTEX_INITIALIZER;
static struct pipe_write *pipe_writes = 0;
static size_t pipe_write_count = 0;
static size_t pipe_write_capacity = 0;

/* Whether a recorded write to the pipe `device`/`inode` keeps a setting this
 * runtime made. Called with `pipe_writes_lock` held. */
static int setting_kept(dev_t device, ino_t inode) {
    for (size_t i = 0; i < pipe_write_count; i += 1) {
        if (pipe_writes[i].device == device && pipe_writes[i].inode == inode && pipe_writes[i].keeps_setting) return 1;
    }
    return 0;
}

static void must_lock(int status) {
    if (status != 0) abort();
}

/* Records a write to `fd`, the pipe `device`/`inode`, setting its
 * `F_SETNOSIGPIPE` if it is clear, and stores in `keeps` whether the write
 * keeps a setting this runtime made. Answers zero, or the errno that kept the
 * write from being made quiet. */
static int begin_pipe_write(int fd, dev_t device, ino_t inode, int *keeps) {
    must_lock(pthread_mutex_lock(&pipe_writes_lock));
    int error = 0;
    if (pipe_write_count == pipe_write_capacity) {
        const size_t capacity = pipe_write_capacity == 0 ? 8 : pipe_write_capacity * 2;
        struct pipe_write *grown = realloc(pipe_writes, capacity * sizeof *grown);
        if (grown == 0) {
            error = ENOMEM;
        } else {
            pipe_writes = grown;
            pipe_write_capacity = capacity;
        }
    }
    *keeps = 0;
    if (error == 0) {
        const int set = fcntl(fd, F_GETNOSIGPIPE);
        if (set < 0) {
            error = errno;
        } else if (set == 0) {
            if (fcntl(fd, F_SETNOSIGPIPE, 1) != 0) error = errno;
            *keeps = 1;
        } else {
            *keeps = setting_kept(device, inode);
        }
    }
    if (error == 0) pipe_writes[pipe_write_count++] = (struct pipe_write){device, inode, *keeps};
    must_lock(pthread_mutex_unlock(&pipe_writes_lock));
    return error;
}

/* Removes a write `begin_pipe_write` recorded, and clears the setting this
 * runtime made once no other write keeps it. A clear that fails leaves the
 * setting in place, which only spares later writes their SIGPIPE. */
static void end_pipe_write(int fd, dev_t device, ino_t inode, int keeps) {
    must_lock(pthread_mutex_lock(&pipe_writes_lock));
    for (size_t i = 0; i < pipe_write_count; i += 1) {
        const struct pipe_write *w = &pipe_writes[i];
        if (w->device != device || w->inode != inode || w->keeps_setting != keeps) continue;
        pipe_writes[i] = pipe_writes[--pipe_write_count];
        break;
    }
    if (keeps && !setting_kept(device, inode)) (void)fcntl(fd, F_SETNOSIGPIPE, 0);
    must_lock(pthread_mutex_unlock(&pipe_writes_lock));
}

/* Writes without raising SIGPIPE, answering the count or a negated errno. */
static long write_quietly(int fd, const void *bytes, size_t len) {
    struct stat status;
    if (fstat(fd, &status) != 0) return -(long)errno;
    ssize_t written;
    if (S_ISSOCK(status.st_mode)) {
        do {
            written = send(fd, bytes, len, MSG_NOSIGNAL);
        } while (written < 0 && errno == EINTR);
        return written < 0 ? -(long)errno : (long)written;
    }
    const int is_pipe = S_ISFIFO(status.st_mode);
    int keeps = 0;
    if (is_pipe) {
        const int error = begin_pipe_write(fd, status.st_dev, status.st_ino, &keeps);
        if (error != 0) return -(long)error;
    }
    do {
        written = write(fd, bytes, len);
    } while (written < 0 && errno == EINTR);
    const long answer = written < 0 ? -(long)errno : (long)written;
    if (is_pipe) end_pipe_write(fd, status.st_dev, status.st_ino, keeps);
    return answer;
}
#endif

long linea_write_some(int fd, unsigned long at, unsigned long len) {
    const int invalid = byte_range(at, len);
    if (invalid != 0) return -(long)invalid;
    if (len == 0) return 0;

#if defined(F_SETNOSIGPIPE)
    return write_quietly(fd, (const void *)(uintptr_t)at, (size_t)len);
#else
    struct sigaction action;
    if (sigaction(SIGPIPE, NULL, &action) == 0 && action.sa_handler == SIG_IGN) {
        ssize_t count;
        do {
            count = write(fd, (const void *)(uintptr_t)at, (size_t)len);
        } while (count < 0 && errno == EINTR);
        return count < 0 ? -(long)errno : (long)count;
    }

    sigset_t blocked, previous, pending;
    if (sigemptyset(&blocked) != 0 || sigaddset(&blocked, SIGPIPE) != 0) abort();
    const int mask_error = pthread_sigmask(SIG_BLOCK, &blocked, &previous);
    if (mask_error != 0) return -(long)mask_error;
    if (sigpending(&pending) != 0) {
        const int error = errno;
        if (pthread_sigmask(SIG_SETMASK, &previous, NULL) != 0) abort();
        return -(long)error;
    }
    const int already_pending = sigismember(&pending, SIGPIPE);
    ssize_t count;
    do {
        count = write(fd, (const void *)(uintptr_t)at, (size_t)len);
    } while (count < 0 && errno == EINTR);
    const int error = count < 0 ? errno : 0;

    /* A blocked standard signal coalesces with one already pending. Consume
     * only a newly generated SIGPIPE; ignored signals need no consumption. */
    if (error == EPIPE && already_pending == 0) {
        if (sigpending(&pending) != 0) abort();
        if (sigismember(&pending, SIGPIPE) == 1) {
            int received;
            int wait_error;
            do {
                wait_error = sigwait(&blocked, &received);
            } while (wait_error == EINTR);
            if (wait_error != 0 || received != SIGPIPE) abort();
        }
    }
    /* These calls use sets returned by the same APIs. Failure would violate
     * the runtime contract; reporting it as I/O would lose accepted bytes. */
    if (pthread_sigmask(SIG_SETMASK, &previous, NULL) != 0) abort();
    return error != 0 ? -(long)error : (long)count;
#endif
}

long linea_read_at(int fd, unsigned long at, unsigned long len, unsigned long offset) {
    const int invalid = byte_range(at, len);
    if (invalid != 0) return -(long)invalid;
    if (len == 0) return 0;
    if (offset > (unsigned long)INT64_MAX) return -(long)EOVERFLOW;
    ssize_t count;
    do {
        count = pread(fd, (void *)(uintptr_t)at, (size_t)len, (off_t)offset);
    } while (count < 0 && errno == EINTR);
    return count < 0 ? -(long)errno : (long)count;
}

long linea_write_at(int fd, unsigned long at, unsigned long len, unsigned long offset) {
    const int invalid = byte_range(at, len);
    if (invalid != 0) return -(long)invalid;
    if (len == 0) return 0;
    if (offset > (unsigned long)INT64_MAX) return -(long)EOVERFLOW;
    ssize_t count;
    do {
        count = pwrite(fd, (const void *)(uintptr_t)at, (size_t)len, (off_t)offset);
    } while (count < 0 && errno == EINTR);
    return count < 0 ? -(long)errno : (long)count;
}

long linea_close(int fd) {
    /* close is not retried after EINTR: POSIX leaves the descriptor's fate
     * unspecified in that case, and this runtime's supported kernels remove
     * it before reporting close errors, EINTR included, so a retry could
     * close an unrelated descriptor that already reused the number. */
    return close(fd) == 0 ? 0 : -(long)errno;
}

long linea_random_bytes(unsigned long at, unsigned long len) {
    const int invalid = byte_range(at, len);
    if (invalid != 0) return -(long)invalid;
    if (len == 0) return 0;
    /* Both supported platforms provide getentropy with a 256-byte limit. */
    const unsigned long entropy_limit = 256;
    const unsigned long count = len < entropy_limit ? len : entropy_limit;
    int result;
    do {
        result = getentropy((void *)(uintptr_t)at, (size_t)count);
    } while (result != 0 && errno == EINTR);
    return result == 0 ? (long)count : -(long)errno;
}

long linea_random_words(unsigned long *high, unsigned long *low) {
    uint64_t words[2];
    int result;
    do {
        result = getentropy(words, sizeof(words));
    } while (result != 0 && errno == EINTR);
    if (result != 0) return -(long)errno;
    *high = (unsigned long)words[0];
    *low = (unsigned long)words[1];
    return 0;
}

/* `(memchr)` names the function rather than the macro newer glibc headers
 * define with C11's `_Generic`, which this C99 source may not use. */
static int path_bytes(unsigned long at, unsigned long extent, int component) {
    const int invalid = byte_range(at, extent);
    if (invalid != 0) return invalid;
    if (extent < 2) return EINVAL;
    const char *path = (const char *)(uintptr_t)at;
    if (path[extent - 1] != '\0' || (memchr)(path, '\0', (size_t)(extent - 1)) != NULL) return EINVAL;
    if (component && ((memchr)(path, '/', (size_t)(extent - 1)) != NULL ||
                      strcmp(path, ".") == 0 || strcmp(path, "..") == 0)) return EINVAL;
    return 0;
}

long linea_open_parent(unsigned long at, unsigned long extent) {
    const int invalid = path_bytes(at, extent, 0);
    if (invalid != 0) return -(long)invalid;
    /* Relative file operations require search access, not directory listing. */
#if defined(__linux__)
    const int flags = O_PATH | O_DIRECTORY | O_CLOEXEC;
#elif defined(__APPLE__)
    const int flags = O_SEARCH | O_CLOEXEC;
#else
#error "directory anchors require Linux O_PATH or macOS O_SEARCH"
#endif
    int fd;
    do {
        fd = open((const char *)(uintptr_t)at, flags);
    } while (fd < 0 && errno == EINTR);
    return fd < 0 ? -(long)errno : (long)fd;
}

long linea_open_at(int parent, unsigned long at, unsigned long extent,
                   uint8_t policy, unsigned long mode) {
    const int invalid = path_bytes(at, extent, 1);
    if (invalid != 0) return -(long)invalid;
    if (policy > 2 || mode > 0777) return -EINVAL;
    int flags = O_CLOEXEC;
    switch (policy) {
        case 0: flags |= O_RDONLY; break;
        case 1: flags |= O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW; break;
        case 2: flags |= O_WRONLY | O_CREAT | O_TRUNC | O_NOFOLLOW; break;
        default: abort();
    }
    int fd;
    do {
        fd = openat(parent, (const char *)(uintptr_t)at, flags, (mode_t)mode);
    } while (fd < 0 && errno == EINTR);
    return fd < 0 ? -(long)errno : (long)fd;
}

long linea_mode_at(int parent, unsigned long at, unsigned long extent) {
    const int invalid = path_bytes(at, extent, 1);
    if (invalid != 0) return -(long)invalid;
    struct stat info;
    int result;
    do {
        result = fstatat(parent, (const char *)(uintptr_t)at, &info, AT_SYMLINK_NOFOLLOW);
    } while (result != 0 && errno == EINTR);
    if (result != 0) return -(long)errno;
    if (S_ISLNK(info.st_mode)) return -ELOOP;
    if (!S_ISREG(info.st_mode)) return -EINVAL;
    return (long)(info.st_mode & 0777);
}

long linea_set_mode(int fd, unsigned long mode) {
    if (mode > 0777) return -EINVAL;
    int result;
    do {
        result = fchmod(fd, (mode_t)mode);
    } while (result != 0 && errno == EINTR);
    return result == 0 ? 0 : -(long)errno;
}

long linea_publish_at(int parent, unsigned long from, unsigned long from_extent,
                      unsigned long to, unsigned long to_extent, uint8_t replace) {
    int invalid = path_bytes(from, from_extent, 1);
    if (invalid == 0) invalid = path_bytes(to, to_extent, 1);
    if (invalid != 0) return -(long)invalid;
    if (replace > 1) return -EINVAL;
    const char *source = (const char *)(uintptr_t)from;
    const char *destination = (const char *)(uintptr_t)to;
    int result;
    if (replace == 1) {
        /* renameat does not block; Linux and macOS document no EINTR for it. */
        result = renameat(parent, source, parent, destination);
    } else {
#if defined(__APPLE__)
        /* renameatx_np does not block; macOS documents no EINTR for it. */
        result = renameatx_np(parent, source, parent, destination, RENAME_EXCL);
#elif defined(__linux__) && defined(SYS_renameat2)
        /* RENAME_NOREPLACE is bit zero in the Linux renameat2 ABI.
         * renameat2 does not block; Linux documents no EINTR for it. */
        const unsigned int no_replace = 1U;
        result = (int)syscall(SYS_renameat2, parent, source, parent, destination, no_replace);
#else
        return -ENOTSUP;
#endif
    }
    return result == 0 ? 0 : -(long)errno;
}

long linea_unlink_at(int parent, unsigned long at, unsigned long extent) {
    const int invalid = path_bytes(at, extent, 1);
    if (invalid != 0) return -(long)invalid;
    /* unlinkat does not block; Linux and macOS document no EINTR for it. */
    return unlinkat(parent, (const char *)(uintptr_t)at, 0) == 0 ? 0 : -(long)errno;
}
