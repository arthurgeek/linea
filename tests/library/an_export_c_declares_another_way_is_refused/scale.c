/* C calls the exported `scale` with a 64-bit argument and reads a 64-bit
 * answer. */
long long scale(long long value);

long long scale_twice(long long value) { return scale(scale(value)); }
