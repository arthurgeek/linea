#define _GNU_SOURCE
#undef NDEBUG
#include "process.h"

#include "clock.h"
#include "loop.h"
#include "task.h"

#include <assert.h>
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <stdio.h>
#include <string.h>
#include <sys/resource.h>
#if defined(__APPLE__)
#include <sys/event.h>
#endif
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

long linea_loop_open(unsigned long carriers);
long linea_task_prepare_on(unsigned long stack_bytes, unsigned long identity);

static const unsigned long stack_bytes = 2097152;

/* The descriptors this process holds open, counted below 1024, which is
 * more than any test here opens. */
static int open_descriptors(void) {
    int count = 0;
    for (int fd = 0; fd < 1024; fd++) {
        if (fcntl(fd, F_GETFD) != -1) count++;
    }
    return count;
}

/* A block of NUL-terminated strings, as `linea_process_spawn` takes them. */
struct block {
    char bytes[4096];
    unsigned long extent;
    unsigned long count;
};

static void add(struct block *block, const char *text) {
    const size_t length = strlen(text) + 1;
    assert(block->extent + length <= sizeof block->bytes);
    memcpy(block->bytes + block->extent, text, length);
    block->extent += length;
    block->count += 1;
}

static struct block shell(const char *script) {
    struct block block = { { 0 }, 0, 0 };
    add(&block, "/bin/sh");
    add(&block, "-c");
    add(&block, script);
    return block;
}

static char *table[64];

struct child {
    long pid;
    int in, out, err;
};

static struct child start(struct block *arguments, struct block *environment, const char *directory, uint8_t setup) {
    struct child child = { 0, -1, -1, -1 };
    unsigned long environment_at = 0, environment_extent = 0, environment_count = 0;
    if (environment != NULL) {
        setup = (uint8_t)(setup | LINEA_PROCESS_ENVIRONMENT);
        environment_at = (unsigned long)environment->bytes;
        environment_extent = environment->extent;
        environment_count = environment->count;
    }
    const unsigned long directory_extent = directory == NULL ? 0 : strlen(directory) + 1;
    child.pid = linea_process_spawn((unsigned long)arguments->bytes, arguments->extent, arguments->count,
                                    environment_at, environment_extent, environment_count,
                                    (unsigned long)directory, directory_extent,
                                    (unsigned long)table, sizeof table, setup, &child.in, &child.out, &child.err);
    return child;
}

static uint8_t streams(unsigned in, unsigned out, unsigned err) {
    return (uint8_t)(in | (out << 2) | (err << 4));
}

static long finish(long pid, unsigned long *status) {
    const long answer = linea_process_wait((int)pid, status);
    /* A reaped child is gone: no zombie is left behind. */
    int raw;
    assert(waitpid((pid_t)pid, &raw, WNOHANG) == -1 && errno == ECHILD);
    return answer;
}

/* Read `fd` to its end into `into`, answering the count. */
static size_t drain(int fd, char *into, size_t capacity) {
    size_t total = 0;
    for (;;) {
        char scratch[4096];
        const long count = linea_pipe_read(fd, (unsigned long)scratch, sizeof scratch);
        assert(count >= 0);
        if (count == 0) return total;
        if (into != NULL) {
            assert(total + (size_t)count <= capacity);
            memcpy(into + total, scratch, (size_t)count);
        }
        total += (size_t)count;
    }
}

static void an_exit_code_and_a_signal_are_reported(void) {
    unsigned long status = 99;
    struct block three = shell("exit 3");
    struct child child = start(&three, NULL, NULL, 0);
    assert(child.pid > 0 && child.in == -1 && child.out == -1 && child.err == -1);
    assert(finish(child.pid, &status) == 0 && status == 3);

    struct block terminated = shell("kill -TERM $$");
    child = start(&terminated, NULL, NULL, 0);
    assert(child.pid > 0);
    assert(finish(child.pid, &status) == 1 && status == SIGTERM);

    struct block sleeping = shell("exec sleep 30");
    child = start(&sleeping, NULL, NULL, 0);
    assert(child.pid > 0);
    assert(linea_process_kill((int)child.pid) == 0);
    assert(finish(child.pid, &status) == 1 && status == SIGKILL);
}

static void a_missing_program_is_not_found_and_leaves_nothing_open(void) {
    const int before = open_descriptors();
    struct block missing = { { 0 }, 0, 0 };
    add(&missing, "linea-no-such-program-anywhere");
    struct child child = start(&missing, NULL, NULL, streams(LINEA_PROCESS_PIPE, LINEA_PROCESS_PIPE, LINEA_PROCESS_PIPE));
    assert(child.pid == -(long)ENOENT);
    assert(child.in == -1 && child.out == -1 && child.err == -1);
    struct block absent = { { 0 }, 0, 0 };
    add(&absent, "/linea/no/such/program");
    child = start(&absent, NULL, NULL, streams(LINEA_PROCESS_PIPE, LINEA_PROCESS_NULL, LINEA_PROCESS_PIPE));
    assert(child.pid == -(long)ENOENT);
    assert(open_descriptors() == before);
}

static void a_malformed_block_is_refused(void) {
    const int before = open_descriptors();
    struct block arguments = shell("exit 0");
    long pid = linea_process_spawn((unsigned long)arguments.bytes, arguments.extent, arguments.count + 1, 0, 0, 0, 0, 0,
                                   (unsigned long)table, sizeof table, 0, &(int){ 0 }, &(int){ 0 }, &(int){ 0 });
    assert(pid == -(long)EINVAL);
    pid = linea_process_spawn((unsigned long)arguments.bytes, arguments.extent, arguments.count, 0, 0, 0, 0, 0,
                              (unsigned long)table, 2 * sizeof(char *), 0, &(int){ 0 }, &(int){ 0 }, &(int){ 0 });
    assert(pid == -(long)EINVAL);
    pid = linea_process_spawn((unsigned long)arguments.bytes, arguments.extent, arguments.count, 0, 0, 0, 0, 0,
                              (unsigned long)table, sizeof table, 0x3f, &(int){ 0 }, &(int){ 0 }, &(int){ 0 });
    assert(pid == -(long)EINVAL);
    assert(open_descriptors() == before);
}

static void no_descriptor_reaches_the_child_and_none_stays_in_the_parent(void) {
    int leaky[2];
    assert(pipe(leaky) == 0);
    /* Descriptor 7 is open without close-on-exec, as one C code opened. */
    assert(dup2(leaky[0], 7) == 7);
    assert(close(leaky[0]) == 0 && close(leaky[1]) == 0);
    const int before = open_descriptors();
    unsigned long status = 99;
    struct block probe = shell("if [ -e /dev/fd/7 ]; then exit 1; fi; exit 0");
    struct child child = start(&probe, NULL, NULL, streams(LINEA_PROCESS_PIPE, LINEA_PROCESS_PIPE, LINEA_PROCESS_PIPE));
    assert(child.pid > 0 && child.in > 2 && child.out > 2 && child.err > 2);
    assert(open_descriptors() == before + 3);
    assert((fcntl(child.out, F_GETFL) & O_NONBLOCK) != 0);
    assert((fcntl(child.out, F_GETFD) & FD_CLOEXEC) != 0);
    assert(close(child.in) == 0 && close(child.out) == 0 && close(child.err) == 0);
    assert(finish(child.pid, &status) == 0 && status == 0);
    assert(open_descriptors() == before);
    assert(close(7) == 0);

    /* The probe sees a descriptor the child does hold. */
    struct block held = shell("exec 7</dev/null; if [ -e /dev/fd/7 ]; then exit 1; fi; exit 0");
    child = start(&held, NULL, NULL, 0);
    assert(finish(child.pid, &status) == 0 && status == 1);
}

static void megabytes_on_both_pipes_arrive_whole(void) {
    /* Standard error is written first, so a parent reading standard output
     * alone would wait forever on a child blocked on a full error pipe. */
    struct block both = shell("head -c 3000000 /dev/zero >&2; head -c 5000000 /dev/zero");
    struct child child = start(&both, NULL, NULL, streams(LINEA_PROCESS_NULL, LINEA_PROCESS_PIPE, LINEA_PROCESS_PIPE));
    assert(child.pid > 0);
    size_t out = 0, err = 0;
    int out_open = 1, err_open = 1;
    while (out_open || err_open) {
        struct pollfd ready[2] = { { out_open ? child.out : -1, POLLIN, 0 }, { err_open ? child.err : -1, POLLIN, 0 } };
        assert(poll(ready, 2, -1) > 0);
        char scratch[65536];
        if (ready[0].revents != 0) {
            const long count = linea_pipe_read(child.out, (unsigned long)scratch, sizeof scratch);
            assert(count >= 0);
            if (count == 0) out_open = 0;
            out += (size_t)count;
        }
        if (ready[1].revents != 0) {
            const long count = linea_pipe_read(child.err, (unsigned long)scratch, sizeof scratch);
            assert(count >= 0);
            if (count == 0) err_open = 0;
            err += (size_t)count;
        }
    }
    assert(out == 5000000 && err == 3000000);
    assert(close(child.out) == 0 && close(child.err) == 0);
    unsigned long status = 99;
    assert(finish(child.pid, &status) == 0 && status == 0);
}

static void input_written_comes_back_and_a_closed_reader_is_a_broken_pipe(void) {
    struct block echo = { { 0 }, 0, 0 };
    add(&echo, "cat");
    struct child child = start(&echo, NULL, NULL, streams(LINEA_PROCESS_PIPE, LINEA_PROCESS_PIPE, LINEA_PROCESS_INHERIT));
    assert(child.pid > 0);
    const char tea[] = "green tea";
    assert(linea_pipe_write(child.in, (unsigned long)tea, sizeof tea - 1) == (long)(sizeof tea - 1));
    assert(close(child.in) == 0);
    char back[64];
    assert(drain(child.out, back, sizeof back) == sizeof tea - 1 && memcmp(back, tea, sizeof tea - 1) == 0);
    assert(close(child.out) == 0);
    unsigned long status = 99;
    assert(finish(child.pid, &status) == 0 && status == 0);

    struct block gone = shell("exit 0");
    child = start(&gone, NULL, NULL, streams(LINEA_PROCESS_PIPE, LINEA_PROCESS_INHERIT, LINEA_PROCESS_INHERIT));
    assert(finish(child.pid, &status) == 0 && status == 0);
    assert(linea_pipe_write(child.in, (unsigned long)tea, sizeof tea - 1) == -(long)EPIPE);
    assert(close(child.in) == 0);
}

static void a_directory_and_an_environment_are_the_childs(void) {
    struct block where = shell("pwd");
    struct child child = start(&where, NULL, "/", streams(LINEA_PROCESS_NULL, LINEA_PROCESS_PIPE, LINEA_PROCESS_INHERIT));
    assert(child.pid > 0);
    char path[64];
    assert(drain(child.out, path, sizeof path) == 2 && memcmp(path, "/\n", 2) == 0);
    assert(close(child.out) == 0);
    unsigned long status = 99;
    assert(finish(child.pid, &status) == 0 && status == 0);

    struct block environment = { { 0 }, 0, 0 };
    add(&environment, "LINEA_PROCESS_TEST=oolong");
    struct block show = shell("printf '%s|%s' \"$LINEA_PROCESS_TEST\" \"${HOME-unset}\"");
    child = start(&show, &environment, NULL, streams(LINEA_PROCESS_NULL, LINEA_PROCESS_PIPE, LINEA_PROCESS_INHERIT));
    assert(child.pid > 0);
    char seen[64];
    const size_t length = drain(child.out, seen, sizeof seen);
    assert(length == strlen("oolong|unset") && memcmp(seen, "oolong|unset", length) == 0);
    assert(close(child.out) == 0);
    assert(finish(child.pid, &status) == 0 && status == 0);

    struct block empty = { { 0 }, 0, 0 };
    struct block count = shell("set | grep -c LINEA_PROCESS_TEST; exit 0");
    child = start(&count, &empty, NULL, streams(LINEA_PROCESS_NULL, LINEA_PROCESS_NULL, LINEA_PROCESS_INHERIT));
    assert(child.pid > 0);
    assert(finish(child.pid, &status) == 0 && status == 0);
}

static unsigned long other_fiber_ran;
static int fiber_pipe = -1;

static void release_body(unsigned long at, unsigned long len) {
    assert(at == 0 && len == 0);
}

/* Sleep briefly, which parks this fiber, then note that it ran: the note is
 * made before the main fiber's wait returns only if that wait left the one
 * carrier free to wake this fiber. */
static void note_running(unsigned long endpoint, unsigned long at, unsigned long len) {
    assert(at == 0 && len == 0);
    assert(linea_clock_sleep(50000000UL) == 0);
    __atomic_store_n(&other_fiber_ran, 1, __ATOMIC_RELEASE);
    linea_chan_close(endpoint);
}

static void wait_on_a_fiber(unsigned long endpoint, unsigned long at, unsigned long len) {
    assert(at == 0 && len == 0);
    struct block slow = shell("sleep 0.3; printf done");
    struct child child = start(&slow, NULL, NULL, streams(LINEA_PROCESS_NULL, LINEA_PROCESS_PIPE, LINEA_PROCESS_INHERIT));
    assert(child.pid > 0);
    fiber_pipe = child.out;
    const long prepared = linea_task_prepare_on(stack_bytes, linea_io_current());
    assert(prepared > 0);
    const unsigned long other = linea_task_start((unsigned long)prepared, note_running, release_body, 0, 0, 0);
    /* The read parks this fiber, so the one carrier runs the other fiber
     * while the child sleeps. */
    char done[8];
    assert(drain(child.out, done, sizeof done) == 4 && memcmp(done, "done", 4) == 0);
    assert(__atomic_load_n(&other_fiber_ran, __ATOMIC_ACQUIRE) == 1);
    linea_chan_close(other);
    assert(close(child.out) == 0);
    unsigned long status = 99;
    assert(finish(child.pid, &status) == 0 && status == 0);

    /* A wait parks the fiber too. */
    __atomic_store_n(&other_fiber_ran, 0, __ATOMIC_RELEASE);
    struct block sleeping = shell("sleep 0.3");
    child = start(&sleeping, NULL, NULL, 0);
    assert(child.pid > 0);
    const long again = linea_task_prepare_on(stack_bytes, linea_io_current());
    assert(again > 0);
    const unsigned long noted = linea_task_start((unsigned long)again, note_running, release_body, 0, 0, 0);
    assert(finish(child.pid, &status) == 0 && status == 0);
    assert(__atomic_load_n(&other_fiber_ran, __ATOMIC_ACQUIRE) == 1);
    linea_chan_close(noted);

    /* A child that ended before the wait is reaped at once. */
    struct block quick = shell("exit 5");
    child = start(&quick, NULL, NULL, 0);
    struct timespec pause = { 0, 200000000L };
    nanosleep(&pause, NULL);
    assert(finish(child.pid, &status) == 0 && status == 5);
    linea_chan_close(endpoint);
}

static void a_fiber_waiting_on_a_child_leaves_its_carrier(void) {
    const long loop = linea_loop_open(1);
    assert(loop > 0);
    const long prepared = linea_task_prepare_on(stack_bytes, (unsigned long)loop);
    assert(prepared > 0);
    linea_chan_close(linea_task_start((unsigned long)prepared, wait_on_a_fiber, release_body, 0, 0, 0));
    assert(fiber_pipe > 2);
}

static void a_closed_standard_stream_stays_closed_in_the_child(void) {
    const int saved = fcntl(0, F_DUPFD_CLOEXEC, 3);
    assert(saved > 2);
    assert(close(0) == 0);
    /* The child inherits standard input closed: reading it fails. */
    struct block probe = shell("if read line 2>/dev/null; then exit 1; fi; exit 0");
    struct child child = start(&probe, NULL, NULL, 0);
    assert(dup2(saved, 0) == 0 && close(saved) == 0);
    assert(child.pid > 0);
    unsigned long status = 99;
    assert(finish(child.pid, &status) == 0 && status == 0);
}

/* A runtime descriptor, close-on-exec, can take the number of a standard
 * stream this process closed, as a loop's kqueue does. It is not the
 * program's stream, so the child starts with that stream closed. */
static void a_runtime_descriptor_in_a_closed_stream_is_not_inherited(void) {
    const int saved = fcntl(0, F_DUPFD_CLOEXEC, 3);
    assert(saved > 2);
    assert(close(0) == 0);
#if defined(__APPLE__)
    /* A kqueue, as a loop opens one; macOS passes none to a child. */
    const int runtime_held = kqueue();
    assert(runtime_held == 0 && fcntl(runtime_held, F_SETFD, FD_CLOEXEC) == 0);
#else
    const int runtime_held = open("/dev/null", O_RDONLY | O_CLOEXEC);
    assert(runtime_held == 0);
#endif
    struct block probe = shell("if read line 2>/dev/null; then exit 1; fi; exit 0");
    struct child child = start(&probe, NULL, NULL, 0);
    assert(close(runtime_held) == 0);
    assert(dup2(saved, 0) == 0 && close(saved) == 0);
    assert(child.pid > 0);
    unsigned long status = 99;
    assert(finish(child.pid, &status) == 0 && status == 0);
}

static void an_ignored_child_signal_refuses_a_spawn(void) {
    /* An ignored SIGCHLD has the kernel reap children itself, after which a
     * process ID could name a stranger. */
    struct sigaction ignore, saved;
    memset(&ignore, 0, sizeof ignore);
    ignore.sa_handler = SIG_IGN;
    assert(sigaction(SIGCHLD, &ignore, &saved) == 0);
    const int before = open_descriptors();
    struct block quick = shell("exit 0");
    struct child child = start(&quick, NULL, NULL, streams(LINEA_PROCESS_PIPE, LINEA_PROCESS_PIPE, LINEA_PROCESS_INHERIT));
    assert(child.pid == -(long)ECHILD);
    assert(child.in == -1 && child.out == -1 && open_descriptors() == before);
    assert(sigaction(SIGCHLD, &saved, NULL) == 0);
}

static void wait_without_descriptors(unsigned long endpoint, unsigned long at, unsigned long len) {
    assert(at == 0 && len == 0);
    struct block slow = shell("sleep 0.2");
    struct child child = start(&slow, NULL, NULL, 0);
    assert(child.pid > 0);
    struct rlimit saved, lowered;
    assert(getrlimit(RLIMIT_NOFILE, &saved) == 0);
    lowered = saved;
    lowered.rlim_cur = 64;
    assert(setrlimit(RLIMIT_NOFILE, &lowered) == 0);
    int filled[64];
    int count = 0;
    for (;;) {
        const int fd = open("/dev/null", O_RDONLY | O_CLOEXEC);
        if (fd < 0) break;
        assert(count < 64);
        filled[count++] = fd;
    }
    /* No descriptor is left for a pidfd or a kqueue, and the wait still
     * reaps the child. */
    unsigned long status = 99;
    assert(finish(child.pid, &status) == 0 && status == 0);
    for (int i = 0; i < count; i++) assert(close(filled[i]) == 0);
    assert(setrlimit(RLIMIT_NOFILE, &saved) == 0);
    linea_chan_close(endpoint);
}

static void a_wait_with_no_descriptor_left_still_reaps(void) {
    const long loop = linea_loop_open(1);
    assert(loop > 0);
    const long prepared = linea_task_prepare_on(stack_bytes, (unsigned long)loop);
    assert(prepared > 0);
    linea_chan_close(linea_task_start((unsigned long)prepared, wait_without_descriptors, release_body, 0, 0, 0));
}

int main(void) {
    an_exit_code_and_a_signal_are_reported();
    a_missing_program_is_not_found_and_leaves_nothing_open();
    a_malformed_block_is_refused();
    no_descriptor_reaches_the_child_and_none_stays_in_the_parent();
    megabytes_on_both_pipes_arrive_whole();
    input_written_comes_back_and_a_closed_reader_is_a_broken_pipe();
    a_directory_and_an_environment_are_the_childs();
    a_fiber_waiting_on_a_child_leaves_its_carrier();
    a_closed_standard_stream_stays_closed_in_the_child();
    a_runtime_descriptor_in_a_closed_stream_is_not_inherited();
    an_ignored_child_signal_refuses_a_spawn();
    a_wait_with_no_descriptor_left_still_reaps();
    puts("native process tests passed");
    return 0;
}
