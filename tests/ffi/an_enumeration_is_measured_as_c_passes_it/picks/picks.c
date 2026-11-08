/* `HUGE` makes `big_t` 64 bits wide, whatever the macro after it says. */
typedef enum { SMALL = 1, HUGE = 0x100000000LL } big_t;

big_t picks_big(big_t wanted) { return wanted == SMALL ? HUGE : SMALL; }

#define big_t unsigned int

/* The enumeration this parameter declares is 64 bits wide, unlike the one
 * of the same name outside it. */
enum inner { ONE = 1 };

unsigned int picks_inner(enum inner { BIG = 0x100000000LL } wanted) { return (unsigned int)(wanted == BIG); }
