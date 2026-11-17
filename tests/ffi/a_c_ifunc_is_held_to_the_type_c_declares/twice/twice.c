long long twice_impl(long long value) { return value * 2; }

static void *twice_resolve(void) { return (void *)twice_impl; }

/* The loader binds `twice_of` to what `twice_resolve` answers, and C calls
 * it through this declaration, so the Linea declaration is held to it. */
long long twice_of(long long value) __attribute__((ifunc("twice_resolve")));
