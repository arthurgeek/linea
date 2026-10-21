#include <stdint.h>

/* Calls `visit` with each square from 1 up to `count` squared, handing back
 * `context` each time, and stops early when `visit` answers nonzero. Answers
 * how many squares it visited. */
int32_t squares_visit(int32_t count, int32_t (*visit)(void *context, int32_t square), void *context) {
    int32_t visited = 0;
    for (int32_t i = 1; i <= count; i++) {
        visited++;
        if (visit(context, i * i) != 0) break;
    }
    return visited;
}
