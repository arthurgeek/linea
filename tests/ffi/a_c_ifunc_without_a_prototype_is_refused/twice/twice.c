long long twice_impl(long long value) { return value * 2; }

static void *twice_resolve(void) { return (void *)twice_impl; }

/* `twice_of()` states no parameter types, so C declares no function type
 * the symbol's resolved function could be held to. */
long long twice_of() __attribute__((ifunc("twice_resolve")));
