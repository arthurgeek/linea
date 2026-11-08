#include <stdint.h>

struct counter {
    int64_t total;
};

// The one counter lives for the whole program.
static struct counter shared = { 41 };

struct counter *counter_open(void) { return &shared; }

int64_t counter_total(const struct counter *counter) { return counter->total; }

/* Calls `visit` once, during this call, with the context it was lent. */
int32_t counter_visit(int32_t (*visit)(void *, int32_t), void *context) {
    return visit(context, 1);
}
