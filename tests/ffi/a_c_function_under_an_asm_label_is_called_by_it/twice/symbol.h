/* The symbol a label names, as the platform spells a C symbol. */
#ifdef __APPLE__
#define LINEA_SYMBOL(name) __asm__("_" name)
#else
#define LINEA_SYMBOL(name) __asm__(name)
#endif
