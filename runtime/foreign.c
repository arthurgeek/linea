#define _POSIX_C_SOURCE 200809L
#define _DARWIN_C_SOURCE
#include "foreign.h"
#include <limits.h>
#include "pipe_signal.h"
#include <stdlib.h>

/* Pinned fibers never switch with a foreign frame live, so this carrier's
 * depth belongs to its executing stack until the last foreign frame returns. */
static __thread unsigned long foreign_depth;

void linea_foreign_enter(void) {
    if (foreign_depth == ULONG_MAX) {
        report_bytes("linea: foreign frame depth overflow\n", sizeof "linea: foreign frame depth overflow\n" - 1);
        abort();
    }
    foreign_depth += 1;
}

void linea_foreign_leave(void) {
    if (foreign_depth == 0) {
        report_bytes("linea: foreign frame depth underflow\n", sizeof "linea: foreign frame depth underflow\n" - 1);
        abort();
    }
    foreign_depth -= 1;
}

unsigned long linea_foreign_depth(void) {
    return foreign_depth;
}
