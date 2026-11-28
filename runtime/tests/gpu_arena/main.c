/* Real Vulkan execution and physical allocation evidence. Including production
 * gpu.c exposes its private identities only to this harness; no fake loader,
 * public observability API or production counter participates. */
#define _POSIX_C_SOURCE 200809L
#include "../../gpu.c"
#include <stdio.h>
#include <sched.h>
#include <time.h>

static PFN_vkAllocateMemory allocate_memory;
static PFN_vkFreeMemory free_memory;
static unsigned commits, frees;
static VkDeviceSize committed_bytes;
static VkDeviceMemory committed_memory;
static unsigned checks;
static pthread_mutex_t watchdog_lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t watchdog_changed = PTHREAD_COND_INITIALIZER;
static int watchdog_finished;

/* As in the native fault harness, a separate native thread bounds setup,
 * fence completion, worker metadata release and teardown without changing
 * the production runtime's indeterminate-completion policy. */
static void watchdog_require(int condition) {
    if (!condition) { fprintf(stderr, "GPU arena: watchdog synchronization failed\n"); _Exit(1); }
}
static void *watchdog(void *unused) {
    (void)unused;
    struct timespec end;
    watchdog_require(clock_gettime(CLOCK_REALTIME, &end) == 0);
    end.tv_sec += 120;
    watchdog_require(pthread_mutex_lock(&watchdog_lock) == 0);
    while (!watchdog_finished) {
        int result = pthread_cond_timedwait(&watchdog_changed, &watchdog_lock, &end);
        if (result == ETIMEDOUT) {
            fprintf(stderr, "GPU arena: 120-second watchdog detected stuck device setup, fence completion, worker release or teardown\n");
            _Exit(1);
        }
        watchdog_require(result == 0);
    }
    watchdog_require(pthread_mutex_unlock(&watchdog_lock) == 0);
    return NULL;
}

static void require(int condition, const char *what) {
    ++checks;
    if (!condition) { fprintf(stderr, "GPU arena failure: %s\n", what); exit(1); }
}
static unsigned long checked(long value, const char *what) {
    ++checks;
    if (value < 0) { fprintf(stderr, "GPU arena %s: %ld\n", what, value); exit(1); }
    return (unsigned long)value;
}
static VKAPI_ATTR VkResult VKAPI_CALL record_allocate(VkDevice device,
        const VkMemoryAllocateInfo *info, const VkAllocationCallbacks *callbacks, VkDeviceMemory *memory) {
    VkResult status = allocate_memory(device, info, callbacks, memory);
    if (status == VK_SUCCESS) { ++commits; committed_bytes += info->allocationSize; committed_memory = *memory; }
    return status;
}
static VKAPI_ATTR void VKAPI_CALL record_free(VkDevice device, VkDeviceMemory memory,
        const VkAllocationCallbacks *callbacks) {
    if (memory) { require(memory == committed_memory, "release freed a different allocation"); ++frees; }
    free_memory(device, memory, callbacks);
}
static void *image(const char *path, unsigned long *bytes) {
    FILE *file = fopen(path, "rb"); require(file != NULL, "open copy shader");
    require(fseek(file, 0, SEEK_END) == 0, "seek copy shader");
    long length = ftell(file); require(length > 0, "copy shader extent");
    rewind(file);
    void *data = malloc((size_t)length); require(data != NULL, "copy shader allocation");
    require(fread(data, 1, (size_t)length, file) == (size_t)length, "read copy shader");
    require(fclose(file) == 0, "close copy shader");
    *bytes = (unsigned long)length; return data;
}
int main(int argc, char **argv) {
    require(argc == 2, "one production copy shader is required");
    pthread_t watcher;
    require(pthread_create(&watcher, NULL, watchdog, NULL) == 0, "start harness watchdog");
    unsigned long image_bytes;
    void *shader = image(argv[1], &image_bytes);
    unsigned long device = checked(linea_gpu_open(), "open real Vulkan device");
    struct gpu_device *d = (struct gpu_device *)(uintptr_t)device;
    printf("GPU arena device: %s\n", d->properties.deviceName);
    allocate_memory = d->api.AllocateMemory; free_memory = d->api.FreeMemory;
    d->api.AllocateMemory = record_allocate; d->api.FreeMemory = record_free;
    require(d->references == 1, "initial device references");
    unsigned long empty = checked(linea_gpu_arena_new(device, 0), "open zero-cap arena");
    require(linea_gpu_arena_buffer_new(empty, 0) == -ENOMEM, "empty view needs descriptor capacity");
    require(linea_gpu_arena_reset(empty) == 0, "reset zero-cap arena");
    linea_gpu_arena_drop(empty);
    require(commits == 0 && frees == 0, "zero-cap arena committed memory");

    unsigned long owner = checked(linea_gpu_arena_new(device, 1048576), "open arena");
    struct gpu_arena *a = (struct gpu_arena *)(uintptr_t)owner;
    require(a->committed == 0 && a->blocks == NULL, "opening is lazy");
    VkDeviceMemory retained_memory = VK_NULL_HANDLE;
    VkBuffer retained_buffer = VK_NULL_HANDLE;
    VkDeviceSize retained_bytes = 0;
    unsigned long jobs[3];
    const uint32_t values[4] = { 2, 0x7fc00001u, 0x80000000u, 0x40800000u };
    for (unsigned epoch = 0; epoch < 3; ++epoch) {
        unsigned long input = checked(linea_gpu_arena_buffer_new(owner, sizeof(values)), "arena input");
        unsigned long output = checked(linea_gpu_buffer_sized_like(input, sizeof(values)), "arena sibling");
        struct gpu_buffer *first = (struct gpu_buffer *)(uintptr_t)input;
        struct gpu_buffer *second = (struct gpu_buffer *)(uintptr_t)output;
        require(first->arena == a && second->arena == a, "sibling preserves arena identity");
        require(first->block == second->block && first->offset != second->offset, "views use distinct ranges of one block");
        checked(linea_gpu_buffer_write(input, values, sizeof(values)), "raw-bit upload");
        jobs[epoch] = checked(linea_gpu_submit(input, output, shader, image_bytes, 4), "real GPU copy");
        checked(linea_gpu_wait(jobs[epoch]), "copy completion");
        uint32_t result[4] = { 0 };
        checked(linea_gpu_buffer_read(output, result, sizeof(result)), "raw-bit download");
        require(memcmp(values, result, sizeof(values)) == 0, "real shader changed raw bits");
        require(a->pending == 0, "completed jobs retain arena pins");
        require(commits == 1 && frees == 0 && a->committed == committed_bytes && first->memory == committed_memory,
                "physical commitment counter disagrees with arena accounting");
        require(a->committed <= a->limit, "physical commitment exceeded cap");
        if (epoch == 0) {
            retained_memory = first->memory; retained_buffer = first->buffer;
            retained_bytes = committed_bytes;
        } else {
            require(first->memory == retained_memory && first->buffer == retained_buffer,
                    "reset did not reuse the physical allocation and buffer");
            require(committed_bytes == retained_bytes, "another epoch committed memory");
        }
        checked(linea_gpu_arena_reset(owner), "reset with completed public job retained");
        require(a->views == NULL && a->blocks->cursor == 0 && a->committed == retained_bytes,
                "reset did not rewind metadata while retaining committed storage");
    }
    linea_gpu_arena_drop(owner);
    require(frees == commits, "arena release left device memory committed");
    /* Completed public jobs are deliberately settled after their arena metadata
     * is gone. Their remaining lifetime must not read any old view pointer. */
    for (unsigned epoch = 0; epoch < 3; ++epoch) {
        struct gpu_submission *job = (struct gpu_submission *)(uintptr_t)jobs[epoch];
        /* done is published just before the worker drops its private metadata
         * reference. Synchronize with that final drop before counting owners. */
        for (;;) {
            linea_park_lock(&job->park);
            int worker_released = job->references == 1;
            linea_park_unlock(&job->park);
            if (worker_released) break;
            sched_yield();
        }
        linea_gpu_submission_drop(jobs[epoch]);
    }
    require(d->references == 1, "arena or completed job retained device ownership");
    d->api.AllocateMemory = allocate_memory; d->api.FreeMemory = free_memory;
    linea_gpu_close(device); free(shader);
    require(pthread_mutex_lock(&watchdog_lock) == 0, "stop watchdog lock");
    watchdog_finished = 1;
    require(pthread_cond_broadcast(&watchdog_changed) == 0, "wake watchdog");
    require(pthread_mutex_unlock(&watchdog_lock) == 0, "stop watchdog unlock");
    require(pthread_join(watcher, NULL) == 0, "join harness watchdog");
    printf("GPU arena: %u checks, %u physical commit, %llu committed bytes, %u free, 3 epochs\n",
           checks, commits, (unsigned long long)committed_bytes, frees);
    return 0;
}
