#include <stdint.h>
#include <string.h>

/* A negative quiet NaN with the lowest payload bit set: neither its sign nor
 * its payload is the positive quiet NaN's. */
static double odd_nan(void) {
    uint64_t bits = 0xFFF8000000000001u;
    double value;
    memcpy(&value, &bits, sizeof value);
    return value;
}

double nans_returned(void) { return odd_nan(); }

void nans_written(double *out) { *out = odd_nan(); }

int32_t nans_handed_over(int32_t (*receive)(void *context, double value), void *context) {
    return receive(context, odd_nan());
}
