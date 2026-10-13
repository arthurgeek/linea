#ifndef LINEA_IO_H
#define LINEA_IO_H

#include <stdint.h>

/* Stable categories cross the scalar ABI independently of platform errno. */
enum linea_io_category {
    LINEA_IO_OTHER = 0,
    LINEA_IO_NOT_FOUND = 1,
    LINEA_IO_PERMISSION_DENIED = 2,
    LINEA_IO_ALREADY_EXISTS = 3,
    LINEA_IO_WOULD_BLOCK = 4,
    LINEA_IO_BROKEN_PIPE = 5,
    LINEA_IO_INTERRUPTED = 6,
    LINEA_IO_INVALID_INPUT = 7,
    LINEA_IO_NOT_DIRECTORY = 8,
    LINEA_IO_IS_DIRECTORY = 9,
    LINEA_IO_UNSUPPORTED = 10,
    LINEA_IO_NO_SPACE = 11,
    LINEA_IO_RESOURCE_EXHAUSTED = 12,
    LINEA_IO_SYMLINK = 13,
    LINEA_IO_INVALID_DESCRIPTOR = 14,
    LINEA_IO_TIMED_OUT = 15,
    LINEA_IO_CONNECTION_RESET = 16,
    LINEA_IO_CONNECTION_REFUSED = 17,
    LINEA_IO_ADDRESS_IN_USE = 18
};
uint8_t linea_io_category(int code);

long linea_read_some(int fd, unsigned long at, unsigned long len);
long linea_write_some(int fd, unsigned long at, unsigned long len);
long linea_close(int fd);
/* Random bytes make at most 256 bytes of progress per call. */
long linea_random_bytes(unsigned long at, unsigned long len);
/* Path extents include exactly one terminating NUL. At-relative names are
 * single components. Every failure is a negated errno, captured immediately. */
long linea_open_parent(unsigned long at, unsigned long extent);
/* Policies: 0 reads and follows symlinks; 1 exclusively creates; 2 creates or
 * truncates. Both writing policies refuse a final symlink. */
long linea_open_at(int parent, unsigned long at, unsigned long extent,
                   uint8_t policy, unsigned long mode);
long linea_mode_at(int parent, unsigned long at, unsigned long extent);
long linea_set_mode(int fd, unsigned long mode);
/* replace=0 refuses any existing destination atomically; replace=1 renames. */
long linea_publish_at(int parent, unsigned long from, unsigned long from_extent,
                      unsigned long to, unsigned long to_extent, uint8_t replace);
long linea_unlink_at(int parent, unsigned long at, unsigned long extent);

#endif
