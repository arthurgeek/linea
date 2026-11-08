#include <stdint.h>

/* Defined by the C program that links this library: it calls `visit` back,
 * handing it `context` each time. */
int32_t visit(int32_t (*visit)(void *context, int32_t value), void *context);
