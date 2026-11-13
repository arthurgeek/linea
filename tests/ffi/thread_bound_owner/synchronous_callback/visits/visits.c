#include <assert.h>
#include <pthread.h>
#include <stdint.h>
static __thread pthread_t calling;
int32_t visits_same_thread(void) { return pthread_equal(calling, pthread_self()); }
int32_t visits_each(int32_t (*visit)(void *, int32_t), void *context) {
    calling = pthread_self();
    int32_t answer = visit(context, 19) + visit(context, 23);
    assert(*(uint64_t *)context == 42);
    return answer;
}
