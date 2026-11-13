#define _GNU_SOURCE
#undef NDEBUG
#include "loop.h"
#include "sim.h"
#include "task.h"
#include "waitset.h"
#include <assert.h>
#include <stdio.h>

void linea_set_args(int argc, char **argv);
static unsigned released;

static void release_body(unsigned long at, unsigned long len) {
    assert(at == 0 && len == 0);
    released += 1;
}

static void answer(unsigned long endpoint, unsigned long at, unsigned long len) {
    assert(at == 0 && len == 0);
    const unsigned long word = 42;
    linea_chan_send(endpoint, (unsigned long)&word, sizeof word);
    linea_chan_close(endpoint);
}

static void parent(unsigned long endpoint, unsigned long at, unsigned long len) {
    assert(at == 0 && len == 0);
    const long prepared = linea_task_prepare_on(2097152, linea_io_current());
    assert(prepared > 0);
    const unsigned long handle = linea_task_start((unsigned long)prepared, answer, release_body, 0, 0, 0);
    const unsigned long set = linea_waitset_open();
    assert(set != 0);
    const unsigned long received = linea_waitset_reserve(set);
    linea_waitset_received(set, received >> 32, handle);
    const unsigned long timer = linea_waitset_reserve(set);
    linea_waitset_timer(set, timer >> 32, 100);
    assert(linea_waitset_next(set) == (long)(received >> 32));
    assert(linea_waitset_take(set, timer >> 32, (uint32_t)timer, 1) == 1);
    linea_waitset_close(set);
    unsigned long word = 0;
    linea_chan_recv(handle, (unsigned long)&word, sizeof word);
    assert(word == 42);
    linea_chan_close(handle);
    linea_chan_close(endpoint);
}

int main(int argc, char **argv) {
    linea_set_args(argc, argv);
    const unsigned long sim = linea_sim_open(42, 0, 0, 0, 64, 0, 0);
    assert(sim != 0);
    const unsigned long outer = linea_io_switch(sim);
    const unsigned long before = linea_sim_now();
    const long prepared = linea_task_prepare_on(2097152, sim);
    assert(prepared > 0);
    const unsigned long handle = linea_task_start((unsigned long)prepared, parent, release_body, 0, 0, 0);
    const unsigned long set = linea_waitset_open();
    assert(set != 0);
    const unsigned long returned = linea_waitset_reserve(set);
    linea_waitset_returned(set, returned >> 32, handle);
    const unsigned long timer = linea_waitset_reserve(set);
    linea_waitset_timer(set, timer >> 32, 50);
    assert(linea_waitset_next(set) == (long)(returned >> 32));
    assert(linea_waitset_take(set, timer >> 32, (uint32_t)timer, 1) == 1);
    linea_waitset_close(set);
    linea_chan_close(handle);
    assert(linea_sim_now() == before && released == 2);
    (void)linea_io_switch(outer);
    linea_sim_close(sim);
    puts("native simulated wait sets: root and child sources progress before virtual timers");
    return 0;
}
