/* C code calling `twice_of` calls the symbol `twice_impl`. */
long long twice_of(long long value) __asm__("twice_impl");

long long twice_of(long long value) { return value * 2; }
