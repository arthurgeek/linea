#include <stdint.h>
#include <stdlib.h>
#include <string.h>

/* An object holding a name C allocates. Renaming frees the old name. */
struct named { char *name; };

uint64_t named_open(void) {
    struct named *n = malloc(sizeof *n);
    n->name = strdup("first");
    return (uint64_t)(uintptr_t)n;
}

const char *named_name(uint64_t handle) { return ((struct named *)(uintptr_t)handle)->name; }

void named_reset(uint64_t handle) {
    struct named *n = (struct named *)(uintptr_t)handle;
    free(n->name);
    n->name = strdup("second");
}

void named_close(uint64_t handle) {
    struct named *n = (struct named *)(uintptr_t)handle;
    free(n->name);
    free(n);
}
