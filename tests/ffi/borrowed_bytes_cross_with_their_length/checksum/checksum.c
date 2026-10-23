#include <stdint.h>

uint64_t checksum_sum(const uint8_t *bytes, uint64_t length) {
    uint64_t total = 0;
    for (uint64_t i = 0; i < length; i++) total += bytes[i];
    return total;
}

int32_t checksum_has_address(const uint8_t *bytes) { return bytes != 0; }
