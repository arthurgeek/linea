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
    LINEA_IO_ADDRESS_IN_USE = 18,
    LINEA_IO_NAME_TOO_LONG = 19
};
uint8_t linea_io_category(int code);
/* `errno` as the call just made left it. The compiler calls this immediately
 * after a call to an `extern` declared to answer `ffi.Errno`, with no other
 * code in between that could change it. */
int linea_errno(void);

/* Zero when the bytes at `at` are ones a system call may be handed, after
 * giving them to the allocator's checks; otherwise an errno. */
int linea_io_byte_range(unsigned long at, unsigned long len);
long linea_read_some(int fd, unsigned long at, unsigned long len);
long linea_write_some(int fd, unsigned long at, unsigned long len);
long linea_read_at(int fd, unsigned long at, unsigned long len, unsigned long offset);
long linea_write_at(int fd, unsigned long at, unsigned long len, unsigned long offset);
long linea_close(int fd);
/* Random bytes make at most 256 bytes of progress per call. */
long linea_random_bytes(unsigned long at, unsigned long len);
/* Two random 64-bit words, written only when both were read: zero, or a
 * negated errno. */
long linea_random_words(unsigned long *high, unsigned long *low);
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
/* Creates the directory `at` in `parent` with permission bits `mode`, which
 * the umask then narrows; removes the empty directory `at`; and creates the
 * symbolic link `at` naming `target_at`, whose extent includes its NUL. */
long linea_make_dir_at(int parent, unsigned long at, unsigned long extent, unsigned long mode);
long linea_remove_dir_at(int parent, unsigned long at, unsigned long extent);
long linea_symlink_at(int parent, unsigned long at, unsigned long extent,
                      unsigned long target_at, unsigned long target_extent);

/* A directory stream reads the entries of one open directory. Its handle is
 * the address of the runtime's stream, written to `*stream`; each call answers
 * zero or a negated errno. `linea_dir_open` opens the path `at`, following a
 * final symbolic link only when `follow` is 1. `linea_dir_open_at` opens the
 * single component `at` of the directory the stream `parent` reads, under
 * the same rule. */
long linea_dir_open(unsigned long at, unsigned long extent, uint8_t follow, unsigned long *stream);
long linea_dir_open_at(unsigned long parent, unsigned long at, unsigned long extent,
                       uint8_t follow, unsigned long *stream);
/* Reads the stream's next entry other than "." and "..", writes its record
 * to the `len` bytes at `at`, and answers the length of its name, 0 once the
 * directory is exhausted, or a negated errno when reading failed. The record
 * is six 64-bit words and then the name, without a NUL, from byte 48; `len`
 * must hold the longest name a platform's directory entry holds, so at least
 * `LINEA_DIR_RECORD_BYTES`. The words are, in order: the kind (0 a regular
 * file, 1 a directory, 2 a symbolic link, 3 anything else), the permission
 * bits (mode & 07777), the size in bytes, the modification time in whole
 * seconds since the Unix epoch (two's complement) and the nanoseconds past
 * them, and the errno of a metadata read that failed, or 0. The metadata describes the entry itself unless `follow` is 1,
 * when a symbolic link is described by what it names; a failed read leaves
 * every word before the last 0 and the kind as the directory entry gives it. */
#define LINEA_DIR_RECORD_HEADER 48
#define LINEA_DIR_RECORD_BYTES (LINEA_DIR_RECORD_HEADER + 1024)
long linea_dir_next(unsigned long stream, unsigned long at, unsigned long len, uint8_t follow);
/* Writes the device and inode numbers of the directory the stream reads. */
long linea_dir_identity(unsigned long stream, unsigned long *device, unsigned long *inode);
/* Closes the stream and its descriptor; the handle is invalid afterwards,
 * whatever the answer. */
long linea_dir_close(unsigned long stream);
/* Raises the soft limit on open descriptors to the hard limit, capped where
 * the system caps a process (`kern.maxfilesperproc` on macOS), and answers how
 * many descriptors the process may now open: the soft limit, or the cap when
 * the soft limit is above it or unlimited. A soft limit at or above the cap is
 * left alone. A failure is a negated errno. */
long linea_raise_open_files(void);

#endif
