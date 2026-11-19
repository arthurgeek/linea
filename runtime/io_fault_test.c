#define _GNU_SOURCE
/* Assertions execute test setup, checks, and cleanup in every build mode. */
#undef NDEBUG
#include "io.h"

#include <assert.h>
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

static int interrupt_read = 1;
static int interrupt_readdir = 1;
static int interrupt_write = 1;
static int recycled_fd = -1;
static unsigned long checked_at = 0;
static unsigned long checked_len = 0;

/* Stands in for the allocator, recording which bytes a system call is handed. */
void linea_storage_extent(unsigned long at, unsigned long len) {
    checked_at = at;
    checked_len = len;
}

int linea_test_getentropy(void *bytes, size_t len) {
    (void)bytes;
    (void)len;
    errno = EIO;
    return -1;
}

/* Only the transport translation unit substitutes these syscall boundaries.
 * Successful operations still use real descriptors and transfer real bytes. */
ssize_t linea_test_read(int fd, void *bytes, size_t len) {
    if (interrupt_read) {
        interrupt_read = 0;
        errno = EINTR;
        return -1;
    }
    return read(fd, bytes, len);
}

ssize_t linea_test_write(int fd, const void *bytes, size_t len) {
    if (interrupt_write) {
        interrupt_write = 0;
        errno = EINTR;
        return -1;
    }
    return write(fd, bytes, len > 2 ? 2 : len);
}

/* Directory reads are interrupted once, as a signal arriving during one would. */
struct dirent *linea_test_readdir(DIR *dir);
struct dirent *linea_test_readdir(DIR *dir) {
    if (interrupt_readdir) {
        interrupt_readdir = 0;
        errno = EINTR;
        return NULL;
    }
    return readdir(dir);
}

#if defined(__linux__) && defined(STATX_BTIME)
/* `statx` is refused, as a seccomp filter in an older container refuses it. */
int linea_test_statx(int dirfd, const char *path, int flags, unsigned int mask, struct statx *buffer);
int linea_test_statx(int dirfd, const char *path, int flags, unsigned int mask, struct statx *buffer) {
    (void)dirfd;
    (void)path;
    (void)flags;
    (void)mask;
    (void)buffer;
    errno = EPERM;
    return -1;
}
#endif

int linea_test_close(int fd) {
    const int result = close(fd);
    if (result != 0) return result;
    if (recycled_fd == -1) {
        recycled_fd = open("/dev/null", O_RDONLY);
        assert(recycled_fd == fd);
        errno = EIO;
        return -1;
    }
    return 0;
}

int main(void) {
    int descriptors[2];
    char bytes[8] = {0};
    assert(pipe(descriptors) == 0);
    assert(linea_random_bytes((unsigned long)(uintptr_t)bytes, sizeof(bytes)) == -EIO);
    unsigned long high = 3;
    unsigned long low = 4;
    assert(linea_random_words(&high, &low) == -EIO);
    assert(high == 3 && low == 4);
    assert(linea_write_some(descriptors[1], (unsigned long)(uintptr_t)"abcd", 4) == 2);
    assert(linea_read_some(descriptors[0], (unsigned long)(uintptr_t)bytes, sizeof(bytes)) == 2);
    assert(memcmp(bytes, "ab", 2) == 0);
    assert(linea_close(descriptors[0]) == -EIO);
    assert(fcntl(recycled_fd, F_GETFD) >= 0);
    assert(close(recycled_fd) == 0);
    assert(close(descriptors[1]) == 0);

    /* Every extent a system call is handed is shown to the allocator first. */
    int again[2];
    char more[8] = {0};
    const char *sent = "xy";
    assert(pipe(again) == 0);
    assert(linea_write_some(again[1], (unsigned long)(uintptr_t)sent, 2) == 2);
    assert(checked_at == (unsigned long)(uintptr_t)sent && checked_len == 2);
    assert(linea_read_some(again[0], (unsigned long)(uintptr_t)more, 5) == 2);
    assert(checked_at == (unsigned long)(uintptr_t)more && checked_len == 5);
    assert(linea_random_bytes((unsigned long)(uintptr_t)more, 8) == -EIO);
    assert(checked_at == (unsigned long)(uintptr_t)more && checked_len == 8);
    assert(close(again[0]) == 0 && close(again[1]) == 0);

    /* An interrupted directory read is tried again rather than ending the
     * directory or failing it. */
    char directory[] = "/tmp/linea-native-readdir-XXXXXX";
    assert(mkdtemp(directory) != NULL);
    char file[sizeof(directory) + 8];
    assert(snprintf(file, sizeof(file), "%s/entry", directory) > 0);
    const int created = open(file, O_WRONLY | O_CREAT | O_EXCL, 0600);
    assert(created >= 0 && close(created) == 0);
    unsigned long stream = 0;
    assert(linea_dir_open((unsigned long)(uintptr_t)directory, strlen(directory) + 1, 1, &stream) == 0);
    static uint64_t record[LINEA_DIR_RECORD_BYTES / sizeof(uint64_t)];
    assert(linea_dir_next(stream, (unsigned long)(uintptr_t)record, LINEA_DIR_RECORD_BYTES, 0) == 5);
    assert(interrupt_readdir == 0);
    assert(memcmp((const char *)record + LINEA_DIR_RECORD_HEADER, "entry", 5) == 0);
    assert(linea_dir_next(stream, (unsigned long)(uintptr_t)record, LINEA_DIR_RECORD_BYTES, 0) == 0);
#if defined(__linux__) && defined(STATX_BTIME)
    /* A refused statx leaves the directory identified by fstat, with its
     * birth time unknown, rather than failing the identity. */
    unsigned long device = 0;
    unsigned long inode = 0;
    unsigned long born = 7;
    unsigned long born_nanoseconds = 7;
    assert(linea_dir_identity(stream, &device, &inode, &born, &born_nanoseconds) == 1);
    assert(inode != 0 && born == 0 && born_nanoseconds == 0);
#endif
    assert(linea_dir_close(stream) == 0);
    assert(unlink(file) == 0 && rmdir(directory) == 0);
    puts("native I/O: interrupted operations preserve progress; failed close is not retried");
    return 0;
}
