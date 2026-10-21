#include <stdint.h>

uint8_t narrow_arguments_arrive_whole(void);
int8_t negate(int8_t value);

int32_t widen_signed(int8_t value) { return value; }
int32_t widen_unsigned(uint16_t value) { return value; }

int main(void) {
    if (narrow_arguments_arrive_whole() != 1) return 1;
    int32_t negated = negate(5);
    return negated == -5 ? 0 : 2;
}
