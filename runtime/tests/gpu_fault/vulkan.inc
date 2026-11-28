/* Typed Vulkan substitutes used only at the dynamic-loader boundary. */
static VkResult VKAPI_CALL fake_EnumerateInstanceExtensionProperties(const char* pLayerName, uint32_t* pPropertyCount, VkExtensionProperties* pProperties) {
    (void)pLayerName; (void)pPropertyCount; (void)pProperties;
    VkResult r = tick("EnumerateInstanceExtensionProperties"); *pPropertyCount = 0; return r;
}
static VkResult VKAPI_CALL fake_CreateInstance(const VkInstanceCreateInfo* pCreateInfo, const VkAllocationCallbacks* pAllocator, VkInstance* pInstance) {
    (void)pCreateInfo; (void)pAllocator; (void)pInstance;
    VkResult r = tick("CreateInstance"); *pInstance = HANDLE(VkInstance, r == VK_SUCCESS ? acquired(INSTANCE, 0) : 0xdead); return r;
}
static void VKAPI_CALL fake_DestroyInstance(VkInstance instance, const VkAllocationCallbacks* pAllocator) {
    (void)instance; (void)pAllocator;
    released(ID(instance), INSTANCE);
}
static VkResult VKAPI_CALL fake_EnumeratePhysicalDevices(VkInstance instance, uint32_t* pPhysicalDeviceCount, VkPhysicalDevice* pPhysicalDevices) {
    (void)instance; (void)pPhysicalDeviceCount; (void)pPhysicalDevices;
    VkResult r = tick("EnumeratePhysicalDevices"); *pPhysicalDeviceCount = state.no_devices ? 0 : 1; if (pPhysicalDevices && *pPhysicalDeviceCount) pPhysicalDevices[0] = HANDLE(VkPhysicalDevice, 0x1000); return r;
}
static void VKAPI_CALL fake_GetPhysicalDeviceProperties(VkPhysicalDevice physicalDevice, VkPhysicalDeviceProperties* pProperties) {
    (void)physicalDevice; (void)pProperties;
    memset(pProperties, 0, sizeof(*pProperties)); pProperties->apiVersion = VK_API_VERSION_1_1; pProperties->vendorID = 0x106b; pProperties->deviceType = state.unsuitable_device ? VK_PHYSICAL_DEVICE_TYPE_CPU : VK_PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU; pProperties->limits.maxStorageBufferRange = 1048576; pProperties->limits.minStorageBufferOffsetAlignment = state.descriptor_align; pProperties->limits.nonCoherentAtomSize = state.atom; pProperties->limits.maxComputeWorkGroupCount[0] = 65535; pProperties->limits.maxComputeWorkGroupInvocations = 64; pProperties->limits.maxComputeWorkGroupSize[0] = 64;
}
static void VKAPI_CALL fake_GetPhysicalDeviceMemoryProperties(VkPhysicalDevice physicalDevice, VkPhysicalDeviceMemoryProperties* pMemoryProperties) {
    (void)physicalDevice; (void)pMemoryProperties;
    memset(pMemoryProperties, 0, sizeof(*pMemoryProperties)); pMemoryProperties->memoryTypeCount = 1; pMemoryProperties->memoryTypes[0].propertyFlags = state.no_host_memory ? 0 : VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT;
}
static void VKAPI_CALL fake_GetPhysicalDeviceQueueFamilyProperties(VkPhysicalDevice physicalDevice, uint32_t* pQueueFamilyPropertyCount, VkQueueFamilyProperties* pQueueFamilyProperties) {
    (void)physicalDevice; (void)pQueueFamilyPropertyCount; (void)pQueueFamilyProperties;
    *pQueueFamilyPropertyCount = 1; if (pQueueFamilyProperties) { memset(pQueueFamilyProperties, 0, sizeof(*pQueueFamilyProperties)); pQueueFamilyProperties->queueCount = state.no_queues ? 0 : 1; pQueueFamilyProperties->queueFlags = VK_QUEUE_COMPUTE_BIT; }
}
static VkResult VKAPI_CALL fake_EnumerateDeviceExtensionProperties(VkPhysicalDevice physicalDevice, const char* pLayerName, uint32_t* pPropertyCount, VkExtensionProperties* pProperties) {
    (void)physicalDevice; (void)pLayerName; (void)pPropertyCount; (void)pProperties;
    VkResult r = tick("EnumerateDeviceExtensionProperties"); *pPropertyCount = 0; return r;
}
static VkResult VKAPI_CALL fake_CreateDevice(VkPhysicalDevice physicalDevice, const VkDeviceCreateInfo* pCreateInfo, const VkAllocationCallbacks* pAllocator, VkDevice* pDevice) {
    (void)physicalDevice; (void)pCreateInfo; (void)pAllocator; (void)pDevice;
    VkResult r = tick("CreateDevice"); *pDevice = HANDLE(VkDevice, r == VK_SUCCESS ? acquired(DEVICE, 0) : 0xdead); return r;
}
static void VKAPI_CALL fake_DestroyDevice(VkDevice device, const VkAllocationCallbacks* pAllocator) {
    (void)device; (void)pAllocator;
    released(ID(device), DEVICE);
}
static void VKAPI_CALL fake_GetDeviceQueue(VkDevice device, uint32_t queueFamilyIndex, uint32_t queueIndex, VkQueue* pQueue) {
    (void)device; (void)queueFamilyIndex; (void)queueIndex; (void)pQueue;
    *pQueue = HANDLE(VkQueue, 0x2000);
}
static VkResult VKAPI_CALL fake_CreateBuffer(VkDevice device, const VkBufferCreateInfo* pCreateInfo, const VkAllocationCallbacks* pAllocator, VkBuffer* pBuffer) {
    (void)device; (void)pCreateInfo; (void)pAllocator; (void)pBuffer;
    VkResult r = tick("CreateBuffer"); *pBuffer = HANDLE(VkBuffer, r == VK_SUCCESS ? acquired(BUFFER, 0) : 0xdead); if (r == VK_SUCCESS) state.objects[ID(*pBuffer)].size = pCreateInfo->size; return r;
}
static void VKAPI_CALL fake_DestroyBuffer(VkDevice device, VkBuffer buffer, const VkAllocationCallbacks* pAllocator) {
    (void)device; (void)buffer; (void)pAllocator;
    released(ID(buffer), BUFFER);
}
static void VKAPI_CALL fake_GetBufferMemoryRequirements(VkDevice device, VkBuffer buffer, VkMemoryRequirements* pMemoryRequirements) {
    (void)device; (void)buffer; (void)pMemoryRequirements;
    memset(pMemoryRequirements, 0, sizeof(*pMemoryRequirements)); VkDeviceSize size = state.objects[ID(buffer)].size; VkDeviceSize round = state.requirement_round; pMemoryRequirements->size = ((size + round - 1) / round) * round + state.requirement_extra; state.objects[ID(buffer)].requirements = pMemoryRequirements->size; pMemoryRequirements->alignment = 4; pMemoryRequirements->memoryTypeBits = 1;
}
static VkResult VKAPI_CALL fake_AllocateMemory(VkDevice device, const VkMemoryAllocateInfo* pAllocateInfo, const VkAllocationCallbacks* pAllocator, VkDeviceMemory* pMemory) {
    (void)device; (void)pAllocateInfo; (void)pAllocator; (void)pMemory;
    ++state.memory_calls; VkResult r = tick("AllocateMemory"); *pMemory = HANDLE(VkDeviceMemory, r == VK_SUCCESS ? acquired(MEMORY, 0) : 0xdead); if (r == VK_SUCCESS) { struct object *m = &state.objects[ID(*pMemory)]; m->size = pAllocateInfo->allocationSize; m->bytes = calloc(1, (size_t)m->size); REQUIRE(m->bytes != NULL); } return r;
}
static void VKAPI_CALL fake_FreeMemory(VkDevice device, VkDeviceMemory memory, const VkAllocationCallbacks* pAllocator) {
    (void)device; (void)memory; (void)pAllocator;
    released(ID(memory), MEMORY);
}
static VkResult VKAPI_CALL fake_BindBufferMemory(VkDevice device, VkBuffer buffer, VkDeviceMemory memory, VkDeviceSize memoryOffset) {
    (void)device; (void)buffer; (void)memory; (void)memoryOffset;
    VkResult r = tick("BindBufferMemory"); if (r == VK_SUCCESS) { REQUIRE(memoryOffset == 0); REQUIRE(state.objects[ID(memory)].size >= state.objects[ID(buffer)].requirements); state.objects[ID(buffer)].bound = ID(memory); } return r;
}
static VkResult VKAPI_CALL fake_MapMemory(VkDevice device, VkDeviceMemory memory, VkDeviceSize offset, VkDeviceSize size, VkMemoryMapFlags flags, void** ppData) {
    (void)device; (void)memory; (void)offset; (void)size; (void)flags; (void)ppData;
    VkResult r = tick("MapMemory"); if (r == VK_SUCCESS) { state.objects[ID(memory)].mapped = 1; *ppData = state.objects[ID(memory)].bytes; } else *ppData = (void *)(uintptr_t)0xdead; return r;
}
static void VKAPI_CALL fake_UnmapMemory(VkDevice device, VkDeviceMemory memory) {
    (void)device; (void)memory;
    lock_state(); REQUIRE(state.objects[ID(memory)].alive && state.objects[ID(memory)].mapped); state.objects[ID(memory)].mapped = 0; unlock_state();
}
static VkResult VKAPI_CALL fake_FlushMappedMemoryRanges(VkDevice device, uint32_t memoryRangeCount, const VkMappedMemoryRange* pMemoryRanges) {
    (void)device;
    REQUIRE(memoryRangeCount == 1); const VkMappedMemoryRange *range = pMemoryRanges; VkDeviceSize size = state.objects[ID(range->memory)].size; REQUIRE(range->offset <= size); if (range->size != VK_WHOLE_SIZE) { REQUIRE(range->size <= size - range->offset); REQUIRE(range->offset % state.atom == 0); REQUIRE(range->size % state.atom == 0 || range->offset + range->size == size); }
    REQUIRE(state.objects[ID(pMemoryRanges[0].memory)].mapped);
    state.last_flush = pMemoryRanges[0]; return host_range("FlushMappedMemoryRanges");
}
static VkResult VKAPI_CALL fake_InvalidateMappedMemoryRanges(VkDevice device, uint32_t memoryRangeCount, const VkMappedMemoryRange* pMemoryRanges) {
    (void)device;
    REQUIRE(memoryRangeCount == 1); const VkMappedMemoryRange *range = pMemoryRanges; VkDeviceSize size = state.objects[ID(range->memory)].size; REQUIRE(range->offset <= size); if (range->size != VK_WHOLE_SIZE) { REQUIRE(range->size <= size - range->offset); REQUIRE(range->offset % state.atom == 0); REQUIRE(range->size % state.atom == 0 || range->offset + range->size == size); }
    REQUIRE(state.objects[ID(pMemoryRanges[0].memory)].mapped);
    state.last_invalidate = pMemoryRanges[0]; return host_range("InvalidateMappedMemoryRanges");
}
static VkResult VKAPI_CALL fake_CreateShaderModule(VkDevice device, const VkShaderModuleCreateInfo* pCreateInfo, const VkAllocationCallbacks* pAllocator, VkShaderModule* pShaderModule) {
    (void)device; (void)pCreateInfo; (void)pAllocator; (void)pShaderModule;
    VkResult r = tick("CreateShaderModule"); *pShaderModule = HANDLE(VkShaderModule, r == VK_SUCCESS ? acquired(SHADER, 0) : 0xdead); return r;
}
static void VKAPI_CALL fake_DestroyShaderModule(VkDevice device, VkShaderModule shaderModule, const VkAllocationCallbacks* pAllocator) {
    (void)device; (void)shaderModule; (void)pAllocator;
    released(ID(shaderModule), SHADER);
}
static VkResult VKAPI_CALL fake_CreateDescriptorSetLayout(VkDevice device, const VkDescriptorSetLayoutCreateInfo* pCreateInfo, const VkAllocationCallbacks* pAllocator, VkDescriptorSetLayout* pSetLayout) {
    (void)device; (void)pCreateInfo; (void)pAllocator; (void)pSetLayout;
    REQUIRE(pCreateInfo->bindingCount == 3); VkResult r = tick("CreateDescriptorSetLayout"); *pSetLayout = HANDLE(VkDescriptorSetLayout, r == VK_SUCCESS ? acquired(SET_LAYOUT, 0) : 0xdead); return r;
}
static void VKAPI_CALL fake_DestroyDescriptorSetLayout(VkDevice device, VkDescriptorSetLayout descriptorSetLayout, const VkAllocationCallbacks* pAllocator) {
    (void)device; (void)descriptorSetLayout; (void)pAllocator;
    released(ID(descriptorSetLayout), SET_LAYOUT);
}
static VkResult VKAPI_CALL fake_CreatePipelineLayout(VkDevice device, const VkPipelineLayoutCreateInfo* pCreateInfo, const VkAllocationCallbacks* pAllocator, VkPipelineLayout* pPipelineLayout) {
    (void)device; (void)pCreateInfo; (void)pAllocator; (void)pPipelineLayout;
    REQUIRE(pCreateInfo->pushConstantRangeCount == 1 && pCreateInfo->pPushConstantRanges[0].size == 16); VkResult r = tick("CreatePipelineLayout"); *pPipelineLayout = HANDLE(VkPipelineLayout, r == VK_SUCCESS ? acquired(PIPELINE_LAYOUT, 0) : 0xdead); return r;
}
static void VKAPI_CALL fake_DestroyPipelineLayout(VkDevice device, VkPipelineLayout pipelineLayout, const VkAllocationCallbacks* pAllocator) {
    (void)device; (void)pipelineLayout; (void)pAllocator;
    released(ID(pipelineLayout), PIPELINE_LAYOUT);
}
static VkResult VKAPI_CALL fake_CreateComputePipelines(VkDevice device, VkPipelineCache pipelineCache, uint32_t createInfoCount, const VkComputePipelineCreateInfo* pCreateInfos, const VkAllocationCallbacks* pAllocator, VkPipeline* pPipelines) {
    (void)device; (void)pipelineCache; (void)createInfoCount; (void)pCreateInfos; (void)pAllocator; (void)pPipelines;
    VkResult r = tick("CreateComputePipelines"); REQUIRE(createInfoCount == 1); *pPipelines = (r == VK_SUCCESS || state.partial_pipeline) ? HANDLE(VkPipeline, acquired(PIPELINE, 0)) : VK_NULL_HANDLE; return r;
}
static void VKAPI_CALL fake_DestroyPipeline(VkDevice device, VkPipeline pipeline, const VkAllocationCallbacks* pAllocator) {
    (void)device; (void)pipeline; (void)pAllocator;
    released(ID(pipeline), PIPELINE);
}
static VkResult VKAPI_CALL fake_CreateDescriptorPool(VkDevice device, const VkDescriptorPoolCreateInfo* pCreateInfo, const VkAllocationCallbacks* pAllocator, VkDescriptorPool* pDescriptorPool) {
    (void)device; (void)pCreateInfo; (void)pAllocator; (void)pDescriptorPool;
    VkResult r = tick("CreateDescriptorPool"); *pDescriptorPool = HANDLE(VkDescriptorPool, r == VK_SUCCESS ? acquired(DESCRIPTOR_POOL, 0) : 0xdead); return r;
}
static void VKAPI_CALL fake_DestroyDescriptorPool(VkDevice device, VkDescriptorPool descriptorPool, const VkAllocationCallbacks* pAllocator) {
    (void)device; (void)descriptorPool; (void)pAllocator;
    released(ID(descriptorPool), DESCRIPTOR_POOL);
}
static VkResult VKAPI_CALL fake_AllocateDescriptorSets(VkDevice device, const VkDescriptorSetAllocateInfo* pAllocateInfo, VkDescriptorSet* pDescriptorSets) {
    (void)device; (void)pAllocateInfo; (void)pDescriptorSets;
    VkResult r = tick("AllocateDescriptorSets"); *pDescriptorSets = HANDLE(VkDescriptorSet, r == VK_SUCCESS ? acquired(DESCRIPTOR_SET, ID(pAllocateInfo->descriptorPool)) : 0xdead); return r;
}
static void VKAPI_CALL fake_UpdateDescriptorSets(VkDevice device, uint32_t descriptorWriteCount, const VkWriteDescriptorSet* pDescriptorWrites, uint32_t descriptorCopyCount, const VkCopyDescriptorSet* pDescriptorCopies) {
    (void)device; (void)descriptorWriteCount; (void)pDescriptorWrites; (void)descriptorCopyCount; (void)pDescriptorCopies;
    REQUIRE(descriptorWriteCount == 3); for (unsigned i = 0; i < descriptorWriteCount; ++i) { REQUIRE(pDescriptorWrites[i].dstBinding == i); REQUIRE(pDescriptorWrites[i].pBufferInfo->range != 0);
        const VkDescriptorBufferInfo *info = pDescriptorWrites[i].pBufferInfo;
        REQUIRE(info->offset % state.descriptor_align == 0);
        REQUIRE(info->offset <= state.objects[ID(info->buffer)].size);
        REQUIRE(info->range <= state.objects[ID(info->buffer)].size - info->offset);
        state.objects[ID(pDescriptorWrites[i].dstSet)].bindings[i] = *info; }
}
static VkResult VKAPI_CALL fake_CreateCommandPool(VkDevice device, const VkCommandPoolCreateInfo* pCreateInfo, const VkAllocationCallbacks* pAllocator, VkCommandPool* pCommandPool) {
    (void)device; (void)pCreateInfo; (void)pAllocator; (void)pCommandPool;
    VkResult r = tick("CreateCommandPool"); *pCommandPool = HANDLE(VkCommandPool, r == VK_SUCCESS ? acquired(COMMAND_POOL, 0) : 0xdead); return r;
}
static void VKAPI_CALL fake_DestroyCommandPool(VkDevice device, VkCommandPool commandPool, const VkAllocationCallbacks* pAllocator) {
    (void)device; (void)commandPool; (void)pAllocator;
    lock_state();
    if (state.teardown_gate) { state.teardown_entered = 1; changed(); struct timespec end = deadline();
        while (!state.allow_teardown) wait_changed(&end); }
    unlock_state(); released(ID(commandPool), COMMAND_POOL);
}
static VkResult VKAPI_CALL fake_AllocateCommandBuffers(VkDevice device, const VkCommandBufferAllocateInfo* pAllocateInfo, VkCommandBuffer* pCommandBuffers) {
    (void)device; (void)pAllocateInfo; (void)pCommandBuffers;
    VkResult r = tick("AllocateCommandBuffers"); *pCommandBuffers = HANDLE(VkCommandBuffer, r == VK_SUCCESS ? acquired(COMMAND_BUFFER, ID(pAllocateInfo->commandPool)) : 0xdead); return r;
}
static VkResult VKAPI_CALL fake_BeginCommandBuffer(VkCommandBuffer commandBuffer, const VkCommandBufferBeginInfo* pBeginInfo) {
    (void)commandBuffer; (void)pBeginInfo;
    return tick("BeginCommandBuffer");
}
static void VKAPI_CALL fake_CmdPipelineBarrier(VkCommandBuffer commandBuffer, VkPipelineStageFlags srcStageMask, VkPipelineStageFlags dstStageMask, VkDependencyFlags dependencyFlags, uint32_t memoryBarrierCount, const VkMemoryBarrier* pMemoryBarriers, uint32_t bufferMemoryBarrierCount, const VkBufferMemoryBarrier* pBufferMemoryBarriers, uint32_t imageMemoryBarrierCount, const VkImageMemoryBarrier* pImageMemoryBarriers) {
    (void)pBufferMemoryBarriers; (void)pImageMemoryBarriers;
    REQUIRE(!dependencyFlags && memoryBarrierCount == 1 && !bufferMemoryBarrierCount && !imageMemoryBarrierCount);
    unsigned barrier = state.objects[ID(commandBuffer)].barriers++;
    REQUIRE(barrier < 2);
    if (barrier == 0) {
        REQUIRE(srcStageMask == (VK_PIPELINE_STAGE_HOST_BIT | VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT));
        REQUIRE(dstStageMask == VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT);
        REQUIRE(pMemoryBarriers[0].srcAccessMask == (VK_ACCESS_HOST_WRITE_BIT | VK_ACCESS_SHADER_WRITE_BIT));
        REQUIRE(pMemoryBarriers[0].dstAccessMask == (VK_ACCESS_SHADER_READ_BIT | VK_ACCESS_SHADER_WRITE_BIT));
    } else {
        REQUIRE(srcStageMask == VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT && dstStageMask == VK_PIPELINE_STAGE_HOST_BIT);
        REQUIRE(pMemoryBarriers[0].srcAccessMask == VK_ACCESS_SHADER_WRITE_BIT && pMemoryBarriers[0].dstAccessMask == VK_ACCESS_HOST_READ_BIT);
    }
}
static void VKAPI_CALL fake_CmdBindPipeline(VkCommandBuffer commandBuffer, VkPipelineBindPoint pipelineBindPoint, VkPipeline pipeline) {
    (void)commandBuffer; (void)pipelineBindPoint; (void)pipeline;

}
static void VKAPI_CALL fake_CmdBindDescriptorSets(VkCommandBuffer commandBuffer, VkPipelineBindPoint pipelineBindPoint, VkPipelineLayout layout, uint32_t firstSet, uint32_t descriptorSetCount, const VkDescriptorSet* pDescriptorSets, uint32_t dynamicOffsetCount, const uint32_t* pDynamicOffsets) {
    (void)pipelineBindPoint; (void)layout; (void)firstSet; (void)dynamicOffsetCount; (void)pDynamicOffsets;
    REQUIRE(descriptorSetCount == 1); state.objects[ID(commandBuffer)].bound = ID(*pDescriptorSets);
}
static void VKAPI_CALL fake_CmdPushConstants(VkCommandBuffer commandBuffer, VkPipelineLayout layout, VkShaderStageFlags stageFlags, uint32_t offset, uint32_t size, const void* pValues) {
    (void)commandBuffer; (void)layout; (void)stageFlags; (void)offset; (void)size; (void)pValues;
    REQUIRE(offset == 0 && (size == 4 || size == 8 || size == 16));
}
static void VKAPI_CALL fake_CmdDispatch(VkCommandBuffer commandBuffer, uint32_t groupCountX, uint32_t groupCountY, uint32_t groupCountZ) {
    (void)commandBuffer; (void)groupCountX; (void)groupCountY; (void)groupCountZ;
    REQUIRE(state.objects[ID(commandBuffer)].barriers == 1);
    REQUIRE(groupCountX == 1 && groupCountY == 1 && groupCountZ == 1);
}
static VkResult VKAPI_CALL fake_EndCommandBuffer(VkCommandBuffer commandBuffer) {
    REQUIRE(state.objects[ID(commandBuffer)].barriers == 2);
    return tick("EndCommandBuffer");
}
static VkResult VKAPI_CALL fake_CreateFence(VkDevice device, const VkFenceCreateInfo* pCreateInfo, const VkAllocationCallbacks* pAllocator, VkFence* pFence) {
    (void)device; (void)pCreateInfo; (void)pAllocator; (void)pFence;
    VkResult r = tick("CreateFence"); *pFence = HANDLE(VkFence, r == VK_SUCCESS ? acquired(FENCE, 0) : 0xdead); return r;
}
static void VKAPI_CALL fake_DestroyFence(VkDevice device, VkFence fence, const VkAllocationCallbacks* pAllocator) {
    (void)device; (void)fence; (void)pAllocator;
    released(ID(fence), FENCE);
}
/* Count use per fence and per resource, including repeated bindings and two
 * simultaneous jobs. A global pending bit cannot validate shared-block use. */
static void pending_resources(unsigned fence, int delta) {
    struct object *command = &state.objects[state.objects[fence].bound];
    struct object *set = &state.objects[command->bound];
    command->pending += delta; state.objects[command->owner].pending += delta;
    set->pending += delta; state.objects[set->owner].pending += delta;
    for (unsigned i = 0; i < 3; ++i) {
        struct object *buffer = &state.objects[ID(set->bindings[i].buffer)];
        buffer->pending += delta; state.objects[buffer->bound].pending += delta;
    }
}
static VkResult VKAPI_CALL fake_QueueSubmit(VkQueue queue, uint32_t submitCount, const VkSubmitInfo* pSubmits, VkFence fence) {
    (void)queue; (void)submitCount; (void)pSubmits; (void)fence;
    VkResult r = tick("QueueSubmit"); if (r == VK_SUCCESS) { lock_state(); REQUIRE(!state.objects[ID(fence)].pending); state.objects[ID(fence)].pending = 1; state.objects[ID(fence)].bound = ID(*pSubmits->pCommandBuffers); pending_resources(ID(fence), 1); if (state.host_active) state.submit_host_overlap = 1; ++state.gpu_pending; unlock_state(); } return r;
}
static VkResult VKAPI_CALL fake_WaitForFences(VkDevice device, uint32_t fenceCount, const VkFence* pFences, VkBool32 waitAll, uint64_t timeout) {
    (void)device; (void)fenceCount; (void)pFences; (void)waitAll; (void)timeout;
    REQUIRE(fenceCount == 1 && waitAll && timeout == UINT64_MAX);
    struct timespec end = deadline(); lock_state(); unsigned fence = ID(*pFences);
    REQUIRE(state.objects[fence].pending);
    state.wait_entered = 1; state.fence_entered[fence] = 1; changed();
    while (state.selective_completion ? !state.fence_allowed[fence] : !state.allow_completion) wait_changed(&end);
    VkResult result = state.wait_result;
    /* Timeout/allocation failure does not prove that queued work completed. */
    if (result == VK_SUCCESS || result == VK_ERROR_DEVICE_LOST) {
        pending_resources(fence, -1); state.objects[fence].pending = 0; --state.gpu_pending;
    }
    changed(); unlock_state(); return result;
}
static void *test_dlsym(void *library, const char *name) {
    REQUIRE(library == &state); lock_state(); unsigned call = ++state.dlsym_calls; int missing = state.fail_symbol == call; unlock_state(); if (missing) return NULL;
    if (!strcmp(name, "vkEnumerateInstanceExtensionProperties")) { PFN_vkEnumerateInstanceExtensionProperties function = fake_EnumerateInstanceExtensionProperties; void *address = NULL; REQUIRE(sizeof(address) == sizeof(function)); memcpy(&address, &function, sizeof(address)); return address; }
    if (!strcmp(name, "vkCreateInstance")) { PFN_vkCreateInstance function = fake_CreateInstance; void *address = NULL; REQUIRE(sizeof(address) == sizeof(function)); memcpy(&address, &function, sizeof(address)); return address; }
    if (!strcmp(name, "vkDestroyInstance")) { PFN_vkDestroyInstance function = fake_DestroyInstance; void *address = NULL; REQUIRE(sizeof(address) == sizeof(function)); memcpy(&address, &function, sizeof(address)); return address; }
    if (!strcmp(name, "vkEnumeratePhysicalDevices")) { PFN_vkEnumeratePhysicalDevices function = fake_EnumeratePhysicalDevices; void *address = NULL; REQUIRE(sizeof(address) == sizeof(function)); memcpy(&address, &function, sizeof(address)); return address; }
    if (!strcmp(name, "vkGetPhysicalDeviceProperties")) { PFN_vkGetPhysicalDeviceProperties function = fake_GetPhysicalDeviceProperties; void *address = NULL; REQUIRE(sizeof(address) == sizeof(function)); memcpy(&address, &function, sizeof(address)); return address; }
    if (!strcmp(name, "vkGetPhysicalDeviceMemoryProperties")) { PFN_vkGetPhysicalDeviceMemoryProperties function = fake_GetPhysicalDeviceMemoryProperties; void *address = NULL; REQUIRE(sizeof(address) == sizeof(function)); memcpy(&address, &function, sizeof(address)); return address; }
    if (!strcmp(name, "vkGetPhysicalDeviceQueueFamilyProperties")) { PFN_vkGetPhysicalDeviceQueueFamilyProperties function = fake_GetPhysicalDeviceQueueFamilyProperties; void *address = NULL; REQUIRE(sizeof(address) == sizeof(function)); memcpy(&address, &function, sizeof(address)); return address; }
    if (!strcmp(name, "vkEnumerateDeviceExtensionProperties")) { PFN_vkEnumerateDeviceExtensionProperties function = fake_EnumerateDeviceExtensionProperties; void *address = NULL; REQUIRE(sizeof(address) == sizeof(function)); memcpy(&address, &function, sizeof(address)); return address; }
    if (!strcmp(name, "vkCreateDevice")) { PFN_vkCreateDevice function = fake_CreateDevice; void *address = NULL; REQUIRE(sizeof(address) == sizeof(function)); memcpy(&address, &function, sizeof(address)); return address; }
    if (!strcmp(name, "vkDestroyDevice")) { PFN_vkDestroyDevice function = fake_DestroyDevice; void *address = NULL; REQUIRE(sizeof(address) == sizeof(function)); memcpy(&address, &function, sizeof(address)); return address; }
    if (!strcmp(name, "vkGetDeviceQueue")) { PFN_vkGetDeviceQueue function = fake_GetDeviceQueue; void *address = NULL; REQUIRE(sizeof(address) == sizeof(function)); memcpy(&address, &function, sizeof(address)); return address; }
    if (!strcmp(name, "vkCreateBuffer")) { PFN_vkCreateBuffer function = fake_CreateBuffer; void *address = NULL; REQUIRE(sizeof(address) == sizeof(function)); memcpy(&address, &function, sizeof(address)); return address; }
    if (!strcmp(name, "vkDestroyBuffer")) { PFN_vkDestroyBuffer function = fake_DestroyBuffer; void *address = NULL; REQUIRE(sizeof(address) == sizeof(function)); memcpy(&address, &function, sizeof(address)); return address; }
    if (!strcmp(name, "vkGetBufferMemoryRequirements")) { PFN_vkGetBufferMemoryRequirements function = fake_GetBufferMemoryRequirements; void *address = NULL; REQUIRE(sizeof(address) == sizeof(function)); memcpy(&address, &function, sizeof(address)); return address; }
    if (!strcmp(name, "vkAllocateMemory")) { PFN_vkAllocateMemory function = fake_AllocateMemory; void *address = NULL; REQUIRE(sizeof(address) == sizeof(function)); memcpy(&address, &function, sizeof(address)); return address; }
    if (!strcmp(name, "vkFreeMemory")) { PFN_vkFreeMemory function = fake_FreeMemory; void *address = NULL; REQUIRE(sizeof(address) == sizeof(function)); memcpy(&address, &function, sizeof(address)); return address; }
    if (!strcmp(name, "vkBindBufferMemory")) { PFN_vkBindBufferMemory function = fake_BindBufferMemory; void *address = NULL; REQUIRE(sizeof(address) == sizeof(function)); memcpy(&address, &function, sizeof(address)); return address; }
    if (!strcmp(name, "vkMapMemory")) { PFN_vkMapMemory function = fake_MapMemory; void *address = NULL; REQUIRE(sizeof(address) == sizeof(function)); memcpy(&address, &function, sizeof(address)); return address; }
    if (!strcmp(name, "vkUnmapMemory")) { PFN_vkUnmapMemory function = fake_UnmapMemory; void *address = NULL; REQUIRE(sizeof(address) == sizeof(function)); memcpy(&address, &function, sizeof(address)); return address; }
    if (!strcmp(name, "vkFlushMappedMemoryRanges")) { PFN_vkFlushMappedMemoryRanges function = fake_FlushMappedMemoryRanges; void *address = NULL; REQUIRE(sizeof(address) == sizeof(function)); memcpy(&address, &function, sizeof(address)); return address; }
    if (!strcmp(name, "vkInvalidateMappedMemoryRanges")) { PFN_vkInvalidateMappedMemoryRanges function = fake_InvalidateMappedMemoryRanges; void *address = NULL; REQUIRE(sizeof(address) == sizeof(function)); memcpy(&address, &function, sizeof(address)); return address; }
    if (!strcmp(name, "vkCreateShaderModule")) { PFN_vkCreateShaderModule function = fake_CreateShaderModule; void *address = NULL; REQUIRE(sizeof(address) == sizeof(function)); memcpy(&address, &function, sizeof(address)); return address; }
    if (!strcmp(name, "vkDestroyShaderModule")) { PFN_vkDestroyShaderModule function = fake_DestroyShaderModule; void *address = NULL; REQUIRE(sizeof(address) == sizeof(function)); memcpy(&address, &function, sizeof(address)); return address; }
    if (!strcmp(name, "vkCreateDescriptorSetLayout")) { PFN_vkCreateDescriptorSetLayout function = fake_CreateDescriptorSetLayout; void *address = NULL; REQUIRE(sizeof(address) == sizeof(function)); memcpy(&address, &function, sizeof(address)); return address; }
    if (!strcmp(name, "vkDestroyDescriptorSetLayout")) { PFN_vkDestroyDescriptorSetLayout function = fake_DestroyDescriptorSetLayout; void *address = NULL; REQUIRE(sizeof(address) == sizeof(function)); memcpy(&address, &function, sizeof(address)); return address; }
    if (!strcmp(name, "vkCreatePipelineLayout")) { PFN_vkCreatePipelineLayout function = fake_CreatePipelineLayout; void *address = NULL; REQUIRE(sizeof(address) == sizeof(function)); memcpy(&address, &function, sizeof(address)); return address; }
    if (!strcmp(name, "vkDestroyPipelineLayout")) { PFN_vkDestroyPipelineLayout function = fake_DestroyPipelineLayout; void *address = NULL; REQUIRE(sizeof(address) == sizeof(function)); memcpy(&address, &function, sizeof(address)); return address; }
    if (!strcmp(name, "vkCreateComputePipelines")) { PFN_vkCreateComputePipelines function = fake_CreateComputePipelines; void *address = NULL; REQUIRE(sizeof(address) == sizeof(function)); memcpy(&address, &function, sizeof(address)); return address; }
    if (!strcmp(name, "vkDestroyPipeline")) { PFN_vkDestroyPipeline function = fake_DestroyPipeline; void *address = NULL; REQUIRE(sizeof(address) == sizeof(function)); memcpy(&address, &function, sizeof(address)); return address; }
    if (!strcmp(name, "vkCreateDescriptorPool")) { PFN_vkCreateDescriptorPool function = fake_CreateDescriptorPool; void *address = NULL; REQUIRE(sizeof(address) == sizeof(function)); memcpy(&address, &function, sizeof(address)); return address; }
    if (!strcmp(name, "vkDestroyDescriptorPool")) { PFN_vkDestroyDescriptorPool function = fake_DestroyDescriptorPool; void *address = NULL; REQUIRE(sizeof(address) == sizeof(function)); memcpy(&address, &function, sizeof(address)); return address; }
    if (!strcmp(name, "vkAllocateDescriptorSets")) { PFN_vkAllocateDescriptorSets function = fake_AllocateDescriptorSets; void *address = NULL; REQUIRE(sizeof(address) == sizeof(function)); memcpy(&address, &function, sizeof(address)); return address; }
    if (!strcmp(name, "vkUpdateDescriptorSets")) { PFN_vkUpdateDescriptorSets function = fake_UpdateDescriptorSets; void *address = NULL; REQUIRE(sizeof(address) == sizeof(function)); memcpy(&address, &function, sizeof(address)); return address; }
    if (!strcmp(name, "vkCreateCommandPool")) { PFN_vkCreateCommandPool function = fake_CreateCommandPool; void *address = NULL; REQUIRE(sizeof(address) == sizeof(function)); memcpy(&address, &function, sizeof(address)); return address; }
    if (!strcmp(name, "vkDestroyCommandPool")) { PFN_vkDestroyCommandPool function = fake_DestroyCommandPool; void *address = NULL; REQUIRE(sizeof(address) == sizeof(function)); memcpy(&address, &function, sizeof(address)); return address; }
    if (!strcmp(name, "vkAllocateCommandBuffers")) { PFN_vkAllocateCommandBuffers function = fake_AllocateCommandBuffers; void *address = NULL; REQUIRE(sizeof(address) == sizeof(function)); memcpy(&address, &function, sizeof(address)); return address; }
    if (!strcmp(name, "vkBeginCommandBuffer")) { PFN_vkBeginCommandBuffer function = fake_BeginCommandBuffer; void *address = NULL; REQUIRE(sizeof(address) == sizeof(function)); memcpy(&address, &function, sizeof(address)); return address; }
    if (!strcmp(name, "vkCmdPipelineBarrier")) { PFN_vkCmdPipelineBarrier function = fake_CmdPipelineBarrier; void *address = NULL; REQUIRE(sizeof(address) == sizeof(function)); memcpy(&address, &function, sizeof(address)); return address; }
    if (!strcmp(name, "vkCmdBindPipeline")) { PFN_vkCmdBindPipeline function = fake_CmdBindPipeline; void *address = NULL; REQUIRE(sizeof(address) == sizeof(function)); memcpy(&address, &function, sizeof(address)); return address; }
    if (!strcmp(name, "vkCmdBindDescriptorSets")) { PFN_vkCmdBindDescriptorSets function = fake_CmdBindDescriptorSets; void *address = NULL; REQUIRE(sizeof(address) == sizeof(function)); memcpy(&address, &function, sizeof(address)); return address; }
    if (!strcmp(name, "vkCmdPushConstants")) { PFN_vkCmdPushConstants function = fake_CmdPushConstants; void *address = NULL; REQUIRE(sizeof(address) == sizeof(function)); memcpy(&address, &function, sizeof(address)); return address; }
    if (!strcmp(name, "vkCmdDispatch")) { PFN_vkCmdDispatch function = fake_CmdDispatch; void *address = NULL; REQUIRE(sizeof(address) == sizeof(function)); memcpy(&address, &function, sizeof(address)); return address; }
    if (!strcmp(name, "vkEndCommandBuffer")) { PFN_vkEndCommandBuffer function = fake_EndCommandBuffer; void *address = NULL; REQUIRE(sizeof(address) == sizeof(function)); memcpy(&address, &function, sizeof(address)); return address; }
    if (!strcmp(name, "vkCreateFence")) { PFN_vkCreateFence function = fake_CreateFence; void *address = NULL; REQUIRE(sizeof(address) == sizeof(function)); memcpy(&address, &function, sizeof(address)); return address; }
    if (!strcmp(name, "vkDestroyFence")) { PFN_vkDestroyFence function = fake_DestroyFence; void *address = NULL; REQUIRE(sizeof(address) == sizeof(function)); memcpy(&address, &function, sizeof(address)); return address; }
    if (!strcmp(name, "vkQueueSubmit")) { PFN_vkQueueSubmit function = fake_QueueSubmit; void *address = NULL; REQUIRE(sizeof(address) == sizeof(function)); memcpy(&address, &function, sizeof(address)); return address; }
    if (!strcmp(name, "vkWaitForFences")) { PFN_vkWaitForFences function = fake_WaitForFences; void *address = NULL; REQUIRE(sizeof(address) == sizeof(function)); memcpy(&address, &function, sizeof(address)); return address; }
    REQUIRE(0); return NULL;
}
