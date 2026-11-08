#include <stdint.h>
#include <stdlib.h>

struct counter {
    int64_t total;
};

struct counter *counter_make(void) { return calloc(1, sizeof(struct counter)); }

int64_t counter_total(const struct counter *counter) { return counter->total; }
