#include <stdint.h>
#include <stdlib.h>
#include <string.h>

/* An object holding a name C allocates. */
struct named { char *name; };

uint64_t named_open(void) {
    struct named *n = malloc(sizeof *n);
    n->name = strdup("first");
    return (uint64_t)(uintptr_t)n;
}

/* Frees `b`, then answers the length of `a`'s name. */
uint64_t named_close_then_length(uint64_t a, uint64_t b) {
    struct named *closed = (struct named *)(uintptr_t)b;
    free(closed->name);
    free(closed);
    return strlen(((struct named *)(uintptr_t)a)->name);
}
