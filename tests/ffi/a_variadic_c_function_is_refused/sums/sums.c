#include <stdarg.h>
#include <stdint.h>

int32_t sums_add(int32_t count, ...) {
    va_list arguments;
    va_start(arguments, count);
    int32_t total = 0;
    for (int32_t i = 0; i < count; i++) total += va_arg(arguments, int32_t);
    va_end(arguments);
    return total;
}
