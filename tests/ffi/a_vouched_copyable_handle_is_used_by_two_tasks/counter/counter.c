#include <stdint.h>

struct counter {
    int64_t total;
};

// The one counter lives for the whole program, so no handle to it dangles.
static struct counter shared;

struct counter *counter_open(void) { return &shared; }

void counter_add(struct counter *counter, int8_t amount) {
    __atomic_fetch_add(&counter->total, amount, __ATOMIC_SEQ_CST);
}

int64_t counter_total(const struct counter *counter) {
    return __atomic_load_n(&counter->total, __ATOMIC_SEQ_CST);
}
