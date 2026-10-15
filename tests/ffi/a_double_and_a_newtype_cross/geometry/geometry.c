#include <math.h>
#include <stdint.h>

double geometry_scale(double length, int32_t times) { return length * times; }

double geometry_not_a_number(void) { return NAN; }

uint64_t geometry_next_id(uint64_t id) { return id + 1; }
