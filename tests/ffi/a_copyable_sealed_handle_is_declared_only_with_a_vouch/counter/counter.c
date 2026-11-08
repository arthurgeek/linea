#include <stdint.h>

struct counter {
    int64_t total;
};

// The one counter lives for the whole program.
static struct counter shared;

struct counter *counter_open(void) { return &shared; }

void counter_add(struct counter *counter, int8_t amount) { counter->total += amount; }

int64_t counter_total(const struct counter *counter) { return counter->total; }
