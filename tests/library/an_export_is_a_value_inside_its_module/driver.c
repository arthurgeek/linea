#include <stdint.h>

int32_t apply(int32_t);

int main(void) {
    return apply(7) == 8 ? 0 : 1;
}
