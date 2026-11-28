/* Actual production kernels and runtime, with a bitwise CPU oracle for the
 * specified tree order and for separately rounded matmul products and sums. */
#include "../../gpu.h"
#include <errno.h>
#include <fenv.h>
#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define GUARDS 16u
static unsigned checks;
static void require(int condition, const char *what) {
    ++checks;
    if (!condition) { fprintf(stderr, "GPU numerical failure: %s\n", what); exit(1); }
}
static long checked(long result, const char *what) {
    ++checks;
    if (result < 0) { fprintf(stderr, "GPU numerical %s: %ld\n", what, result); exit(1); }
    return result;
}
static uint32_t arithmetic(unsigned op, uint32_t a, uint32_t b) {
    float first, second, answer; volatile float x, y, z;
    memcpy(&first, &a, 4); memcpy(&second, &b, 4); x = first; y = second;
    if (op == 0) z = x + y;
    else if (op == 1) z = x - y;
    else z = x * y;
    answer = z;
    uint32_t bits; memcpy(&bits, &answer, 4);
    return (bits & 0x7fffffffu) > 0x7f800000u ? 0x7fc00000u : bits;
}
static uint32_t tree_reference(const uint32_t *data, uint32_t count, uint32_t initial, unsigned op) {
    uint32_t partial[64] = {0}, present[64] = {0};
    for (uint32_t lane = 0; lane < 64; ++lane) {
        if (lane >= count) continue;
        partial[lane] = data[lane]; present[lane] = 1;
        for (uint32_t i = lane + 64; i < count; i += 64)
            partial[lane] = arithmetic(op, partial[lane], data[i]);
    }
    for (uint32_t width = 32; width; width /= 2)
        for (uint32_t lane = 0; lane < width; ++lane) {
            if (!present[lane + width]) continue;
            partial[lane] = present[lane] ? arithmetic(op, partial[lane], partial[lane + width]) : partial[lane + width];
            present[lane] = 1;
        }
    return count ? arithmetic(op, initial, partial[0]) : initial;
}
static void guards(const uint32_t *words, size_t count) {
    for (size_t i = count; i < count + GUARDS; ++i) require(words[i] == 0xa5a5a5a5u, "output guard overwritten");
}
static void fill(uint32_t *data, size_t count, unsigned profile) {
    static const uint32_t finite[] = {0x4b800000, 0x3f800000, 0xcb800000, 1, 0x80000001, 0x00800000, 0x007fffff, 0x80000000, 0x3f800001, 0xbf800000, 0x33800000, 0x40400000};
    static const uint32_t special[] = {0x80000000, 0, 0x7f800000, 0xff800000, 0x7f812345, 0xffc54321, 1, 0x80000001};
    for (size_t i = 0; i < count; ++i)
        data[i] = profile ? special[i % (sizeof(special) / 4)] : finite[i % (sizeof(finite) / 4)];
}
static struct linea_gpu_kernel read_kernel(const char *path, unsigned long kind) {
    FILE *f = fopen(path, "rb"); require(f != NULL, "open image");
    require(!fseek(f, 0, SEEK_END), "seek image");
    long bytes = ftell(f); require(bytes > 0 && !fseek(f, 0, SEEK_SET), "image length");
    void *image = malloc((size_t)bytes); require(image != NULL, "image allocation");
    require(fread(image, 1, bytes, f) == (size_t)bytes && !fclose(f), "read image");
    return (struct linea_gpu_kernel){ image, (unsigned long)bytes, kind };
}
static void reduction(unsigned long device, struct linea_gpu_kernel *kernel, uint32_t count, uint32_t initial, unsigned op, unsigned profile) {
    uint32_t *data = calloc(count ? count : 1, 4); require(data != NULL, "allocate reduction reference");
    fill(data, count, profile);
    long input = checked(linea_gpu_buffer_new(device, count * 4ul), "reduction input");
    long output = checked(linea_gpu_buffer_sized_like(input, (1 + GUARDS) * 4ul), "reduction output");
    uint32_t result[1 + GUARDS]; memset(result, 0xa5, sizeof(result));
    checked(linea_gpu_buffer_write(input, data, count * 4ul), "reduction upload");
    checked(linea_gpu_buffer_write(output, result, sizeof(result)), "reduction guards");
    long job = checked(linea_gpu_reduce(input, output, (unsigned long)(uintptr_t)kernel, count, initial), "reduce submit");
    /* The submission, not this owner, must retain the pending input. */
    linea_gpu_buffer_drop(input);
    checked(linea_gpu_wait(job), "reduce wait"); linea_gpu_submission_drop(job);
    checked(linea_gpu_buffer_read(output, result, sizeof(result)), "reduce read");
    uint32_t expected = tree_reference(data, count, initial, op);
    if (result[0] != expected) fprintf(stderr, "reduce op%u n%u initial%08x -> %08x expected %08x\n", op, count, initial, result[0], expected);
    require(result[0] == expected, "reduction differs from tree reference");
    guards(result, 1); linea_gpu_buffer_drop(output); free(data);
}
static void elementwise(unsigned long device, struct linea_gpu_kernel *kernel, uint32_t count, unsigned op, int uniform, int alias) {
    size_t bytes = (size_t)count * 4, result_bytes = ((size_t)count + GUARDS) * 4;
    uint32_t *a = calloc(count ? count : 1, 4), *b = calloc(count ? count : 1, 4), *result = malloc(result_bytes);
    require(a && b && result, "elementwise reference allocation");
    fill(a, count, 1); fill(b, count, 0);
    long left = checked(linea_gpu_buffer_new(device, bytes), "elementwise left");
    long right = alias ? left : checked(linea_gpu_buffer_new(device, bytes), "elementwise right");
    long output = checked(linea_gpu_buffer_new(device, result_bytes), "elementwise output");
    checked(linea_gpu_buffer_write(left, a, bytes), "elementwise left upload");
    if (!alias) checked(linea_gpu_buffer_write(right, b, bytes), "elementwise right upload");
    memset(result, 0xa5, result_bytes);
    checked(linea_gpu_buffer_write(output, result, result_bytes), "elementwise guards");
    const uint32_t scalar = 0x00000001;
    long job = checked(uniform
        ? linea_gpu_map_uniform(left, output, (unsigned long)(uintptr_t)kernel, count, scalar)
        : linea_gpu_zip(left, right, output, (unsigned long)(uintptr_t)kernel, count), "elementwise submit");
    linea_gpu_buffer_drop(left);
    if (!alias) linea_gpu_buffer_drop(right);
    checked(linea_gpu_wait(job), "elementwise wait"); linea_gpu_submission_drop(job);
    checked(linea_gpu_buffer_read(output, result, result_bytes), "elementwise download");
    for (uint32_t i = 0; i < count; ++i) {
        uint32_t expected = arithmetic(op, a[i], uniform ? scalar : alias ? a[i] : b[i]);
        if (result[i] != expected) fprintf(stderr, "elementwise op%u n%u i%u uniform%d alias%d: %08x expected %08x\n", op, count, i, uniform, alias, result[i], expected);
        require(result[i] == expected, "elementwise differs from independently rounded CPU bits");
    }
    guards(result, count);
    linea_gpu_buffer_drop(output); free(a); free(b); free(result);
}

static void matrix(unsigned long device, struct linea_gpu_kernel *kernel, uint32_t rows, uint32_t inner, uint32_t columns, unsigned profile, int alias) {
    size_t ac = rows * (size_t)inner, bc = inner * (size_t)columns, cc = rows * (size_t)columns;
    uint32_t *a = calloc(ac ? ac : 1, 4), *b = calloc(bc ? bc : 1, 4), *result = malloc((cc + GUARDS) * 4);
    require(a && b && result, "matrix reference allocation");
    fill(a, ac, profile); fill(b, bc, profile);
    long left = checked(linea_gpu_buffer_new(device, ac * 4), "matrix left");
    long right = alias ? left : checked(linea_gpu_buffer_new(device, bc * 4), "matrix right");
    long output = checked(linea_gpu_buffer_sized_like(left, (cc + GUARDS) * 4), "matrix output");
    checked(linea_gpu_buffer_write(left, a, ac * 4), "matrix left upload");
    if (!alias) checked(linea_gpu_buffer_write(right, b, bc * 4), "matrix right upload");
    memset(result, 0xa5, (cc + GUARDS) * 4);
    checked(linea_gpu_buffer_write(output, result, (cc + GUARDS) * 4), "matrix guards");
    long job = checked(linea_gpu_matmul(left, right, output, (unsigned long)(uintptr_t)kernel, rows, inner, columns), "matrix submit");
    if (!alias) linea_gpu_buffer_drop(left);
    checked(linea_gpu_wait(job), "matrix wait"); linea_gpu_submission_drop(job);
    /* Both separate and aliased right operands must leave in-flight state. */
    uint32_t restored = 0;
    checked(linea_gpu_buffer_read(right, &restored, bc ? 4 : 0), "matrix right access restored");
    if (bc) require(restored == b[0], "matrix changed its right input");
    linea_gpu_buffer_drop(right);
    checked(linea_gpu_buffer_read(output, result, (cc + GUARDS) * 4), "matrix read");
    for (size_t row = 0; row < rows; ++row)
        for (size_t column = 0; column < columns; ++column) {
            uint32_t expected = 0;
            for (size_t k = 0; k < inner; ++k)
                expected = arithmetic(0, expected, arithmetic(2, a[row * inner + k], b[k * columns + column]));
            if (result[row * columns + column] != expected)
                fprintf(stderr, "matrix %ux%ux%u at %zu,%zu -> %08x expected %08x\n", rows, inner, columns, row, column, result[row * columns + column], expected);
            require(result[row * columns + column] == expected, "matmul differs from strict reference");
        }
    guards(result, cc); linea_gpu_buffer_drop(output); free(a); free(b); free(result);
}
/* No synthetic-lane call is permitted: admitted numerical functions may
 * contain loops, so evaluating and discarding an extra call is observable. */
static unsigned counted_reductions(unsigned long device, struct linea_gpu_kernel *kernel) {
    const uint32_t sizes[] = {0, 1, 3, 63, 64, 65};
    unsigned mismatches = 0;
    for (unsigned sample = 0; sample < sizeof(sizes)/sizeof(*sizes); ++sample) {
        uint32_t count = sizes[sample], data[65], result[2 + GUARDS];
        for (uint32_t i = 0; i < count; ++i) data[i] = 0x3f800000;
        memset(result, 0xa5, sizeof(result)); result[1] = 0;
        long input = checked(linea_gpu_buffer_new(device, count * 4ul), "counted input");
        long output = checked(linea_gpu_buffer_sized_like(input, sizeof(result)), "counted output");
        checked(linea_gpu_buffer_write(input, data, count * 4ul), "counted upload");
        checked(linea_gpu_buffer_write(output, result, sizeof(result)), "counted guards");
        long job = checked(linea_gpu_reduce(input, output, (unsigned long)(uintptr_t)kernel, count, 0), "counted reduce");
        linea_gpu_buffer_drop(input);
        checked(linea_gpu_wait(job), "counted wait"); linea_gpu_submission_drop(job);
        checked(linea_gpu_buffer_read(output, result, sizeof(result)), "counted read");
        require(result[0] == tree_reference(data, count, 0, 0), "counted numerical answer");
        guards(result, 2);
        if (result[1] != count) {
            fprintf(stderr, "reduction body calls: n=%u actual=%u expected=%u\n", count, result[1], count);
            ++mismatches;
        }
        linea_gpu_buffer_drop(output);
    }
    return mismatches;
}
static void invalid(unsigned long device, struct linea_gpu_kernel *reduce, struct linea_gpu_kernel *matmul) {
    long a = checked(linea_gpu_buffer_new(device, 64), "invalid-test a");
    long b = checked(linea_gpu_buffer_new(device, 64), "invalid-test b");
    long out = checked(linea_gpu_buffer_new(device, 64), "invalid-test output");
    long empty = checked(linea_gpu_buffer_new(device, 0), "invalid-test empty");
    unsigned long r = (unsigned long)(uintptr_t)reduce, m = (unsigned long)(uintptr_t)matmul;
    require(linea_gpu_map(a, out, r, 1) == -EINVAL, "map accepts reduce descriptor");
    require(linea_gpu_reduce(a, out, m, 1, 0) == -EINVAL, "reduce accepts matmul descriptor");
    require(linea_gpu_matmul(a, b, out, r, 1, 1, 1) == -EINVAL, "matmul accepts reduce descriptor");
    require(linea_gpu_map_uniform(a, out, m, 1, 0) == -EINVAL, "uniform accepts matmul descriptor");
    require(linea_gpu_zip(a, b, out, m, 1) == -EINVAL, "zip accepts matmul descriptor");
    require(linea_gpu_map_uniform(a, out, r, 17, 0) == -EINVAL, "uniform accepts short input");
    require(linea_gpu_zip(a, empty, out, r, 1) == -EINVAL, "zip accepts short right input");
    require(linea_gpu_reduce(a, empty, r, 0, 0) == -EINVAL, "reduce accepts short output");
    require(linea_gpu_reduce(a, out, r, 17, 0) == -EINVAL, "reduce accepts short input");
    require(linea_gpu_reduce(a, out, r, 0, ULONG_MAX) == -EINVAL, "reduce accepts wide initial bits");
    require(linea_gpu_matmul(a, b, a, m, 2, 2, 2) == -EINVAL, "matmul aliases output with left");
    require(linea_gpu_matmul(a, b, b, m, 2, 2, 2) == -EINVAL, "matmul aliases output with right");
    require(linea_gpu_matmul(a, b, out, m, 17, 1, 1) == -EINVAL, "matmul accepts short A");
    require(linea_gpu_matmul(a, b, out, m, 1, 1, 17) == -EINVAL, "matmul accepts short B/output");
    require(linea_gpu_matmul(a, b, out, m, ULONG_MAX, 0, 0) == -EOVERFLOW, "matmul accepts wide dimension");
    require(linea_gpu_matmul(a, b, out, m, UINT32_MAX, 2, 1) == -EOVERFLOW, "matmul accepts product overflow");
    long other = checked(linea_gpu_open(), "second device");
    long foreign = checked(linea_gpu_buffer_new(other, 64), "foreign buffer");
    require(linea_gpu_reduce(a, foreign, r, 0, 0) == -EINVAL, "reduce accepts cross-device output");
    require(linea_gpu_matmul(a, foreign, out, m, 1, 1, 1) == -EINVAL, "matmul accepts cross-device right");
    require(linea_gpu_map_uniform(a, foreign, r, 1, 0) == -EINVAL, "uniform accepts cross-device output");
    require(linea_gpu_zip(a, foreign, out, r, 1) == -EINVAL, "zip accepts cross-device right");
    require(linea_gpu_matmul(a, b, foreign, m, 1, 1, 1) == -EINVAL, "matmul accepts cross-device output");
    linea_gpu_buffer_drop(foreign); linea_gpu_close(other);
    linea_gpu_buffer_drop(empty); linea_gpu_buffer_drop(out); linea_gpu_buffer_drop(b); linea_gpu_buffer_drop(a);
}
int main(int argc, char **argv) {
    require(argc == 5 && fesetround(FE_TONEAREST) == 0, "arguments/rounding mode");
    require(arithmetic(0, 1, 1) == 2 && arithmetic(2, 0x00800000, 0x3f000000) == 0x00400000, "CPU preserves subnormals");
    struct linea_gpu_kernel add = read_kernel(argv[1], 1), sub = read_kernel(argv[2], 1), matmul = read_kernel(argv[3], 2), counted = read_kernel(argv[4], 1);
    long device = checked(linea_gpu_open(), "open GPU");
    const uint32_t counts[] = {0, 1, 2, 3, 31, 32, 33, 63, 64, 65, 127, 128, 129, 1000, 4097, 65537};
    for (unsigned op = 0; op < 2; ++op)
        for (unsigned profile = 0; profile < 2; ++profile)
            for (unsigned i = 0; i < sizeof(counts) / sizeof(*counts); ++i) {
                reduction(device, op ? &sub : &add, counts[i], 0x80000000, op, profile);
                reduction(device, op ? &sub : &add, counts[i], 0x3f800001, op, profile);
            }
    reduction(device, &add, 0, 0xff812345, 0, 0);
    const uint32_t element_counts[] = {0, 1, 63, 64, 65, 129, 1000};
    for (unsigned op = 0; op < 2; ++op)
        for (unsigned i = 0; i < sizeof(element_counts) / sizeof(*element_counts); ++i) {
            elementwise(device, op ? &sub : &add, element_counts[i], op, 0, 0);
            elementwise(device, op ? &sub : &add, element_counts[i], op, 1, 0);
        }
    elementwise(device, &sub, 129, 1, 0, 1);
    const uint32_t shapes[][3] = {{0,0,0},{0,3,7},{4,0,5},{3,4,0},{1,1,1},{1,65,3},{3,5,7},{7,9,11},{16,17,19},{65,3,1}};
    for (unsigned profile = 0; profile < 2; ++profile)
        for (unsigned i = 0; i < sizeof(shapes) / sizeof(*shapes); ++i)
            matrix(device, &matmul, shapes[i][0], shapes[i][1], shapes[i][2], profile, 0);
    matrix(device, &matmul, 17, 17, 17, 0, 1);
    unsigned call_mismatches = counted_reductions(device, &counted);
    invalid(device, &add, &matmul);
    /* Release both distinct input owners and the device owner before wait. */
    long input = checked(linea_gpu_buffer_new(device, 4), "last input");
    long right = checked(linea_gpu_buffer_sized_like(input, 4), "last right");
    long output = checked(linea_gpu_buffer_sized_like(input, 4), "last output");
    uint32_t one = 0x3f800000;
    checked(linea_gpu_buffer_write(input, &one, 4), "last upload");
    checked(linea_gpu_buffer_write(right, &one, 4), "last right upload");
    long pending = checked(linea_gpu_matmul(input, right, output, (unsigned long)(uintptr_t)&matmul, 1, 1, 1), "last submit");
    linea_gpu_close(device); linea_gpu_buffer_drop(input); linea_gpu_buffer_drop(right);
    checked(linea_gpu_wait(pending), "last wait"); linea_gpu_submission_drop(pending);
    checked(linea_gpu_buffer_read(output, &one, 4), "last read"); require(one == 0x3f800000, "pending owners survive");
    linea_gpu_buffer_drop(output);
    free((void *)add.image); free((void *)sub.image); free((void *)matmul.image); free((void *)counted.image);
    printf("GPU numerical: 129 tree reductions, 6 counted reductions, 29 elementwise operations, 22 matrix products, validation/lifetime checks; %u checks, %u call-count mismatches\n", checks, call_mismatches);
    return call_mismatches ? 1 : 0;
}
