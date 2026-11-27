/* The explicit CPU-only build implements the canonical GPU ABI without
 * acquiring resources or substituting CPU execution. */
#include "gpu.h"
#include <errno.h>

long linea_gpu_open(void) {
    return -ENODEV;
}

void linea_gpu_close(unsigned long device) {
    (void)device;
}

long linea_gpu_buffer_new(unsigned long device, unsigned long bytes) {
    (void)device;
    (void)bytes;
    return -ENODEV;
}

void linea_gpu_buffer_drop(unsigned long buffer) {
    (void)buffer;
}

long linea_gpu_buffer_write(unsigned long buffer, const void *source, unsigned long bytes) {
    (void)buffer;
    (void)source;
    (void)bytes;
    return -ENODEV;
}

long linea_gpu_buffer_read(unsigned long buffer, void *destination, unsigned long bytes) {
    (void)buffer;
    (void)destination;
    (void)bytes;
    return -ENODEV;
}

long linea_gpu_submit(unsigned long input, unsigned long output, const void *image, unsigned long image_bytes, unsigned long count) {
    (void)input;
    (void)output;
    (void)image;
    (void)image_bytes;
    (void)count;
    return -ENODEV;
}

long linea_gpu_wait(unsigned long submission) {
    (void)submission;
    return -ENODEV;
}

void linea_gpu_submission_drop(unsigned long submission) {
    (void)submission;
}

long linea_gpu_buffer_like(unsigned long buffer) {
    (void)buffer;
    return -ENODEV;
}

long linea_gpu_buffer_sized_like(unsigned long input, unsigned long bytes) {
    (void)input;
    (void)bytes;
    return -ENODEV;
}

long linea_gpu_upload(unsigned long buffer, unsigned long at, unsigned long bytes) {
    (void)buffer;
    (void)at;
    (void)bytes;
    return -ENODEV;
}

long linea_gpu_download(unsigned long buffer, unsigned long at, unsigned long bytes) {
    (void)buffer;
    (void)at;
    (void)bytes;
    return -ENODEV;
}

long linea_gpu_map(unsigned long input, unsigned long output, unsigned long kernel, unsigned long count) {
    (void)input;
    (void)output;
    (void)kernel;
    (void)count;
    return -ENODEV;
}

long linea_gpu_reduce(unsigned long input, unsigned long output, unsigned long kernel, unsigned long count, unsigned long initial_bits) {
    (void)input;
    (void)output;
    (void)kernel;
    (void)count;
    (void)initial_bits;
    return -ENODEV;
}

long linea_gpu_matmul(unsigned long left, unsigned long right, unsigned long output, unsigned long kernel, unsigned long rows, unsigned long inner, unsigned long columns) {
    (void)left;
    (void)right;
    (void)output;
    (void)kernel;
    (void)rows;
    (void)inner;
    (void)columns;
    return -ENODEV;
}

long linea_gpu_map_uniform(unsigned long input, unsigned long output, unsigned long kernel, unsigned long count, unsigned long uniform_bits) {
    (void)input;
    (void)output;
    (void)kernel;
    (void)count;
    (void)uniform_bits;
    return -ENODEV;
}

long linea_gpu_zip(unsigned long left, unsigned long right, unsigned long output, unsigned long kernel, unsigned long count) {
    (void)left;
    (void)right;
    (void)output;
    (void)kernel;
    (void)count;
    return -ENODEV;
}
