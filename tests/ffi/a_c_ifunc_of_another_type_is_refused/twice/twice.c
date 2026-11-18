long long twice_impl(long long value) { return value * 2; }

static void *twice_resolve(void) { return (void *)twice_impl; }

/* C declares the function the symbol `twice_of` resolves to as taking and
 * answering a `long long`, so an `extern` of it must too. */
long long twice_of(long long value) __attribute__((ifunc("twice_resolve")));
