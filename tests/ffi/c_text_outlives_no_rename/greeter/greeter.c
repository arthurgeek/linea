#include <stdint.h>
#include <stdlib.h>
#include <string.h>

struct greeter {
    char name[16];
};

struct greeter *greeter_open(void) {
    struct greeter *greeter = calloc(1, sizeof(struct greeter));
    if (greeter != NULL) strcpy(greeter->name, "Ada");
    return greeter;
}

/* The name lives inside the greeter, so it is valid until the greeter changes
 * or closes. */
const char *greeter_name(const struct greeter *greeter) { return greeter->name; }

void greeter_rename(struct greeter *greeter) { strcpy(greeter->name, "Grace"); }

const char *greeter_nothing(const struct greeter *greeter) {
    (void)greeter;
    return NULL;
}

/* Three bytes that are not UTF-8, then a NUL. */
const char *greeter_garbled(const struct greeter *greeter) {
    (void)greeter;
    return "\xff\xfe\xfd";
}

/* Bytes holding a NUL of their own, which only a copy of a known length
 * keeps whole. */
const char *greeter_record(const struct greeter *greeter) {
    (void)greeter;
    return "id\0Ada";
}

void greeter_close(struct greeter *greeter) { free(greeter); }
