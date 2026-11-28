#define _POSIX_C_SOURCE 200809L
#define VK_NO_PROTOTYPES
#include <vulkan/vulkan.h>
#include <dlfcn.h>
#include <errno.h>
#include <limits.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <signal.h>
#include <sys/wait.h>
#include <sys/resource.h>
#include <unistd.h>
#include "../../fiber.h"
#include "../../loop.h"
#include "../../task.h"

/* The only substituted interfaces are the dynamic loader and failure-capable
 * CPU resource constructors called directly by gpu.c. Park/task/fiber remain
 * the actual runtime, including their synchronization and context switches. */
static void *test_dlopen(const char *, int);
static void *test_dlsym(void *, const char *);
static int test_dlclose(void *);
static void *test_calloc(size_t, size_t);
static void test_free(void *);
static int test_mutex_init(pthread_mutex_t *, const pthread_mutexattr_t *);
static int test_mutex_destroy(pthread_mutex_t *);
static int test_attr_init(pthread_attr_t *);
static int test_attr_setdetachstate(pthread_attr_t *, int);
static int test_attr_destroy(pthread_attr_t *);
static int test_thread_create(pthread_t *, const pthread_attr_t *, void *(*)(void *), void *);
#undef LINEA_VULKAN_LIBRARY
#define LINEA_VULKAN_LIBRARY "/missing-build-host/libvulkan-test"
#define dlopen test_dlopen
#define dlsym test_dlsym
#define dlclose test_dlclose
#define calloc test_calloc
#define free test_free
#define pthread_mutex_init test_mutex_init
#define pthread_mutex_destroy test_mutex_destroy
#define pthread_attr_init test_attr_init
#define pthread_attr_setdetachstate test_attr_setdetachstate
#define pthread_attr_destroy test_attr_destroy
#define pthread_create test_thread_create
#include "../../gpu.c"
#undef dlopen
#undef dlsym
#undef dlclose
#undef calloc
#undef free
#undef pthread_mutex_init
#undef pthread_mutex_destroy
#undef pthread_attr_init
#undef pthread_attr_setdetachstate
#undef pthread_attr_destroy
#undef pthread_create

#define REQUIRE(condition) do { if (!(condition)) { fprintf(stderr, "GPU fault: %s:%d: %s\n", __FILE__, __LINE__, #condition); _Exit(1); } } while (0)
#define ID(handle) ((unsigned)(uintptr_t)(handle))
#define HANDLE(type, id) ((type)(uintptr_t)(id))
enum object_kind { INSTANCE=1, DEVICE, BUFFER, MEMORY, SHADER, SET_LAYOUT, PIPELINE_LAYOUT, PIPELINE, DESCRIPTOR_POOL, DESCRIPTOR_SET, COMMAND_POOL, COMMAND_BUFFER, FENCE };
struct object { unsigned kind, owner, bound, barriers; int alive, mapped; VkDeviceSize size, requirements; unsigned char *bytes; VkDescriptorBufferInfo bindings[3]; int pending; };
struct fake_state {
    struct object objects[256];
    void *allocations[64];
    pthread_mutex_t *mutexes[8];
    unsigned next, live, cpu_live, cpu_calls, mutex_live, mutex_calls, attr_live;
    unsigned fail_cpu, fail_mutex, dlsym_calls, fail_symbol;
    const char *fail_name, *fail_host;
    unsigned fail_nth, named_calls;
    VkResult fail_result, wait_result;
    unsigned loader_calls, memory_calls;
    VkDeviceSize requirement_round, requirement_extra, descriptor_align, atom;
    VkMappedMemoryRange last_flush, last_invalidate;
    int standard_only, pinned_only;
    int library_live, fail_loader, no_devices, unsuitable_device, no_queues, no_host_memory;
    int allow_completion, wait_entered, gpu_pending, partial_pipeline;
    int about_wait, cpu_progress, gpu_done;
    int teardown_gate, teardown_entered, allow_teardown, reset_entered, reset_done;
    int monitor_host, allow_host, host_guarded, submit_host_overlap;
    unsigned host_entries, host_active, host_peak, host_workers;
    pthread_mutex_t *host_reference_lock;
    pthread_t gpu_carrier, cpu_carrier;
};
static struct fake_state state;
static pthread_mutex_t state_lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t state_changed = PTHREAD_COND_INITIALIZER;
static unsigned cases;
static unsigned long expected_loop;
static pthread_mutex_t watchdog_lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t watchdog_changed = PTHREAD_COND_INITIALIZER;
static int watchdog_finished;
static const uint32_t image_words[5] = {0x07230203, 0x00010300, 0, 1, 0};
static void lock_state(void) { REQUIRE(pthread_mutex_lock(&state_lock) == 0); }
static void unlock_state(void) { REQUIRE(pthread_mutex_unlock(&state_lock) == 0); }
static void changed(void) { REQUIRE(pthread_cond_broadcast(&state_changed) == 0); }
static struct timespec deadline(void) {
    struct timespec end; REQUIRE(clock_gettime(CLOCK_REALTIME, &end) == 0); end.tv_sec += 10; return end;
}
static void wait_changed(const struct timespec *end) {
    int result = pthread_cond_timedwait(&state_changed, &state_lock, end);
    if (result == ETIMEDOUT) { fprintf(stderr, "GPU fault: timed out waiting for deterministic completion/cleanup\n"); _Exit(1); }
    REQUIRE(result == 0);
}
static void reset(void) {
    lock_state();
    REQUIRE(!state.live && !state.cpu_live && !state.mutex_live && !state.attr_live && !state.library_live);
    memset(&state, 0, sizeof(state)); state.next = 1; state.fail_nth = 1;
    state.fail_result = VK_ERROR_OUT_OF_HOST_MEMORY; state.wait_result = VK_SUCCESS; state.allow_completion = 1; state.requirement_round = 256; state.descriptor_align = 16; state.atom = 64;
    unlock_state(); ++cases;
}
static void clean(void) {
    struct timespec end = deadline(); lock_state();
    while (state.live || state.cpu_live || state.mutex_live || state.attr_live || state.library_live) wait_changed(&end);
    REQUIRE(!state.gpu_pending); unlock_state();
}
static unsigned acquired(unsigned kind, unsigned owner) {
    lock_state(); unsigned id = state.next++; REQUIRE(id < 256);
    state.objects[id].alive = 1; state.objects[id].kind = kind; state.objects[id].owner = owner; ++state.live;
    unlock_state(); return id;
}
static void released(unsigned id, unsigned kind) {
    lock_state(); REQUIRE(id < state.next && state.objects[id].alive && state.objects[id].kind == kind);
    REQUIRE(!state.objects[id].pending); REQUIRE(!state.objects[id].mapped);
    if (kind == MEMORY)
        for (unsigned i = 1; i < state.next; ++i) REQUIRE(!state.objects[i].alive || state.objects[i].bound != id);
    if (kind == DESCRIPTOR_POOL || kind == COMMAND_POOL)
        for (unsigned i = 1; i < state.next; ++i)
            if (state.objects[i].alive && state.objects[i].owner == id) { state.objects[i].alive = 0; --state.live; }
    if (kind == DEVICE) REQUIRE(state.live == 2);
    if (kind == INSTANCE) REQUIRE(state.live == 1);
    if (kind == MEMORY) { free(state.objects[id].bytes); state.objects[id].bytes = NULL; }
    state.objects[id].alive = 0; state.objects[id].bound = 0; --state.live; changed(); unlock_state();
}
static VkResult tick(const char *name) {
    lock_state(); VkResult result = VK_SUCCESS;
    if (state.fail_name && !strcmp(state.fail_name, name) && ++state.named_calls == state.fail_nth) result = state.fail_result;
    unlock_state(); return result;
}
/* Pause an actual production host-copy API inside its fake Vulkan call.
 * A first caller's trylock result chooses which barrier the test can await:
 * an unguarded implementation must allow the competing operation to arrive,
 * while the guarded implementation cannot progress until host access ends. */
static VkResult host_range(const char *name) {
    VkResult result = tick(name);
    lock_state();
    if (state.monitor_host) {
        if (++state.host_entries == 1) {
            int status = pthread_mutex_trylock(state.host_reference_lock);
            if (status == 0) REQUIRE(pthread_mutex_unlock(state.host_reference_lock) == 0);
            else REQUIRE(status == EBUSY);
            state.host_guarded = status == EBUSY;
        }
        ++state.host_active;
        if (state.host_active > state.host_peak) state.host_peak = state.host_active;
        changed();
        struct timespec end = deadline();
        while (!state.allow_host) wait_changed(&end);
        --state.host_active;
    }
    unlock_state();
    return result;
}
static int host_failure(const char *name) { return state.fail_host && !strcmp(state.fail_host, name); }
static void *test_calloc(size_t count, size_t bytes) {
    lock_state(); unsigned call = ++state.cpu_calls;
    if (state.fail_cpu && call == state.fail_cpu) { unlock_state(); return NULL; }
    void *value = calloc(count, bytes); REQUIRE(value != NULL);
    unsigned i; for (i = 0; i < 64 && state.allocations[i]; ++i) {}
    REQUIRE(i < 64); state.allocations[i] = value; ++state.cpu_live; unlock_state(); return value;
}
static void test_free(void *value) {
    if (!value) return;
    lock_state(); unsigned i; for (i = 0; i < 64 && state.allocations[i] != value; ++i) {}
    REQUIRE(i < 64); state.allocations[i] = NULL; --state.cpu_live; changed(); unlock_state(); free(value);
}
static int test_mutex_init(pthread_mutex_t *mutex, const pthread_mutexattr_t *attr) {
    lock_state(); unsigned call = ++state.mutex_calls;
    if (state.fail_mutex == call) { unlock_state(); return EAGAIN; }
    int result = pthread_mutex_init(mutex, attr); REQUIRE(result == 0);
    unsigned i; for (i = 0; i < 8 && state.mutexes[i]; ++i) {}
    REQUIRE(i < 8); state.mutexes[i] = mutex; ++state.mutex_live; unlock_state(); return 0;
}
static int test_mutex_destroy(pthread_mutex_t *mutex) {
    lock_state(); unsigned i; for (i = 0; i < 8 && state.mutexes[i] != mutex; ++i) {}
    REQUIRE(i < 8); state.mutexes[i] = NULL; --state.mutex_live; changed(); unlock_state(); return pthread_mutex_destroy(mutex);
}
static int test_attr_init(pthread_attr_t *attr) {
    if (host_failure("pthread_attr_init")) return EAGAIN;
    int result = pthread_attr_init(attr); REQUIRE(result == 0); lock_state(); ++state.attr_live; unlock_state(); return result;
}
static int test_attr_setdetachstate(pthread_attr_t *attr, int detach) {
    if (host_failure("pthread_attr_setdetachstate")) return EAGAIN;
    return pthread_attr_setdetachstate(attr, detach);
}
static int test_attr_destroy(pthread_attr_t *attr) {
    lock_state(); REQUIRE(state.attr_live); --state.attr_live; changed(); unlock_state(); return pthread_attr_destroy(attr);
}
static int test_thread_create(pthread_t *thread, const pthread_attr_t *attr, void *(*entry)(void *), void *arg) {
    if (host_failure("pthread_create")) return EAGAIN;
    return pthread_create(thread, attr, entry, arg);
}
static void *test_dlopen(const char *path, int flags) {
    REQUIRE(path != NULL && (flags & RTLD_NOW)); lock_state();
#if defined(__APPLE__)
    const char *standard = "libvulkan.1.dylib";
#else
    const char *standard = "libvulkan.so.1";
#endif
    ++state.loader_calls;
    int is_standard = strcmp(path, standard) == 0;
    REQUIRE(is_standard || strcmp(path, LINEA_VULKAN_LIBRARY) == 0);
    if (state.standard_only) REQUIRE(state.loader_calls == 1 && is_standard);
    if (state.pinned_only) REQUIRE((state.loader_calls == 1 && is_standard) || (state.loader_calls == 2 && !is_standard));
    if (state.fail_loader || (state.pinned_only && is_standard)) { unlock_state(); return NULL; }
    REQUIRE(!state.library_live); state.library_live = 1; unlock_state(); return &state;
}
static int test_dlclose(void *library) {
    REQUIRE(library == &state); lock_state(); REQUIRE(state.library_live && !state.live);
    state.library_live = 0; changed(); unlock_state(); return 0;
}

#include "vulkan.inc"

static long device(void) { long value = linea_gpu_open(); REQUIRE(value > 0); return value; }
static long buffer(long owner) { long value = linea_gpu_buffer_new((unsigned long)owner, 64); REQUIRE(value > 0); return value; }
static void owners(long d, long a, long b, long c) {
    if (a > 0) linea_gpu_buffer_drop((unsigned long)a);
    if (b > 0 && b != a) linea_gpu_buffer_drop((unsigned long)b);
    if (c > 0 && c != a && c != b) linea_gpu_buffer_drop((unsigned long)c);
    linea_gpu_close((unsigned long)d);
}
static void dispatch_clean(unsigned cpu, unsigned handles) {
    struct timespec end = deadline(); lock_state();
    while (state.cpu_live != cpu || state.live != handles || state.attr_live) wait_changed(&end);
    unlock_state();
}
static void accessible(long handle) {
    uint32_t word = 0; REQUIRE(linea_gpu_buffer_read((unsigned long)handle, &word, 4) == 0);
}
static void inject(const char *name, unsigned nth) { state.fail_name = name; state.fail_nth = nth; state.named_calls = 0; }
static void loader_policy(void) {
    /* An installed loader works even after the build host's store is gone. */
    reset(); state.standard_only = 1; long d = device();
    REQUIRE(state.loader_calls == 1); linea_gpu_close((unsigned long)d); clean();
    /* Nix development retains its configured path as a second choice. */
    reset(); state.pinned_only = 1; d = device();
    REQUIRE(state.loader_calls == 2); linea_gpu_close((unsigned long)d); clean();
    /* A present but incomplete loader is an error, not a fallback trigger. */
    reset(); state.standard_only = 1; state.fail_symbol = 1;
    REQUIRE(linea_gpu_open() == -ENODEV); REQUIRE(state.loader_calls == 1); clean();
}
static void constructors(void) {
    reset(); long d = device(); unsigned cpu_allocs = state.cpu_calls; linea_gpu_close((unsigned long)d); clean();
    for (unsigned i = 1; i <= cpu_allocs; ++i) { reset(); state.fail_cpu = i; REQUIRE(linea_gpu_open() == -ENOMEM); clean(); }
    for (unsigned i = 1; i <= 2; ++i) { reset(); state.fail_mutex = i; REQUIRE(linea_gpu_open() == -EAGAIN); clean(); }
    reset(); state.fail_loader = 1; REQUIRE(linea_gpu_open() == -ENODEV); clean();
    /* Every function lookup can fail without leaving a loaded library. */
    reset(); d = device(); unsigned symbols = state.dlsym_calls; linea_gpu_close((unsigned long)d); clean();
    for (unsigned i = 1; i <= symbols; ++i) { reset(); state.fail_symbol = i; REQUIRE(linea_gpu_open() == -ENODEV); clean(); }
    const char *discovery[] = {"EnumerateInstanceExtensionProperties", "CreateInstance", "EnumeratePhysicalDevices", "EnumerateDeviceExtensionProperties", "CreateDevice"};
    for (unsigned i = 0; i < sizeof(discovery)/sizeof(*discovery); ++i)
        for (unsigned nth = 1; nth <= (i == 1 || i == 4 ? 1u : 2u); ++nth) {
            reset(); inject(discovery[i], nth); REQUIRE(linea_gpu_open() == -ENOMEM); clean();
        }
    for (unsigned shape = 0; shape < 3; ++shape) {
        reset(); if (shape == 0) state.no_devices = 1; else if (shape == 1) state.unsuitable_device = 1; else state.no_queues = 1;
        REQUIRE(linea_gpu_open() == -ENODEV); clean();
    }
    const char *stages[] = {"CreateBuffer", "AllocateMemory", "BindBufferMemory", "MapMemory"};
    for (unsigned i = 0; i < sizeof(stages)/sizeof(*stages); ++i) {
        reset(); d = device(); inject(stages[i], 1); REQUIRE(linea_gpu_buffer_new((unsigned long)d, 64) == -ENOMEM);
        linea_gpu_close((unsigned long)d); clean();
    }
    reset(); d = device(); state.fail_cpu = state.cpu_calls + 1; REQUIRE(linea_gpu_buffer_new((unsigned long)d, 64) == -ENOMEM); linea_gpu_close((unsigned long)d); clean();
    reset(); state.no_host_memory = 1; d = device(); REQUIRE(linea_gpu_buffer_new((unsigned long)d, 64) == -ENODEV); linea_gpu_close((unsigned long)d); clean();
}
static void dispatch_failures(void) {
    const char *stages[] = {"CreateShaderModule", "CreateDescriptorSetLayout", "CreatePipelineLayout", "CreateComputePipelines", "CreateDescriptorPool", "AllocateDescriptorSets", "CreateCommandPool", "AllocateCommandBuffers", "BeginCommandBuffer", "EndCommandBuffer", "CreateFence", "QueueSubmit"};
    for (unsigned i = 0; i < sizeof(stages)/sizeof(*stages); ++i) {
        reset(); long d = device(), a = buffer(d), b = buffer(d), c = buffer(d);
        unsigned cpu = state.cpu_live, handles = state.live;
        inject(stages[i], 1); state.partial_pipeline = 1;
        struct linea_gpu_kernel kernel = { image_words, sizeof(image_words), 2 };
        REQUIRE(linea_gpu_matmul((unsigned long)a, (unsigned long)b, (unsigned long)c, (unsigned long)(uintptr_t)&kernel, 2, 2, 2) == -ENOMEM);
        dispatch_clean(cpu, handles); accessible(a); accessible(b); accessible(c);
        owners(d, a, b, c); clean(); REQUIRE(!state.wait_entered);
    }
    reset(); long d = device(), a = buffer(d), c = buffer(d); inject("CreateComputePipelines", 1);
    REQUIRE(linea_gpu_submit((unsigned long)a, (unsigned long)c, image_words, sizeof(image_words), 1) == -ENOMEM); owners(d, a, c, 0); clean();
    const char *host[] = {"pthread_attr_init", "pthread_attr_setdetachstate", "pthread_create"};
    for (unsigned i = 0; i < sizeof(host)/sizeof(*host); ++i) {
        reset(); d = device(); a = buffer(d); c = buffer(d); state.fail_host = host[i];
        REQUIRE(linea_gpu_submit((unsigned long)a, (unsigned long)c, image_words, sizeof(image_words), 1) == -EAGAIN); accessible(a); accessible(c); owners(d, a, c, 0); clean();
    }
    reset(); d = device(); a = buffer(d); c = buffer(d); state.fail_cpu = state.cpu_calls + 1;
    REQUIRE(linea_gpu_submit((unsigned long)a, (unsigned long)c, image_words, sizeof(image_words), 1) == -ENOMEM); owners(d, a, c, 0); clean();
}
static void transfers(void) {
    reset(); long d = device(), a = buffer(d); uint32_t value = 0x12345678;
    REQUIRE(linea_gpu_upload((unsigned long)a, (unsigned long)(uintptr_t)&value, sizeof(value)) == 0);
    value = 0;
    REQUIRE(linea_gpu_download((unsigned long)a, (unsigned long)(uintptr_t)&value, sizeof(value)) == 0);
    REQUIRE(value == 0x12345678); /* The call returned with the copy complete. */
    REQUIRE(linea_gpu_buffer_read((unsigned long)a, NULL, 0) == 0);
    REQUIRE(linea_gpu_buffer_write((unsigned long)a, NULL, 0) == 0);
    REQUIRE(linea_gpu_buffer_read((unsigned long)a, NULL, 65) == -EINVAL);
    REQUIRE(linea_gpu_buffer_write((unsigned long)a, NULL, 65) == -EINVAL);
    inject("FlushMappedMemoryRanges", 1); state.fail_result = VK_ERROR_MEMORY_MAP_FAILED;
    REQUIRE(linea_gpu_buffer_write((unsigned long)a, &value, sizeof(value)) == -EIO);
    inject("InvalidateMappedMemoryRanges", 1); value = 0xfeedface;
    REQUIRE(linea_gpu_buffer_read((unsigned long)a, &value, sizeof(value)) == -EIO); REQUIRE(value == 0xfeedface);
    owners(d, a, 0, 0); clean();
}
static void arena_geometry(void) {
    reset(); long d = device();
    long arena = linea_gpu_arena_new((unsigned long)d, 0); REQUIRE(arena > 0);
    REQUIRE(linea_gpu_arena_buffer_new((unsigned long)arena, 0) == -ENOMEM);
    REQUIRE(state.memory_calls == 0); REQUIRE(linea_gpu_arena_reset((unsigned long)arena) == 0);
    linea_gpu_arena_drop((unsigned long)arena); linea_gpu_close((unsigned long)d); clean();
    for (unsigned cap = 255; cap <= 256; ++cap) {
        reset(); d = device(); arena = linea_gpu_arena_new((unsigned long)d, cap); REQUIRE(arena > 0);
        long a = linea_gpu_arena_buffer_new((unsigned long)arena, 4);
        if (cap == 255) { REQUIRE(a == -ENOMEM); REQUIRE(!state.memory_calls); }
        else {
            REQUIRE(a > 0); long b = linea_gpu_buffer_sized_like((unsigned long)a, 4); REQUIRE(b > 0);
            uint32_t x = 0xfeed1234, y = 0x1234feed, got = 0;
            REQUIRE(linea_gpu_buffer_write((unsigned long)a, &x, 4) == 0);
            REQUIRE(linea_gpu_buffer_write((unsigned long)b, &y, 4) == 0);
            REQUIRE(state.last_flush.offset == 64 && state.last_flush.size == 64);
            REQUIRE(linea_gpu_buffer_read((unsigned long)a, &got, 4) == 0 && got == x);
            REQUIRE(linea_gpu_buffer_read((unsigned long)b, &got, 4) == 0 && got == y);
            unsigned calls = state.memory_calls;
            REQUIRE(linea_gpu_arena_reset((unsigned long)arena) == 0);
            REQUIRE(linea_gpu_arena_buffer_new((unsigned long)arena, 4) > 0);
            REQUIRE(state.memory_calls == calls);
        }
        linea_gpu_arena_drop((unsigned long)arena); linea_gpu_close((unsigned long)d); clean();
    }
    reset(); state.descriptor_align = 24; state.atom = 40; state.requirement_round = 1;
    d = device(); arena = linea_gpu_arena_new((unsigned long)d, 512); REQUIRE(arena > 0);
    long first = linea_gpu_arena_buffer_new((unsigned long)arena, 4), second = linea_gpu_buffer_sized_like((unsigned long)first, 4);
    REQUIRE(first > 0 && second > 0);
    REQUIRE(((struct gpu_buffer *)(uintptr_t)second)->offset == 120);
    struct gpu_buffer overlapping = *(struct gpu_buffer *)(uintptr_t)first;
    REQUIRE(linea_gpu_submit((unsigned long)first, (unsigned long)(uintptr_t)&overlapping, image_words, sizeof(image_words), 1) == -EINVAL);
    linea_gpu_arena_drop((unsigned long)arena); linea_gpu_close((unsigned long)d); clean();
}
static void system_buffer_independence(void) {
    reset(); long d = device(), a = buffer(d); linea_gpu_close((unsigned long)d);
    long sibling = linea_gpu_buffer_sized_like((unsigned long)a, 4); REQUIRE(sibling > 0);
    uint32_t word = 0x7fc12345, got = 0;
    REQUIRE(linea_gpu_buffer_write((unsigned long)sibling, &word, 4) == 0);
    linea_gpu_buffer_drop((unsigned long)a);
    REQUIRE(linea_gpu_buffer_read((unsigned long)sibling, &got, 4) == 0 && got == word);
    linea_gpu_buffer_drop((unsigned long)sibling); clean();
}
static void arena_allocation_fallback(void) {
    const char *stages[] = {"CreateBuffer", "AllocateMemory", "BindBufferMemory", "MapMemory"};
    const VkResult recoverable[] = {VK_ERROR_OUT_OF_HOST_MEMORY, VK_ERROR_OUT_OF_DEVICE_MEMORY};
    for (unsigned stage = 0; stage < sizeof(stages) / sizeof(*stages); ++stage) {
        for (unsigned kind = 0; kind < sizeof(recoverable) / sizeof(*recoverable); ++kind) {
            reset(); long d = device(), arena = linea_gpu_arena_new((unsigned long)d, 131072); REQUIRE(arena > 0);
            inject(stages[stage], 1); state.fail_result = recoverable[kind];
            long view = linea_gpu_arena_buffer_new((unsigned long)arena, 4); REQUIRE(view > 0);
            struct gpu_arena *a = (struct gpu_arena *)(uintptr_t)arena;
            REQUIRE(state.named_calls == 2 && a->blocks == a->current && !a->blocks->next);
            REQUIRE(a->blocks->capacity == 4 && a->blocks->cursor == 4);
            REQUIRE(a->committed == 256 && a->blocks->allocated == 256);
            uint32_t word = 0x5aabc123, got = 0;
            REQUIRE(linea_gpu_buffer_write((unsigned long)view, &word, 4) == 0);
            REQUIRE(linea_gpu_buffer_read((unsigned long)view, &got, 4) == 0 && got == word);
            linea_gpu_arena_drop((unsigned long)arena); linea_gpu_close((unsigned long)d); clean();
        }
    }
    /* A failed preferred-block metadata allocation is recoverable too. The
     * already allocated view is published only after the smaller block works. */
    reset(); long d = device(), arena = linea_gpu_arena_new((unsigned long)d, 131072); REQUIRE(arena > 0);
    state.fail_cpu = state.cpu_calls + 2;
    long view = linea_gpu_arena_buffer_new((unsigned long)arena, 4); REQUIRE(view > 0);
    struct gpu_arena *a = (struct gpu_arena *)(uintptr_t)arena;
    REQUIRE(a->blocks->capacity == 4 && a->committed == 256);
    linea_gpu_arena_drop((unsigned long)arena); linea_gpu_close((unsigned long)d); clean();
    /* If the exact retry also fails, neither attempt commits arena state. */
    reset(); d = device(); arena = linea_gpu_arena_new((unsigned long)d, 131072); REQUIRE(arena > 0);
    a = (struct gpu_arena *)(uintptr_t)arena;
    inject("AllocateMemory", 1); state.fail_cpu = state.cpu_calls + 3;
    REQUIRE(linea_gpu_arena_buffer_new((unsigned long)arena, 4) == -ENOMEM);
    REQUIRE(!a->blocks && !a->current && !a->views && !a->committed);
    state.fail_name = NULL; state.fail_cpu = 0;
    REQUIRE(linea_gpu_arena_buffer_new((unsigned long)arena, 4) > 0);
    linea_gpu_arena_drop((unsigned long)arena); linea_gpu_close((unsigned long)d); clean();
    /* A smaller allocation cannot recover device loss or other API errors. */
    const VkResult refused[] = {VK_ERROR_DEVICE_LOST, VK_ERROR_INITIALIZATION_FAILED, VK_ERROR_FEATURE_NOT_PRESENT};
    for (unsigned kind = 0; kind < sizeof(refused) / sizeof(*refused); ++kind) {
        reset(); d = device(); arena = linea_gpu_arena_new((unsigned long)d, 131072); REQUIRE(arena > 0);
        a = (struct gpu_arena *)(uintptr_t)arena;
        inject("CreateBuffer", 1); state.fail_result = refused[kind];
        REQUIRE(linea_gpu_arena_buffer_new((unsigned long)arena, 4) == (kind == 2 ? -ENODEV : -EIO));
        REQUIRE(state.named_calls == 1 && !a->blocks && !a->views && !a->committed);
        if (kind == 0) REQUIRE(linea_gpu_arena_buffer_new((unsigned long)arena, 4) == -EIO && state.named_calls == 1);
        linea_gpu_arena_drop((unsigned long)arena); linea_gpu_close((unsigned long)d); clean();
    }
    reset(); d = device(); arena = linea_gpu_arena_new((unsigned long)d, 131072); REQUIRE(arena > 0);
    unsigned calls = state.cpu_calls;
    inject("CreateBuffer", 1); state.fail_result = VK_ERROR_DEVICE_LOST;
    REQUIRE(linea_gpu_arena_buffer_new((unsigned long)arena, ULONG_MAX) == -EOVERFLOW);
    REQUIRE(!state.named_calls && state.cpu_calls == calls && !((struct gpu_device *)(uintptr_t)d)->terminal);
    linea_gpu_arena_drop((unsigned long)arena); linea_gpu_close((unsigned long)d); clean();
}
static void arena_failures(void) {
    const char *stages[] = {"CreateBuffer", "AllocateMemory", "BindBufferMemory", "MapMemory"};
    for (unsigned stage = 0; stage < 6; ++stage) {
        reset(); long d = device(); long arena = linea_gpu_arena_new((unsigned long)d, 131072); REQUIRE(arena > 0);
        long first = linea_gpu_arena_buffer_new((unsigned long)arena, 65536); REQUIRE(first > 0);
        uint32_t sentinel = 0xabcddcba, got = 0;
        REQUIRE(linea_gpu_buffer_write((unsigned long)first, &sentinel, 4) == 0);
        struct gpu_arena *a = (struct gpu_arena *)(uintptr_t)arena;
        unsigned long cursor = a->blocks->cursor, committed = a->committed;
        if (stage < 4) inject(stages[stage], 1); else state.fail_cpu = state.cpu_calls + (stage == 4 ? 1u : 2u);
        /* Fill retained capacity before forcing transactional growth failure. */
        long fail = linea_gpu_arena_buffer_new((unsigned long)arena, 65536);
        REQUIRE(fail == -ENOMEM); REQUIRE(a->committed == committed && a->blocks->cursor == cursor);
        REQUIRE(linea_gpu_buffer_read((unsigned long)first, &got, 4) == 0 && got == sentinel);
        state.fail_name = NULL; state.fail_cpu = 0;
        REQUIRE(linea_gpu_arena_buffer_new((unsigned long)arena, 4) > 0);
        linea_gpu_arena_drop((unsigned long)arena); linea_gpu_close((unsigned long)d); clean();
    }
    /* Preferred 273 rounds to 401, rejected without AllocateMemory. The
     * minimum four-byte buffer commits 145 including a partial final atom. */
    reset(); state.requirement_round = 128; state.requirement_extra = 17;
    long d = device(), arena = linea_gpu_arena_new((unsigned long)d, 273); REQUIRE(arena > 0);
    long empty = linea_gpu_arena_buffer_new((unsigned long)arena, 0); REQUIRE(empty > 0);
    REQUIRE(state.memory_calls == 1); REQUIRE(((struct gpu_arena *)(uintptr_t)arena)->committed == 145);
    REQUIRE(linea_gpu_buffer_read((unsigned long)empty, NULL, 0) == 0);
    REQUIRE(linea_gpu_buffer_write((unsigned long)empty, NULL, 0) == 0);
    REQUIRE(state.last_flush.memory == VK_NULL_HANDLE && state.last_invalidate.memory == VK_NULL_HANDLE);
    linea_gpu_arena_drop((unsigned long)arena); linea_gpu_close((unsigned long)d); clean();
    reset(); state.requirement_round = 1; state.requirement_extra = 13;
    d = device(); arena = linea_gpu_arena_new((unsigned long)d, 145); REQUIRE(arena > 0);
    long a = linea_gpu_arena_buffer_new((unsigned long)arena, 132); REQUIRE(a > 0);
    unsigned char data[132]; memset(data, 0xa5, sizeof(data));
    REQUIRE(linea_gpu_buffer_write((unsigned long)a, data, sizeof(data)) == 0);
    REQUIRE(state.last_flush.offset == 0 && state.last_flush.size == 145);
    REQUIRE(linea_gpu_arena_reset((unsigned long)arena) == 0);
    a = linea_gpu_arena_buffer_new((unsigned long)arena, 4); REQUIRE(a > 0);
    long tail = linea_gpu_buffer_sized_like((unsigned long)a, 68); REQUIRE(tail > 0);
    REQUIRE(linea_gpu_buffer_write((unsigned long)tail, data, 68) == 0);
    REQUIRE(state.last_flush.offset == 64 && state.last_flush.size == 81);
    REQUIRE(linea_gpu_buffer_read((unsigned long)tail, data, 68) == 0);
    REQUIRE(state.last_invalidate.offset == 64 && state.last_invalidate.size == 81);
    linea_gpu_arena_drop((unsigned long)arena); linea_gpu_close((unsigned long)d); clean();
}
static void release_completion(void);
static void wait_started(void);
struct host_work { long buffer, output, result; int write, submit; uint32_t word; };
static void *host_worker(void *raw) {
    struct host_work *work = raw;
    lock_state(); ++state.host_workers; changed(); unlock_state();
    if (work->submit) work->result = linea_gpu_submit((unsigned long)work->buffer,
        (unsigned long)work->output, image_words, sizeof(image_words), 1);
    else if (work->write) work->result = linea_gpu_buffer_write((unsigned long)work->buffer, &work->word, 4);
    else work->result = linea_gpu_buffer_read((unsigned long)work->buffer, &work->word, 4);
    return NULL;
}
static void concurrent_host_access(void) {
    /* Two shared downloads; then each host direction versus a real submission.
     * The latter holds the fake fence pending until host access is tested. */
    for (unsigned step = 0; step < 3; ++step) {
        unsigned variant = (step + 1) % 3;
        reset(); state.allow_completion = 0;
        long d = device(), a = buffer(d), output = buffer(d);
        state.monitor_host = 1;
        state.host_reference_lock = &((struct gpu_device *)(uintptr_t)d)->references_lock;
        struct host_work first = { .buffer = a, .write = variant == 2, .word = 0x3f800000 };
        struct host_work second = { .buffer = a, .output = output, .submit = variant != 0 };
        pthread_t first_thread, second_thread;
        REQUIRE(pthread_create(&first_thread, NULL, host_worker, &first) == 0);
        struct timespec end = deadline(); lock_state();
        while (!state.host_entries) wait_changed(&end);
        unlock_state();
        REQUIRE(pthread_create(&second_thread, NULL, host_worker, &second) == 0);
        lock_state(); while (state.host_workers != 2) wait_changed(&end);
        if (!state.host_guarded) {
            while (variant == 0 ? state.host_entries != 2 : !state.gpu_pending) wait_changed(&end);
        }
        state.allow_host = 1; changed(); unlock_state();
        REQUIRE(pthread_join(first_thread, NULL) == 0);
        REQUIRE(pthread_join(second_thread, NULL) == 0);
        REQUIRE(first.result == 0);
        if (variant == 0) REQUIRE(second.result == 0);
        else {
            REQUIRE(second.result > 0); wait_started();
            uint32_t word = 0;
            REQUIRE(linea_gpu_buffer_read((unsigned long)a, &word, 4) == -EBUSY);
            release_completion();
            REQUIRE(linea_gpu_wait((unsigned long)second.result) == 0);
            linea_gpu_submission_drop((unsigned long)second.result);
        }
        REQUIRE(state.host_peak == 1);
        REQUIRE(!state.submit_host_overlap);
        state.monitor_host = 0;
        owners(d, a, output, 0); clean();
    }
}
static void narrowing(void) {
    reset(); long d = device(), a = buffer(d), b = buffer(d), c = buffer(d);
    const unsigned long wide = (unsigned long)UINT32_MAX + 1;
    struct linea_gpu_kernel kernel = { image_words, sizeof(image_words), 1 };
    REQUIRE(linea_gpu_submit((unsigned long)a, (unsigned long)c, image_words, sizeof(image_words), wide) == -EINVAL);
    REQUIRE(linea_gpu_reduce((unsigned long)a, (unsigned long)c, (unsigned long)(uintptr_t)&kernel, wide, 0) == -EINVAL);
    REQUIRE(linea_gpu_reduce((unsigned long)a, (unsigned long)c, (unsigned long)(uintptr_t)&kernel, 0, wide) == -EINVAL);
    REQUIRE(linea_gpu_map_uniform((unsigned long)a, (unsigned long)c, (unsigned long)(uintptr_t)&kernel, wide, 0) == -EINVAL);
    REQUIRE(linea_gpu_map_uniform((unsigned long)a, (unsigned long)c, (unsigned long)(uintptr_t)&kernel, 0, wide) == -EINVAL);
    REQUIRE(linea_gpu_zip((unsigned long)a, (unsigned long)b, (unsigned long)c, (unsigned long)(uintptr_t)&kernel, wide) == -EINVAL);
    REQUIRE(linea_gpu_zip((unsigned long)a, (unsigned long)b, (unsigned long)c, (unsigned long)(uintptr_t)&kernel, 17) == -EINVAL);
    kernel.kind = 2;
    REQUIRE(linea_gpu_matmul((unsigned long)a, (unsigned long)b, (unsigned long)c, (unsigned long)(uintptr_t)&kernel, wide, 0, 0) == -EOVERFLOW);
    REQUIRE(linea_gpu_matmul((unsigned long)a, (unsigned long)b, (unsigned long)c, (unsigned long)(uintptr_t)&kernel, 0, wide, 0) == -EOVERFLOW);
    REQUIRE(linea_gpu_matmul((unsigned long)a, (unsigned long)b, (unsigned long)c, (unsigned long)(uintptr_t)&kernel, 0, 0, wide) == -EOVERFLOW);
    REQUIRE(linea_gpu_matmul((unsigned long)a, (unsigned long)b, (unsigned long)c, (unsigned long)(uintptr_t)&kernel, UINT32_MAX, 2, 1) == -EOVERFLOW);
    REQUIRE(linea_gpu_matmul((unsigned long)a, (unsigned long)b, (unsigned long)c, (unsigned long)(uintptr_t)&kernel, 1, UINT32_MAX, 2) == -EOVERFLOW);
    REQUIRE(linea_gpu_matmul((unsigned long)a, (unsigned long)b, (unsigned long)c, (unsigned long)(uintptr_t)&kernel, UINT32_MAX, 1, 2) == -EOVERFLOW);
    owners(d, a, b, c); clean();
}
static void release_completion(void) { lock_state(); state.allow_completion = 1; changed(); unlock_state(); }
static void wait_started(void) {
    struct timespec end = deadline(); lock_state(); while (!state.wait_entered) wait_changed(&end); unlock_state();
}
static void pending_and_aliases(void) {
    for (unsigned kind = 0; kind < 6; ++kind) {
        reset(); state.allow_completion = 0; if (kind == 3) state.wait_result = VK_ERROR_DEVICE_LOST;
        long d = device(), a = buffer(d), b = kind == 3 ? buffer(d) : a, c = buffer(d), job;
        struct linea_gpu_kernel kernel = { image_words, sizeof(image_words), kind == 0 ? 0 : kind == 1 || kind >= 4 ? 1 : 2 };
        if (kind == 0) job = linea_gpu_map((unsigned long)a, (unsigned long)c, (unsigned long)(uintptr_t)&kernel, 1);
        else if (kind == 1) job = linea_gpu_reduce((unsigned long)a, (unsigned long)c, (unsigned long)(uintptr_t)&kernel, 1, 0);
        else if (kind < 4) job = linea_gpu_matmul((unsigned long)a, (unsigned long)b, (unsigned long)c, (unsigned long)(uintptr_t)&kernel, 2, 2, 2);
        else if (kind == 4) job = linea_gpu_map_uniform((unsigned long)a, (unsigned long)c, (unsigned long)(uintptr_t)&kernel, 1, 0x3f800000);
        else job = linea_gpu_zip((unsigned long)a, (unsigned long)b, (unsigned long)c, (unsigned long)(uintptr_t)&kernel, 1);
        REQUIRE(job > 0); wait_started();
        uint32_t word = 0;
        REQUIRE(linea_gpu_buffer_read((unsigned long)a, &word, 4) == -EBUSY);
        REQUIRE(linea_gpu_buffer_write((unsigned long)c, &word, 4) == -EBUSY);
        if (kind >= 2) REQUIRE(linea_gpu_buffer_write((unsigned long)b, &word, 4) == -EBUSY);
        owners(d, a, b, c); /* Only the pending submission now owns resources. */
        release_completion(); REQUIRE(linea_gpu_wait((unsigned long)job) == (kind == 3 ? -EIO : 0)); linea_gpu_submission_drop((unsigned long)job); clean();
    }
    /* A zero map produces a settled job without creating GPU execution. */
    reset(); long d = device(), a = buffer(d), c = buffer(d);
    long job = linea_gpu_submit((unsigned long)a, (unsigned long)c, image_words, sizeof(image_words), 0); REQUIRE(job > 0);
    owners(d, a, c, 0); REQUIRE(linea_gpu_wait((unsigned long)job) == 0); linea_gpu_submission_drop((unsigned long)job); clean(); REQUIRE(!state.wait_entered);
}
static void arena_submission_paths(void) {
    const char *stages[] = {"CreateShaderModule", "CreateDescriptorSetLayout", "CreatePipelineLayout", "CreateComputePipelines", "CreateDescriptorPool", "AllocateDescriptorSets", "CreateCommandPool", "AllocateCommandBuffers", "BeginCommandBuffer", "EndCommandBuffer", "CreateFence", "QueueSubmit", "pthread_create"};
    for (unsigned i = 0; i < sizeof(stages)/sizeof(*stages); ++i) {
        reset(); long d = device(), arena = linea_gpu_arena_new((unsigned long)d, 256); REQUIRE(arena > 0);
        long a = linea_gpu_arena_buffer_new((unsigned long)arena, 4), b = linea_gpu_buffer_sized_like((unsigned long)a, 4); REQUIRE(a > 0 && b > 0);
        if (i == 12) state.fail_host = stages[i]; else inject(stages[i], 1);
        REQUIRE(linea_gpu_submit((unsigned long)a, (unsigned long)b, image_words, sizeof(image_words), 1) == (i == 12 ? -EAGAIN : -ENOMEM));
        REQUIRE(linea_gpu_arena_reset((unsigned long)arena) == 0);
        REQUIRE(((struct gpu_arena *)(uintptr_t)arena)->pending == 0);
        linea_gpu_arena_drop((unsigned long)arena); linea_gpu_close((unsigned long)d); clean();
    }
    for (unsigned kind = 0; kind < 3; ++kind) {
        reset(); long d = device(), arena = linea_gpu_arena_new((unsigned long)d, 256); REQUIRE(arena > 0);
        long a = linea_gpu_arena_buffer_new((unsigned long)arena, 4), b = linea_gpu_buffer_sized_like((unsigned long)a, 4); REQUIRE(a > 0 && b > 0);
        if (kind == 1) { inject("QueueSubmit", 1); state.fail_result = VK_ERROR_DEVICE_LOST; }
        if (kind == 2) state.wait_result = VK_ERROR_DEVICE_LOST;
        long job = linea_gpu_submit((unsigned long)a, (unsigned long)b, image_words, sizeof(image_words), kind ? 1 : 0);
        if (kind == 1) REQUIRE(job == -EIO); else { REQUIRE(job > 0); REQUIRE(linea_gpu_wait((unsigned long)job) == (kind ? -EIO : 0)); }
        REQUIRE(linea_gpu_arena_reset((unsigned long)arena) == (kind ? -EIO : 0));
        if (kind) {
            REQUIRE(linea_gpu_arena_buffer_new((unsigned long)arena, 4) == -EIO);
            REQUIRE(linea_gpu_buffer_new((unsigned long)d, 4) == -EIO);
        } else REQUIRE(linea_gpu_arena_buffer_new((unsigned long)arena, 4) > 0);
        linea_gpu_arena_drop((unsigned long)arena); linea_gpu_close((unsigned long)d);
        if (job > 0) linea_gpu_submission_drop((unsigned long)job); clean();
    }
    reset(); state.allow_completion = 0; long d = device();
    long arenas[2], jobs[2];
    for (unsigned i = 0; i < 2; ++i) { arenas[i] = linea_gpu_arena_new((unsigned long)d, 256); REQUIRE(arenas[i] > 0); }
    long a = linea_gpu_arena_buffer_new((unsigned long)arenas[0], 4);
    long b = linea_gpu_arena_buffer_new((unsigned long)arenas[1], 4);
    for (unsigned i = 0; i < 2; ++i) {
        long output = linea_gpu_arena_buffer_new((unsigned long)arenas[i], 4); REQUIRE(output > 0);
        struct linea_gpu_kernel kernel = {image_words, sizeof(image_words), 1};
        jobs[i] = linea_gpu_zip((unsigned long)a, (unsigned long)b, (unsigned long)output, (unsigned long)(uintptr_t)&kernel, 1); REQUIRE(jobs[i] > 0);
    }
    release_completion();
    for (unsigned i = 0; i < 2; ++i) REQUIRE(linea_gpu_arena_reset((unsigned long)arenas[i]) == 0);
    for (unsigned i = 0; i < 2; ++i) linea_gpu_arena_drop((unsigned long)arenas[i]);
    linea_gpu_close((unsigned long)d);
    for (unsigned i = 0; i < 2; ++i) { REQUIRE(linea_gpu_wait((unsigned long)jobs[i]) == 0); linea_gpu_submission_drop((unsigned long)jobs[i]); }
    clean();
}
static void *watchdog(void *unused) {
    (void)unused; struct timespec end = deadline(); end.tv_sec += 20;
    REQUIRE(pthread_mutex_lock(&watchdog_lock) == 0);
    while (!watchdog_finished) {
        int result = pthread_cond_timedwait(&watchdog_changed, &watchdog_lock, &end);
        if (result == ETIMEDOUT) { fprintf(stderr, "GPU fault: watchdog detected a stuck constructor, completion or carrier\n"); _Exit(1); }
        REQUIRE(result == 0);
    }
    REQUIRE(pthread_mutex_unlock(&watchdog_lock) == 0); return NULL;
}
static void release_body(unsigned long at, unsigned long len) { REQUIRE(!at && !len); }
static void gpu_task(unsigned long endpoint, unsigned long at, unsigned long len) {
    REQUIRE(!len && linea_io_current() == expected_loop);
    lock_state(); state.about_wait = 1; state.gpu_carrier = pthread_self(); changed(); unlock_state();
    REQUIRE(linea_gpu_wait(at) == 0);
    lock_state(); REQUIRE(state.cpu_progress); state.gpu_done = 1; changed(); unlock_state();
    linea_chan_close(endpoint);
}
static void cpu_task(unsigned long endpoint, unsigned long at, unsigned long len) {
    REQUIRE(!at && !len && linea_io_current() == expected_loop);
    lock_state(); REQUIRE(state.about_wait && state.wait_entered && !state.allow_completion);
    state.cpu_carrier = pthread_self(); REQUIRE(pthread_equal(state.cpu_carrier, state.gpu_carrier));
    state.cpu_progress = 1; state.allow_completion = 1; changed(); unlock_state(); linea_chan_close(endpoint);
}
static void single_carrier(void) {
    reset(); state.allow_completion = 0; long d = device(), a = buffer(d), c = buffer(d);
    long job = linea_gpu_submit((unsigned long)a, (unsigned long)c, image_words, sizeof(image_words), 1); REQUIRE(job > 0); wait_started();
    long loop = linea_loop_open(1); REQUIRE(loop > 0); expected_loop = (unsigned long)loop;
    long waiting = linea_task_prepare_on(256 * 1024, expected_loop); REQUIRE(waiting > 0);
    unsigned long gpu_handle = linea_task_start((unsigned long)waiting, gpu_task, release_body, (unsigned long)job, 0, 0);
    struct timespec end = deadline(); lock_state(); while (!state.about_wait) wait_changed(&end); unlock_state();
    long runnable = linea_task_prepare_on(256 * 1024, expected_loop); REQUIRE(runnable > 0);
    unsigned long cpu_handle = linea_task_start((unsigned long)runnable, cpu_task, release_body, 0, 0, 0);
    /* A carrier blocked in GPU wait would prevent the CPU task from opening
     * the only completion gate. Main and the fake worker both have deadlines. */
    end = deadline(); lock_state(); while (!state.cpu_progress || !state.gpu_done) wait_changed(&end); unlock_state();
    linea_chan_close(cpu_handle); linea_chan_close(gpu_handle); linea_gpu_submission_drop((unsigned long)job); owners(d, a, c, 0); clean();
}
struct arena_teardown_work {
    unsigned long arena, other, job;
    struct gpu_buffer *views, *block, *first, *second;
    unsigned long cursor, committed, pending, first_pins, second_pins;
    int drop;
};
static void reset_task(unsigned long endpoint, unsigned long at, unsigned long len) {
    REQUIRE(!len); struct arena_teardown_work *work = (struct arena_teardown_work *)(uintptr_t)at;
    struct gpu_device *d = ((struct gpu_arena *)(uintptr_t)work->arena)->device;
    lock_state(); state.reset_entered = 1; state.gpu_carrier = pthread_self(); changed(); unlock_state();
    if (work->drop) linea_gpu_arena_drop(work->arena);
    else {
        REQUIRE(linea_gpu_arena_reset(work->arena) == 0);
        struct gpu_arena *a = (struct gpu_arena *)(uintptr_t)work->arena;
        REQUIRE(!a->views && !a->pending && !a->draining && a->blocks->cursor == 0);
    }
    /* Pending pins must be detached before reset/drop can return, even if the
     * completion worker has not yet published the public job's done flag. */
    linea_park_lock(&d->storage_changed);
    struct gpu_submission *job = (struct gpu_submission *)(uintptr_t)work->job;
    REQUIRE(!job->input && !job->output && !job->right);
    linea_park_unlock(&d->storage_changed);
    lock_state(); state.reset_done = 1; changed(); unlock_state(); linea_chan_close(endpoint);
}
static void teardown_task(unsigned long endpoint, unsigned long at, unsigned long len) {
    REQUIRE(!len); struct arena_teardown_work *work = (struct arena_teardown_work *)(uintptr_t)at;
    lock_state(); REQUIRE(state.reset_entered && !state.reset_done);
    REQUIRE(pthread_equal(state.gpu_carrier, pthread_self())); unlock_state();
    struct gpu_arena *a = (struct gpu_arena *)(uintptr_t)work->arena;
    struct gpu_device *d = a->device;
    linea_park_lock(&d->storage_changed);
    REQUIRE(a->draining && a->pending == work->pending && a->pending > 0);
    REQUIRE(a->views == work->views && a->blocks == work->block && a->current == work->block);
    REQUIRE(a->committed == work->committed && a->blocks->cursor == work->cursor);
    if (pthread_mutex_lock(&d->references_lock) != 0) abort();
    REQUIRE(work->first->in_flight == work->first_pins && work->second->in_flight == work->second_pins);
    if (pthread_mutex_unlock(&d->references_lock) != 0) abort();
    linea_park_unlock(&d->storage_changed);
    /* The arena is still alive while draining: same-domain work is refused,
     * while an independent arena on this device can allocate on this carrier. */
    REQUIRE(linea_gpu_arena_buffer_new(work->arena, 4) == -EBUSY);
    REQUIRE(linea_gpu_submit((unsigned long)(uintptr_t)work->first, (unsigned long)(uintptr_t)work->second,
        image_words, sizeof(image_words), 1) == -EBUSY);
    REQUIRE(linea_gpu_arena_buffer_new(work->other, 4) > 0);
    lock_state(); state.allow_teardown = 1; changed(); unlock_state(); linea_chan_close(endpoint);
}
static void arena_teardown(void) {
    for (unsigned drop = 0; drop < 2; ++drop) {
        reset(); state.teardown_gate = 1; long d = device();
        long arena = linea_gpu_arena_new((unsigned long)d, 256); REQUIRE(arena > 0);
        long other = linea_gpu_arena_new((unsigned long)d, 256); REQUIRE(other > 0);
        long first = linea_gpu_arena_buffer_new((unsigned long)arena, 4), second = linea_gpu_buffer_sized_like((unsigned long)first, 4);
        REQUIRE(first > 0 && second > 0);
        long job = linea_gpu_submit((unsigned long)first, (unsigned long)second, image_words, sizeof(image_words), 1); REQUIRE(job > 0);
        struct timespec end = deadline(); lock_state(); while (!state.teardown_entered) wait_changed(&end); unlock_state();
        struct gpu_arena *a = (struct gpu_arena *)(uintptr_t)arena;
        struct arena_teardown_work work = {
            .arena = (unsigned long)arena, .other = (unsigned long)other, .job = (unsigned long)job,
            .views = a->views, .block = a->blocks, .first = (struct gpu_buffer *)(uintptr_t)first,
            .second = (struct gpu_buffer *)(uintptr_t)second, .cursor = a->blocks->cursor,
            .committed = a->committed, .pending = a->pending,
            .first_pins = ((struct gpu_buffer *)(uintptr_t)first)->in_flight,
            .second_pins = ((struct gpu_buffer *)(uintptr_t)second)->in_flight, .drop = drop != 0,
        };
        REQUIRE(work.pending && work.first_pins && work.second_pins);
        long loop = linea_loop_open(1); REQUIRE(loop > 0);
        long prepared = linea_task_prepare_on(256 * 1024, (unsigned long)loop); REQUIRE(prepared > 0);
        unsigned long waiting = linea_task_start((unsigned long)prepared, reset_task, release_body, (unsigned long)(uintptr_t)&work, 0, 0);
        end = deadline(); lock_state(); while (!state.reset_entered) wait_changed(&end); unlock_state();
        prepared = linea_task_prepare_on(256 * 1024, (unsigned long)loop); REQUIRE(prepared > 0);
        unsigned long release = linea_task_start((unsigned long)prepared, teardown_task, release_body, (unsigned long)(uintptr_t)&work, 0, 0);
        end = deadline(); lock_state(); while (!state.reset_done) wait_changed(&end); unlock_state();
        if (!drop) {
            REQUIRE(linea_gpu_arena_buffer_new((unsigned long)arena, 4) > 0);
            linea_gpu_arena_drop((unsigned long)arena);
        }
        linea_gpu_arena_drop((unsigned long)other); linea_gpu_close((unsigned long)d);
        REQUIRE(linea_gpu_wait((unsigned long)job) == 0); linea_gpu_submission_drop((unsigned long)job);
        linea_chan_close(waiting); linea_chan_close(release); clean();
    }
}
static void fatal_fence_policy(const char *self) {
    const char *results[] = { "allocation", "timeout" };
    for (unsigned i = 0; i < sizeof(results) / sizeof(*results); ++i) {
        pid_t child = fork(); REQUIRE(child >= 0);
        if (child == 0) { execl(self, self, "--indeterminate-wait", results[i], (char *)NULL); _Exit(127); }
        int status = 0; REQUIRE(waitpid(child, &status, 0) == child);
        REQUIRE(WIFSIGNALED(status) && WTERMSIG(status) == SIGABRT);
        ++cases;
    }
}
int main(int argc, char **argv) {
    if (argc == 3 && !strcmp(argv[1], "--indeterminate-wait")) {
        struct rlimit core = {0, 0}; REQUIRE(setrlimit(RLIMIT_CORE, &core) == 0);
        alarm(10);
        reset();
        state.wait_result = !strcmp(argv[2], "allocation") ? VK_ERROR_OUT_OF_HOST_MEMORY : VK_TIMEOUT;
        long d = device(), a = buffer(d), output = buffer(d);
        long job = linea_gpu_submit((unsigned long)a, (unsigned long)output, image_words, sizeof(image_words), 1);
        REQUIRE(job > 0);
        (void)linea_gpu_wait((unsigned long)job);
        return 91; /* Indeterminate completion must abort, never settle. */
    }
    fatal_fence_policy(argv[0]);
    pthread_t watcher; REQUIRE(pthread_create(&watcher, NULL, watchdog, NULL) == 0);
    system_buffer_independence(); arena_geometry(); arena_allocation_fallback(); arena_failures(); arena_teardown(); arena_submission_paths(); loader_policy(); constructors(); dispatch_failures(); transfers(); concurrent_host_access(); narrowing(); pending_and_aliases(); single_carrier();
    REQUIRE(pthread_mutex_lock(&watchdog_lock) == 0); watchdog_finished = 1;
    REQUIRE(pthread_cond_broadcast(&watchdog_changed) == 0); REQUIRE(pthread_mutex_unlock(&watchdog_lock) == 0);
    REQUIRE(pthread_join(watcher, NULL) == 0);
    printf("production GPU failure/lifetime tests: %u isolated cases; same-carrier CPU progress passed\n", cases);
    return 0;
}
