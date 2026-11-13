#define _GNU_SOURCE
#undef NDEBUG
#include "fiber.h"
#include "loop.h"
#include "sim.h"
#include "park.h"
#include "net.h"
#include "task.h"
#include <assert.h>
#include <pthread.h>
#include <stdio.h>
#include <signal.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>
#include "waitset.h"
void linea_set_args(int argc, char **argv);
void linea_thread_guard_bounds(unsigned long *low, unsigned long *high);
static struct linea_park done;
static int completed;
static pthread_t owner;
static unsigned long start_time;
static unsigned long order[64], order_count;
static unsigned long address;
static void entry(void *unused) {
    unsigned long id = (unsigned long)unused;
    assert(pthread_equal(owner, pthread_self()));
    assert(linea_sim_now() == start_time);
    order[order_count++] = id;
    linea_fiber_yield();
    assert(linea_sim_now() == start_time);
    assert(linea_sim_sleep(100 + id) == 0);
}
static void ended(void *unused) {
    (void)unused;
    linea_park_lock(&done);
    completed += 1;
    linea_unpark(&done);
    linea_park_unlock(&done);
}
static unsigned long run(unsigned long seed) {
    unsigned long sim = linea_sim_open(seed, 0, 0, 0, 64, 0, 0);
    assert(sim != 0);
    unsigned long previous = linea_io_switch(sim);
    unsigned long before = linea_sim_now();
    start_time = before;
    order_count = 0;
    int error = 0;
    struct linea_fiber *fibers[64];
    completed = 0;
    for (unsigned long i = 0; i < 64; i += 1) {
        fibers[i] = linea_fiber_create(sim, 262144, entry, ended, (void *)i, &error);
        assert(fibers[i] != NULL && error == 0);
        linea_fiber_start(fibers[i]);
    }
    assert(linea_sim_now() == before);
    /* A run can end with children suspended, and resume on its carrier. */
    assert(linea_io_switch(previous) == sim);
    assert(linea_io_switch(sim) == previous);
    linea_park_lock(&done);
    while (completed != 64) linea_park(&done, 0);
    linea_park_unlock(&done);
    assert(order_count == 64);
    assert(linea_sim_now() == before + 163);
    for (unsigned long i = 0; i < 64; i += 1) linea_fiber_destroy(fibers[i]);
    unsigned long trace = linea_sim_fingerprint(sim);
    assert(linea_io_switch(previous) == sim);
    linea_sim_close(sim);
    return trace;
}
static void client(void *unused) {
    (void)unused;
    long fd = linea_net_connect(address, 0);
    assert(fd >= 0);
    unsigned char byte = 91;
    assert(linea_net_write((int)fd, (unsigned long)&byte, 1, 0) == 1);
    assert(linea_net_close((int)fd) == 0);
}
static void network_progress(void) {
    unsigned long sim = linea_sim_open(9, 100, 0, 1, 4, 0, 0);
    unsigned long previous = linea_io_switch(sim);
    long listener = linea_net_listen(0x7f0000010000UL, 8);
    assert(listener >= 0);
    address = (unsigned long)linea_net_local_address((int)listener);
    int error;
    struct linea_fiber *f = linea_fiber_create(sim, 262144, client, ended, NULL, &error);
    assert(f != NULL && error == 0);
    completed = 0;
    linea_fiber_start(f);
    long server = linea_net_accept((int)listener, 0);
    assert(server >= 0);
    unsigned char byte = 0;
    assert(linea_net_read((int)server, (unsigned long)&byte, 1, 0) == 1 && byte == 91);
    assert(linea_net_close((int)server) == 0);
    assert(linea_net_close((int)listener) == 0);
    linea_park_lock(&done);
    while (!completed) linea_park(&done, 0);
    linea_park_unlock(&done);
    linea_fiber_destroy(f);
    linea_io_switch(previous);
    linea_sim_close(sim);
}
static void release_nested(unsigned long at, unsigned long len) {
    assert(at == 0 && len == 0);
}
static unsigned long nested_outer;
static int nested_done;
static void nested_leaf(unsigned long endpoint, unsigned long at, unsigned long len) {
    (void)at; (void)len;
    assert(linea_io_is_simulated(linea_io_current()));
    assert(linea_io_current() != nested_outer);
    assert(pthread_equal(owner, pthread_self()));
    assert(linea_sim_sleep(77) == 0);
    unsigned long answer = 77;
    linea_chan_send(endpoint, (unsigned long)&answer, sizeof answer);
    linea_chan_close(endpoint);
}
static void nested_child(unsigned long endpoint, unsigned long at, unsigned long len) {
    (void)at; (void)len;
    assert(linea_io_current() == nested_outer);
    unsigned long outer_time = linea_sim_now();
    unsigned long guard_low, guard_high;
    linea_thread_guard_bounds(&guard_low, &guard_high);
    assert(guard_low != 0 && guard_high > guard_low);
    unsigned long inner = linea_sim_open(53, 0, 0, 0, 64, 0, 0);
    assert(linea_io_switch(inner) == nested_outer);
    unsigned long inner_time = linea_sim_now();
    long prepared = linea_task_prepare_on(262144, linea_io_current());
    assert(prepared > 0);
    unsigned long handle = linea_task_start((unsigned long)prepared, nested_leaf, release_nested, 0, 0, 0);
    unsigned long answer = 0;
    linea_chan_recv(handle, (unsigned long)&answer, sizeof answer);
    linea_chan_close(handle);
    assert(answer == 77 && linea_sim_now() == inner_time + 77);
    unsigned long restored_low, restored_high;
    linea_thread_guard_bounds(&restored_low, &restored_high);
    assert(restored_low == guard_low && restored_high == guard_high);
    assert(linea_io_switch(nested_outer) == inner);
    assert(linea_io_current() == nested_outer);
    assert(linea_sim_now() == outer_time);
    linea_thread_guard_bounds(&restored_low, &restored_high);
    assert(restored_low == guard_low && restored_high == guard_high);
    linea_sim_close(inner);
    linea_fiber_yield();
    assert(linea_io_current() == nested_outer);
    linea_chan_send(endpoint, (unsigned long)&answer, sizeof answer);
    linea_chan_close(endpoint);
}
static void nested_runs(void) {
    nested_outer = linea_sim_open(51, 0, 0, 0, 64, 0, 0);
    unsigned long inner = linea_sim_open(52, 0, 0, 0, 64, 0, 0);
    assert(linea_io_switch(nested_outer) == 0);
    assert(linea_io_switch(inner) == nested_outer);
    assert(linea_io_switch(nested_outer) == inner);
    long prepared = linea_task_prepare_on(262144, linea_io_current());
    assert(prepared > 0);
    unsigned long handle = linea_task_start((unsigned long)prepared, nested_child, release_nested, 0, 0, 0);
    unsigned long answer = 0;
    linea_chan_recv(handle, (unsigned long)&answer, sizeof answer);
    linea_chan_close(handle);
    assert(answer == 77);
    assert(linea_io_switch(0) == nested_outer);
    assert(!linea_fiber_active());
    linea_sim_close(inner);
    linea_sim_close(nested_outer);
    /* A new root run must not inherit the retired outer carrier. */
    assert(run(54) != 0);
    nested_done += 1;
}
static void outside_child(unsigned long endpoint, unsigned long at, unsigned long len) {
    (void)at; (void)len;
    linea_chan_close(endpoint);
}

static void outside_sender(unsigned long endpoint, unsigned long at, unsigned long len) {
    (void)at; (void)len;
    const unsigned long word = 7;
    linea_chan_send(endpoint, (unsigned long)&word, sizeof word);
    linea_chan_close(endpoint);
}

static void rejects_real_task_registration(int returned) {
    int descriptors[2];
    assert(pipe(descriptors) == 0);
    const pid_t child = fork();
    assert(child >= 0);
    if (child == 0) {
        close(descriptors[0]);
        assert(dup2(descriptors[1], STDERR_FILENO) >= 0);
        close(descriptors[1]);
        const long prepared = linea_task_prepare_on(262144, 0);
        assert(prepared > 0);
        const unsigned long handle = linea_task_start((unsigned long)prepared, returned ? outside_child : outside_sender, release_nested, 0, 0, 0);
        const unsigned long simulation = linea_sim_open(71, 0, 0, 0, 64, 0, 0);
        assert(simulation != 0);
        (void)linea_io_switch(simulation);
        const unsigned long set = linea_waitset_open();
        const unsigned long slot = linea_waitset_reserve(set) >> 32;
        if (returned) linea_waitset_returned(set, slot, handle);
        else linea_waitset_received(set, slot, handle);
        _exit(0);
    }
    close(descriptors[1]);
    char report[256] = {0};
    const ssize_t count = read(descriptors[0], report, sizeof report - 1);
    close(descriptors[0]);
    int status;
    assert(waitpid(child, &status, 0) == child);
    assert(WIFSIGNALED(status) && WTERMSIG(status) == SIGABRT);
    assert(count > 0 && (strstr)(report, "a session crosses a simulation's boundary") != NULL);
}

int main(void) {
    linea_set_args(0, NULL);
    owner = pthread_self();
    rejects_real_task_registration(0);
    rejects_real_task_registration(1);
    assert(linea_park_init(&done) == 0);
    unsigned long first = run(17);
    unsigned long first_order[64];
    for (unsigned long i = 0; i < 64; i += 1) first_order[i] = order[i];
    assert(first == run(17));
    for (unsigned long i = 0; i < 64; i += 1) assert(first_order[i] == order[i]);
    assert(first != run(18));
    network_progress();
    nested_runs();
    assert(nested_done == 1);
    linea_park_destroy(&done);
    puts("simulated fiber clock and session park passed");
}
