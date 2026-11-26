#ifndef LINEA_GPU_DEVICE_H
#define LINEA_GPU_DEVICE_H
#include "probe.h"
#include <vulkan/vulkan.h>
_Static_assert(PROBE_MIN_API == VK_API_VERSION_1_1, "probe API floor matches Vulkan encoding");

struct probe_device {
    VkInstance instance;
    VkPhysicalDevice physical;
    VkDevice logical;
    VkQueue queue;
    uint32_t family;
    VkPhysicalDeviceProperties properties;
    VkPhysicalDeviceMemoryProperties memory;
    VkPhysicalDeviceFloatControlsProperties floats;
    unsigned profile;
};
#endif
