#include <stdlib.h>

/* This shim calls `labs` before the compiler looks at it. */
long long numbers_distance(long long from, long long to) { return labs(to - from); }
