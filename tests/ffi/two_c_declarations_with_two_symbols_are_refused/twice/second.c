#include "symbol.h"

long long twice_of(long long value) LINEA_SYMBOL("twice_second");

long long twice_of(long long value) { return value + value; }
