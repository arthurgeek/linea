#include "symbol.h"

/* C code calling these reaches the runtime's own `linea_close`, and a
 * symbol of the program's own Linea functions. */
long long labels_close(long long descriptor) LINEA_SYMBOL("linea_close");

long long labels_main(long long value) LINEA_SYMBOL("lin.main");
