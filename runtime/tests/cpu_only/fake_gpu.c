/* Positive device acquisition without a loader or hardware. This provider is
 * confined to mixed-configuration tests; every other operation is unavailable. */
#define linea_gpu_open linea_test_unused_gpu_open
#define linea_gpu_close linea_test_unused_gpu_close
#include "../../gpu_unavailable.c"
#undef linea_gpu_open
#undef linea_gpu_close
#include <stdlib.h>
#include <stdio.h>

long linea_gpu_open(void) { puts("fake GPU acquisition entered"); return 42; }
void linea_gpu_close(unsigned long device) { if (device != 42) abort(); }
