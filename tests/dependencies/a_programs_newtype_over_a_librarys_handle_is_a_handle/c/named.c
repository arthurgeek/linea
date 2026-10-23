#include <stdint.h>
#include <stdlib.h>
#include <string.h>

/* An object holding a name C allocates. Resetting it frees the name. */
struct named { char *name; };

uint64_t n_open(void) {
    struct named *n = malloc(sizeof *n);
    n->name = strdup("first");
    return (uint64_t)(uintptr_t)n;
}

const char *n_name(uint64_t h) { return ((struct named *)(uintptr_t)h)->name; }

void n_reset(uint64_t h) {
    struct named *n = (struct named *)(uintptr_t)h;
    free(n->name);
    n->name = strdup("second");
}
