#include "probe.h"
#include <stdio.h>
#include <inttypes.h>

int probe_select_device(const struct probe_candidate *devices, size_t count, size_t *selected) {
    for (size_t i = 0; i < count; ++i) {
        if (devices[i].vendor == 0x106b && devices[i].hardware && devices[i].compute && devices[i].api >= PROBE_MIN_API) {
            *selected = i;
            return 1;
        }
    }
    return 0;
}

int probe_workgroups(uint64_t count, uint32_t limit, uint32_t *groups) {
    if (count > UINT32_MAX - 2) return 0;
    uint64_t n = count / 64 + (count % 64 != 0);
    if (n > limit) return 0;
    *groups = (uint32_t)n;
    return 1;
}

int probe_buffer_bytes(uint32_t count, uint64_t limit, uint64_t *bytes) {
    if (count > UINT32_MAX - 2) return 0;
    uint64_t n = ((uint64_t)count + 2) * 4;
    if (n > limit) return 0;
    *bytes = n;
    return 1;
}

int probe_check_words(const uint32_t *expected, const uint32_t *actual, uint32_t count) {
    int status = PROBE_OK;
    const size_t guards[] = {0, (size_t)count + 1};
    for (unsigned i = 0; i < 2; ++i) {
        size_t index = guards[i];
        if (actual[index] != 0x12345678) {
            printf("mismatch op=copy guard=%zu actual=%08" PRIx32 " expected=12345678\n", index, actual[index]);
            status = PROBE_MISMATCH;
        }
    }
    for (uint32_t i = 0; i < count; ++i) {
        if (actual[(size_t)i + 1] != expected[i]) {
            printf("mismatch op=copy index=%u actual=%08" PRIx32 " expected=%08" PRIx32 "\n", i, actual[(size_t)i + 1], expected[i]);
            status = PROBE_MISMATCH;
        }
    }
    return status;
}

int probe_compare_word(const char *operation, uint32_t left, uint32_t right, uint32_t actual, uint32_t expected) {
    if (actual == expected) return PROBE_OK;
    printf("mismatch op=%s left=%08" PRIx32 " right=%08" PRIx32 " actual=%08" PRIx32 " expected=%08" PRIx32 "\n",
        operation, left, right, actual, expected);
    return PROBE_MISMATCH;
}

unsigned probe_float_profile(int denorm, int preserve, int nearest) {
    return (denorm ? 1u : 0u) | (preserve ? 2u : 0u) | (nearest ? 4u : 0u);
}
