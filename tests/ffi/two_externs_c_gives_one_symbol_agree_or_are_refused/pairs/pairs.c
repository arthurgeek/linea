#include "symbol.h"

int pairs_add(int left, int right) { return left + right; }

/* Both of these reach the symbol `pairs_add`. */
int pairs_sum(int left, int right) LINEA_SYMBOL("pairs_add");

long long pairs_twice(long long value) LINEA_SYMBOL("pairs_add");
