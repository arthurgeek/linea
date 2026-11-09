#include <stdint.h>

int32_t squares_visit(int32_t count, int32_t (*visit)(void *context, int64_t square), void *context) {
    int32_t visited = 0;
    for (int32_t i = 1; i <= count; i++) {
        visited++;
        if (visit(context, (int64_t)i * i) != 0) break;
    }
    return visited;
}
