/* Differential tests for the actual compiler-owned SPIR-V Float32 fragment.
 * The volatile CPU operation is binary32; memcpy preserves every input bit.
 * IEEE invalid-operation results are canonicalised as Linea requires. */
#include "../../gpu.h"
#include "float_cases.h"
#include <fenv.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define CAPACITY 1100000u
#define GUARDS 16u
static uint32_t pairs[CAPACITY * 2], result[CAPACITY + GUARDS];
static uint32_t count;
static void append(uint32_t a, uint32_t b) {
    if (count == CAPACITY) abort();
    pairs[count * 2] = a; pairs[count * 2 + 1] = b; ++count;
}
static uint32_t reference(unsigned op, uint32_t a, uint32_t b) {
    volatile float x, y, z;
    float first, second, answer;
    memcpy(&first, &a, 4); memcpy(&second, &b, 4);
    x = first; y = second;
    switch (op) {
    case 0: z = x + y; break;
    case 1: z = x - y; break;
    case 2: z = x * y; break;
    default: z = x / y; break;
    }
    answer = z;
    uint32_t bits; memcpy(&bits, &answer, 4);
    return (bits & 0x7fffffffu) > 0x7f800000u ? 0x7fc00000u : bits;
}
static void checked(long status, const char *action) {
    if (status < 0) { fprintf(stderr, "%s failed: %ld\n", action, status); exit(1); }
}
static uint32_t random_word(uint32_t *state) {
    uint32_t x = *state; x ^= x << 13; x ^= x >> 17; x ^= x << 5;
    return *state = x;
}
int main(int argc, char **argv) {
    if (argc != 5 || fesetround(FE_TONEAREST)) return 2;
    /* Pin known boundary cases to independently written expected answers. */
    const struct float_case *fixed[] = {add_cases, subtract_cases, multiply_cases, divide_cases};
    const size_t sizes[] = {sizeof(add_cases)/sizeof(*add_cases), sizeof(subtract_cases)/sizeof(*subtract_cases), sizeof(multiply_cases)/sizeof(*multiply_cases), sizeof(divide_cases)/sizeof(*divide_cases)};
    for (unsigned op = 0; op < 4; ++op)
        for (size_t i = 0; i < sizes[op]; ++i) {
            struct float_case c = fixed[op][i];
            if (reference(op, c.left, c.right) != c.expected) {
                fprintf(stderr, "CPU reference does not preserve strict binary32 semantics\n"); return 1;
            }
            append(c.left, c.right);
        }
    /* Cartesian special values, including signed zero and signalling NaNs. */
    for (size_t i = 0; i < sizeof(identity_cases)/sizeof(*identity_cases); ++i)
        for (size_t j = 0; j < sizeof(identity_cases)/sizeof(*identity_cases); ++j)
            append(identity_cases[i], identity_cases[j]);
    /* Every exponent pair at significand edges, both relative signs. */
    const uint32_t fractions[] = {0, 1, 0x3fffff, 0x400000, 0x7ffffe, 0x7fffff};
    for (uint32_t a = 0; a < 256; ++a)
        for (uint32_t b = 0; b < 256; ++b)
            for (unsigned f = 0; f < sizeof(fractions)/sizeof(*fractions); ++f) {
                uint32_t x = (a << 23) | fractions[f];
                uint32_t y = (b << 23) | fractions[5-f];
                append(x, y); append(x | 0x80000000u, y);
            }
    uint32_t state = 0x91e10da5;
    for (unsigned i = 0; i < 262144; ++i) {
        uint32_t a = random_word(&state), b = random_word(&state);
        append(a, b);
    }
    long device = linea_gpu_open(); checked(device, "open GPU");
    long input = linea_gpu_buffer_new(device, count * 8ul);
    long output = linea_gpu_buffer_new(device, (count + GUARDS) * 4ul);
    checked(input, "allocate input"); checked(output, "allocate output");
    checked(linea_gpu_buffer_write(input, pairs, count * 8ul), "write input");
    const char *names[] = {"add", "sub", "mul", "div"};
    unsigned failures = 0;
    for (unsigned op = 0; op < 4; ++op) {
        FILE *file = fopen(argv[op + 1], "rb"); if (!file) return 1;
        if (fseek(file, 0, SEEK_END)) return 1;
        long bytes = ftell(file); if (bytes <= 0 || fseek(file, 0, SEEK_SET)) return 1;
        void *image = malloc((size_t)bytes); if (!image) abort();
        if (fread(image, 1, (size_t)bytes, file) != (size_t)bytes || fclose(file)) return 1;
        memset(result, 0xa5, (count + GUARDS) * 4ul);
        checked(linea_gpu_buffer_write(output, result, (count + GUARDS) * 4ul), "write output guards");
        long job = linea_gpu_submit(input, output, image, bytes, count); checked(job, "submit");
        free(image);
        checked(linea_gpu_wait(job), "wait"); linea_gpu_submission_drop(job);
        checked(linea_gpu_buffer_read(output, result, (count + GUARDS) * 4ul), "read output");
        unsigned mismatches = 0;
        for (uint32_t i = 0; i < count; ++i) {
            uint32_t expected = reference(op, pairs[i * 2], pairs[i * 2 + 1]);
            if (result[i] != expected) {
                if (mismatches < 12) fprintf(stderr, "%s[%u]: %08x, %08x -> %08x expected %08x\n", names[op], i, pairs[i*2], pairs[i*2+1], result[i], expected);
                ++mismatches;
            }
        }
        for (uint32_t i = count; i < count + GUARDS; ++i)
            if (result[i] != 0xa5a5a5a5) ++mismatches;
        printf("strict Float32 %s: %u pairs, %u mismatches\n", names[op], count, mismatches);
        failures += mismatches != 0;
    }
    linea_gpu_buffer_drop(output); linea_gpu_buffer_drop(input); linea_gpu_close(device);
    return failures ? 1 : 0;
}
