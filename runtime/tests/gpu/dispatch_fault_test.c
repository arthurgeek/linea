#include "device.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

int probe_dispatch(struct probe_device *, const char *, const char *, const uint32_t *, const uint32_t *, uint32_t *, uint32_t);

/* Vulkan owns external resources. Replace only that boundary: the real host
 * dispatch, size checks, acquisition and cleanup code still run. */
static unsigned step, fail_at, next_handle, pending, extra_copy, mapped_count, mapped_ids[3];
static unsigned live[128], binding[128], mapped[128];
static uint32_t storage[128][64];
static VkResult wait_result;
static unsigned id(uint64_t h) { assert(h < 128); return (unsigned)h; }
#define ID(h) id((uint64_t)(uintptr_t)(h))
static VkResult tick(void) { return ++step == fail_at ? VK_ERROR_OUT_OF_HOST_MEMORY : VK_SUCCESS; }
static unsigned acquired(unsigned kind) { unsigned n = ++next_handle; assert(n < 128); live[n] = kind; return n; }
static void released(unsigned n, unsigned kind) { assert(!pending); assert(live[n] == kind); live[n] = 0; }
#define CREATE(kind, type, out) do { VkResult r = tick(); if (r != VK_SUCCESS) { *(out) = (type)(uintptr_t)0xbad; return r; } *(out) = (type)(uintptr_t)acquired(kind); return VK_SUCCESS; } while (0)
#define UNUSED(x) (void)(x)

VkResult vkCreateBuffer(VkDevice d, const VkBufferCreateInfo *i, const VkAllocationCallbacks *a, VkBuffer *o) {
    UNUSED(d); UNUSED(a); assert(i->size == 20); CREATE(1, VkBuffer, o);
}
void vkGetBufferMemoryRequirements(VkDevice d, VkBuffer b, VkMemoryRequirements *o) {
    UNUSED(d); UNUSED(b); *o = (VkMemoryRequirements){ .size = 256, .alignment = 16, .memoryTypeBits = 1 };
}
VkResult vkAllocateMemory(VkDevice d, const VkMemoryAllocateInfo *i, const VkAllocationCallbacks *a, VkDeviceMemory *o) {
    UNUSED(d); UNUSED(a); assert(i->allocationSize == 256); CREATE(2, VkDeviceMemory, o);
}
VkResult vkBindBufferMemory(VkDevice d, VkBuffer b, VkDeviceMemory m, VkDeviceSize offset) {
    UNUSED(d); assert(offset == 0); VkResult r = tick(); if (r == VK_SUCCESS) binding[ID(b)] = ID(m); return r;
}
VkResult vkMapMemory(VkDevice d, VkDeviceMemory m, VkDeviceSize offset, VkDeviceSize size, VkMemoryMapFlags f, void **o) {
    UNUSED(d); UNUSED(f); assert(offset == 0 && size == VK_WHOLE_SIZE);
    VkResult r = tick(); if (r == VK_SUCCESS) { mapped[ID(m)] = 1; *o = storage[ID(m)]; mapped_ids[mapped_count++] = ID(m); } else { *o = (void *)(uintptr_t)0xbad; } return r;
}
void vkUnmapMemory(VkDevice d, VkDeviceMemory m) { UNUSED(d); assert(mapped[ID(m)]); mapped[ID(m)] = 0; }
void vkDestroyBuffer(VkDevice d, VkBuffer b, const VkAllocationCallbacks *a) { UNUSED(d); UNUSED(a); binding[ID(b)] = 0; released(ID(b), 1); }
void vkFreeMemory(VkDevice d, VkDeviceMemory m, const VkAllocationCallbacks *a) {
    UNUSED(d); UNUSED(a); assert(!mapped[ID(m)]);
    for (unsigned i = 0; i < 128; ++i) assert(!live[i] || binding[i] != ID(m));
    released(ID(m), 2);
}
VkResult vkFlushMappedMemoryRanges(VkDevice d, uint32_t n, const VkMappedMemoryRange *r) { UNUSED(d); assert(n == 3 && r[0].size == VK_WHOLE_SIZE); return tick(); }
VkResult vkInvalidateMappedMemoryRanges(VkDevice d, uint32_t n, const VkMappedMemoryRange *r) { UNUSED(d); assert(n == 1 && r[0].size == VK_WHOLE_SIZE); return tick(); }
VkResult vkCreateShaderModule(VkDevice d, const VkShaderModuleCreateInfo *i, const VkAllocationCallbacks *a, VkShaderModule *o) { UNUSED(d); UNUSED(a); assert(i->codeSize >= 20); CREATE(3, VkShaderModule, o); }
void vkDestroyShaderModule(VkDevice d, VkShaderModule h, const VkAllocationCallbacks *a) { UNUSED(d); UNUSED(a); released(ID(h), 3); }
VkResult vkCreateDescriptorSetLayout(VkDevice d, const VkDescriptorSetLayoutCreateInfo *i, const VkAllocationCallbacks *a, VkDescriptorSetLayout *o) { UNUSED(d); UNUSED(i); UNUSED(a); CREATE(4, VkDescriptorSetLayout, o); }
void vkDestroyDescriptorSetLayout(VkDevice d, VkDescriptorSetLayout h, const VkAllocationCallbacks *a) { UNUSED(d); UNUSED(a); released(ID(h), 4); }
VkResult vkCreatePipelineLayout(VkDevice d, const VkPipelineLayoutCreateInfo *i, const VkAllocationCallbacks *a, VkPipelineLayout *o) { UNUSED(d); UNUSED(i); UNUSED(a); CREATE(5, VkPipelineLayout, o); }
void vkDestroyPipelineLayout(VkDevice d, VkPipelineLayout h, const VkAllocationCallbacks *a) { UNUSED(d); UNUSED(a); released(ID(h), 5); }
VkResult vkCreateComputePipelines(VkDevice d, VkPipelineCache c, uint32_t n, const VkComputePipelineCreateInfo *i, const VkAllocationCallbacks *a, VkPipeline *o) { UNUSED(d); UNUSED(c); UNUSED(i); UNUSED(a); assert(n == 1); VkResult r = tick(); *o = (VkPipeline)(uintptr_t)acquired(6); return r; }
void vkDestroyPipeline(VkDevice d, VkPipeline h, const VkAllocationCallbacks *a) { UNUSED(d); UNUSED(a); released(ID(h), 6); }
VkResult vkCreateDescriptorPool(VkDevice d, const VkDescriptorPoolCreateInfo *i, const VkAllocationCallbacks *a, VkDescriptorPool *o) { UNUSED(d); UNUSED(i); UNUSED(a); CREATE(7, VkDescriptorPool, o); }
void vkDestroyDescriptorPool(VkDevice d, VkDescriptorPool h, const VkAllocationCallbacks *a) { UNUSED(d); UNUSED(a); released(ID(h), 7); }
VkResult vkAllocateDescriptorSets(VkDevice d, const VkDescriptorSetAllocateInfo *i, VkDescriptorSet *o) { UNUSED(d); UNUSED(i); *o = (VkDescriptorSet)(uintptr_t)100; return tick(); }
void vkUpdateDescriptorSets(VkDevice d, uint32_t n, const VkWriteDescriptorSet *w, uint32_t copies, const VkCopyDescriptorSet *c) { UNUSED(d); UNUSED(copies); UNUSED(c); assert(n == 3); for (unsigned i = 0; i < n; ++i) assert(w[i].pBufferInfo->range == 20); }
VkResult vkCreateCommandPool(VkDevice d, const VkCommandPoolCreateInfo *i, const VkAllocationCallbacks *a, VkCommandPool *o) { UNUSED(d); UNUSED(i); UNUSED(a); CREATE(8, VkCommandPool, o); }
void vkDestroyCommandPool(VkDevice d, VkCommandPool h, const VkAllocationCallbacks *a) { UNUSED(d); UNUSED(a); released(ID(h), 8); }
VkResult vkAllocateCommandBuffers(VkDevice d, const VkCommandBufferAllocateInfo *i, VkCommandBuffer *o) { UNUSED(d); UNUSED(i); *o = (VkCommandBuffer)(uintptr_t)101; return tick(); }
VkResult vkBeginCommandBuffer(VkCommandBuffer c, const VkCommandBufferBeginInfo *i) { UNUSED(c); UNUSED(i); return tick(); }
void vkCmdBindPipeline(VkCommandBuffer c, VkPipelineBindPoint p, VkPipeline h) { UNUSED(c); UNUSED(p); UNUSED(h); }
void vkCmdBindDescriptorSets(VkCommandBuffer c, VkPipelineBindPoint p, VkPipelineLayout l, uint32_t first, uint32_t n, const VkDescriptorSet *s, uint32_t offsets, const uint32_t *o) { UNUSED(c); UNUSED(p); UNUSED(l); UNUSED(first); UNUSED(n); UNUSED(s); UNUSED(offsets); UNUSED(o); }
void vkCmdPushConstants(VkCommandBuffer c, VkPipelineLayout l, VkShaderStageFlags s, uint32_t offset, uint32_t size, const void *v) { UNUSED(c); UNUSED(l); UNUSED(s); UNUSED(v); assert(offset == 0 && size == 4); }
void vkCmdDispatch(VkCommandBuffer c, uint32_t x, uint32_t y, uint32_t z) { UNUSED(c); assert(x == 1 && y == 1 && z == 1); }
void vkCmdPipelineBarrier(VkCommandBuffer c, VkPipelineStageFlags s, VkPipelineStageFlags t, VkDependencyFlags f, uint32_t n, const VkMemoryBarrier *b, uint32_t bn, const VkBufferMemoryBarrier *bs, uint32_t in, const VkImageMemoryBarrier *is) { UNUSED(c); UNUSED(s); UNUSED(t); UNUSED(f); UNUSED(n); UNUSED(b); UNUSED(bn); UNUSED(bs); UNUSED(in); UNUSED(is); }
VkResult vkEndCommandBuffer(VkCommandBuffer c) { UNUSED(c); return tick(); }
VkResult vkCreateFence(VkDevice d, const VkFenceCreateInfo *i, const VkAllocationCallbacks *a, VkFence *o) { UNUSED(d); UNUSED(i); UNUSED(a); CREATE(9, VkFence, o); }
void vkDestroyFence(VkDevice d, VkFence h, const VkAllocationCallbacks *a) { UNUSED(d); UNUSED(a); released(ID(h), 9); }
VkResult vkQueueSubmit(VkQueue q, uint32_t n, const VkSubmitInfo *s, VkFence f) { UNUSED(q); UNUSED(n); UNUSED(s); UNUSED(f); VkResult r = tick(); if (r == VK_SUCCESS) { pending = 1; for (unsigned i = 1; i <= 3 + extra_copy; ++i) storage[mapped_ids[1]][i] = storage[mapped_ids[0]][i]; } return r; }
VkResult vkWaitForFences(VkDevice d, uint32_t n, const VkFence *f, VkBool32 all, uint64_t timeout) {
    UNUSED(d); UNUSED(n); UNUSED(f); UNUSED(all); assert(timeout == UINT64_C(30000000000));
    VkResult r = tick(); if (r != VK_SUCCESS) return r;
    if (wait_result == VK_SUCCESS || wait_result == VK_ERROR_DEVICE_LOST) pending = 0;
    return wait_result;
}

static void reset(unsigned fail) {
    step = next_handle = pending = extra_copy = mapped_count = 0; fail_at = fail; wait_result = VK_SUCCESS;
    memset(live, 0, sizeof(live)); memset(binding, 0, sizeof(binding)); memset(mapped, 0, sizeof(mapped));
}

int main(int argc, char **argv) {
    assert(argc == 2);
    struct probe_device d = {0};
    d.properties.limits.maxComputeWorkGroupCount[0] = 65535;
    d.properties.limits.maxComputeWorkGroupInvocations = 64;
    d.properties.limits.maxComputeWorkGroupSize[0] = 64;
    d.properties.limits.maxStorageBufferRange = 4096;
    d.memory.memoryTypeCount = 1;
    d.memory.memoryTypes[0].propertyFlags = VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT;
    uint32_t input[] = {1, 2, 3}, output[5];
    reset(0);
    assert(probe_dispatch(&d, argv[1], "copy", input, NULL, output, 3) == PROBE_OK);
    unsigned calls = step;
    assert(probe_check_words(input, output, 3) == PROBE_OK);
    for (unsigned i = 0; i < 128; ++i) assert(!live[i]);
    reset(0); extra_copy = 1;
    assert(probe_dispatch(&d, argv[1], "copy", input, NULL, output, 3) == PROBE_OK);
    assert(probe_check_words(input, output, 3) == PROBE_MISMATCH);
    for (unsigned i = 0; i < 128; ++i) assert(!live[i]);
    for (unsigned fail = 1; fail <= calls; ++fail) {
        fflush(NULL);
        pid_t child = fork(); assert(child >= 0);
        if (!child) {
            reset(fail);
            assert(probe_dispatch(&d, argv[1], "copy", input, NULL, output, 3) == PROBE_FAILED);
            for (unsigned i = 0; i < 128; ++i) assert(!live[i]);
            _exit(0);
        }
        int status; assert(waitpid(child, &status, 0) == child);
        assert(WIFEXITED(status) && WEXITSTATUS(status) == (fail == calls - 1 ? 2 : 0));
    }
    const VkResult waits[] = {VK_TIMEOUT, VK_ERROR_DEVICE_LOST};
    for (unsigned i = 0; i < 2; ++i) {
        fflush(NULL);
        pid_t child = fork(); assert(child >= 0);
        if (!child) {
            reset(0); wait_result = waits[i];
            assert(probe_dispatch(&d, argv[1], "copy", input, NULL, output, 3) == PROBE_FAILED);
            for (unsigned j = 0; j < 128; ++j) assert(!live[j]);
            _exit(0);
        }
        int status; assert(waitpid(child, &status, 0) == child);
        assert(WIFEXITED(status) && WEXITSTATUS(status) == (waits[i] == VK_TIMEOUT ? 2 : 0));
    }
    reset(0);
    assert(probe_dispatch(&d, argv[1], "copy", input, NULL, output, 0) == PROBE_OK && step == 0);
    assert(probe_dispatch(&d, argv[1], "copy", input, NULL, output, UINT32_MAX) == PROBE_FAILED && step == 0);
    puts("GPU host dispatch fault paths passed");
    return 0;
}
