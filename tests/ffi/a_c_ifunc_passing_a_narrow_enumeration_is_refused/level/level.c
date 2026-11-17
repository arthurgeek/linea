enum level : signed char { low = -1, high = 1 };

enum level flip_impl(enum level value) { return value == low ? high : low; }

static void *flip_resolve(void) { return (void *)flip_impl; }

/* An `ifunc` states its function's type but not whether C extends an 8-bit
 * enumeration to pass it, so no Linea declaration can be held to how it is
 * passed. */
enum level flip(enum level value) __attribute__((ifunc("flip_resolve")));
