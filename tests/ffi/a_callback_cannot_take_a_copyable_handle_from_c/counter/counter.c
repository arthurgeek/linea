#include <stdint.h>
#include <stdlib.h>

struct counter { int64_t total; };

int64_t counter_total(const struct counter *counter) { return counter->total; }

/* Makes a temporary counter, shows it to the callback, then frees it. */
int32_t counter_each(int32_t (*visit)(void *, struct counter *), void *context) {
    struct counter *c = calloc(1, sizeof *c);
    c->total = 41;
    int32_t r = visit(context, c);
    c->total = 0xdead;
    free(c);
    return r;
}
