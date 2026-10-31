#define _GNU_SOURCE
/* Assertions execute test setup, checks, and cleanup in every build mode. */
#undef NDEBUG
#include "io.h"

#include <assert.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <pthread.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

#define ADDRESS(p) ((unsigned long)(uintptr_t)(p))
#define EXTENT(s) ((unsigned long)strlen(s) + 1UL)

static void transfers(void) {
    int pipe_fds[2];
    char bytes[16] = {0};
    assert(pipe(pipe_fds) == 0);
    assert(linea_read_some(-1, 0, 0) == 0);
    assert(linea_write_some(-1, 0, 0) == 0);
    assert(linea_read_some(pipe_fds[0], 0, 1) == -EFAULT);
    assert(linea_write_some(pipe_fds[1], ULONG_MAX, 2) == -EOVERFLOW);
    assert(linea_write_some(pipe_fds[1], ADDRESS("abc"), 3) == 3);
    assert(linea_read_some(pipe_fds[0], ADDRESS(bytes), sizeof(bytes)) == 3);
    assert(memcmp(bytes, "abc", 3) == 0);
    assert(linea_close(pipe_fds[1]) == 0);
    assert(linea_read_some(pipe_fds[0], ADDRESS(bytes), sizeof(bytes)) == 0);
    assert(linea_close(pipe_fds[0]) == 0);
    assert(linea_close(-1) == -EBADF);
    assert(linea_read_some(-1, ADDRESS(bytes), sizeof(bytes)) == -EBADF);
    assert(linea_write_some(-1, ADDRESS(bytes), sizeof(bytes)) == -EBADF);
}

static void broken_pipe(void) {
    int pipe_fds[2];
    sigset_t before, after, blocked, pending;
    struct sigaction action, after_action;
    assert(sigaction(SIGPIPE, NULL, &action) == 0);
    assert(pthread_sigmask(SIG_SETMASK, NULL, &before) == 0);
    assert(pipe(pipe_fds) == 0);
    assert(close(pipe_fds[0]) == 0);
    assert(linea_write_some(pipe_fds[1], ADDRESS("x"), 1) == -EPIPE);
    assert(pthread_sigmask(SIG_SETMASK, NULL, &after) == 0);
    assert(sigismember(&before, SIGPIPE) == sigismember(&after, SIGPIPE));
    assert(sigaction(SIGPIPE, NULL, &after_action) == 0);
    assert(action.sa_handler == after_action.sa_handler);
    assert(sigpending(&pending) == 0);
    assert(sigismember(&pending, SIGPIPE) == 0);

    assert(sigemptyset(&blocked) == 0);
    assert(sigaddset(&blocked, SIGPIPE) == 0);
    assert(pthread_sigmask(SIG_BLOCK, &blocked, &before) == 0);
    assert(raise(SIGPIPE) == 0);
    assert(linea_write_some(pipe_fds[1], ADDRESS("x"), 1) == -EPIPE);
    assert(sigpending(&pending) == 0);
    assert(sigismember(&pending, SIGPIPE) == 1);
    int received = 0;
    assert(sigwait(&blocked, &received) == 0 && received == SIGPIPE);
    assert(pthread_sigmask(SIG_SETMASK, &before, NULL) == 0);
    assert(close(pipe_fds[1]) == 0);
}

struct broken_pipe_arg {
    int fd;
    long result;
};

static void *broken_pipe_worker(void *ptr) {
    struct broken_pipe_arg *arg = ptr;
    arg->result = linea_write_some(arg->fd, ADDRESS("x"), 1);
    return NULL;
}

static void concurrent_broken_pipe(void) {
    enum { num_threads = 16 };
    struct sigaction sa, old_sa;
    memset(&sa, 0, sizeof sa);
    sa.sa_handler = SIG_IGN;
    assert(sigaction(SIGPIPE, &sa, &old_sa) == 0);

    int pipe_fds[2];
    assert(pipe(pipe_fds) == 0);
    assert(close(pipe_fds[0]) == 0);

    pthread_t threads[num_threads];
    struct broken_pipe_arg args[num_threads];
    for (int i = 0; i < num_threads; i++) {
        args[i].fd = pipe_fds[1];
        args[i].result = 0;
        assert(pthread_create(&threads[i], NULL, broken_pipe_worker, &args[i]) == 0);
    }
    for (int i = 0; i < num_threads; i++) {
        assert(pthread_join(threads[i], NULL) == 0);
        assert(args[i].result == -EPIPE);
    }
    assert(close(pipe_fds[1]) == 0);
    assert(sigaction(SIGPIPE, &old_sa, NULL) == 0);
}

static void random_bytes(void) {
    unsigned char bytes[300];
    memset(bytes, 0x55, sizeof(bytes));
    assert(linea_random_bytes(0, 0) == 0);
    assert(linea_random_bytes(0, 1) == -EFAULT);
    assert(linea_random_bytes(ULONG_MAX, 2) == -EOVERFLOW);
    assert(linea_random_bytes(ADDRESS(bytes), sizeof(bytes)) == 256);
    for (size_t i = 256; i < sizeof(bytes); ++i) assert(bytes[i] == 0x55);
    assert(linea_random_bytes(ADDRESS(bytes + 256), 44) == 44);
}

static void short_write(void) {
    int pipe_fds[2];
    assert(pipe(pipe_fds) == 0);
    assert(fcntl(pipe_fds[1], F_SETFL, O_NONBLOCK) == 0);
    const size_t size = 1024U * 1024U;
    char *bytes = malloc(size);
    assert(bytes != NULL);
    memset(bytes, 'x', size);
    const long count = linea_write_some(pipe_fds[1], ADDRESS(bytes), (unsigned long)size);
    assert(count > 0 && (unsigned long)count < size);
    while (linea_write_some(pipe_fds[1], ADDRESS(bytes), (unsigned long)size) > 0) {}
    assert(linea_write_some(pipe_fds[1], ADDRESS(bytes), (unsigned long)size) == -EAGAIN);
    free(bytes);
    assert(close(pipe_fds[0]) == 0);
    assert(close(pipe_fds[1]) == 0);
}

static void check_contents(int parent, const char *name, const char *expected) {
    const long result = linea_open_at(parent, ADDRESS(name), EXTENT(name), 0, 0);
    assert(result >= 0 && result <= INT_MAX);
    char bytes[32] = {0};
    assert(linea_read_some((int)result, ADDRESS(bytes), sizeof(bytes)) == (long)strlen(expected));
    assert(memcmp(bytes, expected, strlen(expected)) == 0);
    assert(linea_close((int)result) == 0);
}

static void searchable_parent(void) {
    if (geteuid() == 0) {
        puts("native I/O: search-only directory permissions skipped for root");
        return;
    }
    char directory[] = "/tmp/linea-native-search-XXXXXX";
    assert(mkdtemp(directory) != NULL);
    assert(chmod(directory, 0300) == 0);
    errno = 0;
    assert(open(directory, O_RDONLY | O_DIRECTORY | O_CLOEXEC) == -1);
    assert(errno == EACCES);

    const long opened = linea_open_parent(ADDRESS(directory), EXTENT(directory));
    if (opened < 0) {
        assert(chmod(directory, 0700) == 0);
        assert(rmdir(directory) == 0);
    }
    assert(opened >= 0 && opened <= INT_MAX);
    const int parent = (int)opened;
    assert((fcntl(parent, F_GETFD) & FD_CLOEXEC) != 0);
    const long created = linea_open_at(parent, ADDRESS("before"), EXTENT("before"), 1, 0600);
    assert(created >= 0 && created <= INT_MAX);
    assert(linea_write_some((int)created, ADDRESS("saved"), 5) == 5);
    assert(linea_close((int)created) == 0);
    assert(linea_mode_at(parent, ADDRESS("before"), EXTENT("before")) == 0600);
    assert(linea_publish_at(parent, ADDRESS("before"), EXTENT("before"),
                            ADDRESS("after"), EXTENT("after"), 0) == 0);
    check_contents(parent, "after", "saved");
    assert(linea_unlink_at(parent, ADDRESS("after"), EXTENT("after")) == 0);
    assert(linea_close(parent) == 0);
    assert(chmod(directory, 0700) == 0);
    assert(rmdir(directory) == 0);
}

static void filesystem(void) {
    char directory[] = "/tmp/linea-native-io-XXXXXX";
    assert(mkdtemp(directory) != NULL);
    const long opened = linea_open_parent(ADDRESS(directory), EXTENT(directory));
    assert(opened >= 0 && opened <= INT_MAX);
    const int parent = (int)opened;
    assert((fcntl(parent, F_GETFD) & FD_CLOEXEC) != 0);
    char moved[sizeof(directory) + 8];
    const int moved_length = snprintf(moved, sizeof(moved), "%s-moved", directory);
    assert(moved_length > 0 && (size_t)moved_length < sizeof(moved));
    assert(rename(directory, moved) == 0);
    const char bad[] = {'a', 0, 'b', 0};
    assert(linea_open_at(parent, ADDRESS(bad), sizeof(bad), 1, 0600) == -EINVAL);
    assert(linea_open_at(parent, ADDRESS("../x"), 5, 1, 0600) == -EINVAL);
    assert(linea_open_at(parent, ADDRESS("."), 2, 1, 0600) == -EINVAL);
    assert(linea_open_at(parent, ADDRESS("x"), 1, 1, 0600) == -EINVAL);
    assert(linea_open_at(parent, ADDRESS("x"), 2, 3, 0600) == -EINVAL);
    assert(linea_open_at(parent, ADDRESS("x"), 2, 1, 01000) == -EINVAL);
    assert(linea_mode_at(parent, ADDRESS("missing"), 8) == -ENOENT);

    const mode_t previous_mask = umask(0077);
    long fd = linea_open_at(parent, ADDRESS("masked"), 7, 1, 0666);
    umask(previous_mask);
    assert(fd >= 0 && fd <= INT_MAX);
    assert(linea_close((int)fd) == 0);
    assert(linea_mode_at(parent, ADDRESS("masked"), 7) == 0600);
    assert(linea_unlink_at(parent, ADDRESS("masked"), 7) == 0);
    const char raw_name[] = {(char)0xff, 0};
    const int raw_expected = openat(parent, raw_name, O_WRONLY | O_CREAT | O_EXCL, 0600);
    const int raw_error = raw_expected < 0 ? errno : 0;
    if (raw_expected >= 0) {
        assert(close(raw_expected) == 0);
        assert(unlinkat(parent, raw_name, 0) == 0);
    }
    fd = linea_open_at(parent, ADDRESS(raw_name), sizeof(raw_name), 1, 0600);
    if (raw_expected < 0) {
        assert(fd == -(long)raw_error);
    } else {
        assert(fd >= 0 && fd <= INT_MAX);
        assert(linea_close((int)fd) == 0);
        assert(linea_unlink_at(parent, ADDRESS(raw_name), sizeof(raw_name)) == 0);
    }

    fd = linea_open_at(parent, ADDRESS("old"), 4, 1, 0600);
    assert(fd >= 0 && fd <= INT_MAX);
    assert((fcntl((int)fd, F_GETFD) & FD_CLOEXEC) != 0);
    assert(linea_write_some((int)fd, ADDRESS("old"), 3) == 3);
    assert(linea_close((int)fd) == 0);
    assert(linea_open_at(parent, ADDRESS("old"), 4, 1, 0600) == -EEXIST);
    fd = linea_open_at(parent, ADDRESS("temp"), 5, 1, 0600);
    assert(fd >= 0 && fd <= INT_MAX);
    assert(linea_write_some((int)fd, ADDRESS("new"), 3) == 3);
    assert(linea_set_mode((int)fd, 0640) == 0);
    assert(linea_close((int)fd) == 0);
    assert(linea_mode_at(parent, ADDRESS("temp"), 5) == 0640);
    assert(linea_publish_at(parent, ADDRESS("temp"), 5, ADDRESS("old"), 4, 0) == -EEXIST);
    check_contents(parent, "old", "old");
    check_contents(parent, "temp", "new");
    assert(linea_publish_at(parent, ADDRESS("temp"), 5, ADDRESS("new"), 4, 0) == 0);
    assert(linea_mode_at(parent, ADDRESS("temp"), 5) == -ENOENT);
    assert(linea_publish_at(parent, ADDRESS("new"), 4, ADDRESS("old"), 4, 1) == 0);
    check_contents(parent, "old", "new");
    assert(linea_mode_at(parent, ADDRESS("old"), 4) == 0640);

    assert(symlinkat("old", parent, "link") == 0);
    check_contents(parent, "link", "new");
    assert(symlink(moved, directory) == 0);
    const long linked_parent = linea_open_parent(ADDRESS(directory), EXTENT(directory));
    assert(linked_parent >= 0 && linked_parent <= INT_MAX);
    check_contents((int)linked_parent, "link", "new");
    assert(linea_close((int)linked_parent) == 0);
    assert(unlink(directory) == 0);
    assert(linea_mode_at(parent, ADDRESS("link"), 5) == -ELOOP);
    assert(linea_open_at(parent, ADDRESS("link"), 5, 1, 0600) == -EEXIST);
    assert(linea_open_at(parent, ADDRESS("link"), 5, 2, 0600) == -ELOOP);
    check_contents(parent, "old", "new");
    assert(linea_unlink_at(parent, ADDRESS("link"), 5) == 0);
    assert(linea_unlink_at(parent, ADDRESS("old"), 4) == 0);
    assert(linea_unlink_at(parent, ADDRESS("old"), 4) == -ENOENT);
    assert(linea_close(parent) == 0);
    assert(rmdir(moved) == 0);
}

static void error_categories(void) {
    assert(linea_io_category(ENOENT) == LINEA_IO_NOT_FOUND);
    assert(linea_io_category(EACCES) == LINEA_IO_PERMISSION_DENIED);
    assert(linea_io_category(EPERM) == LINEA_IO_PERMISSION_DENIED);
    assert(linea_io_category(EEXIST) == LINEA_IO_ALREADY_EXISTS);
    assert(linea_io_category(EAGAIN) == LINEA_IO_WOULD_BLOCK);
    assert(linea_io_category(EWOULDBLOCK) == LINEA_IO_WOULD_BLOCK);
    assert(linea_io_category(EPIPE) == LINEA_IO_BROKEN_PIPE);
    assert(linea_io_category(EINTR) == LINEA_IO_INTERRUPTED);
    assert(linea_io_category(EINVAL) == LINEA_IO_INVALID_INPUT);
    assert(linea_io_category(ENOTDIR) == LINEA_IO_NOT_DIRECTORY);
    assert(linea_io_category(EISDIR) == LINEA_IO_IS_DIRECTORY);
    assert(linea_io_category(ENOSYS) == LINEA_IO_UNSUPPORTED);
    assert(linea_io_category(ENOTSUP) == LINEA_IO_UNSUPPORTED);
    assert(linea_io_category(ENOSPC) == LINEA_IO_NO_SPACE);
    assert(linea_io_category(ENOMEM) == LINEA_IO_RESOURCE_EXHAUSTED);
    assert(linea_io_category(EMFILE) == LINEA_IO_RESOURCE_EXHAUSTED);
    assert(linea_io_category(ENFILE) == LINEA_IO_RESOURCE_EXHAUSTED);
    assert(linea_io_category(ELOOP) == LINEA_IO_SYMLINK);
    assert(linea_io_category(EBADF) == LINEA_IO_INVALID_DESCRIPTOR);
    assert(linea_io_category(ETIMEDOUT) == LINEA_IO_TIMED_OUT);
    assert(linea_io_category(ECONNRESET) == LINEA_IO_CONNECTION_RESET);
    assert(linea_io_category(ECONNABORTED) == LINEA_IO_CONNECTION_RESET);
    assert(linea_io_category(ECONNREFUSED) == LINEA_IO_CONNECTION_REFUSED);
    assert(linea_io_category(EADDRINUSE) == LINEA_IO_ADDRESS_IN_USE);
    assert(linea_io_category(INT_MAX) == LINEA_IO_OTHER);
}

static void positional_io(void) {
    char template[] = "/tmp/linea_pos_XXXXXX";
    int fd = mkstemp(template);
    assert(fd >= 0);
    unlink(template);

    assert(linea_read_at(fd, 0, 0, 0) == 0);
    assert(linea_write_at(fd, 0, 0, 0) == 0);
    assert(linea_read_at(fd, 0, 1, 0) == -EFAULT);
    assert(linea_write_at(fd, 0, 1, 0) == -EFAULT);

    assert(linea_write_at(fd, ADDRESS("hello world"), 11, 0) == 11);
    assert(linea_write_at(fd, ADDRESS("linea"), 5, 6) == 5);

    char buf[16] = {0};
    assert(linea_read_at(fd, ADDRESS(buf), 5, 0) == 5);
    assert(memcmp(buf, "hello", 5) == 0);

    memset(buf, 0, sizeof(buf));
    assert(linea_read_at(fd, ADDRESS(buf), 5, 6) == 5);
    assert(memcmp(buf, "linea", 5) == 0);

    assert(linea_close(fd) == 0);
}

int main(void) {
    error_categories();
    transfers();
    random_bytes();
    broken_pipe();
    concurrent_broken_pipe();
    positional_io();
    short_write();
    searchable_parent();
    filesystem();
    puts("native I/O: transfers, short writes, SIGPIPE, and atomic files passed");
    return 0;
}
