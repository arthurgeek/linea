#include "../../gpu.h"
#include <assert.h>
#include <stdint.h>
#include <stdio.h>

int main(void) {
    long device = linea_gpu_open();
    assert(device > 0);
    const uint32_t values[] = {0, 1, 0x007fffff, 0x80000000, 0x7fc01234};
    long buffer = linea_gpu_buffer_new((unsigned long)device, sizeof(values));
    assert(buffer > 0);
    assert(linea_gpu_buffer_write((unsigned long)buffer, values, sizeof(values)) == 0);
    /* A buffer retains its device after the user's device owner is settled. */
    linea_gpu_close((unsigned long)device);
    uint32_t actual[5] = {0};
    assert(linea_gpu_buffer_read((unsigned long)buffer, actual, sizeof(actual)) == 0);
    for (unsigned i = 0; i < 5; ++i) assert(actual[i] == values[i]);
    assert(linea_gpu_buffer_read((unsigned long)buffer, actual, sizeof(actual) + 1) < 0);
    assert(linea_gpu_buffer_write((unsigned long)buffer, NULL, sizeof(actual) + 1) < 0);
    linea_gpu_buffer_drop((unsigned long)buffer);
    device = linea_gpu_open();
    assert(device > 0);
    long empty = linea_gpu_buffer_new((unsigned long)device, 0);
    assert(empty > 0);
    assert(linea_gpu_buffer_write((unsigned long)empty, NULL, 0) == 0);
    assert(linea_gpu_buffer_read((unsigned long)empty, NULL, 0) == 0);
    assert(linea_gpu_buffer_new((unsigned long)device, ~0UL) < 0);
    linea_gpu_buffer_drop((unsigned long)empty);
    linea_gpu_close((unsigned long)device);
    puts("production GPU buffers preserve uploaded Float32 bits");
    return 0;
}
