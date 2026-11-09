#include "symbol.h"

int pairs_add(int left, int right) { return left + right; }

/* C code calling `pairs_sum` calls `pairs_add`. */
int pairs_sum(int left, int right) LINEA_SYMBOL("pairs_add");
