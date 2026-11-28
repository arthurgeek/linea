#include "../../gpu.h"
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char **argv) {
    assert(argc == 2);
    FILE *f = fopen(argv[1], "rb");
    assert(f && fseek(f, 0, SEEK_END) == 0);
    long bytes = ftell(f);
    assert(bytes >= 20 && bytes % 4 == 0 && fseek(f, 0, SEEK_SET) == 0);
    uint32_t *code = malloc((size_t)bytes);
    assert(code && fread(code, 1, (size_t)bytes, f) == (size_t)bytes);
    assert(fclose(f) == 0);
    const uint32_t lengths[] = {0, 1, 1000, 1024};
    for (unsigned sample = 0; sample < 4; ++sample) {
        uint32_t count = lengths[sample];
        uint32_t source[1088], result[1088], guards[1088];
        for (uint32_t i = 0; i < count + 64; ++i) guards[i] = 0xdeadbeefu;
        for (uint32_t i = 0; i < count; ++i) source[i] = 0x12340000u + i;
        long device = linea_gpu_open();
        assert(device > 0);
        long a = linea_gpu_buffer_new((unsigned long)device, (unsigned long)count * 4);
        long b = linea_gpu_buffer_new((unsigned long)device, ((unsigned long)count + 64) * 4);
        long c = linea_gpu_buffer_new((unsigned long)device, ((unsigned long)count + 64) * 4);
        assert(a > 0 && b > 0 && c > 0);
        assert(linea_gpu_buffer_write((unsigned long)a, source, (unsigned long)count * 4) == 0);
        assert(linea_gpu_submit((unsigned long)a, (unsigned long)b, code, (unsigned long)bytes, (unsigned long)count + 1) < 0);
        assert(linea_gpu_submit((unsigned long)a, (unsigned long)a, code, (unsigned long)bytes, count) < 0);
        assert(linea_gpu_submit((unsigned long)a, (unsigned long)b, code, (unsigned long)bytes - 1, count) < 0);
        assert(linea_gpu_buffer_write((unsigned long)b, guards, ((unsigned long)count + 64) * 4) == 0);
        assert(linea_gpu_buffer_write((unsigned long)c, guards, ((unsigned long)count + 64) * 4) == 0);
        long first = linea_gpu_submit((unsigned long)a, (unsigned long)b, code, (unsigned long)bytes, count);
        long second = linea_gpu_submit((unsigned long)b, (unsigned long)c, code, (unsigned long)bytes, count);
        assert(first > 0 && second > 0);
        /* Submitters can settle owners before either GPU operation completes. */
        linea_gpu_buffer_drop((unsigned long)a);
        linea_gpu_buffer_drop((unsigned long)b);
        linea_gpu_close((unsigned long)device);
        assert(linea_gpu_wait((unsigned long)second) == 0);
        assert(linea_gpu_buffer_read((unsigned long)c, result, ((unsigned long)count + 64) * 4) == 0);
        for (uint32_t i = 0; i < count; ++i) assert(result[i] == source[i]);
        for (uint32_t i = count; i < count + 64; ++i) assert(result[i] == guards[i]);
        linea_gpu_submission_drop((unsigned long)first);
        linea_gpu_submission_drop((unsigned long)second);
        linea_gpu_buffer_drop((unsigned long)c);
    }
    free(code);
    puts("production GPU submissions chain resident buffers and retain pending resources");
    return 0;
}
