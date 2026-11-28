#ifndef LINEA_GPU_H
#define LINEA_GPU_H

/* Compiler-owned handles. A device owner and every buffer keep a reference
 * to the device. A failed constructor answers a negated errno and owns no
 * resource. These entries are not an unchecked foreign interface for Linea. */
/* Try the platform Vulkan loader soname first. LINEA_VULKAN_LIBRARY, when
 * supplied by the build, is only a fallback if that loader cannot be opened.
 * Missing loaders/devices remain errors; no CPU execution is substituted. */
long linea_gpu_open(void);
void linea_gpu_close(unsigned long device);
long linea_gpu_buffer_new(unsigned long device, unsigned long bytes);
void linea_gpu_buffer_drop(unsigned long buffer);

/* Copy exactly bytes between host storage and a buffer. The caller lends
 * host storage for the duration of the call. Extents beyond the buffer are
 * refused before any host memory is accessed. Zero bytes needs no storage.
 * The caller keeps the buffer owner alive throughout the call. Host copies
 * and cache visibility operations serialize with submission reservations. */
long linea_gpu_buffer_write(unsigned long buffer, const void *source, unsigned long bytes);
long linea_gpu_buffer_read(unsigned long buffer, void *destination, unsigned long bytes);

/* Submit a compiler-generated Float32 map image, with storage bindings 0
 * (input) and 1 (output), a UInt32 count push constant and local size 64.
 * Both buffers belong to one device. The image is borrowed only by submit;
 * buffers are retained through completion. Host access while pending is
 * refused. The library must exclusively lend output for the submission. */
long linea_gpu_submit(unsigned long input, unsigned long output, const void *image,
                      unsigned long image_bytes, unsigned long count);

/* Waiting parks the current Linea fiber, or its native thread outside a
 * fiber. Dropping settles the submission and releases its retained buffers.
 * Success and device loss establish settlement. Any other fence-wait result
 * leaves queued resource use indeterminate and aborts the process; it is not
 * answered as a recoverable error followed by unsafe resource destruction. */
long linea_gpu_wait(unsigned long submission);
void linea_gpu_submission_drop(unsigned long submission);

/* Library adapters keep addresses confined to checked mem operations. */
long linea_gpu_buffer_like(unsigned long buffer);
long linea_gpu_buffer_sized_like(unsigned long input, unsigned long bytes);
long linea_gpu_upload(unsigned long buffer, unsigned long at, unsigned long bytes);
long linea_gpu_download(unsigned long buffer, unsigned long at, unsigned long bytes);
long linea_gpu_map(unsigned long input, unsigned long output, unsigned long kernel, unsigned long count);

/* The compiler's immutable image descriptor, retained for the program's life. */
struct linea_gpu_kernel {
    const void *image;
    unsigned long bytes;
    /* 0: unary map, 1: binary callable, 2: matrix multiplication. */
    unsigned long kind;
};

/* Reduction dispatches one fixed 64-lane tree, writes one word, and combines
 * initial_bits exactly once, last. Matrix dimensions are row-major M,K,N.
 * Both operations retain every input until their submission completes. */
long linea_gpu_reduce(unsigned long input, unsigned long output, unsigned long kernel,
                      unsigned long count, unsigned long initial_bits);
/* Binary images also expose elementwise entry points. Uniform values are
 * raw Float32 bits, copied into push constants before submission returns. */
long linea_gpu_map_uniform(unsigned long input, unsigned long output, unsigned long kernel,
                           unsigned long count, unsigned long uniform_bits);
long linea_gpu_zip(unsigned long left, unsigned long right, unsigned long output,
                   unsigned long kernel, unsigned long count);
long linea_gpu_matmul(unsigned long left, unsigned long right, unsigned long output,
                      unsigned long kernel, unsigned long rows, unsigned long inner,
                      unsigned long columns);

#endif
