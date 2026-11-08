/* This declaration states no parameters, so C passes whatever a call
 * writes. */
long long twice_of();

long long twice_called(void) { return twice_of(1LL); }
