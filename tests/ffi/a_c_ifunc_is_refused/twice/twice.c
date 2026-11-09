int twice_impl(int value, int extra) { return value + extra; }

static void *twice_resolve(void) { return (void *)twice_impl; }

/* The symbol `twice_of` is whatever `twice_resolve` answers at load time,
 * here a function of another prototype. */
long long twice_of(long long value) __attribute__((ifunc("twice_resolve")));
