#include <stdint.h>
#include <stdlib.h>

struct counter {
    int64_t total;
};

struct counter *counter_open(void) { return calloc(1, sizeof(struct counter)); }

void counter_add(struct counter *counter, int8_t amount) {
    __atomic_fetch_add(&counter->total, amount, __ATOMIC_SEQ_CST);
}

int64_t counter_total(const struct counter *counter) {
    return __atomic_load_n(&counter->total, __ATOMIC_SEQ_CST);
}

void counter_close(struct counter *counter) { free(counter); }
