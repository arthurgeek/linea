#include <stdint.h>
#include <stdlib.h>

extern unsigned long linea_foreign_depth(void);

uint64_t boundary_depth(void) { return linea_foreign_depth(); }

uint8_t boundary_run(uint8_t (*visit)(void *), void *context) {
    if (linea_foreign_depth() != 1) abort();
    uint8_t first = visit(context);
    if (linea_foreign_depth() != 1) abort();
    uint8_t second = visit(context);
    if (linea_foreign_depth() != 1) abort();
    return first == 37 && second == 37 ? 37 : 1;
}
