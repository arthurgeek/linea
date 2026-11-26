#include "probe.h"
#include <stdio.h>

int main(int argc, char **argv) {
#ifndef __APPLE__
    fprintf(stderr, "GPU probe requires Apple hardware on Darwin\n");
    return PROBE_FAILED;
#endif
    struct probe_device *device = NULL;
    int status = probe_device_open(&device);
    if (status != PROBE_OK) return status;
    if (argc != 10) {
        fprintf(stderr, "usage: gpu-probe COPY.spv FLOAT0.spv ... FLOAT7.spv\n");
        probe_device_close(device);
        return PROBE_FAILED;
    }
    const uint32_t lengths[] = {0, 1, 1000, 1024};
    for (size_t i = 0; i < sizeof(lengths) / sizeof(lengths[0]); ++i) {
        int result = probe_copy(device, argv[1], lengths[i]);
        if (result > status) status = result;
        if (result == PROBE_FAILED) break;
    }
    if (status != PROBE_FAILED) {
        const char *paths[8];
        for (unsigned i = 0; i < 8; ++i) paths[i] = argv[i + 2];
        int result = probe_float(device, paths);
        if (result > status) status = result;
    }
    probe_device_close(device);
    return status;
}
