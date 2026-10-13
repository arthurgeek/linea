#define _GNU_SOURCE
/* Assertions execute test setup, checks, and cleanup in every build mode. */
#undef NDEBUG
#include "io.h"

#include <assert.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

static int interrupt_read = 1;
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
    puts("native I/O: interrupted operations preserve progress; failed close is not retried");
    return 0;
}
