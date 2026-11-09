#include "symbol.h"

/* This root's C calls `twice_of` by the symbol `twice_impl`. */
long long twice_of(long long value) LINEA_SYMBOL("twice_impl");

long long twice_of(long long value) { return value * 2; }
