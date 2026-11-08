#include <stdint.h>
#include <stdlib.h>

struct counter {
    int64_t total;
};

struct counter *counter_open(void) { return calloc(1, sizeof(struct counter)); }

/* Takes the counter the callback answers and frees it. */
int32_t counter_keep(struct counter *(*give)(int32_t)) {
    struct counter *c = give(1);
    free(c);
    return 0;
}
