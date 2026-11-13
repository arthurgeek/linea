#define _GNU_SOURCE
#define _DARWIN_C_SOURCE
#define _POSIX_C_SOURCE 200809L
#include <time.h>
#include <assert.h>
#include <errno.h>
#include <pthread.h>
#include <stdint.h>
#if defined(__linux__)
#include <sys/syscall.h>
#include <unistd.h>
#endif
static int main_thread(void) {
#if defined(__linux__)
    return (long)getpid() == syscall(SYS_gettid);
#else
    return pthread_main_np() != 0;
#endif
}
static pthread_t caller;
static unsigned initialized;
int64_t cheap_value(uint64_t value) {
    assert(main_thread());
    if (!initialized) { caller = pthread_self(); initialized = 1; }
    assert(pthread_equal(caller, pthread_self()));
    return value == 1234 ? -77 : (int64_t)value;
}

void cheap_blocking(void) {
    assert(!main_thread());
    assert(initialized && !pthread_equal(caller, pthread_self()));
    struct timespec delay = {0, 1000000};
    while (nanosleep(&delay, &delay) != 0) {}
}
