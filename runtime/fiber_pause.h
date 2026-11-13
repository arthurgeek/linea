#ifndef LINEA_FIBER_PAUSE_H
#define LINEA_FIBER_PAUSE_H

enum linea_fiber_pause_point {
    linea_fiber_before_switch,
    linea_fiber_context_saved,
    linea_fiber_parked,
    linea_fiber_entering,
    linea_fiber_finishing,
};

#if defined(LINEA_FIBER_PAUSES)
void fiber_test_pause(enum linea_fiber_pause_point point);
#define linea_fiber_pause(point) fiber_test_pause(point)
#else
#define linea_fiber_pause(point) ((void)(point))
#endif

#endif
