#include <stdint.h>

/* `HUGE` needs 64 bits, so the compiler makes `enum big` a 64-bit integer. */
enum big { SMALL = 1, HUGE = 0x100000000LL };

enum big levels_pick(enum big wanted) { return wanted == SMALL ? HUGE : SMALL; }

/* A fixed underlying type makes `enum level` one byte wide. */
enum level : unsigned char { LOW = 1, HIGH = 200 };

enum level levels_raise(enum level level) { return (enum level)(level + 1); }
