#define _GNU_SOURCE
#undef NDEBUG
#include "fiber.h"
#include "foreign.h"
#include "loop.h"
#include "sim.h"
#include "task.h"
#include <assert.h>
#include <stdio.h>

void linea_set_args(int argc, char **argv);
static unsigned ran, released;

static void release_body(unsigned long at, unsigned long len) {
    assert(at == 0 && len == 0);
    released += 1;
}

static void child(unsigned long endpoint, unsigned long at, unsigned long len) {
    assert(at == 0 && len == 0);
    ran += 1;
    linea_chan_close(endpoint);
}

int main(int argc, char **argv) {
    linea_set_args(argc, argv);
    const unsigned long simulation = linea_sim_open(17, 0, 0, 0, 64, 0, 0);
    assert(simulation != 0);
    const unsigned long outer = linea_io_switch(simulation);
    const unsigned long before = linea_sim_now();
    const long prepared = linea_task_prepare_on(2097152, simulation);
    assert(prepared > 0);
    const unsigned long handle = linea_task_start((unsigned long)prepared, child, release_body, 0, 0, 0);
    linea_foreign_enter();
    assert(linea_sim_sleep(100) == 0);
    assert(linea_sim_now() == before + 100);
    assert(ran == 0);
    linea_foreign_leave();
    linea_chan_close(handle);
    assert(ran == 1 && released == 1);
    (void)linea_io_switch(outer);
    linea_sim_close(simulation);
    puts("native simulation: a live foreign frame holds its carrier");
    return 0;
}
