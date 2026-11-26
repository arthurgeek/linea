#include "device.h"
#include "float_cases.h"
#include <stdio.h>

int probe_dispatch(struct probe_device *device, const char *path, const char *entry,
    const uint32_t *left, const uint32_t *right, uint32_t *actual, uint32_t count);

int probe_float(struct probe_device *d, const char *paths[8]) {
    const char *names[] = {"identity", "negate", "add", "subtract", "multiply", "divide"};
    const struct float_case *cases[] = {NULL, NULL, add_cases, subtract_cases, multiply_cases, divide_cases};
    const uint32_t counts[] = {
        sizeof(identity_cases) / sizeof(identity_cases[0]), sizeof(identity_cases) / sizeof(identity_cases[0]),
        sizeof(add_cases) / sizeof(add_cases[0]), sizeof(subtract_cases) / sizeof(subtract_cases[0]),
        sizeof(multiply_cases) / sizeof(multiply_cases[0]), sizeof(divide_cases) / sizeof(divide_cases[0]),
    };
    int status = PROBE_OK;
    for (unsigned operation = 0; operation < 6; ++operation) {
        uint32_t left[32], right[32], expected[32], actual[34];
        uint32_t count = counts[operation];
        if (count > 32) return PROBE_FAILED;
        for (uint32_t i = 0; i < count; ++i) {
            if (operation < 2) {
                left[i] = identity_cases[i]; right[i] = 0;
                expected[i] = identity_cases[i] ^ (operation == 1 ? 0x80000000u : 0u);
            } else {
                left[i] = cases[operation][i].left;
                right[i] = cases[operation][i].right;
                expected[i] = cases[operation][i].expected;
            }
        }
        int result = probe_dispatch(d, paths[d->profile], names[operation], left, right, actual, count);
        if (result != PROBE_OK) return PROBE_FAILED;
        unsigned mismatches = 0;
        for (uint32_t i = 0; i < count; ++i)
            if (probe_compare_word(names[operation], left[i], right[i], actual[i + 1], expected[i]) != PROBE_OK)
                ++mismatches;
        if (actual[0] != 0x12345678 || actual[count + 1] != 0x12345678) {
            fprintf(stderr, "GPU probe: %s wrote outside the output region\n", names[operation]);
            ++mismatches;
        }
        printf("float32 op=%s cases=%u mismatches=%u\n", names[operation], count, mismatches);
        if (mismatches) status = PROBE_MISMATCH;
    }
    puts("Numerical samples are characterization, not a proof of complete IEEE conformance.");
    return status;
}
