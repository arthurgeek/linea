#define _POSIX_C_SOURCE 200809L
#include <assert.h>
#include <pthread.h>
#include <stdint.h>
#include <time.h>
static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_t parent;
static unsigned active, peak, completed;
void work_begin(void) { parent = pthread_self(); }
void work_run(uint64_t request) {
    assert(request == 41);
    assert(!pthread_equal(parent, pthread_self()));
    assert(pthread_mutex_lock(&lock) == 0);
    active += 1; if (active > peak) peak = active; assert(active <= 3);
    assert(pthread_mutex_unlock(&lock) == 0);
    struct timespec delay = {0, 20000000};
    while (nanosleep(&delay, &delay) != 0) {}
    assert(pthread_mutex_lock(&lock) == 0);
    active -= 1; completed += 1;
    assert(pthread_mutex_unlock(&lock) == 0);
}
uint8_t work_balanced(void) { return active == 0 && peak <= 3 && completed == 15; }
