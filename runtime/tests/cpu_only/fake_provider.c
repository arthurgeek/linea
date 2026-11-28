#include "../../gpu.h"
#include <assert.h>
int main(void) {
    long device = linea_gpu_open();
    assert(device == 42);
    linea_gpu_close((unsigned long)device);
    return 0;
}
