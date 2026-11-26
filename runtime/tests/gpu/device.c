#include "device.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int failed(const char *operation, VkResult result) {
    fprintf(stderr, "GPU probe: %s failed (%d)\n", operation, result);
    return PROBE_FAILED;
}

static int extension(const VkExtensionProperties *list, uint32_t count, const char *name) {
    for (uint32_t i = 0; i < count; ++i)
        if (strcmp(list[i].extensionName, name) == 0) return 1;
    return 0;
}

void probe_device_close(struct probe_device *device) {
    if (!device) return;
    if (device->logical) vkDestroyDevice(device->logical, NULL);
    if (device->instance) vkDestroyInstance(device->instance, NULL);
    free(device);
}

int probe_device_open(struct probe_device **out) {
    *out = NULL;
    struct probe_device *d = calloc(1, sizeof(*d));
    if (!d) return failed("allocate device record", VK_ERROR_OUT_OF_HOST_MEMORY);
    VkExtensionProperties *extensions = NULL;
    VkPhysicalDevice *devices = NULL;
    struct probe_candidate *candidates = NULL;
    uint32_t *families = NULL;
    VkResult status;
    const char *operation = "enumerate instance extensions";
    uint32_t count = 0;
    status = vkEnumerateInstanceExtensionProperties(NULL, &count, NULL);
    if (status != VK_SUCCESS) goto fail;
    if (count) {
        extensions = calloc(count, sizeof(*extensions));
        if (!extensions) { operation = "allocate extension properties"; status = VK_ERROR_OUT_OF_HOST_MEMORY; goto fail; }
        status = vkEnumerateInstanceExtensionProperties(NULL, &count, extensions);
        if (status != VK_SUCCESS) goto fail;
    }
    const char *instance_extensions[] = { VK_KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME };
    int portability = extension(extensions, count, instance_extensions[0]);
    free(extensions);
    extensions = NULL;
    VkApplicationInfo app = { .sType = VK_STRUCTURE_TYPE_APPLICATION_INFO,
        .pApplicationName = "Linea GPU qualification", .apiVersion = VK_API_VERSION_1_1 };
    VkInstanceCreateInfo instance = { .sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
        .pApplicationInfo = &app, .enabledExtensionCount = portability ? 1 : 0,
        .ppEnabledExtensionNames = instance_extensions,
        .flags = portability ? VK_INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR : 0 };
    VkInstance made_instance;
    operation = "vkCreateInstance";
    status = vkCreateInstance(&instance, NULL, &made_instance);
    if (status != VK_SUCCESS) goto fail;
    d->instance = made_instance;
    count = 0;
    operation = "vkEnumeratePhysicalDevices";
    status = vkEnumeratePhysicalDevices(d->instance, &count, NULL);
    if (status != VK_SUCCESS) goto fail;
    if (!count) { status = VK_ERROR_INITIALIZATION_FAILED; goto fail; }
    devices = calloc(count, sizeof(*devices));
    candidates = calloc(count, sizeof(*candidates));
    families = calloc(count, sizeof(*families));
    if (!devices || !candidates || !families) { operation = "allocate physical device candidates"; status = VK_ERROR_OUT_OF_HOST_MEMORY; goto fail; }
    status = vkEnumeratePhysicalDevices(d->instance, &count, devices);
    if (status != VK_SUCCESS) goto fail;
    for (uint32_t i = 0; i < count; ++i) {
        VkPhysicalDeviceProperties p;
        vkGetPhysicalDeviceProperties(devices[i], &p);
        candidates[i].vendor = p.vendorID;
        candidates[i].hardware = p.deviceType == VK_PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU || p.deviceType == VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU;
        candidates[i].api = p.apiVersion;
        uint32_t n = 0;
        vkGetPhysicalDeviceQueueFamilyProperties(devices[i], &n, NULL);
        VkQueueFamilyProperties *queues = calloc(n ? n : 1, sizeof(*queues));
        if (!queues) { operation = "allocate queue properties"; status = VK_ERROR_OUT_OF_HOST_MEMORY; goto fail; }
        vkGetPhysicalDeviceQueueFamilyProperties(devices[i], &n, queues);
        for (uint32_t j = 0; j < n; ++j) {
            if (queues[j].queueCount && (queues[j].queueFlags & VK_QUEUE_COMPUTE_BIT)) {
                candidates[i].compute = 1;
                families[i] = j;
                break;
            }
        }
        free(queues);
    }
    size_t selected;
    operation = "select Apple physical device with Vulkan 1.1 compute";
    if (!probe_select_device(candidates, count, &selected)) {
        fprintf(stderr, "GPU probe: no Apple-vendor hardware compute device\n");
        status = VK_ERROR_FEATURE_NOT_PRESENT;
        goto fail;
    }
    d->physical = devices[selected];
    d->family = families[selected];
    free(devices); devices = NULL;
    free(candidates); candidates = NULL;
    free(families); families = NULL;
    vkGetPhysicalDeviceProperties(d->physical, &d->properties);
    vkGetPhysicalDeviceMemoryProperties(d->physical, &d->memory);
    count = 0;
    operation = "vkEnumerateDeviceExtensionProperties";
    status = vkEnumerateDeviceExtensionProperties(d->physical, NULL, &count, NULL);
    if (status != VK_SUCCESS) goto fail;
    extensions = calloc(count ? count : 1, sizeof(*extensions));
    if (!extensions) { operation = "allocate extension properties"; status = VK_ERROR_OUT_OF_HOST_MEMORY; goto fail; }
    status = vkEnumerateDeviceExtensionProperties(d->physical, NULL, &count, extensions);
    if (status != VK_SUCCESS) goto fail;
    const char *enabled[2];
    uint32_t enabled_count = 0;
    if (extension(extensions, count, "VK_KHR_portability_subset"))
        enabled[enabled_count++] = "VK_KHR_portability_subset";
    int float_controls = extension(extensions, count, VK_KHR_SHADER_FLOAT_CONTROLS_EXTENSION_NAME);
    if (float_controls) enabled[enabled_count++] = VK_KHR_SHADER_FLOAT_CONTROLS_EXTENSION_NAME;
    if (float_controls) {
        d->floats.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FLOAT_CONTROLS_PROPERTIES;
        VkPhysicalDeviceProperties2 p = { .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PROPERTIES_2, .pNext = &d->floats };
        vkGetPhysicalDeviceProperties2(d->physical, &p);
        d->profile = probe_float_profile(d->floats.shaderDenormPreserveFloat32,
            d->floats.shaderSignedZeroInfNanPreserveFloat32, d->floats.shaderRoundingModeRTEFloat32);
    }
    float priority = 1.0f;
    VkDeviceQueueCreateInfo queue = { .sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
        .queueFamilyIndex = d->family, .queueCount = 1, .pQueuePriorities = &priority };
    VkDeviceCreateInfo device = { .sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
        .queueCreateInfoCount = 1, .pQueueCreateInfos = &queue,
        .enabledExtensionCount = enabled_count, .ppEnabledExtensionNames = enabled };
    VkDevice made_logical;
    operation = "vkCreateDevice";
    status = vkCreateDevice(d->physical, &device, NULL, &made_logical);
    if (status != VK_SUCCESS) goto fail;
    d->logical = made_logical;
    vkGetDeviceQueue(d->logical, d->family, 0, &d->queue);
    uint32_t loader = 0;
    operation = "vkEnumerateInstanceVersion";
    status = vkEnumerateInstanceVersion(&loader);
    if (status != VK_SUCCESS) goto fail;
    printf("device=%s vendor=0x%x api=%u.%u.%u driver=%u loader=%u.%u.%u\n",
        d->properties.deviceName, d->properties.vendorID,
        VK_API_VERSION_MAJOR(d->properties.apiVersion), VK_API_VERSION_MINOR(d->properties.apiVersion),
        VK_API_VERSION_PATCH(d->properties.apiVersion), d->properties.driverVersion,
        VK_API_VERSION_MAJOR(loader), VK_API_VERSION_MINOR(loader), VK_API_VERSION_PATCH(loader));
    printf("float32 denorm_preserve=%u signed_zero_inf_nan=%u round_to_nearest=%u profile=%u\n",
        d->floats.shaderDenormPreserveFloat32, d->floats.shaderSignedZeroInfNanPreserveFloat32,
        d->floats.shaderRoundingModeRTEFloat32, d->profile);
    free(extensions);
    *out = d;
    return PROBE_OK;
fail:
    failed(operation, status);
    free(extensions); free(devices); free(candidates); free(families);
    probe_device_close(d);
    return PROBE_FAILED;
}
