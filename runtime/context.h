#ifndef LINEA_CONTEXT_H
#define LINEA_CONTEXT_H

#include <stdint.h>

/* Private register image for a cooperative call boundary. The scheduler owns
 * sanitizer notifications; this raw switch never invokes sanitizer hooks. */
struct linea_context {
#if defined(__aarch64__)
    uint64_t x19_x30[12];
    uint64_t d8_d15[8];
    uint64_t sp;
    uint64_t fpcr;
#elif defined(__x86_64__)
    uint64_t rbx, rbp, r12, r13, r14, r15;
    uint64_t rsp, rip;
    uint32_t mxcsr;
    uint16_t x87_control;
    uint16_t reserved;
#else
#error "linea contexts require aarch64 or x86_64"
#endif
};

typedef void (*linea_context_entry)(void *argument);

/* The supplied stack remains owned by the caller. bytes must provide enough
 * space for the entry's frames after rounding the stack top down to 16 bytes.
 * entry(argument) must never return. Initial floating control is inherited
 * from the calling thread. Contexts stay pinned to that thread. */
void linea_context_init(struct linea_context *context, void *stack,
                        unsigned long bytes, linea_context_entry entry, void *argument);
void linea_context_switch(struct linea_context *from, struct linea_context *to);

#endif
