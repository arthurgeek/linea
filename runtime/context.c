#include "context.h"

#include <stddef.h>

#if defined(__APPLE__)
#define SYMBOL(name) "_" name
#define START_SYMBOL "Lcontext_start"
#else
#define SYMBOL(name) name
#define START_SYMBOL ".Lcontext_start"
#endif

extern void context_start(void) __asm__(START_SYMBOL)
    __attribute__((visibility("hidden")));

/* Assembly offsets are checked against the C representation, so changing a
 * field cannot silently move a saved register. The switch is a leaf: the
 * caller's frame pointer and return address remain the resumed frame chain. */
#if defined(__aarch64__)
typedef char linea_context_offset_x19_x30[(offsetof(struct linea_context, x19_x30) == 0) ? 1 : -1];
typedef char linea_context_offset_d8_d15[(offsetof(struct linea_context, d8_d15) == 96) ? 1 : -1];
typedef char linea_context_offset_sp[(offsetof(struct linea_context, sp) == 160) ? 1 : -1];
typedef char linea_context_offset_fpcr[(offsetof(struct linea_context, fpcr) == 168) ? 1 : -1];
__asm__(
    ".text\n.p2align 2\n"
    ".globl " SYMBOL("linea_context_switch") "\n"
    SYMBOL("linea_context_switch") ":\n"
    "stp x19, x20, [x0, #0]\n"
    "stp x21, x22, [x0, #16]\n"
    "stp x23, x24, [x0, #32]\n"
    "stp x25, x26, [x0, #48]\n"
    "stp x27, x28, [x0, #64]\n"
    "stp x29, x30, [x0, #80]\n"
    "stp d8, d9, [x0, #96]\n"
    "stp d10, d11, [x0, #112]\n"
    "stp d12, d13, [x0, #128]\n"
    "stp d14, d15, [x0, #144]\n"
    "mov x2, sp\nstr x2, [x0, #160]\n"
    "mrs x2, fpcr\nstr x2, [x0, #168]\n"
    "ldp x19, x20, [x1, #0]\n"
    "ldp x21, x22, [x1, #16]\n"
    "ldp x23, x24, [x1, #32]\n"
    "ldp x25, x26, [x1, #48]\n"
    "ldp x27, x28, [x1, #64]\n"
    "ldp x29, x30, [x1, #80]\n"
    "ldp d8, d9, [x1, #96]\n"
    "ldp d10, d11, [x1, #112]\n"
    "ldp d12, d13, [x1, #128]\n"
    "ldp d14, d15, [x1, #144]\n"
    "ldr x2, [x1, #168]\nmsr fpcr, x2\n"
    "ldr x2, [x1, #160]\nmov sp, x2\nret\n"
    ".p2align 2\n" START_SYMBOL ":\n"
    "mov x0, x20\nblr x19\nbrk #0\n");
#elif defined(__x86_64__)
typedef char linea_context_offset_rbx[(offsetof(struct linea_context, rbx) == 0) ? 1 : -1];
typedef char linea_context_offset_rbp[(offsetof(struct linea_context, rbp) == 8) ? 1 : -1];
typedef char linea_context_offset_r12[(offsetof(struct linea_context, r12) == 16) ? 1 : -1];
typedef char linea_context_offset_r13[(offsetof(struct linea_context, r13) == 24) ? 1 : -1];
typedef char linea_context_offset_r14[(offsetof(struct linea_context, r14) == 32) ? 1 : -1];
typedef char linea_context_offset_r15[(offsetof(struct linea_context, r15) == 40) ? 1 : -1];
typedef char linea_context_offset_rsp[(offsetof(struct linea_context, rsp) == 48) ? 1 : -1];
typedef char linea_context_offset_rip[(offsetof(struct linea_context, rip) == 56) ? 1 : -1];
typedef char linea_context_offset_mxcsr[(offsetof(struct linea_context, mxcsr) == 64) ? 1 : -1];
typedef char linea_context_offset_x87_control[(offsetof(struct linea_context, x87_control) == 68) ? 1 : -1];
__asm__(
    ".text\n.p2align 4\n"
    ".globl " SYMBOL("linea_context_switch") "\n"
    SYMBOL("linea_context_switch") ":\n"
    "movq %rbx, 0(%rdi)\nmovq %rbp, 8(%rdi)\n"
    "movq %r12, 16(%rdi)\nmovq %r13, 24(%rdi)\n"
    "movq %r14, 32(%rdi)\nmovq %r15, 40(%rdi)\n"
    "leaq 8(%rsp), %rax\nmovq %rax, 48(%rdi)\n"
    "movq (%rsp), %rax\nmovq %rax, 56(%rdi)\n"
    "stmxcsr 64(%rdi)\nfnstcw 68(%rdi)\n"
    "movq 0(%rsi), %rbx\nmovq 8(%rsi), %rbp\n"
    "movq 16(%rsi), %r12\nmovq 24(%rsi), %r13\n"
    "movq 32(%rsi), %r14\nmovq 40(%rsi), %r15\n"
    "ldmxcsr 64(%rsi)\nfldcw 68(%rsi)\n"
    "movq 48(%rsi), %rsp\njmp *56(%rsi)\n"
    ".p2align 4\n" START_SYMBOL ":\n"
    "subq $8, %rsp\nmovq %r13, %rdi\ncall *%r12\nud2\n");
#endif

void linea_context_init(struct linea_context *context, void *stack,
                        unsigned long bytes, linea_context_entry entry, void *argument) {
    uintptr_t top = ((uintptr_t)stack + bytes) & ~(uintptr_t)15;
    *context = (struct linea_context){0};
#if defined(__aarch64__)
    context->x19_x30[0] = (uintptr_t)entry;
    context->x19_x30[1] = (uintptr_t)argument;
    context->x19_x30[11] = (uintptr_t)context_start;
    context->sp = top;
    __asm__ volatile("mrs %0, fpcr" : "=r"(context->fpcr));
#elif defined(__x86_64__)
    context->r12 = (uintptr_t)entry;
    context->r13 = (uintptr_t)argument;
    /* A SysV function enters with rsp == 8 modulo 16. A null sentinel also
     * terminates a debugger's walk below the initial entry. */
    context->rsp = top - 8;
    *(uint64_t *)(top - 8) = 0;
    context->rip = (uintptr_t)context_start;
    __asm__ volatile("stmxcsr %0" : "=m"(context->mxcsr));
    __asm__ volatile("fnstcw %0" : "=m"(context->x87_control));
#endif
}
