/* Compile with -DLINEA_CONTEXT_REFERENCE for the ucontext oracle. Both
 * backends execute identical recursion, register and floating-control cases. */
#define _XOPEN_SOURCE 700
#define _DARWIN_C_SOURCE
#include <assert.h>
#include <fenv.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#if defined(LINEA_CONTEXT_REFERENCE)
#include <ucontext.h>
struct test_context {
    ucontext_t saved;
    fenv_t floating;
    void (*entry)(void *);
    void *argument;
};
static struct test_context *entering;
static void reference_entry(void) {
    assert(fesetenv(&entering->floating) == 0);
    void (*entry)(void *) = entering->entry;
    void *argument = entering->argument;
    entry(argument);
    abort();
}
static void context_init(struct test_context *context, void *stack,
                         unsigned long bytes, void (*entry)(void *), void *argument) {
    assert(getcontext(&context->saved) == 0);
    assert(fegetenv(&context->floating) == 0);
    context->saved.uc_stack.ss_sp = stack;
    context->saved.uc_stack.ss_size = bytes;
    context->saved.uc_stack.ss_flags = 0;
    context->saved.uc_link = NULL;
    context->entry = entry;
    context->argument = argument;
    makecontext(&context->saved, reference_entry, 0);
}
__attribute__((noinline, used))
static void context_switch(struct test_context *from, struct test_context *to) {
    /* Darwin ucontext omits FPCR. Give the reference the same floating
     * environment contract as the candidate, using the C fenv operations. */
    assert(fegetenv(&from->floating) == 0);
    entering = to;
    assert(swapcontext(&from->saved, &to->saved) == 0);
    assert(fesetenv(&from->floating) == 0);
}
#else
#include "context.h"
#define test_context linea_context
#define context_init linea_context_init
#define context_switch linea_context_switch
#endif

#if defined(__aarch64__)
#define FP_REGISTER "+w"
#else
#define FP_REGISTER "+x"
#endif

typedef double vector2 __attribute__((vector_size(16)));
enum { rounds = 80, depth = 40, stack_bytes = 256 * 1024 };
static struct test_context caller, fibers[2];
static unsigned progress[2], finished[2];
static uint64_t controls[2];
static int modes[2] = { FE_DOWNWARD, FE_UPWARD };

static uint64_t floating_control(void) {
#if defined(__aarch64__)
    uint64_t control;
    __asm__ volatile("mrs %0, fpcr" : "=r"(control));
    return control;
#else
    uint32_t sse;
    uint16_t x87;
    __asm__ volatile("stmxcsr %0" : "=m"(sse));
    __asm__ volatile("fnstcw %0" : "=m"(x87));
    /* Exception status flags are caller-saved; only control is required. */
    return (uint64_t)(sse & ~UINT32_C(63)) | ((uint64_t)x87 << 32);
#endif
}

/* The assembly harness holds every ABI-preserved register across the actual
 * call, even at O0 where C locals would otherwise be spilled. It restores its
 * own caller's registers before returning a behavioral pass/fail result. */
#if defined(__APPLE__)
#define TEST_SYMBOL(name) "_" name
#else
#define TEST_SYMBOL(name) name
#endif
#if defined(LINEA_CONTEXT_REFERENCE)
#define SWITCH_SYMBOL TEST_SYMBOL("context_switch")
#else
#define SWITCH_SYMBOL TEST_SYMBOL("linea_context_switch")
#endif
extern int abi_exchange(struct test_context *, struct test_context *, uintptr_t);
#if defined(__aarch64__)
__asm__(
    ".text\n.p2align 2\n.globl " TEST_SYMBOL("abi_exchange") "\n"
    TEST_SYMBOL("abi_exchange") ":\n"
    "sub sp, sp, #176\n"
    "stp x29, x30, [sp, #0]\n"
    "mov x29, sp\n"
    "stp x19, x20, [sp, #16]\n"
    "stp x21, x22, [sp, #32]\n"
    "stp x23, x24, [sp, #48]\n"
    "stp x25, x26, [sp, #64]\n"
    "stp x27, x28, [sp, #80]\n"
    "stp d8, d9, [sp, #96]\n"
    "stp d10, d11, [sp, #112]\n"
    "stp d12, d13, [sp, #128]\n"
    "stp d14, d15, [sp, #144]\n"
    "str x2, [sp, #160]\n"
    "add x19, x2, #19\n"
    "add x20, x2, #20\n"
    "add x21, x2, #21\n"
    "add x22, x2, #22\n"
    "add x23, x2, #23\n"
    "add x24, x2, #24\n"
    "add x25, x2, #25\n"
    "add x26, x2, #26\n"
    "add x27, x2, #27\n"
    "add x28, x2, #28\n"
    "add x3, x2, #8\n"
    "fmov d8, x3\n"
    "add x3, x2, #9\n"
    "fmov d9, x3\n"
    "add x3, x2, #10\n"
    "fmov d10, x3\n"
    "add x3, x2, #11\n"
    "fmov d11, x3\n"
    "add x3, x2, #12\n"
    "fmov d12, x3\n"
    "add x3, x2, #13\n"
    "fmov d13, x3\n"
    "add x3, x2, #14\n"
    "fmov d14, x3\n"
    "add x3, x2, #15\n"
    "fmov d15, x3\n"
    "bl " SWITCH_SYMBOL "\n"
    "ldr x2, [sp, #160]\n"
    "mov x3, sp\n"
    "cmp x29, x3\n"
    "b.ne 1f\n"
    "add x3, x2, #19\n"
    "cmp x19, x3\n"
    "b.ne 1f\n"
    "add x3, x2, #20\n"
    "cmp x20, x3\n"
    "b.ne 1f\n"
    "add x3, x2, #21\n"
    "cmp x21, x3\n"
    "b.ne 1f\n"
    "add x3, x2, #22\n"
    "cmp x22, x3\n"
    "b.ne 1f\n"
    "add x3, x2, #23\n"
    "cmp x23, x3\n"
    "b.ne 1f\n"
    "add x3, x2, #24\n"
    "cmp x24, x3\n"
    "b.ne 1f\n"
    "add x3, x2, #25\n"
    "cmp x25, x3\n"
    "b.ne 1f\n"
    "add x3, x2, #26\n"
    "cmp x26, x3\n"
    "b.ne 1f\n"
    "add x3, x2, #27\n"
    "cmp x27, x3\n"
    "b.ne 1f\n"
    "add x3, x2, #28\n"
    "cmp x28, x3\n"
    "b.ne 1f\n"
    "add x3, x2, #8\n"
    "fmov x4, d8\n"
    "cmp x4, x3\n"
    "b.ne 1f\n"
    "add x3, x2, #9\n"
    "fmov x4, d9\n"
    "cmp x4, x3\n"
    "b.ne 1f\n"
    "add x3, x2, #10\n"
    "fmov x4, d10\n"
    "cmp x4, x3\n"
    "b.ne 1f\n"
    "add x3, x2, #11\n"
    "fmov x4, d11\n"
    "cmp x4, x3\n"
    "b.ne 1f\n"
    "add x3, x2, #12\n"
    "fmov x4, d12\n"
    "cmp x4, x3\n"
    "b.ne 1f\n"
    "add x3, x2, #13\n"
    "fmov x4, d13\n"
    "cmp x4, x3\n"
    "b.ne 1f\n"
    "add x3, x2, #14\n"
    "fmov x4, d14\n"
    "cmp x4, x3\n"
    "b.ne 1f\n"
    "add x3, x2, #15\n"
    "fmov x4, d15\n"
    "cmp x4, x3\n"
    "b.ne 1f\n"
    "mov w0, #1\n"
    "b 2f\n"
    "1: mov w0, #0\n"
    "2:\n"
    "ldp d8, d9, [sp, #96]\n"
    "ldp d10, d11, [sp, #112]\n"
    "ldp d12, d13, [sp, #128]\n"
    "ldp d14, d15, [sp, #144]\n"
    "ldp x19, x20, [sp, #16]\n"
    "ldp x21, x22, [sp, #32]\n"
    "ldp x23, x24, [sp, #48]\n"
    "ldp x25, x26, [sp, #64]\n"
    "ldp x27, x28, [sp, #80]\n"
    "ldp x29, x30, [sp, #0]\n"
    "add sp, sp, #176\n"
    "ret\n"
);
#else
__asm__(
    ".text\n.p2align 4\n.globl " TEST_SYMBOL("abi_exchange") "\n"
    TEST_SYMBOL("abi_exchange") ":\n"
    "pushq %rbp\n"
    "movq %rsp, %rbp\n"
    "pushq %rbx\n"
    "pushq %r12\n"
    "pushq %r13\n"
    "pushq %r14\n"
    "pushq %r15\n"
    "subq $24, %rsp\n"
    "movq %rdx, 16(%rsp)\n"
    "leaq 19(%rdx), %rbx\n"
    "leaq 20(%rdx), %r12\n"
    "leaq 21(%rdx), %r13\n"
    "leaq 22(%rdx), %r14\n"
    "leaq 23(%rdx), %r15\n"
    "call " SWITCH_SYMBOL "\n"
    "movq 16(%rsp), %rdx\n"
    "leaq 64(%rsp), %rcx\n"
    "cmpq %rcx, %rbp\n"
    "jne 1f\n"
    "leaq 19(%rdx), %rcx\n"
    "cmpq %rcx, %rbx\n"
    "jne 1f\n"
    "leaq 20(%rdx), %rcx\n"
    "cmpq %rcx, %r12\n"
    "jne 1f\n"
    "leaq 21(%rdx), %rcx\n"
    "cmpq %rcx, %r13\n"
    "jne 1f\n"
    "leaq 22(%rdx), %rcx\n"
    "cmpq %rcx, %r14\n"
    "jne 1f\n"
    "leaq 23(%rdx), %rcx\n"
    "cmpq %rcx, %r15\n"
    "jne 1f\n"
    "movl $1, %eax\n"
    "jmp 2f\n"
    "1: xorl %eax, %eax\n"
    "2: addq $24, %rsp\n"
    "popq %r15\n"
    "popq %r14\n"
    "popq %r13\n"
    "popq %r12\n"
    "popq %rbx\n"
    "popq %rbp\n"
    "ret\n"
);
#endif

__attribute__((noinline)) static void exchange(unsigned id, unsigned turn) {
    double scalar = 1024.125 + id + turn;
    vector2 vector = { 32.25 + id, 64.5 + turn };
    __asm__ volatile("" : FP_REGISTER(vector), FP_REGISTER(scalar));
    assert(abi_exchange(&fibers[id], &caller, 0x1000 * (id + 1) + turn) == 1);
    __asm__ volatile("" : FP_REGISTER(vector), FP_REGISTER(scalar));
    assert(scalar == 1024.125 + id + turn);
    assert(vector[0] == 32.25 + id && vector[1] == 64.5 + turn);
}

/* A broken stack/frame-pointer restore corrupts the pending frames and their
 * independent local storage on return from the leaf. */
__attribute__((noinline)) static void recurse(unsigned id, unsigned level, void *parent) {
    void *frame = __builtin_frame_address(0);
    if (parent != NULL) {
        void *previous;
        memcpy(&previous, frame, sizeof(previous));
        assert(previous == parent);
    }
    volatile uint64_t canary[16];
    for (unsigned i = 0; i < 16; ++i)
        canary[i] = UINT64_C(0x123456789abcdef0) + level * 16 + i + id;
    if (level != 0) {
        recurse(id, level - 1, frame);
    } else {
        for (unsigned turn = 0; turn < rounds; ++turn) {
            assert(fegetround() == modes[id]);
            assert(floating_control() == controls[id]);
            progress[id] = turn + 1;
            exchange(id, turn);
            assert(fegetround() == modes[id]);
            assert(floating_control() == controls[id]);
        }
    }
    for (unsigned i = 0; i < 16; ++i)
        assert(canary[i] == UINT64_C(0x123456789abcdef0) + level * 16 + i + id);
}

static void run_fiber(void *argument) {
    unsigned id = *(unsigned *)argument;
    assert(id < 2);
    assert(fesetround(modes[id]) == 0);
#if defined(__x86_64__)
    /* Independently chosen SSE and x87 rounding detects restoring only one. */
    uint32_t sse;
    __asm__ volatile("stmxcsr %0" : "=m"(sse));
    sse = (sse & ~UINT32_C(0x6000)) | (id == 0 ? 0x4000 : 0x2000);
    __asm__ volatile("ldmxcsr %0" : : "m"(sse));
#endif
    controls[id] = floating_control();
    recurse(id, depth, NULL);
    finished[id] = 1;
    context_switch(&fibers[id], &caller);
    abort();
}

int main(void) {
    unsigned ids[2] = { 0, 1 };
    unsigned char *stacks[2];
    int original = fegetround();
    for (unsigned id = 0; id < 2; ++id) {
        stacks[id] = malloc(stack_bytes + 31);
        assert(stacks[id] != NULL);
        /* Init must align even a deliberately unaligned supplied range. */
        context_init(&fibers[id], stacks[id] + 1, stack_bytes + 7, run_fiber, &ids[id]);
    }
    assert(fesetround(FE_TOWARDZERO) == 0);
    uint64_t caller_control = floating_control();
    for (unsigned turn = 0; turn <= rounds; ++turn) {
        for (unsigned id = 0; id < 2; ++id) {
            context_switch(&caller, &fibers[id]);
            assert(fegetround() == FE_TOWARDZERO);
            assert(floating_control() == caller_control);
            assert(progress[id] == (turn < rounds ? turn + 1 : rounds));
            assert(finished[id] == (turn == rounds));
        }
    }
    assert(fesetround(original) == 0);
    free(stacks[0]);
    free(stacks[1]);
    puts("context: recursion, live registers/vectors and floating control passed");
    return 0;
}
