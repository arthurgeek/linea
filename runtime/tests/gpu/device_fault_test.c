#include "device.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>

static VkPhysicalDeviceType types[3];
static uint32_t versions[3], vendors[3], count;
static unsigned fail_create, instances, devices, selected;
#define HANDLE(type, n) ((type)(uintptr_t)(n))

VkResult vkEnumerateInstanceExtensionProperties(const char *layer, uint32_t *n, VkExtensionProperties *p) {
    (void)layer; if (!p) { *n = 1; return VK_SUCCESS; }
    assert(*n >= 1); strcpy(p[0].extensionName, VK_KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME); *n = 1; return VK_SUCCESS;
}
VkResult vkCreateInstance(const VkInstanceCreateInfo *i, const VkAllocationCallbacks *a, VkInstance *out) {
    (void)a; assert(i->pApplicationInfo->apiVersion == VK_API_VERSION_1_1);
    assert(i->flags & VK_INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR);
    if (fail_create == 1) { *out = HANDLE(VkInstance, 0xbad); return VK_ERROR_OUT_OF_HOST_MEMORY; }
    *out = HANDLE(VkInstance, 11); ++instances; return VK_SUCCESS;
}
void vkDestroyInstance(VkInstance instance, const VkAllocationCallbacks *a) { (void)a; assert(instance == HANDLE(VkInstance, 11) && instances == 1); --instances; }
VkResult vkEnumeratePhysicalDevices(VkInstance i, uint32_t *n, VkPhysicalDevice *p) {
    (void)i; if (!p) { *n = count; return VK_SUCCESS; }
    assert(*n >= count); for (uint32_t k = 0; k < count; ++k) p[k] = HANDLE(VkPhysicalDevice, 100 + k); *n = count; return VK_SUCCESS;
}
void vkGetPhysicalDeviceProperties(VkPhysicalDevice p, VkPhysicalDeviceProperties *out) {
    unsigned i = (unsigned)(uintptr_t)p - 100; assert(i < count); memset(out, 0, sizeof(*out));
    out->vendorID = vendors[i]; out->deviceType = types[i]; out->apiVersion = versions[i];
    strcpy(out->deviceName, "fixture");
}
void vkGetPhysicalDeviceQueueFamilyProperties(VkPhysicalDevice p, uint32_t *n, VkQueueFamilyProperties *out) {
    (void)p; if (!out) { *n = 1; return; }
    assert(*n >= 1); *n = 1; *out = (VkQueueFamilyProperties){ .queueFlags = VK_QUEUE_COMPUTE_BIT, .queueCount = 1 };
}
void vkGetPhysicalDeviceMemoryProperties(VkPhysicalDevice p, VkPhysicalDeviceMemoryProperties *out) { (void)p; memset(out, 0, sizeof(*out)); }
VkResult vkEnumerateDeviceExtensionProperties(VkPhysicalDevice p, const char *layer, uint32_t *n, VkExtensionProperties *out) {
    (void)p; (void)layer; if (!out) { *n = 1; return VK_SUCCESS; }
    assert(*n >= 1); strcpy(out[0].extensionName, "VK_KHR_portability_subset"); *n = 1; return VK_SUCCESS;
}
void vkGetPhysicalDeviceProperties2(VkPhysicalDevice p, VkPhysicalDeviceProperties2 *out) { vkGetPhysicalDeviceProperties(p, &out->properties); }
VkResult vkCreateDevice(VkPhysicalDevice p, const VkDeviceCreateInfo *i, const VkAllocationCallbacks *a, VkDevice *out) {
    (void)i; (void)a; selected = (unsigned)(uintptr_t)p - 100;
    if (fail_create == 2) { *out = HANDLE(VkDevice, 0xbad); return VK_ERROR_OUT_OF_HOST_MEMORY; }
    *out = HANDLE(VkDevice, 12); ++devices; return VK_SUCCESS;
}
void vkDestroyDevice(VkDevice device, const VkAllocationCallbacks *a) { (void)a; assert(device == HANDLE(VkDevice, 12) && devices == 1); --devices; }
void vkGetDeviceQueue(VkDevice d, uint32_t family, uint32_t index, VkQueue *out) { (void)d; (void)family; (void)index; *out = HANDLE(VkQueue, 13); }
VkResult vkEnumerateInstanceVersion(uint32_t *version) { *version = VK_API_VERSION_1_1; return VK_SUCCESS; }

static void reset(void) {
    assert(!instances && !devices); count = 1; fail_create = 0;
    for (unsigned i = 0; i < 3; ++i) { types[i] = VK_PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU; versions[i] = VK_API_VERSION_1_1; vendors[i] = 0x106b; }
}
int main(void) {
    struct probe_device *d = NULL;
    reset(); types[0] = VK_PHYSICAL_DEVICE_TYPE_VIRTUAL_GPU;
    assert(probe_device_open(&d) == PROBE_FAILED && d == NULL && !instances && !devices);
    reset(); types[0] = VK_PHYSICAL_DEVICE_TYPE_OTHER;
    assert(probe_device_open(&d) == PROBE_FAILED && d == NULL && !instances && !devices);
    reset(); versions[0] = VK_API_VERSION_1_0;
    assert(probe_device_open(&d) == PROBE_FAILED && d == NULL && !instances && !devices);
    reset(); count = 3; types[0] = VK_PHYSICAL_DEVICE_TYPE_VIRTUAL_GPU; versions[1] = VK_API_VERSION_1_0;
    assert(probe_device_open(&d) == PROBE_OK && selected == 2); probe_device_close(d);
    for (unsigned fail = 1; fail <= 2; ++fail) {
        reset(); fail_create = fail; d = NULL;
        assert(probe_device_open(&d) == PROBE_FAILED && d == NULL && !instances && !devices);
    }
    puts("GPU device discovery fault paths passed");
    return 0;
}
