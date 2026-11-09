#include "symbol.h"

/* C calls the exported `scale` as `widen`, with a 64-bit argument and a
 * 64-bit answer. */
long long widen(long long value) LINEA_SYMBOL("scale");

long long scale_twice(long long value) { return widen(widen(value)); }
