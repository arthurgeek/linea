#include "gpu.h"
#include "park.h"

#define VK_NO_PROTOTYPES
#include <vulkan/vulkan.h>
#include <dlfcn.h>
#include <errno.h>
#include <limits.h>
#include <pthread.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

typedef char linea_gpu_kernel_width[sizeof(struct linea_gpu_kernel) == 24 ? 1 : -1];

#if defined(__APPLE__)
#define GPU_VULKAN_SONAME "libvulkan.1.dylib"
#else
#define GPU_VULKAN_SONAME "libvulkan.so.1"
#endif

#define GPU_FUNCTIONS(X) \
    X(EnumerateInstanceExtensionProperties) \
    X(CreateInstance) X(DestroyInstance) X(EnumeratePhysicalDevices) \
    X(GetPhysicalDeviceProperties) X(GetPhysicalDeviceMemoryProperties) \
    X(GetPhysicalDeviceQueueFamilyProperties) X(EnumerateDeviceExtensionProperties) \
    X(CreateDevice) X(DestroyDevice) X(GetDeviceQueue) \
    X(CreateBuffer) X(DestroyBuffer) X(GetBufferMemoryRequirements) \
    X(AllocateMemory) X(FreeMemory) X(BindBufferMemory) \
    X(MapMemory) X(UnmapMemory) X(FlushMappedMemoryRanges) X(InvalidateMappedMemoryRanges) \
    X(CreateShaderModule) X(DestroyShaderModule) X(CreateDescriptorSetLayout) X(DestroyDescriptorSetLayout) \
    X(CreatePipelineLayout) X(DestroyPipelineLayout) X(CreateComputePipelines) X(DestroyPipeline) \
    X(CreateDescriptorPool) X(DestroyDescriptorPool) X(AllocateDescriptorSets) X(UpdateDescriptorSets) \
    X(CreateCommandPool) X(DestroyCommandPool) X(AllocateCommandBuffers) X(BeginCommandBuffer) \
    X(CmdPipelineBarrier) X(CmdBindPipeline) X(CmdBindDescriptorSets) X(CmdPushConstants) \
    X(CmdDispatch) X(EndCommandBuffer) X(CreateFence) X(DestroyFence) X(QueueSubmit) X(WaitForFences)

struct gpu_api {
#define FIELD(name) PFN_vk##name name;
    GPU_FUNCTIONS(FIELD)
#undef FIELD
};

struct gpu_device {
    void *library;
    struct gpu_api api;
    VkInstance instance;
    VkPhysicalDevice physical;
    VkDevice logical;
    VkQueue queue;
    uint32_t family;
    VkPhysicalDeviceProperties properties;
    VkPhysicalDeviceMemoryProperties memory;
    pthread_mutex_t references_lock;
    pthread_mutex_t queue_lock;
    unsigned long references;
};

struct gpu_buffer {
    struct gpu_device *device;
    VkBuffer buffer;
    VkDeviceMemory memory;
    void *mapped;
    unsigned long bytes;
    unsigned long references;
    unsigned long in_flight;
};

static long gpu_error(VkResult status) {
    if (status == VK_ERROR_OUT_OF_HOST_MEMORY || status == VK_ERROR_OUT_OF_DEVICE_MEMORY) return -ENOMEM;
    if (status == VK_ERROR_FEATURE_NOT_PRESENT || status == VK_ERROR_INCOMPATIBLE_DRIVER) return -ENODEV;
    return -EIO;
}

static void device_destroy(struct gpu_device *d) {
    if (d->logical) d->api.DestroyDevice(d->logical, NULL);
    if (d->instance) d->api.DestroyInstance(d->instance, NULL);
    if (d->library) dlclose(d->library);
    if (pthread_mutex_destroy(&d->queue_lock) != 0) abort();
    if (pthread_mutex_destroy(&d->references_lock) != 0) abort();
    free(d);
}

static void device_retain(struct gpu_device *d) {
    if (pthread_mutex_lock(&d->references_lock) != 0) abort();
    if (d->references == ULONG_MAX) abort();
    ++d->references;
    if (pthread_mutex_unlock(&d->references_lock) != 0) abort();
}

void linea_gpu_close(unsigned long device) {
    struct gpu_device *d = (struct gpu_device *)(uintptr_t)device;
    if (pthread_mutex_lock(&d->references_lock) != 0) abort();
    int last = --d->references == 0;
    if (pthread_mutex_unlock(&d->references_lock) != 0) abort();
    if (last) device_destroy(d);
}

static int has_extension(const VkExtensionProperties *list, uint32_t count, const char *name) {
    for (uint32_t i = 0; i < count; ++i)
        if (strcmp(list[i].extensionName, name) == 0) return 1;
    return 0;
}

long linea_gpu_open(void) {
    struct gpu_device *d = calloc(1, sizeof(*d));
    if (!d) return -ENOMEM;
    int lock_status = pthread_mutex_init(&d->references_lock, NULL);
    if (lock_status != 0) { free(d); return -lock_status; }
    lock_status = pthread_mutex_init(&d->queue_lock, NULL);
    if (lock_status != 0) {
        if (pthread_mutex_destroy(&d->references_lock) != 0) abort();
        free(d);
        return -lock_status;
    }
    d->references = 1;
    long error = -ENODEV;
    VkExtensionProperties *extensions = NULL;
    VkPhysicalDevice *devices = NULL;
    /* Prefer the deployment machine's standard loader. A build-pinned Nix
     * path is only a development fallback; it must not tie shipped programs
     * to the build host's store. A present loader's errors remain errors. */
    d->library = dlopen(GPU_VULKAN_SONAME, RTLD_NOW | RTLD_LOCAL);
#ifdef LINEA_VULKAN_LIBRARY
    if (!d->library && strcmp(GPU_VULKAN_SONAME, LINEA_VULKAN_LIBRARY) != 0)
        d->library = dlopen(LINEA_VULKAN_LIBRARY, RTLD_NOW | RTLD_LOCAL);
#endif
    if (!d->library) goto fail;
#define LOAD(name) do { \
    void *symbol = dlsym(d->library, "vk" #name); \
    if (!symbol || sizeof(symbol) != sizeof(d->api.name)) goto fail; \
    memcpy(&d->api.name, &symbol, sizeof(symbol)); \
} while (0);
    GPU_FUNCTIONS(LOAD)
#undef LOAD
    uint32_t count = 0;
    VkResult r = d->api.EnumerateInstanceExtensionProperties(NULL, &count, NULL);
    if (r != VK_SUCCESS) { error = gpu_error(r); goto fail; }
    extensions = calloc(count ? count : 1, sizeof(*extensions));
    if (!extensions) { error = -ENOMEM; goto fail; }
    r = d->api.EnumerateInstanceExtensionProperties(NULL, &count, extensions);
    if (r != VK_SUCCESS) { error = gpu_error(r); goto fail; }
    const char *portability = VK_KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME;
    int portable = has_extension(extensions, count, portability);
    free(extensions); extensions = NULL;
    VkApplicationInfo app = { .sType = VK_STRUCTURE_TYPE_APPLICATION_INFO,
        .pApplicationName = "Linea", .apiVersion = VK_API_VERSION_1_1 };
    VkInstanceCreateInfo instance = { .sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
        .pApplicationInfo = &app, .enabledExtensionCount = portable ? 1u : 0u,
        .ppEnabledExtensionNames = &portability,
        .flags = portable ? VK_INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR : 0u };
    VkInstance made_instance;
    r = d->api.CreateInstance(&instance, NULL, &made_instance);
    if (r != VK_SUCCESS) { error = gpu_error(r); goto fail; }
    d->instance = made_instance;
    count = 0;
    r = d->api.EnumeratePhysicalDevices(d->instance, &count, NULL);
    if (r != VK_SUCCESS) { error = gpu_error(r); goto fail; }
    if (!count) goto fail;
    devices = calloc(count, sizeof(*devices));
    if (!devices) { error = -ENOMEM; goto fail; }
    r = d->api.EnumeratePhysicalDevices(d->instance, &count, devices);
    if (r != VK_SUCCESS) { error = gpu_error(r); goto fail; }
    for (uint32_t i = 0; i < count && !d->physical; ++i) {
        VkPhysicalDeviceProperties p;
        d->api.GetPhysicalDeviceProperties(devices[i], &p);
        if (p.apiVersion < VK_API_VERSION_1_1 ||
            (p.deviceType != VK_PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU &&
             p.deviceType != VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU)) continue;
#if defined(__APPLE__)
        if (p.vendorID != 0x106b) continue;
#endif
        uint32_t n = 0;
        d->api.GetPhysicalDeviceQueueFamilyProperties(devices[i], &n, NULL);
        VkQueueFamilyProperties *queues = calloc(n ? n : 1, sizeof(*queues));
        if (!queues) { error = -ENOMEM; goto fail; }
        d->api.GetPhysicalDeviceQueueFamilyProperties(devices[i], &n, queues);
        for (uint32_t j = 0; j < n; ++j) {
            if (queues[j].queueCount && (queues[j].queueFlags & VK_QUEUE_COMPUTE_BIT)) {
                d->physical = devices[i];
                d->family = j;
                d->properties = p;
                break;
            }
        }
        free(queues);
    }
    free(devices); devices = NULL;
    if (!d->physical) goto fail;
    d->api.GetPhysicalDeviceMemoryProperties(d->physical, &d->memory);
    count = 0;
    r = d->api.EnumerateDeviceExtensionProperties(d->physical, NULL, &count, NULL);
    if (r != VK_SUCCESS) { error = gpu_error(r); goto fail; }
    extensions = calloc(count ? count : 1, sizeof(*extensions));
    if (!extensions) { error = -ENOMEM; goto fail; }
    r = d->api.EnumerateDeviceExtensionProperties(d->physical, NULL, &count, extensions);
    if (r != VK_SUCCESS) { error = gpu_error(r); goto fail; }
    const char *subset = "VK_KHR_portability_subset";
    int needs_subset = has_extension(extensions, count, subset);
    free(extensions); extensions = NULL;
    float priority = 1.0f;
    VkDeviceQueueCreateInfo queue = { .sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
        .queueFamilyIndex = d->family, .queueCount = 1, .pQueuePriorities = &priority };
    VkDeviceCreateInfo device = { .sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
        .queueCreateInfoCount = 1, .pQueueCreateInfos = &queue,
        .enabledExtensionCount = needs_subset ? 1u : 0u, .ppEnabledExtensionNames = &subset };
    VkDevice made_device;
    r = d->api.CreateDevice(d->physical, &device, NULL, &made_device);
    if (r != VK_SUCCESS) { error = gpu_error(r); goto fail; }
    d->logical = made_device;
    d->api.GetDeviceQueue(d->logical, d->family, 0, &d->queue);
    if ((uintptr_t)d > LONG_MAX) { error = -EOVERFLOW; goto fail; }
    return (long)(uintptr_t)d;
fail:
    free(extensions);
    free(devices);
    device_destroy(d);
    return error;
}

void linea_gpu_buffer_drop(unsigned long buffer) {
    struct gpu_buffer *b = (struct gpu_buffer *)(uintptr_t)buffer;
    struct gpu_device *d = b->device;
    if (pthread_mutex_lock(&d->references_lock) != 0) abort();
    int last = --b->references == 0;
    if (pthread_mutex_unlock(&d->references_lock) != 0) abort();
    if (!last) return;
    if (b->mapped) d->api.UnmapMemory(d->logical, b->memory);
    if (b->buffer) d->api.DestroyBuffer(d->logical, b->buffer, NULL);
    if (b->memory) d->api.FreeMemory(d->logical, b->memory, NULL);
    free(b);
    linea_gpu_close((unsigned long)(uintptr_t)d);
}

long linea_gpu_buffer_new(unsigned long device, unsigned long bytes) {
    struct gpu_device *d = (struct gpu_device *)(uintptr_t)device;
    if (bytes > d->properties.limits.maxStorageBufferRange) return -EOVERFLOW;
    struct gpu_buffer *b = calloc(1, sizeof(*b));
    if (!b) return -ENOMEM;
    device_retain(d);
    b->device = d;
    b->bytes = bytes;
    b->references = 1;
    long error = -ENOMEM;
    VkBufferCreateInfo info = { .sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
        .size = bytes ? bytes : 4, .usage = VK_BUFFER_USAGE_STORAGE_BUFFER_BIT,
        .sharingMode = VK_SHARING_MODE_EXCLUSIVE };
    VkBuffer made_buffer;
    VkResult r = d->api.CreateBuffer(d->logical, &info, NULL, &made_buffer);
    if (r != VK_SUCCESS) { error = gpu_error(r); goto fail; }
    b->buffer = made_buffer;
    VkMemoryRequirements requirements;
    d->api.GetBufferMemoryRequirements(d->logical, b->buffer, &requirements);
    uint32_t memory_type = UINT32_MAX;
    for (uint32_t i = 0; i < d->memory.memoryTypeCount; ++i) {
        if ((requirements.memoryTypeBits & (1u << i)) &&
            (d->memory.memoryTypes[i].propertyFlags & VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT)) {
            memory_type = i;
            break;
        }
    }
    if (memory_type == UINT32_MAX) { error = -ENODEV; goto fail; }
    VkMemoryAllocateInfo allocation = { .sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
        .allocationSize = requirements.size, .memoryTypeIndex = memory_type };
    VkDeviceMemory made_memory;
    r = d->api.AllocateMemory(d->logical, &allocation, NULL, &made_memory);
    if (r != VK_SUCCESS) { error = gpu_error(r); goto fail; }
    b->memory = made_memory;
    r = d->api.BindBufferMemory(d->logical, b->buffer, b->memory, 0);
    if (r != VK_SUCCESS) { error = gpu_error(r); goto fail; }
    void *made_mapping;
    r = d->api.MapMemory(d->logical, b->memory, 0, VK_WHOLE_SIZE, 0, &made_mapping);
    if (r != VK_SUCCESS) { error = gpu_error(r); goto fail; }
    b->mapped = made_mapping;
    if ((uintptr_t)b > LONG_MAX) { error = -EOVERFLOW; goto fail; }
    return (long)(uintptr_t)b;
fail:
    linea_gpu_buffer_drop((unsigned long)(uintptr_t)b);
    return error;
}

/* A host access and the reservation of a submission are one decision under
 * the device lock. The certified caller still keeps its buffer owner alive;
 * this guard serializes activity, not the lifetime of an unowned C handle. */
static int buffer_access_begin(struct gpu_buffer *b) {
    struct gpu_device *d = b->device;
    if (pthread_mutex_lock(&d->references_lock) != 0) abort();
    if (!b->in_flight) return 1;
    if (pthread_mutex_unlock(&d->references_lock) != 0) abort();
    return 0;
}

static void buffer_access_end(struct gpu_buffer *b) {
    if (pthread_mutex_unlock(&b->device->references_lock) != 0) abort();
}

long linea_gpu_buffer_write(unsigned long buffer, const void *source, unsigned long bytes) {
    struct gpu_buffer *b = (struct gpu_buffer *)(uintptr_t)buffer;
    if (bytes > b->bytes) return -EINVAL;
    if (!bytes) return 0;
    if (!buffer_access_begin(b)) return -EBUSY;
    memcpy(b->mapped, source, bytes);
    VkMappedMemoryRange range = { .sType = VK_STRUCTURE_TYPE_MAPPED_MEMORY_RANGE,
        .memory = b->memory, .size = VK_WHOLE_SIZE };
    VkResult r = b->device->api.FlushMappedMemoryRanges(b->device->logical, 1, &range);
    buffer_access_end(b);
    return r == VK_SUCCESS ? 0 : gpu_error(r);
}

long linea_gpu_buffer_read(unsigned long buffer, void *destination, unsigned long bytes) {
    struct gpu_buffer *b = (struct gpu_buffer *)(uintptr_t)buffer;
    if (bytes > b->bytes) return -EINVAL;
    if (!bytes) return 0;
    if (!buffer_access_begin(b)) return -EBUSY;
    VkMappedMemoryRange range = { .sType = VK_STRUCTURE_TYPE_MAPPED_MEMORY_RANGE,
        .memory = b->memory, .size = VK_WHOLE_SIZE };
    VkResult r = b->device->api.InvalidateMappedMemoryRanges(b->device->logical, 1, &range);
    if (r == VK_SUCCESS) memcpy(destination, b->mapped, bytes);
    buffer_access_end(b);
    return r == VK_SUCCESS ? 0 : gpu_error(r);
}

struct gpu_submission {
    struct linea_park park;
    struct gpu_buffer *input;
    struct gpu_buffer *output;
    struct gpu_buffer *right;
    VkShaderModule shader;
    VkDescriptorSetLayout set_layout;
    VkPipelineLayout layout;
    VkPipeline pipeline;
    VkDescriptorPool descriptors;
    VkCommandPool commands;
    VkFence fence;
    unsigned references;
    int ready;
    int done;
    long status;
};

static void submission_release(struct gpu_submission *s) {
    linea_park_lock(&s->park);
    int last = --s->references == 0;
    linea_park_unlock(&s->park);
    if (!last) return;
    struct gpu_device *d = s->input->device;
    if (s->fence) d->api.DestroyFence(d->logical, s->fence, NULL);
    if (s->commands) d->api.DestroyCommandPool(d->logical, s->commands, NULL);
    if (s->descriptors) d->api.DestroyDescriptorPool(d->logical, s->descriptors, NULL);
    if (s->pipeline) d->api.DestroyPipeline(d->logical, s->pipeline, NULL);
    if (s->layout) d->api.DestroyPipelineLayout(d->logical, s->layout, NULL);
    if (s->set_layout) d->api.DestroyDescriptorSetLayout(d->logical, s->set_layout, NULL);
    if (s->shader) d->api.DestroyShaderModule(d->logical, s->shader, NULL);
    linea_gpu_buffer_drop((unsigned long)(uintptr_t)s->input);
    linea_gpu_buffer_drop((unsigned long)(uintptr_t)s->output);
    linea_gpu_buffer_drop((unsigned long)(uintptr_t)s->right);
    linea_park_destroy(&s->park);
    free(s);
}

static void *submission_complete(void *argument) {
    struct gpu_submission *s = argument;
    struct gpu_device *d = s->input->device;
    linea_park_lock(&s->park);
    while (!s->ready) (void)linea_park(&s->park, 0);
    int submitted = s->ready > 0;
    linea_park_unlock(&s->park);
    if (submitted) {
        VkResult r = d->api.WaitForFences(d->logical, 1, &s->fence, VK_TRUE, UINT64_MAX);
        /* Only completion or device loss permits destruction of resources
         * referenced by submitted commands. Other results leave completion
         * indeterminate: abort the process without clearing in-flight state or
         * freeing queued resources. Retrying or reporting a recoverable error
         * would require a separate proof that commands no longer use them. */
        if (r != VK_SUCCESS && r != VK_ERROR_DEVICE_LOST) abort();
        s->status = r == VK_SUCCESS ? 0 : gpu_error(r);
    }
    if (pthread_mutex_lock(&d->references_lock) != 0) abort();
    --s->input->in_flight;
    --s->output->in_flight;
    --s->right->in_flight;
    if (pthread_mutex_unlock(&d->references_lock) != 0) abort();
    linea_park_lock(&s->park);
    s->done = 1;
    linea_unpark(&s->park);
    linea_park_unlock(&s->park);
    submission_release(s);
    return NULL;
}

long linea_gpu_wait(unsigned long submission) {
    struct gpu_submission *s = (struct gpu_submission *)(uintptr_t)submission;
    linea_park_lock(&s->park);
    while (!s->done) (void)linea_park(&s->park, 0);
    long status = s->status;
    linea_park_unlock(&s->park);
    return status;
}

void linea_gpu_submission_drop(unsigned long submission) {
    (void)linea_gpu_wait(submission);
    submission_release((struct gpu_submission *)(uintptr_t)submission);
}

/* One command path owns layouts, synchronization and completion for every
 * kernel kind. Repeated input handles deliberately acquire repeated references
 * and in-flight counts, so aliased matrix operands have symmetric settlement. */
static long gpu_dispatch(unsigned long input, unsigned long right, unsigned long output,
                         const void *image, unsigned long image_bytes, const char *entry,
                         const uint32_t push_words[4], uint32_t push_bytes, unsigned long groups) {
    struct gpu_buffer *a = (struct gpu_buffer *)(uintptr_t)input;
    struct gpu_buffer *b = (struct gpu_buffer *)(uintptr_t)output;
    struct gpu_buffer *c = (struct gpu_buffer *)(uintptr_t)right;
    struct gpu_device *d = a->device;
    if (a == b || c == b || b->device != d || c->device != d ||
        !image || image_bytes < 20 || image_bytes % 4 || (uintptr_t)image % 4) return -EINVAL;
    if (groups > d->properties.limits.maxComputeWorkGroupCount[0] ||
        d->properties.limits.maxComputeWorkGroupInvocations < 64 ||
        d->properties.limits.maxComputeWorkGroupSize[0] < 64) return -EOVERFLOW;
    struct gpu_buffer *buffers[3] = { a, b, c };
    struct gpu_submission *s = calloc(1, sizeof(*s));
    if (!s) return -ENOMEM;
    if ((uintptr_t)s > LONG_MAX) { free(s); return -EOVERFLOW; }
    int status = linea_park_init(&s->park);
    if (status != 0) { free(s); return -status; }
    s->input = a;
    s->output = b;
    s->right = c;
    s->references = 1;
    if (pthread_mutex_lock(&d->references_lock) != 0) abort();
    for (unsigned i = 0; i < 3; ++i) {
        if (buffers[i]->references == ULONG_MAX) abort();
        ++buffers[i]->references;
    }
    if (pthread_mutex_unlock(&d->references_lock) != 0) abort();
    if (!groups) { s->done = 1; return (long)(uintptr_t)s; }
    long error = -EIO;
    VkResult r;
#define GPU_CHECK(expr) do { r = (expr); if (r != VK_SUCCESS) { error = gpu_error(r); goto fail; } } while (0)
    VkShaderModuleCreateInfo shader = { .sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
        .codeSize = image_bytes, .pCode = image };
    VkShaderModule made_shader;
    GPU_CHECK(d->api.CreateShaderModule(d->logical, &shader, NULL, &made_shader));
    s->shader = made_shader;
    VkDescriptorSetLayoutBinding bindings[3];
    for (uint32_t i = 0; i < 3; ++i)
        bindings[i] = (VkDescriptorSetLayoutBinding){ .binding = i,
            .descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, .descriptorCount = 1,
            .stageFlags = VK_SHADER_STAGE_COMPUTE_BIT };
    VkDescriptorSetLayoutCreateInfo set_info = { .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
        .bindingCount = 3, .pBindings = bindings };
    VkDescriptorSetLayout made_set_layout;
    GPU_CHECK(d->api.CreateDescriptorSetLayout(d->logical, &set_info, NULL, &made_set_layout));
    s->set_layout = made_set_layout;
    VkPushConstantRange push = { .stageFlags = VK_SHADER_STAGE_COMPUTE_BIT, .size = 16 };
    VkPipelineLayoutCreateInfo layout_info = { .sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
        .setLayoutCount = 1, .pSetLayouts = &s->set_layout, .pushConstantRangeCount = 1, .pPushConstantRanges = &push };
    VkPipelineLayout made_layout;
    GPU_CHECK(d->api.CreatePipelineLayout(d->logical, &layout_info, NULL, &made_layout));
    s->layout = made_layout;
    VkComputePipelineCreateInfo pipeline_info = { .sType = VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO,
        .stage = { .sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
            .stage = VK_SHADER_STAGE_COMPUTE_BIT, .module = s->shader, .pName = entry }, .layout = s->layout };
    /* Vulkan may produce a pipeline on partial failure; publish that handle
     * for cleanup even when the result reports an error. */
    GPU_CHECK(d->api.CreateComputePipelines(d->logical, VK_NULL_HANDLE, 1, &pipeline_info, NULL, &s->pipeline));
    VkDescriptorPoolSize pool_size = { .type = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, .descriptorCount = 3 };
    VkDescriptorPoolCreateInfo pool_info = { .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
        .maxSets = 1, .poolSizeCount = 1, .pPoolSizes = &pool_size };
    VkDescriptorPool made_descriptors;
    GPU_CHECK(d->api.CreateDescriptorPool(d->logical, &pool_info, NULL, &made_descriptors));
    s->descriptors = made_descriptors;
    VkDescriptorSet set;
    VkDescriptorSetAllocateInfo allocate = { .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
        .descriptorPool = s->descriptors, .descriptorSetCount = 1, .pSetLayouts = &s->set_layout };
    GPU_CHECK(d->api.AllocateDescriptorSets(d->logical, &allocate, &set));
    VkDescriptorBufferInfo buffer_info[3];
    for (unsigned i = 0; i < 3; ++i)
        buffer_info[i] = (VkDescriptorBufferInfo){ .buffer = buffers[i]->buffer,
            .range = buffers[i]->bytes ? buffers[i]->bytes : 4 };
    VkWriteDescriptorSet writes[3];
    for (uint32_t i = 0; i < 3; ++i)
        writes[i] = (VkWriteDescriptorSet){ .sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
            .dstSet = set, .dstBinding = i, .descriptorCount = 1,
            .descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, .pBufferInfo = &buffer_info[i] };
    d->api.UpdateDescriptorSets(d->logical, 3, writes, 0, NULL);
    VkCommandPoolCreateInfo command_info = { .sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
        .queueFamilyIndex = d->family };
    VkCommandPool made_commands;
    GPU_CHECK(d->api.CreateCommandPool(d->logical, &command_info, NULL, &made_commands));
    s->commands = made_commands;
    VkCommandBuffer command;
    VkCommandBufferAllocateInfo command_allocate = { .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
        .commandPool = s->commands, .level = VK_COMMAND_BUFFER_LEVEL_PRIMARY, .commandBufferCount = 1 };
    GPU_CHECK(d->api.AllocateCommandBuffers(d->logical, &command_allocate, &command));
    VkCommandBufferBeginInfo begin = { .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
        .flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT };
    GPU_CHECK(d->api.BeginCommandBuffer(command, &begin));
    VkMemoryBarrier before = { .sType = VK_STRUCTURE_TYPE_MEMORY_BARRIER,
        .srcAccessMask = VK_ACCESS_HOST_WRITE_BIT | VK_ACCESS_SHADER_WRITE_BIT,
        .dstAccessMask = VK_ACCESS_SHADER_READ_BIT | VK_ACCESS_SHADER_WRITE_BIT };
    d->api.CmdPipelineBarrier(command, VK_PIPELINE_STAGE_HOST_BIT | VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT,
        VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, 0, 1, &before, 0, NULL, 0, NULL);
    d->api.CmdBindPipeline(command, VK_PIPELINE_BIND_POINT_COMPUTE, s->pipeline);
    d->api.CmdBindDescriptorSets(command, VK_PIPELINE_BIND_POINT_COMPUTE, s->layout, 0, 1, &set, 0, NULL);
    d->api.CmdPushConstants(command, s->layout, VK_SHADER_STAGE_COMPUTE_BIT, 0, push_bytes, push_words);
    d->api.CmdDispatch(command, (uint32_t)groups, 1, 1);
    VkMemoryBarrier after = { .sType = VK_STRUCTURE_TYPE_MEMORY_BARRIER,
        .srcAccessMask = VK_ACCESS_SHADER_WRITE_BIT, .dstAccessMask = VK_ACCESS_HOST_READ_BIT };
    d->api.CmdPipelineBarrier(command, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, VK_PIPELINE_STAGE_HOST_BIT,
        0, 1, &after, 0, NULL, 0, NULL);
    GPU_CHECK(d->api.EndCommandBuffer(command));
    VkFenceCreateInfo fence_info = { .sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO };
    VkFence made_fence;
    GPU_CHECK(d->api.CreateFence(d->logical, &fence_info, NULL, &made_fence));
    s->fence = made_fence;
    pthread_attr_t attributes;
    status = pthread_attr_init(&attributes);
    if (status != 0) { error = -status; goto fail; }
    status = pthread_attr_setdetachstate(&attributes, PTHREAD_CREATE_DETACHED);
    if (status != 0) {
        if (pthread_attr_destroy(&attributes) != 0) abort();
        error = -status;
        goto fail;
    }
    /* Allocate completion execution before submitting commands, so failure
     * never forces a carrier to wait for a GPU merely to recover resources. */
    s->references = 2;
    if (pthread_mutex_lock(&d->references_lock) != 0) abort();
    for (unsigned i = 0; i < 3; ++i) {
        if (buffers[i]->in_flight == ULONG_MAX) abort();
        ++buffers[i]->in_flight;
    }
    if (pthread_mutex_unlock(&d->references_lock) != 0) abort();
    pthread_t worker;
    status = pthread_create(&worker, &attributes, submission_complete, s);
    if (pthread_attr_destroy(&attributes) != 0) abort();
    if (status != 0) {
        s->references = 1;
        if (pthread_mutex_lock(&d->references_lock) != 0) abort();
        for (unsigned i = 0; i < 3; ++i) --buffers[i]->in_flight;
        if (pthread_mutex_unlock(&d->references_lock) != 0) abort();
        error = -status;
        goto fail;
    }
    VkSubmitInfo submit = { .sType = VK_STRUCTURE_TYPE_SUBMIT_INFO,
        .commandBufferCount = 1, .pCommandBuffers = &command };
    if (pthread_mutex_lock(&d->queue_lock) != 0) abort();
    r = d->api.QueueSubmit(d->queue, 1, &submit, s->fence);
    if (pthread_mutex_unlock(&d->queue_lock) != 0) abort();
    linea_park_lock(&s->park);
    s->ready = r == VK_SUCCESS ? 1 : -1;
    if (r != VK_SUCCESS) s->status = gpu_error(r);
    linea_unpark(&s->park);
    linea_park_unlock(&s->park);
    if (r == VK_SUCCESS) return (long)(uintptr_t)s;
    error = gpu_error(r);
    submission_release(s);
    return error;
fail:
    submission_release(s);
    return error;
#undef GPU_CHECK
}

long linea_gpu_submit(unsigned long input, unsigned long output, const void *image,
                      unsigned long image_bytes, unsigned long count) {
    struct gpu_buffer *a = (struct gpu_buffer *)(uintptr_t)input;
    struct gpu_buffer *b = (struct gpu_buffer *)(uintptr_t)output;
    if (count > UINT32_MAX || count > a->bytes / 4 || count > b->bytes / 4) return -EINVAL;
    const uint32_t push[4] = { (uint32_t)count, 0, 0, 0 };
    return gpu_dispatch(input, input, output, image, image_bytes, "linea_map", push, 4,
                        count / 64 + (count % 64 != 0));
}

long linea_gpu_buffer_sized_like(unsigned long input, unsigned long bytes) {
    struct gpu_buffer *b = (struct gpu_buffer *)(uintptr_t)input;
    return linea_gpu_buffer_new((unsigned long)(uintptr_t)b->device, bytes);
}

long linea_gpu_buffer_like(unsigned long buffer) {
    struct gpu_buffer *b = (struct gpu_buffer *)(uintptr_t)buffer;
    return linea_gpu_buffer_sized_like(buffer, b->bytes);
}

long linea_gpu_upload(unsigned long buffer, unsigned long at, unsigned long bytes) {
    return linea_gpu_buffer_write(buffer, (const void *)(uintptr_t)at, bytes);
}

long linea_gpu_download(unsigned long buffer, unsigned long at, unsigned long bytes) {
    return linea_gpu_buffer_read(buffer, (void *)(uintptr_t)at, bytes);
}

long linea_gpu_map(unsigned long input, unsigned long output, unsigned long kernel, unsigned long count) {
    const struct linea_gpu_kernel *image = (const struct linea_gpu_kernel *)(uintptr_t)kernel;
    if (image->kind != 0) return -EINVAL;
    return linea_gpu_submit(input, output, image->image, image->bytes, count);
}

long linea_gpu_reduce(unsigned long input, unsigned long output, unsigned long kernel,
                      unsigned long count, unsigned long initial_bits) {
    const struct linea_gpu_kernel *image = (const struct linea_gpu_kernel *)(uintptr_t)kernel;
    struct gpu_buffer *a = (struct gpu_buffer *)(uintptr_t)input;
    struct gpu_buffer *b = (struct gpu_buffer *)(uintptr_t)output;
    if (image->kind != 1 || count > UINT32_MAX || initial_bits > UINT32_MAX ||
        count > a->bytes / 4 || b->bytes < 4) return -EINVAL;
    const uint32_t push[4] = { (uint32_t)count, (uint32_t)initial_bits, 0, 0 };
    return gpu_dispatch(input, input, output, image->image, image->bytes, "linea_reduce", push, 8, 1);
}

long linea_gpu_map_uniform(unsigned long input, unsigned long output, unsigned long kernel,
                           unsigned long count, unsigned long uniform_bits) {
    const struct linea_gpu_kernel *image = (const struct linea_gpu_kernel *)(uintptr_t)kernel;
    struct gpu_buffer *a = (struct gpu_buffer *)(uintptr_t)input;
    struct gpu_buffer *b = (struct gpu_buffer *)(uintptr_t)output;
    if (image->kind != 1 || count > UINT32_MAX || uniform_bits > UINT32_MAX ||
        count > a->bytes / 4 || count > b->bytes / 4) return -EINVAL;
    const uint32_t push[4] = { (uint32_t)count, (uint32_t)uniform_bits, 0, 0 };
    return gpu_dispatch(input, input, output, image->image, image->bytes, "linea_uniform", push, 8,
                        count / 64 + (count % 64 != 0));
}

long linea_gpu_zip(unsigned long left, unsigned long right, unsigned long output,
                   unsigned long kernel, unsigned long count) {
    const struct linea_gpu_kernel *image = (const struct linea_gpu_kernel *)(uintptr_t)kernel;
    struct gpu_buffer *a = (struct gpu_buffer *)(uintptr_t)left;
    struct gpu_buffer *b = (struct gpu_buffer *)(uintptr_t)right;
    struct gpu_buffer *c = (struct gpu_buffer *)(uintptr_t)output;
    if (image->kind != 1 || count > UINT32_MAX || count > a->bytes / 4 ||
        count > b->bytes / 4 || count > c->bytes / 4) return -EINVAL;
    const uint32_t push[4] = { (uint32_t)count, 0, 0, 0 };
    return gpu_dispatch(left, right, output, image->image, image->bytes, "linea_zip", push, 4,
                        count / 64 + (count % 64 != 0));
}

long linea_gpu_matmul(unsigned long left, unsigned long right, unsigned long output,
                      unsigned long kernel, unsigned long rows, unsigned long inner,
                      unsigned long columns) {
    const struct linea_gpu_kernel *image = (const struct linea_gpu_kernel *)(uintptr_t)kernel;
    struct gpu_buffer *a = (struct gpu_buffer *)(uintptr_t)left;
    struct gpu_buffer *b = (struct gpu_buffer *)(uintptr_t)right;
    struct gpu_buffer *c = (struct gpu_buffer *)(uintptr_t)output;
    if (image->kind != 2) return -EINVAL;
    if (rows > UINT32_MAX || inner > UINT32_MAX || columns > UINT32_MAX ||
        (inner && rows > UINT32_MAX / inner) ||
        (columns && inner > UINT32_MAX / columns) ||
        (columns && rows > UINT32_MAX / columns)) return -EOVERFLOW;
    const unsigned long ac = rows * inner, bc = inner * columns, cc = rows * columns;
    if (ac > a->bytes / 4 || bc > b->bytes / 4 || cc > c->bytes / 4) return -EINVAL;
    const uint32_t push[4] = { (uint32_t)cc, (uint32_t)rows, (uint32_t)inner, (uint32_t)columns };
    return gpu_dispatch(left, right, output, image->image, image->bytes, "linea_matmul", push, 16,
                        cc / 64 + (cc % 64 != 0));
}
