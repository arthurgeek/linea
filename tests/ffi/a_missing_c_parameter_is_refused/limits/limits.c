#include <stdint.h>

int32_t limits_clamp(int32_t value, int32_t low, int32_t high) {
    if (value < low) return low;
    if (value > high) return high;
    return value;
}
