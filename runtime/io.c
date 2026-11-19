#define _GNU_SOURCE
#include "io.h"
#include "pipe_signal.h"

#include <dirent.h>
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
#include <sys/resource.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <unistd.h>
#if defined(__linux__)
#include <sys/syscall.h>
#endif
#if defined(__APPLE__)
#include <sys/sysctl.h>
#endif

/* The fault tests read directories through a stand-in that is interrupted
 * once. It is named here rather than by renaming `readdir` on the command
 * line, because macOS's <dirent.h> binds `readdir` to its 64-bit inode
 * symbol through an asm label that a rename would not reach. */
#ifdef LINEA_READDIR
struct dirent *LINEA_READDIR(DIR *dir);
#else
#define LINEA_READDIR readdir
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
    case ENAMETOOLONG: return LINEA_IO_NAME_TOO_LONG;
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
int linea_io_byte_range(unsigned long at, unsigned long len) {
    if (len == 0) return 0;
    if (at == 0) return EFAULT;
    if (len > (unsigned long)LONG_MAX || len > ULONG_MAX - at) return EOVERFLOW;
    linea_storage_extent(at, len);
    return 0;
}

long linea_read_some(int fd, unsigned long at, unsigned long len) {
    const int invalid = linea_io_byte_range(at, len);
    if (invalid != 0) return -(long)invalid;
    if (len == 0) return 0;
    ssize_t count;
    do {
        count = read(fd, (void *)(uintptr_t)at, (size_t)len);
    } while (count < 0 && errno == EINTR);
    return count < 0 ? -(long)errno : (long)count;
}

long linea_write_some(int fd, unsigned long at, unsigned long len) {
    const int invalid = linea_io_byte_range(at, len);
    if (invalid != 0) return -(long)invalid;
    if (len == 0) return 0;
    const void *bytes = (const void *)(uintptr_t)at;

    /* A socket raises no SIGPIPE through `send` with `MSG_NOSIGNAL`. */
    ssize_t count;
    do {
        count = send_without_signal(fd, bytes, (size_t)len);
    } while (count < 0 && errno == EINTR);
    if (count >= 0 || errno != ENOTSOCK) return count < 0 ? -(long)errno : (long)count;

    /* Any other descriptor is written with SIGPIPE blocked on this thread,
     * as `pipe_signal.h` describes. An ignored SIGPIPE needs no block. */
    struct sigaction action;
    if (sigaction(SIGPIPE, NULL, &action) == 0 && action.sa_handler == SIG_IGN) {
        do {
            count = write(fd, bytes, (size_t)len);
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
    do {
        count = write(fd, bytes, (size_t)len);
    } while (count < 0 && errno == EINTR);
    const int error = count < 0 ? errno : 0;

    /* A blocked standard signal merges with one already pending, so only a
     * SIGPIPE this write left pending on this thread is taken. On macOS the
     * write's SIGPIPE may be pending on another thread instead, which blocks
     * it for good in a Linea program. */
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
}

long linea_read_at(int fd, unsigned long at, unsigned long len, unsigned long offset) {
    const int invalid = linea_io_byte_range(at, len);
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
    const int invalid = linea_io_byte_range(at, len);
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
    const int invalid = linea_io_byte_range(at, len);
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
    const int invalid = linea_io_byte_range(at, extent);
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

long linea_make_dir_at(int parent, unsigned long at, unsigned long extent, unsigned long mode) {
    const int invalid = path_bytes(at, extent, 1);
    if (invalid != 0) return -(long)invalid;
    if (mode > 0777) return -EINVAL;
    /* mkdirat does not block on a local file system; neither platform
     * documents EINTR for it. */
    return mkdirat(parent, (const char *)(uintptr_t)at, (mode_t)mode) == 0 ? 0 : -(long)errno;
}

long linea_remove_dir_at(int parent, unsigned long at, unsigned long extent) {
    const int invalid = path_bytes(at, extent, 1);
    if (invalid != 0) return -(long)invalid;
    return unlinkat(parent, (const char *)(uintptr_t)at, AT_REMOVEDIR) == 0 ? 0 : -(long)errno;
}

long linea_symlink_at(int parent, unsigned long at, unsigned long extent,
                      unsigned long target_at, unsigned long target_extent) {
    int invalid = path_bytes(at, extent, 1);
    if (invalid == 0) invalid = path_bytes(target_at, target_extent, 0);
    if (invalid != 0) return -(long)invalid;
    return symlinkat((const char *)(uintptr_t)target_at, parent, (const char *)(uintptr_t)at) == 0 ? 0 : -(long)errno;
}

/* Open `name` relative to `parent` (AT_FDCWD for a path) as a directory and
 * wrap it in a stream, closing the descriptor when the wrap fails. */
static long open_stream(int parent, const char *name, uint8_t follow, unsigned long *stream) {
    if (follow > 1) return -EINVAL;
    const int flags = O_RDONLY | O_DIRECTORY | O_CLOEXEC | (follow ? 0 : O_NOFOLLOW);
    int fd;
    do {
        fd = openat(parent, name, flags);
    } while (fd < 0 && errno == EINTR);
    if (fd < 0) return -(long)errno;
    DIR *dir = fdopendir(fd);
    if (dir == NULL) {
        const int error = errno;
        close(fd);
        return -(long)error;
    }
    *stream = (unsigned long)(uintptr_t)dir;
    return 0;
}

long linea_dir_open(unsigned long at, unsigned long extent, uint8_t follow, unsigned long *stream) {
    const int invalid = path_bytes(at, extent, 0);
    if (invalid != 0) return -(long)invalid;
    return open_stream(AT_FDCWD, (const char *)(uintptr_t)at, follow, stream);
}

long linea_dir_open_at(unsigned long parent, unsigned long at, unsigned long extent,
                       uint8_t follow, unsigned long *stream) {
    const int invalid = path_bytes(at, extent, 1);
    if (invalid != 0) return -(long)invalid;
    DIR *dir = (DIR *)(uintptr_t)parent;
    return open_stream(dirfd(dir), (const char *)(uintptr_t)at, follow, stream);
}

static uint64_t entry_kind(mode_t mode) {
    if (S_ISREG(mode)) return 0;
    if (S_ISDIR(mode)) return 1;
    if (S_ISLNK(mode)) return 2;
    return 3;
}

static uint64_t listed_kind(unsigned char type) {
    switch (type) {
    case DT_REG: return 0;
    case DT_DIR: return 1;
    case DT_LNK: return 2;
    default: return 3;
    }
}

long linea_dir_next(unsigned long stream, unsigned long at, unsigned long len, uint8_t follow) {
    const int invalid = linea_io_byte_range(at, len);
    if (invalid != 0) return -(long)invalid;
    if (len < LINEA_DIR_RECORD_BYTES || follow > 1) return -EINVAL;
    DIR *dir = (DIR *)(uintptr_t)stream;
    struct dirent *entry;
    for (;;) {
        /* readdir answers NULL both at the end, leaving errno alone, and on
         * failure, so errno is cleared first; an interrupted read is tried
         * again, as every other blocking call here is. */
        do {
            errno = 0;
            entry = LINEA_READDIR(dir);
        } while (entry == NULL && errno == EINTR);
        if (entry == NULL) return errno == 0 ? 0 : -(long)errno;
        if (strcmp(entry->d_name, ".") != 0 && strcmp(entry->d_name, "..") != 0) break;
    }
    const size_t name_length = strlen(entry->d_name);
    if (name_length > len - LINEA_DIR_RECORD_HEADER) return -ENAMETOOLONG;
    uint64_t words[6] = {0};
    struct stat info;
    int result;
    do {
        result = fstatat(dirfd(dir), entry->d_name, &info, follow ? 0 : AT_SYMLINK_NOFOLLOW);
    } while (result != 0 && errno == EINTR);
    if (result != 0) {
        words[0] = listed_kind(entry->d_type);
        words[5] = (uint64_t)errno;
    } else {
        words[0] = entry_kind(info.st_mode);
        words[1] = (uint64_t)(info.st_mode & 07777);
        words[2] = (uint64_t)info.st_size;
#if defined(__APPLE__)
        words[3] = (uint64_t)(int64_t)info.st_mtimespec.tv_sec;
        words[4] = (uint64_t)info.st_mtimespec.tv_nsec;
#else
        words[3] = (uint64_t)(int64_t)info.st_mtim.tv_sec;
        words[4] = (uint64_t)info.st_mtim.tv_nsec;
#endif
    }
    char *record = (char *)(uintptr_t)at;
    memcpy(record, words, sizeof(words));
    memcpy(record + LINEA_DIR_RECORD_HEADER, entry->d_name, name_length);
    return (long)name_length;
}

/* Whether `name` is one component: not empty, no slash, and neither "." nor "..". */
static int single_component(const char *name) {
    return name[0] != '\0' && strchr(name, '/') == NULL && strcmp(name, ".") != 0 && strcmp(name, "..") != 0;
}

long linea_dir_reopen(unsigned long anchor, unsigned long names_at, unsigned long names_extent,
                      unsigned long identities_at, unsigned long identities_extent,
                      uint8_t follow, unsigned long *failed, unsigned long *stream) {
    int invalid = linea_io_byte_range(names_at, names_extent);
    if (invalid == 0) invalid = linea_io_byte_range(identities_at, identities_extent);
    if (invalid != 0) return -(long)invalid;
    if (follow > 1 || names_extent == 0 || identities_extent % (2 * sizeof(uint64_t)) != 0) return -EINVAL;
    const char *names = (const char *)(uintptr_t)names_at;
    if (names[names_extent - 1] != '\0') return -EINVAL;
    unsigned long count = 0;
    for (unsigned long i = 0; i < names_extent; i++) {
        if (names[i] == '\0') count++;
    }
    if (count != identities_extent / (2 * sizeof(uint64_t)) + 1) return -EINVAL;
    const unsigned char *identities = (const unsigned char *)(uintptr_t)identities_at;
    const int flags = O_RDONLY | O_DIRECTORY | O_CLOEXEC | (follow ? 0 : O_NOFOLLOW);
    int current = dirfd((DIR *)(uintptr_t)anchor);
    int owned = -1;
    const char *name = names;
    for (unsigned long index = 0;; index++) {
        if (!single_component(name)) {
            if (owned >= 0) close(owned);
            return -EINVAL;
        }
        int fd;
        do {
            fd = openat(current, name, flags);
        } while (fd < 0 && errno == EINTR);
        if (fd < 0) {
            const int error = errno;
            if (owned >= 0) close(owned);
            *failed = index;
            return -(long)error;
        }
        if (owned >= 0) close(owned);
        owned = fd;
        current = fd;
        if (index + 1 == count) break;
        uint64_t want[2];
        memcpy(want, identities + index * sizeof(want), sizeof(want));
        struct stat info;
        int result;
        do {
            result = fstat(fd, &info);
        } while (result != 0 && errno == EINTR);
        if (result != 0) {
            const int error = errno;
            close(owned);
            *failed = index;
            return -(long)error;
        }
        if ((unsigned long)info.st_dev != want[0] || (unsigned long)info.st_ino != want[1]) {
            close(owned);
            *failed = index;
            return 1;
        }
        name += strlen(name) + 1;
    }
    DIR *dir = fdopendir(owned);
    if (dir == NULL) {
        const int error = errno;
        close(owned);
        *failed = count - 1;
        return -(long)error;
    }
    *stream = (unsigned long)(uintptr_t)dir;
    return 0;
}

long linea_dir_open_up(unsigned long stream, unsigned long *parent) {
    return open_stream(dirfd((DIR *)(uintptr_t)stream), "..", 1, parent);
}

long linea_dir_identity(unsigned long stream, unsigned long *device, unsigned long *inode) {
    struct stat info;
    int result;
    do {
        result = fstat(dirfd((DIR *)(uintptr_t)stream), &info);
    } while (result != 0 && errno == EINTR);
    if (result != 0) return -(long)errno;
    *device = (unsigned long)info.st_dev;
    *inode = (unsigned long)info.st_ino;
    return 0;
}

long linea_dir_close(unsigned long stream) {
    /* closedir is not retried after EINTR, for the reason close is not. */
    return closedir((DIR *)(uintptr_t)stream) == 0 ? 0 : -(long)errno;
}

/* An unlimited hard limit is capped here on a system that names no smaller
 * cap of its own. 2^20 is a choice, not a guarantee: it is Linux's default
 * `fs.nr_open`, which an administrator may set lower, and then raising the
 * soft limit this far fails with the errno `setrlimit` gives. */
static const rlim_t linea_most_open_files = (rlim_t)1 << 20;

long linea_raise_open_files(void) {
    struct rlimit limit;
    if (getrlimit(RLIMIT_NOFILE, &limit) != 0) return -(long)errno;
    rlim_t ceiling = limit.rlim_max;
    if (ceiling == RLIM_INFINITY) ceiling = linea_most_open_files;
#if defined(__APPLE__)
    /* macOS refuses a soft limit above `kern.maxfilesperproc`, which its
     * hard limit, often unlimited, does not reflect. */
    int per_process = 0;
    size_t size = sizeof(per_process);
    if (sysctlbyname("kern.maxfilesperproc", &per_process, &size, NULL, 0) == 0 && per_process > 0 && (rlim_t)per_process < ceiling) {
        ceiling = (rlim_t)per_process;
    }
#endif
    /* A soft limit above the ceiling, unlimited included, does not let the
     * process open more than the ceiling, so it is answered as the ceiling
     * and left as it is. */
    if (limit.rlim_cur != RLIM_INFINITY && limit.rlim_cur < ceiling) {
        limit.rlim_cur = ceiling;
        if (setrlimit(RLIMIT_NOFILE, &limit) != 0) return -(long)errno;
    }
    rlim_t in_force = limit.rlim_cur == RLIM_INFINITY || limit.rlim_cur > ceiling ? ceiling : limit.rlim_cur;
    if (in_force > (rlim_t)LONG_MAX) return LONG_MAX;
    return (long)in_force;
}
