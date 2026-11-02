/* What a generated Linea program links against.
 *
 * Code generation emits calls to one symbol and knows nothing else about the
 * environment, so a target that cannot use this implementation supplies its own
 * and the backend does not change.
 *
 * A failure aborts rather than returning a status, so it cannot be confused
 * with any value `main` is able to return. */

#define _GNU_SOURCE
#define _DARWIN_C_SOURCE
#include <errno.h>
#include <pthread.h>
#include <signal.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>

#include "pipe_signal.h"

/* A sanitizer installs a fault handler of its own, which reports a stack
 * overflow and a wild access with more than this one can say, so a
 * sanitized runtime, which the build compiles with `LINEA_SANITIZED`
 * defined, leaves the faults to it. */

/* The interface between generated code and this file, versioned so the two
 * cannot silently disagree.
 *
 * Generated code references the symbol below, so a compiler built against one
 * version and a runtime built against another fail to LINK rather than
 * misreading each other's arguments. The number stays 1 until the runtime ships
 * separately from the compiler; before then both are built from one tree and
 * cannot disagree. */
#define LINEA_RUNTIME_ABI 1

#ifndef LINEA_CHECK_STORAGE
#define LINEA_CHECK_STORAGE 0
#endif

/* Defined only so a generated object can refer to it. Never called.
 *
 * Named from the number above rather than beside it, so bumping that one
 * number is what renames the symbol. Spelled out, the two were a version
 * nothing read and a symbol nothing derived: the macro had no header to export
 * it and no use in this file, so following the instruction to bump it changed
 * nothing at all and the link kept succeeding. */
#define LINEA_ABI_SYMBOL_(n) linea_runtime_abi_##n
#define LINEA_ABI_SYMBOL(n) LINEA_ABI_SYMBOL_(n)
void LINEA_ABI_SYMBOL(LINEA_RUNTIME_ABI)(void);
void LINEA_ABI_SYMBOL(LINEA_RUNTIME_ABI)(void) {}

/* Kept in the order the compiler's trap kinds are numbered. The two sides agree
 * on a small integer rather than a string so the interface stays one call. */
static const char *const what[] = {
    "integer overflow",
    "division by zero",
    "value out of range for its type",
    "reached unreachable code",
    "assertion failed",
    "panic",
    "index out of bounds",
    "misaligned access",
    "not a number",
};

/* Writes a runtime failure and aborts. Written through `report_bytes` rather
 * than stdio, so the fault handler can report through it too: the whole path
 * is `strlen`, what `report_bytes` calls, and `abort`, all
 * async-signal-safe. */
static void fail(const char *message) {
    report_bytes(message, strlen(message));
    abort();
}

/* Where a thread's stack guard pages lie: an access in `[guard_low,
 * guard_high)` is an overflow. Every thread that runs Linea code keeps one at
 * the low end of the alternate signal stack it installs, and finds it through
 * `thread_record_key`.
 *
 * The fault handler runs on every thread, host threads that never ran Linea
 * code included, so it cannot read a `__thread` variable: macOS allocates a
 * thread's thread-local block with `malloc` on its first access, which a
 * signal handler must not call. `pthread_getspecific` reads a slot every
 * thread has from its start on Linux and macOS, allocates nothing, and
 * answers null on a thread that never set it. */
struct thread_record {
    unsigned long guard_low;
    unsigned long guard_high;
};

/* Bytes the record takes from the bottom of an alternate signal stack, a
 * multiple of the 16 bytes a stack is aligned to. */
enum { thread_record_bytes = 32 };
typedef char linea_thread_record_fits[(sizeof(struct thread_record) <= thread_record_bytes) ? 1 : -1];

static pthread_key_t thread_record_key;
static pthread_once_t thread_record_once = PTHREAD_ONCE_INIT;

static void create_thread_record_key(void) {
    if (pthread_key_create(&thread_record_key, 0) != 0) fail("linea: the runtime cannot create its thread record key\n");
}

#if !defined(LINEA_SANITIZED)
/* What a fault in a stack's guard pages reports, on any thread. */
static const char *const overflow_report = "linea: a stack overflowed\n";

#if LINEA_CHECK_STORAGE
static void storage_fault(unsigned long address);
#endif

/* The SIGSEGV and SIGBUS actions in place when the runtime installed its
 * handler. A process that calls exported Linea functions may have installed
 * its own, and a fault that is not Linea's is handed to it. */
static struct sigaction previous_segv;
static struct sigaction previous_bus;

/* Set once a previous action installed with `SA_RESETHAND` has run: the
 * system would have reset it to the default action on that delivery. */
static int previous_segv_spent = 0;
static int previous_bus_spent = 0;

#if defined(__APPLE__)
/* The faults on macOS a previous handler is handed, recorded so an
 * unrepaired fault repeating without end can be told apart.
 *
 * macOS does not report `SA_RESETHAND` through `sigaction`, so the runtime
 * cannot tell that a previous handler asked to run once. A handler that
 * returns without repairing the access would then run for every repetition
 * of the fault, without end, where the system would have taken the default
 * action on the second. So a fault is taken as unrepaired once the same
 * thread has faulted `unrepaired_repeats` times in a row on the same signal
 * and address with the same interrupted thread state, every register the
 * program sees, each within `unrepaired_gap_ns` of the one before: an
 * access no handler repairs faults again within microseconds. That fault
 * takes the default action. A repair in a few steps faults a few times, and
 * a program that re-protects a page to poll it touches it again only after
 * other work, so neither reaches the count.
 *
 * The records are slots chosen by a hash of the faulting thread. A slot
 * another thread holds at that moment is passed over, and two threads that
 * share a slot overwrite each other's count, so an unrepaired fault on one
 * of them is caught only once it repeats `unrepaired_repeats` times between
 * the other's faults. */
typedef __typeof__(((ucontext_t *)0)->uc_mcontext->__ss) interrupted_state;

enum { unrepaired_repeats = 64 };
static const long unrepaired_gap_ns = 10000000;

struct repeated_fault {
    int busy;
    int signal;
    int repeats;
    pthread_t thread;
    unsigned long address;
    struct timespec at;
    interrupted_state state;
};

enum { repeated_fault_slot_bits = 6, repeated_fault_slots = 1 << repeated_fault_slot_bits };
static struct repeated_fault repeated_faults[repeated_fault_slots];
typedef char linea_repeated_fault_claim_is_lock_free[__atomic_always_lock_free(sizeof(int), 0) ? 1 : -1];

/* The slot for `thread`. A `pthread_t` on macOS is the address of a
 * page-aligned record, so the page offset is shifted out and the rest mixed
 * by the 64-bit golden-ratio multiplier, whose top bits spread consecutive
 * page numbers over the slots. The product wraps, which is what mixes it. */
static struct repeated_fault *repeated_fault_slot(pthread_t thread) {
    const unsigned long page = (unsigned long)(uintptr_t)thread >> 12;
    unsigned long mixed;
    (void)__builtin_mul_overflow(page, 0x9E3779B97F4A7C15UL, &mixed);
    return &repeated_faults[mixed >> (64 - repeated_fault_slot_bits)];
}

/* Records this fault, and answers whether it is the `unrepaired_repeats`th
 * of a run of identical faults on this thread, each soon after the last. */
static int fault_left_unrepaired(int signal, unsigned long address, const void *context) {
    struct timespec now;
    if (clock_gettime(CLOCK_MONOTONIC, &now) != 0) return 0;
    struct repeated_fault *slot = repeated_fault_slot(pthread_self());
    if (__atomic_exchange_n(&slot->busy, 1, __ATOMIC_ACQUIRE) != 0) return 0;
    const interrupted_state *state = &((const ucontext_t *)context)->uc_mcontext->__ss;
    const time_t seconds = now.tv_sec - slot->at.tv_sec;
    const int soon = seconds >= 0 && seconds < 2 && seconds * 1000000000L + (now.tv_nsec - slot->at.tv_nsec) < unrepaired_gap_ns;
    const int same = slot->repeats > 0 && soon && slot->signal == signal && pthread_equal(slot->thread, pthread_self()) != 0 &&
                     slot->address == address && memcmp(&slot->state, state, sizeof *state) == 0;
    if (same) {
        slot->repeats += 1;
    } else {
        slot->repeats = 1;
        slot->signal = signal;
        slot->thread = pthread_self();
        slot->address = address;
        slot->state = *state;
    }
    slot->at = now;
    const int unrepaired = slot->repeats >= unrepaired_repeats;
    if (unrepaired) slot->repeats = 0;
    __atomic_store_n(&slot->busy, 0, __ATOMIC_RELEASE);
    return unrepaired;
}
#endif

/* Hands a fault that is not Linea's to the action installed before the
 * runtime's.
 *
 * A handler runs as the system would have run it in some respects and not
 * all. Preserved: the handler is called with the same arguments, and with
 * the thread's signal mask during the call extended by its `sa_mask` and,
 * unless it set `SA_NODEFER`, by the fault's own signal; with `SA_NODEFER`
 * and the signal outside its `sa_mask`, the signal is unblocked during the
 * call. A handler installed with `SA_RESETHAND` runs for the first such fault
 * only, and every later one takes the default action, which the system would
 * have reset it to. macOS does not report `SA_RESETHAND` through
 * `sigaction`; there a fault that repeats unrepaired many times in quick
 * succession takes the default action instead, as `struct repeated_fault`
 * describes.
 *
 * Not reproduced: a handler always runs on the stack the runtime's own
 * handler runs on, the thread's alternate signal stack where it has one,
 * whether or not it asked for `SA_ONSTACK`, since a signal handler cannot
 * move to the interrupted stack; and `sigaction` reports the runtime's
 * handler, not the default action, after an `SA_RESETHAND` handler has run,
 * since resetting the action would also remove the runtime's.
 *
 * Otherwise the default action is reinstalled, so returning runs the access
 * again and the process ends as it would have ended without this runtime. An
 * ignored fault gets the default action too: a process can inherit an ignored
 * SIGSEGV across `exec`, and the access would then fault forever on macOS,
 * where Linux ends the process with the default action.
 *
 * Everything it calls is async-signal-safe. */
static void pass_on(int signal, siginfo_t *info, void *context) {
    const struct sigaction *previous = signal == SIGBUS ? &previous_bus : &previous_segv;
    int *spent = signal == SIGBUS ? &previous_bus_spent : &previous_segv_spent;
    /* The two handler fields share storage, and a process can carry
     * `SA_SIGINFO` beside the default action, so the default and ignored
     * actions are recognised before the flag is read. `SA_RESETHAND` and
     * `SA_NODEFER` do not fit an `int` on every system, so the flags are read
     * unsigned. */
    const unsigned flags = (unsigned)previous->sa_flags;
    int handled = previous->sa_handler != SIG_DFL && previous->sa_handler != SIG_IGN;
    if (handled && (flags & (unsigned)SA_RESETHAND) != 0) {
        handled = __atomic_exchange_n(spent, 1, __ATOMIC_ACQ_REL) == 0;
    }
#if defined(__APPLE__)
    if (handled && fault_left_unrepaired(signal, (unsigned long)info->si_addr, context)) handled = 0;
#endif
    if (handled) {
        /* The fault's signal is blocked already: the runtime's own action
         * does not set `SA_NODEFER`. */
        sigset_t before;
        if (pthread_sigmask(SIG_BLOCK, &previous->sa_mask, &before) != 0) fail("linea: the runtime cannot hand a fault on\n");
        if ((flags & (unsigned)SA_NODEFER) != 0 && sigismember(&previous->sa_mask, signal) != 1) {
            sigset_t own;
            if (sigemptyset(&own) != 0 || sigaddset(&own, signal) != 0 || pthread_sigmask(SIG_UNBLOCK, &own, 0) != 0) {
                fail("linea: the runtime cannot hand a fault on\n");
            }
        }
        if ((flags & (unsigned)SA_SIGINFO) != 0) {
            previous->sa_sigaction(signal, info, context);
        } else {
            previous->sa_handler(signal);
        }
        if (pthread_sigmask(SIG_SETMASK, &before, 0) != 0) fail("linea: the runtime cannot hand a fault on\n");
        return;
    }
    struct sigaction fallback;
    memset(&fallback, 0, sizeof fallback);
    fallback.sa_handler = SIG_DFL;
    sigemptyset(&fallback.sa_mask);
    if (sigaction(signal, &fallback, 0) != 0) fail("linea: the runtime cannot restore a fault's default action\n");
}

/* Runs on a fault, on the faulting thread's alternate signal stack, so an
 * overflow, which leaves no stack to run on, is still reported. A fault in
 * the guard pages is an overflow, and an address inside a region of the
 * checking allocator is that allocator's to explain. Any other fault is
 * passed on. Everything it calls is async-signal-safe, except
 * `pthread_getspecific`, which POSIX does not list but which reads a
 * per-thread slot without allocating or locking on Linux and macOS. */
static void on_fault(int signal, siginfo_t *info, void *context) {
    /* A fault the handler returns from resumes code that may read `errno`
     * next, and the pause in `take_table_in_time` or a handler passed the
     * fault can set it, so it is kept as it was. */
    const int saved_errno = errno;
    const unsigned long address = (unsigned long)info->si_addr;
    const struct thread_record *record = pthread_getspecific(thread_record_key);
    if (record != 0 && address >= record->guard_low && address < record->guard_high) fail(overflow_report);
#if LINEA_CHECK_STORAGE
    storage_fault(address);
#endif
    pass_on(signal, info, context);
    errno = saved_errno;
}

static void install_fault_handler(void) {
    struct sigaction action;
    memset(&action, 0, sizeof action);
    action.sa_sigaction = on_fault;
    sigemptyset(&action.sa_mask);
    action.sa_flags = SA_SIGINFO | SA_ONSTACK;
    if (sigaction(SIGSEGV, &action, &previous_segv) != 0 || sigaction(SIGBUS, &action, &previous_bus) != 0) {
        fail("linea: the runtime cannot install its fault handler\n");
    }
}

static pthread_once_t fault_handler_once = PTHREAD_ONCE_INIT;
#endif

/* Installs the fault handler once per process, from whichever thread asks
 * first. SIGPIPE is left as the process set it: a write the runtime makes
 * answers EPIPE for a closed pipe without the signal ending the process, as
 * `pipe_signal.h` describes. */
static void ensure_fault_handler(void) {
    if (pthread_once(&thread_record_once, create_thread_record_key) != 0) {
        fail("linea: the runtime cannot create its thread record key\n");
    }
#if !defined(LINEA_SANITIZED)
    if (pthread_once(&fault_handler_once, install_fault_handler) != 0) {
        fail("linea: the runtime cannot install its fault handler\n");
    }
#endif
}

/* Installs the `bytes` at `at` as the calling thread's alternate signal
 * stack, less the thread's record at its low end, and records `[low, high)`
 * as the guard pages below its stack. Every thread a task runs on calls it
 * before running Linea code. `at` must be aligned to 16 bytes and `bytes`
 * must exceed the record, or the answer is EINVAL. Answers zero, or
 * the errno that kept the signal stack from being installed. */
int linea_thread_begin(unsigned long at, unsigned long bytes, unsigned long low, unsigned long high) {
    if (bytes <= thread_record_bytes || at % 16 != 0) return EINVAL;
    ensure_fault_handler();
    struct thread_record *record = (struct thread_record *)at;
    record->guard_low = low;
    record->guard_high = high;
    const int recorded = pthread_setspecific(thread_record_key, record);
    if (recorded != 0) return recorded;
    stack_t alternate;
    memset(&alternate, 0, sizeof alternate);
    alternate.ss_sp = (void *)(at + thread_record_bytes);
    alternate.ss_size = bytes - thread_record_bytes;
    if (sigaltstack(&alternate, 0) != 0) {
        const int refused = errno;
        if (pthread_setspecific(thread_record_key, 0) != 0) fail("linea: a thread cannot remove its record\n");
        return refused;
    }
    return 0;
}

/* Removes the calling thread's alternate signal stack and its record, so
 * their bytes can be freed once the thread is joined. */
void linea_thread_end(void) {
    if (pthread_setspecific(thread_record_key, 0) != 0) fail("linea: a thread cannot remove its record\n");
    stack_t alternate;
    memset(&alternate, 0, sizeof alternate);
    alternate.ss_flags = SS_DISABLE;
    /* macOS checks the size even of a stack being removed. glibc defines
     * `MINSIGSTKSZ` as a `sysconf` call, a `long`, and Linux ignores the size
     * of a stack being removed. */
    alternate.ss_size = (size_t)MINSIGSTKSZ;
    if (sigaltstack(&alternate, 0) != 0) fail("linea: a thread cannot remove its signal stack\n");
}

/* Below the lowest address the system reports for the main thread's stack,
 * the bytes a fault is taken as that stack's overflow in. Linux keeps a
 * mebibyte unmapped below a growing stack. */
static const unsigned long main_guard_bytes = 1UL << 20;

/* The main thread's alternate signal stack, 64 KiB after its thread record.
 * It lives as long as the process, since the main thread is never joined. */
static char main_signal_stack[65536 + thread_record_bytes] __attribute__((aligned(16)));

/* Gives the main thread what `linea_thread_begin` gives a task's: an
 * alternate signal stack and the bounds of its stack's guard, read from the
 * system's record of the main thread's stack. */
static void begin_main_thread(void) {
    unsigned long low = 0;
#if defined(__APPLE__)
    pthread_t self = pthread_self();
    low = (unsigned long)pthread_get_stackaddr_np(self) - (unsigned long)pthread_get_stacksize_np(self);
#elif defined(__linux__)
    pthread_attr_t attributes;
    void *start = 0;
    size_t size = 0;
    if (pthread_getattr_np(pthread_self(), &attributes) == 0) {
        if (pthread_attr_getstack(&attributes, &start, &size) == 0) low = (unsigned long)start;
        (void)pthread_attr_destroy(&attributes);
    }
#endif
    const long page = sysconf(_SC_PAGESIZE);
    const unsigned long above = page > 0 ? (unsigned long)page : 4096UL;
    const unsigned long guard = low > main_guard_bytes ? low - main_guard_bytes : 0;
    const unsigned long limit = low > main_guard_bytes ? low + above : 0;
    if (linea_thread_begin((unsigned long)main_signal_stack, sizeof main_signal_stack, guard, limit) != 0) {
        fail("linea: the main thread cannot install its signal stack\n");
    }
}

static pthread_once_t main_thread_once = PTHREAD_ONCE_INIT;

/* Zeroed heap memory from the C allocator, or zero where it refuses. */
static unsigned long system_alloc(unsigned long size) {
    unsigned long at = (unsigned long)calloc(1, size);
    if (at % 8 != 0) fail("linea: the allocator answered a misaligned address\n");
    return at;
}

#if LINEA_CHECK_STORAGE
static unsigned long checked_alloc(unsigned long size);
static void checked_free(unsigned long at, unsigned long size);
static void check_extent(unsigned long at, unsigned long len);

/* Present only in the checking runtime, so whoever links an archive can ask
 * it whether it checks storage. */
const int linea_storage_checked = 1;

/* Every report the checking allocator makes. A report is one line on standard
 * error, and the conformance runner reads this table to tell a case recording
 * one of them from a case recording anything else. */
static const char *const storage_reports[] = {
    "linea: storage was used after it was freed\n",
    "linea: an access reached outside its storage\n",
    "linea: storage was freed twice\n",
    "linea: a disposal named storage that is not allocated\n",
    "linea: a disposal named the wrong size: %lu bytes of a %lu-byte allocation\n",
    "linea: a store reached outside its storage\n",
};
enum { used_after_free, reached_outside, freed_twice, not_allocated, wrong_size, stored_outside };
#endif

/* Heap memory for a buffer, zeroed. Answers the address, or zero where the
 * allocation is refused -- zero rather than an abort because refusal is an
 * answer a program can hold, and this is the one failure it must be able to.
 * Zeroed, so a load of a byte nothing stored answers a defined value rather
 * than whatever a previous owner held: the language admits no operation whose
 * result depends on history it cannot see.
 *
 * Zero means refused and nothing else. An alignment past what this allocator
 * honours is not a refusal -- it is a compiler and a runtime disagreeing
 * about their contract, and it aborts rather than reading as out-of-memory
 * forever. The same goes for `calloc` answering an address the contract says
 * it cannot: the claim that allocation is 8-aligned is checked, not assumed.
 * A zero `size` still allocates, so the address answers for a buffer that
 * merely holds nothing. */
unsigned long linea_alloc(unsigned long size, unsigned long align) {
    if (align > 8) {
        char message[80];
        snprintf(message, sizeof message, "linea: the runtime cannot honour %lu-byte alignment\n", align);
        fail(message);
    }
    if (size == 0) size = 1;
    /* No address space this runtime targets answers a request past 2^47
     * bytes, so it is refused before the allocator sees it. That also keeps
     * a refusal a refusal under allocators that abort on an impossible size
     * rather than answering zero -- a sanitizer's allocator is one. */
    if (size >> 47 != 0) return 0;
#if LINEA_CHECK_STORAGE
    return checked_alloc(size);
#else
    return system_alloc(size);
#endif
}

/* The size and alignment travel so the interface is the one a real allocator
 * needs; `free` has no use for either, and the checking allocator compares
 * the size against the one it recorded.
 *
 * The size is checked rather than merely accepted. An allocation never
 * reserves nothing -- a request for zero bytes is answered with one -- so a
 * disposal naming no extent is a buffer that recorded the length asked for
 * where it should have recorded the length reserved. `free` would not notice,
 * and the allocator this interface exists for would: `munmap` refuses a length
 * of zero. Caught here, it is one abort at the seam; left alone, it is a leak
 * that appears when the first allocator that reads the size arrives. */
void linea_free(unsigned long at, unsigned long size, unsigned long align) {
    (void)align;
    if (size == 0) fail("linea: a disposal named no extent to release\n");
#if LINEA_CHECK_STORAGE
    checked_free(at, size);
#else
    free((void *)at);
#endif
}

/* Called by a runtime entry before it hands the `len` bytes at `at`, which a
 * program handed it as its own storage, to a system call. The checking
 * allocator aborts where any of those bytes were freed or lie outside the
 * allocation `at` falls in, so a system call never meets them. */
void linea_storage_extent(unsigned long at, unsigned long len) {
#if LINEA_CHECK_STORAGE
    check_extent(at, len);
#else
    (void)at;
    (void)len;
#endif
}

#if LINEA_CHECK_STORAGE
/* The checking allocator.
 *
 * Every allocation gets pages of its own inside a region this allocator
 * reserved, with its bytes placed against the end of those pages and one
 * inaccessible guard page after them:
 *
 *     | guard | zeros ... bytes canary | guard | zeros ... bytes canary | ...
 *
 * Disposal replaces the allocation's pages with inaccessible ones, and no
 * address is ever handed out twice. So every later load or store through a
 * stale address faults in the hardware, whatever instruction makes it, and the
 * fault handler below turns that into an abort naming what happened. A read of
 * freed storage is caught exactly, not by chance: there is no poison value it
 * could mistake for data.
 *
 * The bytes between the page start and the allocation stay zero, as fresh
 * pages arrive, and the bytes between its requested end and the next multiple
 * of eight hold `canary`. Disposal checks both, so a store outside the extent
 * that stops short of a guard page is reported when the allocation is freed.
 * A store past the rounded end reaches the guard page and faults at once.
 *
 * Each allocation holds at least one page of memory while it lives. Past
 * `guarded_limit` live allocations, further ones come from `calloc` and are
 * only checked for double and unknown disposal; that bound keeps a program with
 * many small live allocations within memory and within the number of mappings
 * a kernel allows a process.
 *
 * Tasks allocate and free from their own threads, so every piece of the
 * state below, the regions, their extents and the spill table, is read and
 * written only with `storage_lock` held, or, by the fault handler, with
 * `table_busy` alone. */

enum { canary = 0xA5 };

/* Addresses a reservation spans. Reserving costs address space and no memory:
 * the pages are inaccessible until an allocation claims them. */
static const unsigned long region_bytes = 1UL << 34;

/* How many allocations may hold pages of their own at once. */
static const unsigned long guarded_limit = 16384;

struct extent {
    unsigned long start; /* the first byte of the allocation's pages */
    unsigned long at;    /* the address the allocation answered */
    unsigned long size;  /* bytes requested, at least one */
    int freed;
};

/* One reservation. Allocations are carved from it in address order, so its
 * extents are sorted by address and a lookup is a binary search. */
struct region {
    unsigned long base;
    unsigned long end;
    unsigned long next;
    struct extent *extents;
    unsigned long count;
    unsigned long capacity;
};

static struct region *regions = 0;
static unsigned long region_count = 0;
static unsigned long region_capacity = 0;
static unsigned long page_bytes = 0;
static unsigned long guarded_live = 0;

/* Addresses of live allocations that came from `calloc`, in an open-addressed
 * table. Zero marks an empty slot and one a removed entry; neither is an
 * address `calloc` answers, because every answer is a nonzero multiple of 8. */
static unsigned long *spilled = 0;
static unsigned long spilled_capacity = 0;
static unsigned long spilled_used = 0;

static pthread_mutex_t storage_lock = PTHREAD_MUTEX_INITIALIZER;

/* Set while a thread reads or changes the state above. A thread that holds
 * `storage_lock` also holds this flag, so threads wait for each other on the
 * mutex. A fault handler cannot take a mutex, since no pthread mutex call is
 * async-signal-safe, so it takes the flag alone with lock-free atomic
 * operations, which are; the mutex holder waits on the flag only while a
 * fault handler is waiting for it. */
static int table_busy = 0;

/* The thread holding `storage_lock`, valid while `table_owned` is set, so
 * the fault handler can tell a fault on that thread. It is set before the
 * thread takes `table_busy` and cleared after it releases it, so a fault on
 * that thread anywhere between finds it the owner. Kept in shared variables
 * rather than a thread-local one, which the handler cannot read without
 * allocating on macOS, as `struct thread_record` explains. */
static pthread_t table_owner;
static int table_owned = 0;

/* How many fault handlers are waiting for `table_busy`. A thread taking the
 * flag on the allocator's path waits until none is, so a thread that takes
 * and releases the table in a loop cannot keep a fault handler from it. */
static int faults_waiting = 0;

/* The fault handler uses these atomics, and only a lock-free atomic
 * operation is async-signal-safe. */
typedef char linea_table_flag_is_lock_free[__atomic_always_lock_free(sizeof table_busy, 0) ? 1 : -1];
typedef char linea_waiting_count_is_lock_free[__atomic_always_lock_free(sizeof faults_waiting, 0) ? 1 : -1];
typedef char linea_owner_flag_is_lock_free[__atomic_always_lock_free(sizeof table_owned, 0) ? 1 : -1];
typedef char linea_owner_is_lock_free[__atomic_always_lock_free(sizeof table_owner, 0) ? 1 : -1];

static void take_table(void) {
    for (;;) {
        while (__atomic_load_n(&faults_waiting, __ATOMIC_ACQUIRE) != 0) {
        }
        if (__atomic_exchange_n(&table_busy, 1, __ATOMIC_ACQUIRE) == 0) return;
    }
}

static void release_table(void) {
    __atomic_store_n(&table_busy, 0, __ATOMIC_RELEASE);
}

static void lock_storage(void) {
    if (pthread_mutex_lock(&storage_lock) != 0) fail("linea: storage checking cannot take its lock\n");
    __atomic_store_n(&table_owner, pthread_self(), __ATOMIC_RELAXED);
    __atomic_store_n(&table_owned, 1, __ATOMIC_RELEASE);
    take_table();
}

static void unlock_storage(void) {
    release_table();
    __atomic_store_n(&table_owned, 0, __ATOMIC_RELEASE);
    if (pthread_mutex_unlock(&storage_lock) != 0) fail("linea: storage checking cannot release its lock\n");
}

static unsigned long round_up(unsigned long n, unsigned long to) {
    return (n + to - 1) / to * to;
}

/* Bytes of pages an allocation of `size` bytes holds. */
static unsigned long span_of(unsigned long size) {
    return round_up(round_up(size, 8), page_bytes);
}

static const struct region *region_holding(unsigned long address) {
    for (unsigned long i = 0; i < region_count; i += 1) {
        if (address >= regions[i].base && address < regions[i].end) return &regions[i];
    }
    return 0;
}

/* The extent whose pages start last at or before `address`, or null. */
static struct extent *extent_below(const struct region *r, unsigned long address) {
    unsigned long low = 0, high = r->count;
    while (low < high) {
        const unsigned long mid = low + (high - low) / 2;
        if (r->extents[mid].start <= address) low = mid + 1;
        else high = mid;
    }
    return low == 0 ? 0 : &r->extents[low - 1];
}

/* What an address inside a region names, as the message an access to it
 * earns, or null where it names live storage. */
static const char *verdict(const struct region *r, unsigned long address) {
    const struct extent *e = extent_below(r, address);
    if (e != 0 && address < e->start + span_of(e->size)) {
        return e->freed ? storage_reports[used_after_free] : 0;
    }
    return storage_reports[reached_outside];
}

/* Aborts unless the `len` bytes at `at` lie within one live allocation's
 * requested extent, or wholly outside every region. */
static void check_extent_locked(unsigned long at, unsigned long len) {
    if (len == 0) return;
    const unsigned long last = len - 1 > ~0UL - at ? ~0UL : at + (len - 1);
    const struct region *r = region_holding(at);
    if (r == 0) {
        if (region_holding(last) != 0) fail(storage_reports[reached_outside]);
        return;
    }
    const char *message = verdict(r, at);
    if (message != 0) fail(message);
    const struct extent *e = extent_below(r, at);
    if (at < e->at || last - e->at >= e->size) fail(storage_reports[reached_outside]);
}

/* How many times the fault handler tries to take `table_busy`, at least a
 * millisecond apart, before it reports the fault without reading the table:
 * about one second. */
static const int fault_table_attempts = 1000;

/* What the fault handler reports when it could not take `table_busy` in
 * time. It says that the fault is not explained, so it is never read as one
 * of the storage reports above. */
static const char *const storage_busy_report =
    "linea: a memory access faulted while storage checking was busy, so what it reached is not known\n";

/* Takes `table_busy` for the fault handler, making `fault_table_attempts`
 * attempts with a pause of at least a millisecond between two, so it waits
 * at least that many milliseconds less one before giving up; a busy system
 * can lengthen each pause. Counts itself in `faults_waiting` meanwhile so the
 * allocator's path gives way. Answers whether it took it. Waits with
 * `nanosleep`, which is async-signal-safe. */
static int take_table_in_time(void) {
    (void)__atomic_add_fetch(&faults_waiting, 1, __ATOMIC_ACQ_REL);
    int taken = 0;
    for (int attempt = 0; attempt < fault_table_attempts && !taken; attempt += 1) {
        taken = __atomic_exchange_n(&table_busy, 1, __ATOMIC_ACQUIRE) == 0;
        if (!taken) {
            /* A signal that interrupts the pause leaves the rest of it in
             * `pause_for`, and the pause resumes, so each attempt waits its
             * whole millisecond. */
            struct timespec pause_for = {0, 1000000};
            while (nanosleep(&pause_for, &pause_for) != 0 && errno == EINTR) {
            }
        }
    }
    (void)__atomic_sub_fetch(&faults_waiting, 1, __ATOMIC_ACQ_REL);
    return taken;
}

/* Whether the calling thread holds `storage_lock`. `pthread_self` is
 * async-signal-safe. */
static int owns_table(void) {
    return __atomic_load_n(&table_owned, __ATOMIC_ACQUIRE) != 0 &&
           pthread_equal(__atomic_load_n(&table_owner, __ATOMIC_RELAXED), pthread_self()) != 0;
}

/* Explains a fault at `address` where it lies inside a region: an abort
 * naming what the access reached. Called by the fault handler on the
 * faulting thread.
 *
 * Where that thread owns the table, the fault is inside this allocator,
 * which may have left the table half changed, and the thread may hold
 * `table_busy` itself, so the handler reads nothing and aborts with
 * `storage_busy_report`. Otherwise it takes `table_busy`. The thread holding
 * it may never release it: it may be stopped inside the C allocator, waiting
 * for a lock the faulting thread holds. So the handler waits a bounded time
 * and then aborts with `storage_busy_report`, so that a failure is always
 * reported.
 *
 * Whether the address lies inside a region is known only from the table, so
 * every fault comes here first, a fault that is not Linea's included. While
 * the table is busy past the bounded wait, or owned by the faulting thread,
 * such a fault ends with `storage_busy_report` and never reaches a host's
 * handler: the checking runtime prefers a bounded wait followed by a generic
 * report to reading a table that may be changing. */
static void storage_fault(unsigned long address) {
    if (owns_table() || !take_table_in_time()) fail(storage_busy_report);
    const struct region *r = region_holding(address);
    const char *message = r == 0 ? 0 : verdict(r, address);
    if (message != 0) fail(message);
    release_table();
}

/* Runs in the child of a `fork`, where only the forking thread exists.
 * Fault handlers that were waiting on other threads are gone, so
 * `faults_waiting` is cleared, or every later allocation would wait for them
 * forever. A `table_busy` taken with no owner recorded was taken by such a
 * handler, which only reads the table, so it is released too. One taken by
 * an owner is left as it is: the owner also held `storage_lock`, which stays
 * locked in the child, so the table it was changing is never read; the
 * child's own fault handler reports it as busy, and its allocator waits on
 * that lock as on any lock a vanished thread held. */
static void forget_other_threads(void) {
    __atomic_store_n(&faults_waiting, 0, __ATOMIC_RELEASE);
    if (__atomic_load_n(&table_owned, __ATOMIC_ACQUIRE) == 0) release_table();
}

/* Sets up the allocator once; called with the lock held. */
static void set_up(void) {
    if (page_bytes != 0) return;
    const long page = sysconf(_SC_PAGESIZE);
    if (page <= 0) fail("linea: the system reports no page size\n");
    page_bytes = (unsigned long)page;
    ensure_fault_handler();
    if (pthread_atfork(0, 0, forget_other_threads) != 0) fail("linea: storage checking cannot prepare for fork\n");
}

/* Reserves a region able to hold `need` bytes after its leading guard page,
 * or answers null where the address space refuses. */
static struct region *reserve(unsigned long need) {
    if (region_count == region_capacity) {
        const unsigned long capacity = region_capacity == 0 ? 8 : region_capacity * 2;
        struct region *grown = realloc(regions, capacity * sizeof *grown);
        if (grown == 0) return 0;
        regions = grown;
        region_capacity = capacity;
    }
    const unsigned long least = need + page_bytes;
    unsigned long bytes = least > region_bytes ? least : region_bytes;
    void *base = MAP_FAILED;
    while (base == MAP_FAILED) {
        base = mmap(0, bytes, PROT_NONE, MAP_PRIVATE | MAP_ANON | MAP_NORESERVE, -1, 0);
        if (base != MAP_FAILED || bytes == least) break;
        bytes = bytes / 2 > least ? bytes / 2 : least;
    }
    if (base == MAP_FAILED) return 0;
    struct region *r = &regions[region_count];
    region_count += 1;
    r->base = (unsigned long)base;
    r->end = r->base + bytes;
    r->next = r->base + page_bytes;
    r->extents = 0;
    r->count = 0;
    r->capacity = 0;
    return r;
}

static unsigned long spill_slot(unsigned long at) {
    return ((at >> 3) ^ (at >> 12)) % spilled_capacity;
}

static int spill_insert(unsigned long at) {
    if ((spilled_used + 1) * 2 > spilled_capacity) {
        unsigned long *old = spilled;
        const unsigned long old_capacity = spilled_capacity;
        const unsigned long capacity = old_capacity == 0 ? 64 : old_capacity * 2;
        unsigned long *table = calloc(capacity, sizeof *table);
        if (table == 0) return 0;
        spilled = table;
        spilled_capacity = capacity;
        spilled_used = 0;
        for (unsigned long i = 0; i < old_capacity; i += 1) {
            if (old[i] > 1) (void)spill_insert(old[i]);
        }
        free(old);
    }
    unsigned long i = spill_slot(at);
    while (spilled[i] > 1) i = (i + 1) % spilled_capacity;
    if (spilled[i] == 0) spilled_used += 1;
    spilled[i] = at;
    return 1;
}

static int spill_remove(unsigned long at) {
    if (spilled_capacity == 0) return 0;
    unsigned long i = spill_slot(at);
    while (spilled[i] != 0) {
        if (spilled[i] == at) {
            spilled[i] = 1;
            return 1;
        }
        i = (i + 1) % spilled_capacity;
    }
    return 0;
}

static unsigned long spill_alloc(unsigned long size) {
    const unsigned long at = system_alloc(size);
    if (at == 0) return 0;
    if (!spill_insert(at)) {
        free((void *)at);
        return 0;
    }
    return at;
}

static unsigned long checked_alloc_locked(unsigned long size) {
    set_up();
    /* The C allocator decides whether a request is refused, so both runtimes
     * refuse exactly the requests `calloc` refuses. Its answer is released
     * at once; a refusal from it is the answer this allocator gives. */
    const unsigned long probe = system_alloc(size);
    if (probe == 0) return 0;
    free((void *)probe);
    if (guarded_live >= guarded_limit) return spill_alloc(size);

    const unsigned long rounded = round_up(size, 8);
    const unsigned long span = span_of(size);
    const unsigned long need = span + page_bytes;
    struct region *r = region_count == 0 ? 0 : &regions[region_count - 1];
    if (r == 0 || r->end - r->next < need) r = reserve(need);
    if (r == 0) return spill_alloc(size);

    if (r->count == r->capacity) {
        const unsigned long capacity = r->capacity == 0 ? 64 : r->capacity * 2;
        struct extent *grown = realloc(r->extents, capacity * sizeof *grown);
        if (grown == 0) return spill_alloc(size);
        r->extents = grown;
        r->capacity = capacity;
    }

    const unsigned long start = r->next;
    if (mprotect((void *)start, span, PROT_READ | PROT_WRITE) != 0) return spill_alloc(size);
    r->next = start + need;

    const unsigned long at = start + span - rounded;
    memset((void *)(at + size), canary, rounded - size);
    r->extents[r->count] = (struct extent){.start = start, .at = at, .size = size, .freed = 0};
    r->count += 1;
    guarded_live += 1;
    return at;
}

/* Whether every byte of `len` at `at` still holds the canary. */
static int intact(unsigned long at, unsigned long len) {
    const unsigned char *bytes = (const unsigned char *)at;
    for (unsigned long i = 0; i < len; i += 1) {
        if (bytes[i] != canary) return 0;
    }
    return 1;
}

/* Whether the `len` bytes at `at`, both multiples of eight, are all zero. Read
 * a word at a time, since the span before an allocation is up to a page. */
static int untouched(unsigned long at, unsigned long len) {
    const unsigned long *words = (const unsigned long *)at;
    unsigned long seen = 0;
    for (unsigned long i = 0; i < len / 8; i += 1) seen |= words[i];
    return seen == 0;
}

static void checked_free_locked(unsigned long at, unsigned long size) {
    const struct region *r = region_holding(at);
    struct extent *e = r == 0 ? 0 : extent_below(r, at);
    if (e == 0 || e->at != at) {
        if (spill_remove(at)) {
            free((void *)at);
            return;
        }
        fail(storage_reports[not_allocated]);
    }
    if (e->freed) fail(storage_reports[freed_twice]);
    if (e->size != size) {
        char message[128];
        snprintf(message, sizeof message, storage_reports[wrong_size], size, e->size);
        fail(message);
    }
    const unsigned long rounded = round_up(size, 8);
    if (!untouched(e->start, at - e->start) || !intact(at + size, rounded - size)) {
        fail(storage_reports[stored_outside]);
    }

    /* Mapping fresh inaccessible pages over the allocation returns its memory
     * to the system and keeps its addresses reserved, so none is reused. */
    const unsigned long span = span_of(size);
    void *start = (void *)e->start;
    if (mmap(start, span, PROT_NONE, MAP_PRIVATE | MAP_ANON | MAP_NORESERVE | MAP_FIXED, -1, 0) == MAP_FAILED &&
        mprotect(start, span, PROT_NONE) != 0) {
        fail("linea: storage checking cannot retire freed pages\n");
    }
    e->freed = 1;
    guarded_live -= 1;
}

static void check_extent(unsigned long at, unsigned long len) {
    lock_storage();
    check_extent_locked(at, len);
    unlock_storage();
}

static unsigned long checked_alloc(unsigned long size) {
    lock_storage();
    const unsigned long at = checked_alloc_locked(size);
    unlock_storage();
    return at;
}

static void checked_free(unsigned long at, unsigned long size) {
    lock_storage();
    checked_free_locked(at, size);
    unlock_storage();
}
#endif

/* The process's arguments, retained rather than copied.
 *
 * `argv` and the bytes it points at belong to the process and stay valid as
 * long as it runs, which is exactly what a view of text asks of what it views.
 * So retaining the pointer is the whole of the job: copying would buy nothing
 * and would need an allocator before the program has started.
 *
 * Held here because the entry point is the only place that has them, and
 * threading two values through every frame that might one day ask would price
 * the question at every call rather than at the one asking it. */
static int linea_argc = 0;
static char **linea_argv = 0;

/* The environment the process was started with: the `NAME=value` strings C's
 * startup placed beside the arguments, ended by a null pointer.
 *
 * The array and its length are recorded when the arguments are, before any
 * Linea code runs, so reading one entry's address or length never walks the
 * array again. Linea code has no operation that changes the environment, so
 * the array and its strings stay as they were until the process exits, which
 * is what a view of text asks. Only a trusted `extern` can call C's setenv,
 * putenv or unsetenv; such a call voids this, since C may overwrite or shift
 * entries of the recorded array and free a string it put there. */
extern char **environ;
static char **linea_envp = 0;
static unsigned long linea_envc = 0UL;

void linea_set_args(int argc, char **argv) {
    if (pthread_once(&main_thread_once, begin_main_thread) != 0) fail("linea: the main thread cannot be set up\n");
    linea_argc = argc;
    linea_argv = argv;
    linea_envp = environ;
    linea_envc = 0UL;
    if (linea_envp != 0) {
        while (linea_envp[linea_envc] != 0) linea_envc += 1UL;
    }
}

unsigned long linea_arg_count(void) {
    if (linea_argv == 0 || linea_argc < 0) return 0UL;
    return (unsigned long)linea_argc;
}

/* Where one argument starts, and how many bytes it holds.
 *
 * Two calls rather than one answering both, because a declaration in the
 * language names scalars and has no way to spell a value written through. The
 * cost is a second walk of a string that is a handful of bytes long.
 *
 * Both answer zero for an index at or past the end. What absence means is the
 * library's to say and not this file's: a trap here would have nowhere to
 * report where the mistake was, which is the same reason reading a byte out of
 * text is checked above this line rather than below it.
 *
 * The length is measured because the process supplies none, and the only
 * property read of the bytes is where the terminator is. Nothing else is
 * examined, so an argument that is not valid UTF-8 arrives exactly as it was
 * given. */
unsigned long linea_arg_at(unsigned long i) {
    if (i >= linea_arg_count()) return 0UL;
    return (unsigned long)linea_argv[i];
}

unsigned long linea_arg_len(unsigned long i) {
    if (i >= linea_arg_count()) return 0UL;

    const char *s = linea_argv[i];
    unsigned long n = 0UL;
    while (s[n] != '\0') n += 1UL;
    return n;
}

/* How many entries the environment held at startup, and where entry `i`
 * starts and how many bytes it holds. Like the argument calls above, an index
 * at or past the end answers zero, and the bytes are passed on unexamined.
 * The count was taken once at startup, so a walk over every entry reads each
 * string once: its cost is the environment's size in bytes. */
unsigned long linea_env_count(void) {
    return linea_envc;
}

unsigned long linea_env_at(unsigned long i) {
    if (i >= linea_envc) return 0UL;
    return (unsigned long)linea_envp[i];
}

unsigned long linea_env_len(unsigned long i) {
    if (i >= linea_envc) return 0UL;

    const char *s = linea_envp[i];
    unsigned long n = 0UL;
    while (s[n] != '\0') n += 1UL;
    return n;
}

/* Reports where a trap or a panic happened, " at FILE:LINE:COL" and a
 * newline, through `report_bytes`. */
static void report_location(const char *file, int line, int col) {
    char numbers[48];
    const int written = snprintf(numbers, sizeof numbers, ":%d:%d\n", line, col);
    report_bytes(" at ", 4);
    report_bytes(file, strlen(file));
    if (written > 0) report_bytes(numbers, (size_t)written);
}

void linea_trap(int kind, const char *file, int line, int col) {
    const char *msg = "unknown failure";
    if (kind >= 0 && (unsigned)kind < sizeof what / sizeof *what) {
        msg = what[kind];
    }
    report_bytes("linea: ", 7);
    report_bytes(msg, strlen(msg));
    report_location(file, line, col);
    abort();
}

void linea_panic(unsigned long at, unsigned long len,
                 const char *file, int line, int col) {
    report_bytes("linea: panic: ", 14);
    report_bytes((const char *)at, (size_t)len);
    report_location(file, line, col);
    abort();
}
