/* Compare row/column packing with the production strict matmul algorithm.
 * Timings include pipeline creation, submission, completion waiting and cleanup;
 * they are resident-buffer wall times, not device timestamp measurements. */
#define _POSIX_C_SOURCE 200809L
#include "../runtime/gpu.h"
#include <fenv.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static uint64_t now(void) {
    struct timespec t;
    if (clock_gettime(CLOCK_MONOTONIC, &t)) { perror("clock_gettime"); exit(1); }
    return (uint64_t)t.tv_sec * UINT64_C(1000000000) + (uint64_t)t.tv_nsec;
}
static void require(int condition, const char *message) {
    if (!condition) { fprintf(stderr, "layout benchmark: %s\n", message); exit(1); }
}
static unsigned long checked(long value, const char *message) {
    if (value < 0) { fprintf(stderr, "layout benchmark: %s (%ld)\n", message, value); exit(1); }
    return (unsigned long)value;
}
static uint32_t bits(float value) { uint32_t word; memcpy(&word, &value, 4); return word; }
static struct linea_gpu_kernel kernel(const char *path) {
    FILE *file = fopen(path, "rb"); require(file != NULL, "open shader");
    require(!fseek(file, 0, SEEK_END), "seek shader");
    long length = ftell(file); require(length > 0 && !fseek(file, 0, SEEK_SET), "shader size");
    void *data = malloc((size_t)length); require(data != NULL, "shader allocation");
    require(fread(data, 1, (size_t)length, file) == (size_t)length, "read shader");
    require(!fclose(file), "close shader");
    return (struct linea_gpu_kernel){data, (unsigned long)length, 2};
}
static float *allocate(size_t count) {
    float *values = calloc(count, sizeof(float)); require(values != NULL, "host allocation"); return values;
}
static void fill(float *values, unsigned rows, unsigned columns, unsigned seed) {
    for (unsigned r = 0; r < rows; ++r)
        for (unsigned c = 0; c < columns; ++c)
            values[(size_t)r * columns + c] = (float)((int)((r * 7 + c * 3 + seed) % 23) - 11) / 16.0f;
}
static void transpose(float *out, const float *in, unsigned rows, unsigned columns) {
    for (unsigned r = 0; r < rows; ++r)
        for (unsigned c = 0; c < columns; ++c) out[(size_t)c * rows + r] = in[(size_t)r * columns + c];
}
static void reference(float *out, const float *a, const float *b, unsigned m, unsigned k, unsigned n) {
    for (unsigned r = 0; r < m; ++r)
        for (unsigned c = 0; c < n; ++c) {
            volatile float sum = 0.0f;
            for (unsigned lane = 0; lane < k; ++lane) {
                volatile float product = a[(size_t)r * k + lane] * b[(size_t)lane * n + c];
                sum = sum + product;
            }
            out[(size_t)r * n + c] = sum;
        }
}
struct buffers { unsigned long left, right, output; };
static struct buffers upload(unsigned long device, const float *a, const float *b, unsigned m, unsigned k, unsigned n) {
    struct buffers buffers = {
        checked(linea_gpu_buffer_new(device, (unsigned long)m * k * 4), "allocate left"),
        checked(linea_gpu_buffer_new(device, (unsigned long)k * n * 4), "allocate right"),
        checked(linea_gpu_buffer_new(device, (unsigned long)m * n * 4), "allocate output")
    };
    checked(linea_gpu_buffer_write(buffers.left, a, (unsigned long)m * k * 4), "upload left");
    checked(linea_gpu_buffer_write(buffers.right, b, (unsigned long)k * n * 4), "upload right");
    return buffers;
}
static void release(struct buffers b) {
    linea_gpu_buffer_drop(b.output); linea_gpu_buffer_drop(b.right); linea_gpu_buffer_drop(b.left);
}
static uint64_t measure(struct buffers b, const struct linea_gpu_kernel *image, unsigned m, unsigned k, unsigned n, unsigned repetitions) {
    uint64_t start = now();
    for (unsigned i = 0; i < repetitions; ++i) {
        unsigned long job = checked(linea_gpu_matmul(b.left, b.right, b.output,
            (unsigned long)(uintptr_t)image, m, k, n), "submit");
        checked(linea_gpu_wait(job), "wait");
        linea_gpu_submission_drop(job);
    }
    return now() - start;
}
static uint64_t verify(struct buffers b, float *download, const float *expected, unsigned m, unsigned n, int column) {
    checked(linea_gpu_buffer_read(b.output, download, (unsigned long)m * n * 4), "download");
    uint64_t checksum = 0;
    for (unsigned r = 0; r < m; ++r)
        for (unsigned c = 0; c < n; ++c) {
            uint32_t actual = bits(download[column ? (size_t)c * m + r : (size_t)r * n + c]);
            require(actual == bits(expected[(size_t)r * n + c]), "raw-bit output differs from scalar reference");
            checksum += actual;
        }
    return checksum;
}
static void shape(unsigned long device, const struct linea_gpu_kernel *row, const struct linea_gpu_kernel *column,
                  unsigned m, unsigned k, unsigned n, unsigned seed) {
    float *a = allocate((size_t)m * k), *b = allocate((size_t)k * n);
    float *ac = allocate((size_t)m * k), *bc = allocate((size_t)k * n);
    float *expected = allocate((size_t)m * n), *download = allocate((size_t)m * n);
    fill(a, m, k, seed); fill(b, k, n, seed + 7);
    reference(expected, a, b, m, k, n);
    uint64_t start = now();
    struct buffers rb = upload(device, a, b, m, k, n);
    uint64_t row_setup = now() - start;
    start = now(); transpose(ac, a, m, k); transpose(bc, b, k, n);
    uint64_t packing = now() - start;
    start = now(); struct buffers cb = upload(device, ac, bc, m, k, n);
    uint64_t column_setup = now() - start;
    printf("setup,%u,%u,%u,%llu,%llu,%llu\n", m, k, n,
        (unsigned long long)row_setup, (unsigned long long)column_setup, (unsigned long long)packing);
    measure(rb, row, m, k, n, 2); measure(cb, column, m, k, n, 2);
    verify(rb, download, expected, m, n, 0); verify(cb, download, expected, m, n, 1);
    for (unsigned round = 0; round < 9; ++round) {
        uint64_t rt, ct;
        if (round % 2) {
            ct = measure(cb, column, m, k, n, 3); rt = measure(rb, row, m, k, n, 3);
        } else {
            rt = measure(rb, row, m, k, n, 3); ct = measure(cb, column, m, k, n, 3);
        }
        uint64_t checksum = verify(rb, download, expected, m, n, 0);
        require(checksum == verify(cb, download, expected, m, n, 1), "layout checksum differs");
        printf("resident,%u,%u,%u,%u,3,%llu,%llu,%llu\n", m, k, n, round,
            (unsigned long long)rt, (unsigned long long)ct, (unsigned long long)checksum);
    }
    release(cb); release(rb);
    free(download); free(expected); free(bc); free(ac); free(b); free(a);
}
int main(int argc, char **argv) {
    require(argc == 3, "expected row and column shader paths");
    require(!fesetround(FE_TONEAREST), "set round-to-nearest");
    struct linea_gpu_kernel row = kernel(argv[1]), column = kernel(argv[2]);
    unsigned long device = checked(linea_gpu_open(), "open real GPU");
    const unsigned shapes[][3] = {{3,4,5},{4,4,4},{8,8,8},{16,16,16},{32,64,16},{128,128,128},
        {3,4,1},{4,4,1},{8,8,1},{16,16,1},{32,64,1},{128,128,1},
        {1,3,4},{1,4,4},{1,8,8},{1,16,16},{1,32,64},{1,128,128}};
    puts("kind,rows,inner,columns,round,repetitions,row_submit_wait_ns,column_submit_wait_ns,checksum");
    for (size_t i = 0; i < sizeof(shapes) / sizeof(shapes[0]); ++i)
        shape(device, &row, &column, shapes[i][0], shapes[i][1], shapes[i][2], (unsigned)i + 1);
    linea_gpu_close(device); free((void *)column.image); free((void *)row.image);
    return 0;
}
