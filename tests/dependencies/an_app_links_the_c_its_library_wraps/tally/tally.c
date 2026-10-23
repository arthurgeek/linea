#include <stdint.h>

int64_t tally_sum_of_squares(int32_t count) {
    int64_t total = 0;
    for (int32_t i = 1; i <= count; i++) total += (int64_t)i * i;
    return total;
}
