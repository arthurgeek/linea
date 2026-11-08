enum colour { RED, GREEN, BLUE };

/* Every value of `enum colour` fits an `unsigned int`, which is how C passes it. */
enum colour colours_next(enum colour colour) { return (enum colour)((colour + 1) % 3); }

typedef enum { SMALL = -1, LARGE = 1 } size_hint;

size_hint colours_flip(size_hint hint) { return hint == SMALL ? LARGE : SMALL; }
