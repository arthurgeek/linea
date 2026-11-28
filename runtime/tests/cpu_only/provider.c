#include "../../gpu.h"
#include <assert.h>
#include <errno.h>

int main(void) {
    assert(linea_gpu_open() == -ENODEV);
    assert(linea_gpu_arena_new(0, 0) == -ENODEV);
    assert(linea_gpu_arena_buffer_new(0, 0) == -ENODEV);
    assert(linea_gpu_arena_reset(0) == -ENODEV);
    linea_gpu_arena_drop(0);
    assert(linea_gpu_buffer_new(0, 4) == -ENODEV);
    assert(linea_gpu_buffer_write(0, 0, 0) == -ENODEV);
    assert(linea_gpu_buffer_read(0, 0, 0) == -ENODEV);
    assert(linea_gpu_submit(0, 0, 0, 0, 0) == -ENODEV);
    assert(linea_gpu_wait(0) == -ENODEV);
    assert(linea_gpu_buffer_like(0) == -ENODEV);
    assert(linea_gpu_buffer_sized_like(0, 0) == -ENODEV);
    assert(linea_gpu_upload(0, 0, 0) == -ENODEV);
    assert(linea_gpu_download(0, 0, 0) == -ENODEV);
    assert(linea_gpu_map(0, 0, 0, 0) == -ENODEV);
    assert(linea_gpu_reduce(0, 0, 0, 0, 0) == -ENODEV);
    assert(linea_gpu_matmul(0, 0, 0, 0, 0, 0, 0) == -ENODEV);
    assert(linea_gpu_map_uniform(0, 0, 0, 0, 0) == -ENODEV);
    assert(linea_gpu_zip(0, 0, 0, 0, 0) == -ENODEV);
    linea_gpu_close(0);
    linea_gpu_buffer_drop(0);
    linea_gpu_submission_drop(0);
    return 0;
}
