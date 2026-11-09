#include "symbol.h"

/* C code calling `twice_of` calls the symbol `twice_impl`, and so does the
 * Linea declaration of it. */
long long twice_of(long long value) LINEA_SYMBOL("twice_impl");

long long twice_of(long long value) { return value * 2; }
