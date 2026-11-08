#include <stdint.h>

int64_t tally_add_v2(int64_t total, int64_t amount);

/* C code calling `tally_add` calls `tally_add_v2`. */
#define tally_add tally_add_v2
