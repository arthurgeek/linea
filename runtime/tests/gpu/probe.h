#ifndef LINEA_GPU_PROBE_H
#define LINEA_GPU_PROBE_H
#include <stddef.h>
#include <stdint.h>

enum probe_status { PROBE_OK = 0, PROBE_MISMATCH = 1, PROBE_FAILED = 2 };
#define PROBE_MIN_API UINT32_C(0x00401000)
struct probe_candidate { uint32_t vendor; int hardware; int compute; uint32_t api; };
int probe_select_device(const struct probe_candidate *devices, size_t count, size_t *selected);
int probe_workgroups(uint64_t count, uint32_t limit, uint32_t *groups);
int probe_buffer_bytes(uint32_t count, uint64_t limit, uint64_t *bytes);
int probe_check_words(const uint32_t *expected, const uint32_t *actual, uint32_t count);
int probe_compare_word(const char *operation, uint32_t left, uint32_t right, uint32_t actual, uint32_t expected);
unsigned probe_float_profile(int denorm, int preserve, int nearest);
struct probe_device;
int probe_device_open(struct probe_device **out);
void probe_device_close(struct probe_device *device);
int probe_copy(struct probe_device *device, const char *spirv_path, uint32_t count);
int probe_float(struct probe_device *device, const char *paths[8]);
#endif
