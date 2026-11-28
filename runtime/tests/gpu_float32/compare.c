#include "../../gpu.h"
#include "float_cases.h"
#include <fenv.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define CAPACITY 1200000u
#define GUARDS 16u
static uint32_t pairs[CAPACITY * 2], actual[CAPACITY + GUARDS];
static uint32_t count;
static void append(uint32_t a, uint32_t b) {
    if (count == CAPACITY) abort();
    pairs[count * 2] = a; pairs[count * 2 + 1] = b; ++count;
}
static uint32_t reference(unsigned operation, uint32_t a, uint32_t b) {
    float first, second; volatile float x, y;
    memcpy(&first, &a, 4); memcpy(&second, &b, 4); x = first; y = second;
    switch (operation) {
    case 0: return x == y;
    case 1: return x != y;
    case 2: return x < y;
    case 3: return x <= y;
    case 4: return x > y;
    default: return x >= y;
    }
}
static void checked(long status, const char *action) {
    if (status < 0) { fprintf(stderr, "%s failed: %ld\n", action, status); exit(1); }
}
static uint32_t random_word(uint32_t *state) {
    uint32_t x = *state; x ^= x << 13; x ^= x >> 17; x ^= x << 5;
    return *state = x;
}
int main(int argc, char **argv) {
    if (argc != 7 || fesetround(FE_TONEAREST)) return 2;
    /* Independent expected truths pin zeros, signalling NaNs and subnormals
     * before trusting the host's floating-point comparisons as an oracle. */
    const struct { uint32_t a, b; unsigned mask; } fixed[] = {
        {0, 0x80000000, 0x29}, {1, 0, 0x32}, {0x80000001, 0x80000000, 0x0e},
        {0x7f812345, 0x3f800000, 0x02}, {0xffc12345, 0xffc12345, 0x02},
        {0xff800000, 0x7f800000, 0x0e}, {0x7f800000, 0x7f800000, 0x29},
    };
    for (size_t i = 0; i < sizeof(fixed) / sizeof(*fixed); ++i) {
        for (unsigned op = 0; op < 6; ++op)
            if (reference(op, fixed[i].a, fixed[i].b) != ((fixed[i].mask >> op) & 1)) {
                fprintf(stderr, "CPU reference does not implement IEEE Float32 comparisons\n"); return 1;
            }
        append(fixed[i].a, fixed[i].b);
    }
    for (size_t i = 0; i < sizeof(identity_cases)/sizeof(*identity_cases); ++i)
        for (size_t j = 0; j < sizeof(identity_cases)/sizeof(*identity_cases); ++j)
            append(identity_cases[i], identity_cases[j]);
    /* Every exponent and both signs, paired with every special value and
     * with identical/adjacent significands. Adjacency checks reversed ordering
     * of negatives and transitions between normals/subnormals/infinities. */
    const uint32_t fractions[] = {0, 1, 0x3fffff, 0x400000, 0x7ffffe, 0x7fffff};
    for (uint32_t e = 0; e < 256; ++e)
        for (unsigned sign = 0; sign < 2; ++sign)
            for (unsigned f = 0; f < sizeof(fractions)/sizeof(*fractions); ++f) {
                uint32_t x = (sign << 31) | (e << 23) | fractions[f];
                append(x, x); append(x, x + 1); append(x + 1, x);
                append(x, x ^ 0x80000000u);
                for (size_t j = 0; j < sizeof(identity_cases)/sizeof(*identity_cases); ++j)
                    append(x, identity_cases[j]);
            }
    uint32_t state = 0xe284efc9;
    for (unsigned i = 0; i < 1048576; ++i) {
        uint32_t a = random_word(&state), b = random_word(&state);
        append(a, b);
    }
    long device = linea_gpu_open(); checked(device, "open GPU");
    long input = linea_gpu_buffer_new(device, count * 8ul);
    long output = linea_gpu_buffer_new(device, (count + GUARDS) * 4ul);
    checked(input, "allocate input"); checked(output, "allocate output");
    checked(linea_gpu_buffer_write(input, pairs, count * 8ul), "write input");
    const char *names[] = {"eq", "ne", "lt", "le", "gt", "ge"};
    unsigned failures = 0;
    for (unsigned op = 0; op < 6; ++op) {
        FILE *file = fopen(argv[op + 1], "rb"); if (!file) return 1;
        if (fseek(file, 0, SEEK_END)) return 1;
        long bytes = ftell(file); if (bytes <= 0 || fseek(file, 0, SEEK_SET)) return 1;
        void *image = malloc((size_t)bytes); if (!image) abort();
        if (fread(image, 1, (size_t)bytes, file) != (size_t)bytes || fclose(file)) return 1;
        memset(actual, 0xa5, (count + GUARDS) * 4ul);
        checked(linea_gpu_buffer_write(output, actual, (count + GUARDS) * 4ul), "write guards");
        long job = linea_gpu_submit(input, output, image, bytes, count); checked(job, "submit");
        free(image);
        checked(linea_gpu_wait(job), "wait"); linea_gpu_submission_drop(job);
        checked(linea_gpu_buffer_read(output, actual, (count + GUARDS) * 4ul), "read output");
        unsigned mismatches = 0;
        for (uint32_t i = 0; i < count; ++i) {
            uint32_t expected = reference(op, pairs[i * 2], pairs[i * 2 + 1]);
            if (actual[i] != expected) {
                if (mismatches < 12) fprintf(stderr, "%s[%u]: %08x, %08x -> %u expected %u\n", names[op], i, pairs[i*2], pairs[i*2+1], actual[i], expected);
                ++mismatches;
            }
        }
        for (uint32_t i = count; i < count + GUARDS; ++i)
            if (actual[i] != 0xa5a5a5a5) ++mismatches;
        printf("Float32 comparison %s: %u pairs, %u mismatches\n", names[op], count, mismatches);
        failures += mismatches != 0;
    }
    /* Inputs are observations: their raw NaN payloads/signs remain unchanged. */
    uint32_t *observed = malloc(count * 8ul);
    if (!observed) abort();
    checked(linea_gpu_buffer_read(input, observed, count * 8ul), "read unchanged input");
    if (memcmp(observed, pairs, count * 8ul)) { fprintf(stderr, "comparison modified input bits\n"); ++failures; }
    free(observed);
    linea_gpu_buffer_drop(output); linea_gpu_buffer_drop(input); linea_gpu_close(device);
    return failures ? 1 : 0;
}
