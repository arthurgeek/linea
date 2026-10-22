#include <stdint.h>
#include <stdio.h>

int64_t sum_of_squares(int32_t);

int main(void) {
    printf("%lld\n", (long long)sum_of_squares(4));
    return 0;
}
