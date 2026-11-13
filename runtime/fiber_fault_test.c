#define _GNU_SOURCE
#ifndef LINEA_FIBER_PAUSES
#define LINEA_FIBER_PAUSES 1
#endif
#undef NDEBUG
#include "fiber.h"
#include "fiber_pause.h"
#include "task.h"
#include <assert.h>
#include <errno.h>
#include <limits.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

void linea_set_args(int argc, char **argv);
void linea_thread_guard_bounds(unsigned long *low, unsigned long *high);

#if !defined(LINEA_SANITIZED)
static unsigned mode;
static unsigned long fiber_guard;

static void fault_on_guard(void) {
    assert(fiber_guard != 0);
    *(volatile unsigned char *)fiber_guard = 1;
}

void fiber_test_pause(enum linea_fiber_pause_point point) {
    if ((mode == 4 && point == linea_fiber_entering && fiber_guard != 0) ||
        (mode == 5 && point == linea_fiber_finishing)) fault_on_guard();
}

__attribute__((noinline)) static unsigned recurse(unsigned depth) {
    volatile unsigned char frame[4096] = { 0 };
    frame[depth % 4096] = (unsigned char)depth;
    if (depth == UINT_MAX) return frame[0];
    return recurse(depth + 1) + frame[0];
}

static void release_body(unsigned long at, unsigned long len) {
    assert(at == 0 && len == 0);
}

static void body(unsigned long endpoint, unsigned long at, unsigned long len) {
    assert(at == 0 && len == 0);
    unsigned long high;
    linea_thread_guard_bounds(&fiber_guard, &high);
    assert(high - fiber_guard == 65536);
    if (mode == 1) fault_on_guard();
    if (mode == 3) (void)recurse(0);
    if (mode == 2 || mode == 4) {
        linea_fiber_yield();
        fault_on_guard();
    }
    linea_chan_close(endpoint);
}

static void child_case(unsigned which) {
    mode = which;
    const long loop = linea_loop_open(1);
    assert(loop > 0);
    const long task = linea_task_prepare_on(131072, (unsigned long)loop);
    assert(task > 0);
    linea_chan_close(linea_task_start((unsigned long)task, body, release_body, 0, 0, 0));
    _exit(3);
}

static void reports_overflow(const char *executable, unsigned which) {
    int descriptors[2];
    assert(pipe(descriptors) == 0);
    const pid_t child = fork();
    assert(child >= 0);
    if (child == 0) {
        close(descriptors[0]);
        assert(dup2(descriptors[1], STDERR_FILENO) >= 0);
        close(descriptors[1]);
        char number[16];
        assert(snprintf(number, sizeof number, "%u", which) > 0);
        execl(executable, executable, number, (char *)NULL);
        _exit(4);
    }
    close(descriptors[1]);
    char said[256] = { 0 };
    size_t have = 0;
    for (;;) {
        const ssize_t count = read(descriptors[0], said + have, sizeof said - 1 - have);
        if (count < 0 && errno == EINTR) continue;
        assert(count >= 0);
        if (count == 0) break;
        have += (size_t)count;
        assert(have < sizeof said - 1);
    }
    close(descriptors[0]);
    int status;
    assert(waitpid(child, &status, 0) == child);
    assert(WIFSIGNALED(status) && WTERMSIG(status) == SIGABRT);
    assert(strcmp(said, "linea: a stack overflowed\n") == 0);
}
#else
void fiber_test_pause(enum linea_fiber_pause_point point) { (void)point; }
#endif

int main(int argc, char **argv) {
    linea_set_args(argc, argv);
#if !defined(LINEA_SANITIZED)
    if (argc == 2) child_case((unsigned)strtoul(argv[1], NULL, 10));
    (void)alarm(60);
    for (unsigned which = 1; which <= 5; which += 1) reports_overflow(argv[0], which);
    (void)alarm(0);
    puts("native fiber faults: first frame, resumed frame, recursion, entering guard and teardown report overflow");
#else
    puts("native fiber faults: the selected sanitizer owns stack faults");
#endif
    return 0;
}
