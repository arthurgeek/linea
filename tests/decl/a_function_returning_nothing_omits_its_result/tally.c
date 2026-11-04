#include <stdint.h>

/* The last count the program noted. */
static int32_t noted;

void tally_note(int32_t count) { noted = count; }
