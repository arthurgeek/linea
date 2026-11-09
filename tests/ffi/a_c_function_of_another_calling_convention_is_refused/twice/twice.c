/* `preserve_none` passes arguments in other registers than C's own convention. */
__attribute__((preserve_none)) long long twice_of(long long value) { return value * 2; }
