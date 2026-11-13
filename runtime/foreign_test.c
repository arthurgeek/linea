#define _POSIX_C_SOURCE 200809L
#undef NDEBUG
#include <assert.h>
#include <limits.h>
#include <pthread.h>
#include <signal.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>
#include "foreign.c"

static void *other_thread(void *unused) {
    (void)unused;
    assert(linea_foreign_depth() == 0);
    linea_foreign_enter();
    assert(linea_foreign_depth() == 1);
    linea_foreign_leave();
    return NULL;
}

static void fails(int overflow, const char *message) {
    int descriptors[2];
    assert(pipe(descriptors) == 0);
    pid_t child = fork();
    assert(child >= 0);
    if (child == 0) {
        close(descriptors[0]);
        assert(dup2(descriptors[1], STDERR_FILENO) >= 0);
        close(descriptors[1]);
        foreign_depth = overflow ? ULONG_MAX : 0;
        if (overflow) linea_foreign_enter(); else linea_foreign_leave();
        _exit(0);
    }
    close(descriptors[1]);
    char text[128] = {0};
    assert(read(descriptors[0], text, sizeof text - 1) > 0);
    close(descriptors[0]);
    int status;
    assert(waitpid(child, &status, 0) == child);
    assert(WIFSIGNALED(status) && WTERMSIG(status) == SIGABRT);
    assert(strstr(text, message) != NULL);
}

static void fails_with_closed_stderr(void) {
    int descriptors[2];
    assert(pipe(descriptors) == 0);
    close(descriptors[0]);
    pid_t child = fork();
    assert(child >= 0);
    if (child == 0) {
        assert(dup2(descriptors[1], STDERR_FILENO) >= 0);
        close(descriptors[1]);
        assert(signal(SIGPIPE, SIG_DFL) != SIG_ERR);
        sigset_t signals;
        assert(sigemptyset(&signals) == 0);
        assert(sigaddset(&signals, SIGPIPE) == 0);
        assert(pthread_sigmask(SIG_UNBLOCK, &signals, NULL) == 0);
        linea_foreign_leave();
        _exit(0);
    }
    close(descriptors[1]);
    int status;
    assert(waitpid(child, &status, 0) == child);
    assert(WIFSIGNALED(status) && WTERMSIG(status) == SIGABRT);
}

int main(void) {
    assert(linea_foreign_depth() == 0);
    linea_foreign_enter();
    linea_foreign_enter();
    assert(linea_foreign_depth() == 2);
    pthread_t thread;
    assert(pthread_create(&thread, NULL, other_thread, NULL) == 0);
    assert(pthread_join(thread, NULL) == 0);
    assert(linea_foreign_depth() == 2);
    linea_foreign_leave();
    assert(linea_foreign_depth() == 1);
    linea_foreign_leave();
    assert(linea_foreign_depth() == 0);
    fails(0, "foreign frame depth underflow");
    fails(1, "foreign frame depth overflow");
    fails_with_closed_stderr();
    assert(linea_foreign_depth() == 0);
    return 0;
}
