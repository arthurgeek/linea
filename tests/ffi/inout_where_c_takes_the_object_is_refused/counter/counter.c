#include <stdint.h>
#include <stdlib.h>

struct counter {
    int64_t total;
};

struct counter *counter_open(void) { return calloc(1, sizeof(struct counter)); }

void counter_add(struct counter *counter, int8_t amount) { counter->total += amount; }

void counter_close(struct counter *counter) { free(counter); }
