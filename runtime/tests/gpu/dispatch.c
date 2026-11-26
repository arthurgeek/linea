#include "device.h"
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

struct buffer { VkBuffer buffer; VkDeviceMemory memory; void *mapped; };

static int error(const char *operation, VkResult status) {
    fprintf(stderr, "GPU probe: %s failed (%d)\n", operation, status);
    return PROBE_FAILED;
}

static void close_buffer(struct probe_device *d, struct buffer *b) {
    if (b->mapped) vkUnmapMemory(d->logical, b->memory);
    if (b->buffer) vkDestroyBuffer(d->logical, b->buffer, NULL);
    if (b->memory) vkFreeMemory(d->logical, b->memory, NULL);
}

static int open_buffer(struct probe_device *d, VkDeviceSize bytes, struct buffer *out) {
    VkBufferCreateInfo info = { .sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO, .size = bytes,
        .usage = VK_BUFFER_USAGE_STORAGE_BUFFER_BIT, .sharingMode = VK_SHARING_MODE_EXCLUSIVE };
    VkBuffer buffer;
    VkResult r = vkCreateBuffer(d->logical, &info, NULL, &buffer);
    if (r != VK_SUCCESS) return error("create buffer", r);
    out->buffer = buffer;
    VkMemoryRequirements req;
    vkGetBufferMemoryRequirements(d->logical, out->buffer, &req);
    uint32_t type = UINT32_MAX;
    for (uint32_t i = 0; i < d->memory.memoryTypeCount; ++i) {
        if ((req.memoryTypeBits & (1u << i)) &&
            (d->memory.memoryTypes[i].propertyFlags & VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT)) {
            type = i;
            break;
        }
    }
    if (type == UINT32_MAX) return error("find host-visible memory", VK_ERROR_FEATURE_NOT_PRESENT);
    VkMemoryAllocateInfo allocation = { .sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
        .allocationSize = req.size, .memoryTypeIndex = type };
    VkDeviceMemory memory;
    r = vkAllocateMemory(d->logical, &allocation, NULL, &memory);
    if (r != VK_SUCCESS) return error("allocate buffer memory", r);
    out->memory = memory;
    r = vkBindBufferMemory(d->logical, out->buffer, out->memory, 0);
    if (r != VK_SUCCESS) return error("bind buffer memory", r);
    void *mapped;
    r = vkMapMemory(d->logical, out->memory, 0, VK_WHOLE_SIZE, 0, &mapped);
    if (r != VK_SUCCESS) return error("map buffer memory", r);
    out->mapped = mapped;
    return PROBE_OK;
}

static uint32_t *read_shader(const char *path, size_t *bytes) {
    FILE *file = fopen(path, "rb");
    if (!file) { perror(path); return NULL; }
    uint32_t *data = NULL;
    if (fseek(file, 0, SEEK_END) != 0) goto done;
    long size = ftell(file);
    if (size < 20 || size % 4 || (unsigned long)size > 16 * 1024 * 1024) goto done;
    if (fseek(file, 0, SEEK_SET) != 0) goto done;
    data = malloc((size_t)size);
    if (!data) goto done;
    if (fread(data, 1, (size_t)size, file) != (size_t)size || data[0] != 0x07230203) {
        free(data); data = NULL; goto done;
    }
    *bytes = (size_t)size;
 done:
    if (fclose(file) != 0) { free(data); data = NULL; }
    if (!data) fprintf(stderr, "GPU probe: invalid or unreadable SPIR-V: %s\n", path);
    return data;
}

/* Three bindings let numerical probes provide two operands without a second
 * host submission implementation. Copy shaders use the first two only. */
int probe_dispatch(struct probe_device *d, const char *path, const char *entry,
                   const uint32_t *left, const uint32_t *right, uint32_t *actual, uint32_t count) {
    uint32_t groups;
    uint64_t bytes;
    if (!probe_workgroups(count, d->properties.limits.maxComputeWorkGroupCount[0], &groups) ||
        !probe_buffer_bytes(count, d->properties.limits.maxStorageBufferRange, &bytes) ||
        d->properties.limits.maxComputeWorkGroupInvocations < 64 ||
        d->properties.limits.maxComputeWorkGroupSize[0] < 64) {
        return error("dispatch extent", VK_ERROR_FEATURE_NOT_PRESENT);
    }
    if (!count) {
        actual[0] = actual[1] = 0x12345678;
        return PROBE_OK;
    }
    int status = PROBE_FAILED;
    VkResult r = VK_SUCCESS;
    struct buffer buffers[3] = {0};
    VkShaderModule shader = VK_NULL_HANDLE;
    VkDescriptorSetLayout set_layout = VK_NULL_HANDLE;
    VkPipelineLayout pipeline_layout = VK_NULL_HANDLE;
    VkPipeline pipeline = VK_NULL_HANDLE;
    VkDescriptorPool pool = VK_NULL_HANDLE;
    VkCommandPool commands = VK_NULL_HANDLE;
    VkFence fence = VK_NULL_HANDLE;
    uint32_t *code = NULL;
    const char *operation = "prepare dispatch";
#define CHECK(what, expr) do { operation = what; r = (expr); if (r != VK_SUCCESS) goto done; } while (0)
    for (size_t i = 0; i < 3; ++i)
        if (open_buffer(d, bytes, &buffers[i]) != PROBE_OK) goto done;
    for (size_t i = 0; i < 3; ++i) {
        uint32_t *words = buffers[i].mapped;
        for (uint32_t j = 0; j < count + 2; ++j) words[j] = i == 1 ? 0x12345678 : 0x87654321;
    }
    memcpy((uint32_t *)buffers[0].mapped + 1, left, (size_t)count * 4);
    if (right) memcpy((uint32_t *)buffers[2].mapped + 1, right, (size_t)count * 4);
    VkMappedMemoryRange ranges[3];
    for (size_t i = 0; i < 3; ++i)
        ranges[i] = (VkMappedMemoryRange){ .sType = VK_STRUCTURE_TYPE_MAPPED_MEMORY_RANGE,
            .memory = buffers[i].memory, .offset = 0, .size = VK_WHOLE_SIZE };
    CHECK("flush input", vkFlushMappedMemoryRanges(d->logical, 3, ranges));
    size_t code_bytes = 0;
    code = read_shader(path, &code_bytes);
    if (!code) goto done;
    VkShaderModuleCreateInfo shader_info = { .sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
        .codeSize = code_bytes, .pCode = code };
    VkShaderModule made_shader;
    CHECK("create shader", vkCreateShaderModule(d->logical, &shader_info, NULL, &made_shader));
    shader = made_shader;
    VkDescriptorSetLayoutBinding bindings[3];
    for (uint32_t i = 0; i < 3; ++i)
        bindings[i] = (VkDescriptorSetLayoutBinding){ .binding = i,
            .descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, .descriptorCount = 1,
            .stageFlags = VK_SHADER_STAGE_COMPUTE_BIT };
    VkDescriptorSetLayoutCreateInfo set_info = { .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
        .bindingCount = 3, .pBindings = bindings };
    VkDescriptorSetLayout made_set_layout;
    CHECK("create descriptor layout", vkCreateDescriptorSetLayout(d->logical, &set_info, NULL, &made_set_layout));
    set_layout = made_set_layout;
    VkPushConstantRange push = { .stageFlags = VK_SHADER_STAGE_COMPUTE_BIT, .offset = 0, .size = 4 };
    VkPipelineLayoutCreateInfo layout_info = { .sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
        .setLayoutCount = 1, .pSetLayouts = &set_layout, .pushConstantRangeCount = 1, .pPushConstantRanges = &push };
    VkPipelineLayout made_pipeline_layout;
    CHECK("create pipeline layout", vkCreatePipelineLayout(d->logical, &layout_info, NULL, &made_pipeline_layout));
    pipeline_layout = made_pipeline_layout;
    VkComputePipelineCreateInfo pipeline_info = { .sType = VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO,
        .stage = { .sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
            .stage = VK_SHADER_STAGE_COMPUTE_BIT, .module = shader, .pName = entry }, .layout = pipeline_layout };
    CHECK("create compute pipeline", vkCreateComputePipelines(d->logical, VK_NULL_HANDLE, 1, &pipeline_info, NULL, &pipeline));
    VkDescriptorPoolSize pool_size = { .type = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, .descriptorCount = 3 };
    VkDescriptorPoolCreateInfo pool_info = { .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
        .maxSets = 1, .poolSizeCount = 1, .pPoolSizes = &pool_size };
    VkDescriptorPool made_pool;
    CHECK("create descriptor pool", vkCreateDescriptorPool(d->logical, &pool_info, NULL, &made_pool));
    pool = made_pool;
    VkDescriptorSet set;
    VkDescriptorSetAllocateInfo allocate = { .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
        .descriptorPool = pool, .descriptorSetCount = 1, .pSetLayouts = &set_layout };
    CHECK("allocate descriptor set", vkAllocateDescriptorSets(d->logical, &allocate, &set));
    VkDescriptorBufferInfo buffer_info[3];
    VkWriteDescriptorSet writes[3];
    for (uint32_t i = 0; i < 3; ++i) {
        buffer_info[i] = (VkDescriptorBufferInfo){ .buffer = buffers[i].buffer, .offset = 0, .range = bytes };
        writes[i] = (VkWriteDescriptorSet){ .sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
            .dstSet = set, .dstBinding = i, .descriptorCount = 1,
            .descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, .pBufferInfo = &buffer_info[i] };
    }
    vkUpdateDescriptorSets(d->logical, 3, writes, 0, NULL);
    VkCommandPoolCreateInfo command_info = { .sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
        .queueFamilyIndex = d->family };
    VkCommandPool made_commands;
    CHECK("create command pool", vkCreateCommandPool(d->logical, &command_info, NULL, &made_commands));
    commands = made_commands;
    VkCommandBuffer command;
    VkCommandBufferAllocateInfo command_allocate = { .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
        .commandPool = commands, .level = VK_COMMAND_BUFFER_LEVEL_PRIMARY, .commandBufferCount = 1 };
    CHECK("allocate command buffer", vkAllocateCommandBuffers(d->logical, &command_allocate, &command));
    VkCommandBufferBeginInfo begin = { .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
        .flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT };
    CHECK("begin commands", vkBeginCommandBuffer(command, &begin));
    vkCmdBindPipeline(command, VK_PIPELINE_BIND_POINT_COMPUTE, pipeline);
    vkCmdBindDescriptorSets(command, VK_PIPELINE_BIND_POINT_COMPUTE, pipeline_layout, 0, 1, &set, 0, NULL);
    vkCmdPushConstants(command, pipeline_layout, VK_SHADER_STAGE_COMPUTE_BIT, 0, 4, &count);
    vkCmdDispatch(command, groups, 1, 1);
    VkMemoryBarrier barrier = { .sType = VK_STRUCTURE_TYPE_MEMORY_BARRIER,
        .srcAccessMask = VK_ACCESS_SHADER_WRITE_BIT, .dstAccessMask = VK_ACCESS_HOST_READ_BIT };
    vkCmdPipelineBarrier(command, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, VK_PIPELINE_STAGE_HOST_BIT,
        0, 1, &barrier, 0, NULL, 0, NULL);
    CHECK("end commands", vkEndCommandBuffer(command));
    VkFenceCreateInfo fence_info = { .sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO };
    VkFence made_fence;
    CHECK("create fence", vkCreateFence(d->logical, &fence_info, NULL, &made_fence));
    fence = made_fence;
    VkSubmitInfo submit = { .sType = VK_STRUCTURE_TYPE_SUBMIT_INFO,
        .commandBufferCount = 1, .pCommandBuffers = &command };
    CHECK("submit", vkQueueSubmit(d->queue, 1, &submit, fence));
    r = vkWaitForFences(d->logical, 1, &fence, VK_TRUE, UINT64_C(30000000000));
    if (r != VK_SUCCESS && r != VK_ERROR_DEVICE_LOST) {
        error("GPU fence did not establish completion; terminating with resources in flight", r);
        fflush(NULL);
        _Exit(PROBE_FAILED);
    }
    operation = "wait for GPU";
    if (r != VK_SUCCESS) goto done;
    CHECK("invalidate output", vkInvalidateMappedMemoryRanges(d->logical, 1, &ranges[1]));
    memcpy(actual, buffers[1].mapped, (size_t)bytes);
    status = PROBE_OK;
 done:
    if (r != VK_SUCCESS) error(operation, r);
    if (fence) vkDestroyFence(d->logical, fence, NULL);
    if (commands) vkDestroyCommandPool(d->logical, commands, NULL);
    if (pool) vkDestroyDescriptorPool(d->logical, pool, NULL);
    if (pipeline) vkDestroyPipeline(d->logical, pipeline, NULL);
    if (pipeline_layout) vkDestroyPipelineLayout(d->logical, pipeline_layout, NULL);
    if (set_layout) vkDestroyDescriptorSetLayout(d->logical, set_layout, NULL);
    if (shader) vkDestroyShaderModule(d->logical, shader, NULL);
    free(code);
    for (size_t i = 3; i > 0; --i) close_buffer(d, &buffers[i - 1]);
    return status;
#undef CHECK
}

int probe_copy(struct probe_device *d, const char *path, uint32_t count) {
    uint64_t bytes;
    if (!probe_buffer_bytes(count, d->properties.limits.maxStorageBufferRange, &bytes))
        return error("copy extent", VK_ERROR_FEATURE_NOT_PRESENT);
    uint32_t *expected = malloc((size_t)(count ? count : 1) * 4);
    uint32_t *actual = malloc((size_t)bytes);
    if (!expected || !actual) {
        fprintf(stderr, "GPU probe: allocate copy buffers failed (bytes=%" PRIu64 ")\n", bytes);
        free(expected); free(actual); return PROBE_FAILED;
    }
    for (uint32_t i = 0; i < count; ++i) expected[i] = i ^ 0xabcde123u;
    int status = probe_dispatch(d, path, "copy", expected, NULL, actual, count);
    if (status == PROBE_OK) status = probe_check_words(expected, actual, count);
    printf("copy count=%u result=%s\n", count, status == PROBE_OK ? "passed" : "failed");
    free(actual); free(expected);
    return status;
}
