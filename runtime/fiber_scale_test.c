#define _GNU_SOURCE
#ifndef LINEA_FIBER_PAUSES
#define LINEA_FIBER_PAUSES 1
#endif
#undef NDEBUG
#include "fiber.h"
#include "fiber_pause.h"
#include "loop.h"
#include "net.h"
#include "park.h"
#include "task.h"

#include <assert.h>
#include <errno.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/resource.h>
#include <time.h>
#include <unistd.h>
#if defined(__APPLE__)
#include <mach/mach.h>
#else
#include <dirent.h>
#endif

enum { connection_count = 10000, carrier_count = 2 };
static const unsigned long stack_bytes = 2097152;
struct connection {
    int client, server;
    unsigned long handle;
    pthread_t home;
    unsigned parked, responses, releases;
    unsigned char request;
};
static struct connection connections[connection_count];
static pthread_mutex_t control = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t changed = PTHREAD_COND_INITIALIZER;
static pthread_key_t pending_read;
static pthread_t carrier_threads[carrier_count], controller;
static unsigned identities, started, parked, completed, sentinel_releases;

static unsigned process_threads(void) {
#if defined(__APPLE__)
    thread_act_array_t threads;
    mach_msg_type_number_t count;
    assert(task_threads(mach_task_self(), &threads, &count) == KERN_SUCCESS);
    for (mach_msg_type_number_t i = 0; i < count; i += 1)
        assert(mach_port_deallocate(mach_task_self(), threads[i]) == KERN_SUCCESS);
    assert(vm_deallocate(mach_task_self(), (vm_address_t)threads,
                         (vm_size_t)count * sizeof *threads) == KERN_SUCCESS);
    return (unsigned)count;
#else
    DIR *directory = opendir("/proc/self/task");
    assert(directory != NULL);
    unsigned count = 0;
    struct dirent *entry;
    errno = 0;
    while ((entry = readdir(directory)) != NULL)
        if (entry->d_name[0] >= '0' && entry->d_name[0] <= '9') count += 1;
    assert(errno == 0);
    assert(closedir(directory) == 0);
    return count;
#endif
}

static void reserve_descriptors(void) {
    const rlim_t needed = 3 * (rlim_t)connection_count + 128;
    struct rlimit limit;
    if (getrlimit(RLIMIT_NOFILE, &limit) != 0) {
        perror("fiber scale: getrlimit(RLIMIT_NOFILE)");
        exit(EXIT_FAILURE);
    }
    if (limit.rlim_max != RLIM_INFINITY && limit.rlim_max < needed) {
        fprintf(stderr, "fiber scale: 10000 TCP connections require at least %llu descriptors; hard limit is %llu\n",
                (unsigned long long)needed, (unsigned long long)limit.rlim_max);
        exit(EXIT_FAILURE);
    }
    if (limit.rlim_cur < needed) {
        limit.rlim_cur = needed;
        if (setrlimit(RLIMIT_NOFILE, &limit) != 0) {
            fprintf(stderr, "fiber scale: cannot raise soft descriptor limit to %llu within hard limit: %s\n",
                    (unsigned long long)needed, strerror(errno));
            exit(EXIT_FAILURE);
        }
    }
}

/* The entering hook runs after the previous fiber's context was saved and
 * its I/O wait published. No client writes until every read is observed here.
 * One sentinel per carrier makes the final reader observable as well. */
void fiber_test_pause(enum linea_fiber_pause_point point) {
    if (point != linea_fiber_entering) return;
    struct connection *connection = pthread_getspecific(pending_read);
    if (connection == NULL) return;
    assert(pthread_setspecific(pending_read, NULL) == 0);
    assert(pthread_mutex_lock(&control) == 0);
    assert(connection->parked == 0);
    connection->parked = 1;
    parked += 1;
    assert(pthread_cond_signal(&changed) == 0);
    assert(pthread_mutex_unlock(&control) == 0);
}

static void release_connection(unsigned long at, unsigned long len) {
    struct connection *connection = (struct connection *)at;
    assert(len == sizeof *connection);
    assert(connection->releases == 0);
    connection->releases += 1;
}

static void read_connection(unsigned long endpoint, unsigned long at, unsigned long len) {
    struct connection *connection = (struct connection *)at;
    assert(len == sizeof *connection);
    connection->home = pthread_self();
    assert(!pthread_equal(connection->home, controller));
    assert(pthread_mutex_lock(&control) == 0);
    unsigned i;
    for (i = 0; i < identities; i += 1)
        if (pthread_equal(carrier_threads[i], connection->home)) break;
    if (i == identities) {
        assert(identities < carrier_count);
        carrier_threads[identities++] = connection->home;
    }
    started += 1;
    assert(pthread_mutex_unlock(&control) == 0);
    assert(pthread_setspecific(pending_read, connection) == 0);
    unsigned char request = 0;
    assert(linea_net_read(connection->server, (unsigned long)&request, 1, 0) == 1);
    assert(pthread_getspecific(pending_read) == NULL);
    assert(pthread_equal(connection->home, pthread_self()));
    assert(request == connection->request);
    const unsigned char response = (unsigned char)(request ^ 0x5aU);
    assert(linea_net_write(connection->server, (unsigned long)&response, 1, 0) == 1);
    assert(linea_net_close(connection->server) == 0);
    assert(pthread_mutex_lock(&control) == 0);
    assert(connection->responses == 0);
    connection->responses += 1;
    completed += 1;
    assert(pthread_mutex_unlock(&control) == 0);
    linea_chan_close(endpoint);
}

static void sentinel(unsigned long endpoint, unsigned long at, unsigned long len) {
    assert(at == 0 && len == 0);
    linea_chan_close(endpoint);
}

static void release_sentinel(unsigned long at, unsigned long len) {
    assert(at == 0 && len == 0);
    assert(pthread_mutex_lock(&control) == 0);
    sentinel_releases += 1;
    assert(pthread_mutex_unlock(&control) == 0);
}

static void await_parked(void) {
    struct timespec until;
    assert(clock_gettime(CLOCK_REALTIME, &until) == 0);
    until.tv_sec += 60;
    assert(pthread_mutex_lock(&control) == 0);
    while (parked != connection_count) {
        int result = pthread_cond_timedwait(&changed, &control, &until);
        if (result == ETIMEDOUT) {
            fprintf(stderr, "fiber scale: only %u/%u reads parked, %u started, %u carrier identities\n",
                    parked, (unsigned)connection_count, started, identities);
            exit(EXIT_FAILURE);
        }
        assert(result == 0);
    }
    assert(started == connection_count && completed == 0);
    assert(identities == carrier_count);
    for (unsigned i = 0; i < connection_count; i += 1) {
        assert(connections[i].parked == 1);
        assert(connections[i].responses == 0 && connections[i].releases == 0);
    }
    assert(pthread_mutex_unlock(&control) == 0);
}

int main(void) {
    (void)alarm(180);
    controller = pthread_self();
    reserve_descriptors();
    assert(pthread_key_create(&pending_read, NULL) == 0);
    const unsigned baseline_threads = process_threads();
    const long loop = linea_loop_open(carrier_count);
    assert(loop > 0);
    const long listener = linea_net_listen(0x7f000001UL << 16, 128);
    if (listener < 0) {
        fprintf(stderr, "fiber scale: TCP loopback listen failed: %s\n", strerror((int)-listener));
        return EXIT_FAILURE;
    }
    const long address = linea_net_local_address((int)listener);
    assert(address > 0);
    for (unsigned i = 0; i < connection_count; i += 1) {
        struct connection *connection = &connections[i];
        const long client = linea_net_connect((unsigned long)address, linea_park_deadline_after(10000000000UL));
        const long server = client >= 0 ? linea_net_accept((int)listener, linea_park_deadline_after(10000000000UL)) : client;
        if (client < 0 || server < 0) {
            fprintf(stderr, "fiber scale: TCP connection %u/%u failed: %s\n", i + 1,
                    (unsigned)connection_count, strerror((int)-(client < 0 ? client : server)));
            return EXIT_FAILURE;
        }
        connection->client = (int)client;
        connection->server = (int)server;
        connection->request = (unsigned char)(i % 251);
        const long prepared = linea_task_prepare_on(stack_bytes, (unsigned long)loop);
        if (prepared <= 0) {
            fprintf(stderr, "fiber scale: preparing reader %u/%u failed: %s\n", i + 1,
                    (unsigned)connection_count, strerror((int)-prepared));
            return EXIT_FAILURE;
        }
        connection->handle = linea_task_start((unsigned long)prepared, read_connection, release_connection,
                                               (unsigned long)connection, sizeof *connection, (unsigned long)connection);
    }
    assert(linea_net_close((int)listener) == 0);
    unsigned long sentinels[carrier_count];
    for (unsigned i = 0; i < carrier_count; i += 1) {
        const long prepared = linea_task_prepare_on(stack_bytes, (unsigned long)loop);
        assert(prepared > 0);
        sentinels[i] = linea_task_start((unsigned long)prepared, sentinel, release_sentinel, 0, 0, 0);
    }
    await_parked();
    assert(linea_loop_runs((unsigned long)loop) == carrier_count);
    const unsigned parked_threads = process_threads();
    assert(parked_threads == baseline_threads + carrier_count);
    printf("fiber scale: %u TCP readers simultaneously parked on %u carriers; OS threads %u -> %u\n",
           (unsigned)connection_count, identities, baseline_threads, parked_threads);
    for (unsigned i = 0; i < connection_count; i += 1)
        assert(linea_net_write(connections[i].client, (unsigned long)&connections[i].request, 1, 0) == 1);
    for (unsigned i = 0; i < connection_count; i += 1) {
        struct connection *connection = &connections[i];
        unsigned char response = 0;
        const unsigned long deadline = linea_park_deadline_after(30000000000UL);
        assert(linea_net_read(connection->client, (unsigned long)&response, 1, deadline) == 1);
        assert(response == (unsigned char)(connection->request ^ 0x5aU));
        assert(linea_net_read(connection->client, (unsigned long)&response, 1, deadline) == 0);
        assert(linea_net_close(connection->client) == 0);
        linea_chan_close(connection->handle);
        assert(connection->responses == 1 && connection->releases == 1);
    }
    for (unsigned i = 0; i < carrier_count; i += 1) linea_chan_close(sentinels[i]);
    assert(sentinel_releases == carrier_count);
    assert(completed == connection_count);
    assert(process_threads() == baseline_threads + carrier_count);
    /* The loop's process-lifetime carriers can still call the pause hook. */
    (void)alarm(0);
    puts("fiber scale: 10000 TCP responses and task releases occurred exactly once");
    return 0;
}
