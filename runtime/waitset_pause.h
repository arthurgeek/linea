#ifndef LINEA_WAITSET_PAUSE_H
#define LINEA_WAITSET_PAUSE_H

/* The linearization points of the wait set's protocol, and the signal
 * router's handler before it chains to the host's action. A build for the race
 * tests defines `LINEA_WAITSET_PAUSES` and the tests supply
 * `waitset_test_pause`, which stops the thread reaching a point until the
 * test lets it go, so each interleaving is forced rather than hoped for. Any
 * other build compiles every pause away. */
enum linea_pause_point {
    linea_pause_source_before_swap,
    linea_pause_source_after_swap,
    linea_pause_timer_before_swap,
    linea_pause_take_before_swap,
    linea_pause_take_after_swap,
    linea_pause_next_before_wait,
    linea_pause_watch_after_publish,
    linea_pause_send_filled,
    linea_pause_body_finished,
    linea_pause_rehome_before_lock,
    linea_pause_route_before_chain,
    linea_pause_points
};

#if defined(LINEA_WAITSET_PAUSES)
void waitset_test_pause(enum linea_pause_point point);
/* Give a free slot of a set the last generation it may have, so its next
 * release retires it. */
void waitset_test_age(unsigned long set, unsigned long slot);
#define linea_waitset_pause(point) waitset_test_pause(point)
#else
#define linea_waitset_pause(point) ((void)(point))
#endif

#endif
