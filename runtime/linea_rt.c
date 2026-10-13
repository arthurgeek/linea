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
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

/* The interface between generated code and this file, versioned so the two
 * cannot silently disagree.
 *
 * Generated code references the symbol below, so a compiler built against one
 * version and a runtime built against another fail to LINK rather than
 * misreading each other's arguments. The number stays 1 until the runtime ships
 * separately from the compiler; before then both are built from one tree and
 * cannot disagree. */
#define LINEA_RUNTIME_ABI 1

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

/* Writes a runtime failure and aborts. Written with `write` rather than
 * stdio, so the fault handler can report through it too. */
static void fail(const char *message) {
    if (write(2, message, strlen(message)) < 0) {
    }
    abort();
}

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
 * a kernel allows a process. The runtime creates no threads, so none of this
 * state is shared. */
#include <signal.h>
#include <string.h>
#include <sys/mman.h>

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
static void check_extent(unsigned long at, unsigned long len) {
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

/* Runs on a fault. An address inside a region is this allocator's to explain;
 * any other fault is left to the default action, which `SA_RESETHAND` has
 * already restored, so returning re-executes the access and ends the process
 * as it would have ended without this handler. */
static void on_fault(int signal, siginfo_t *info, void *context) {
    (void)signal;
    (void)context;
    const unsigned long address = (unsigned long)info->si_addr;
    const struct region *r = region_holding(address);
    if (r == 0) return;
    const char *message = verdict(r, address);
    if (message != 0) fail(message);
}

static void set_up(void) {
    if (page_bytes != 0) return;
    const long page = sysconf(_SC_PAGESIZE);
    if (page <= 0) fail("linea: the system reports no page size\n");
    page_bytes = (unsigned long)page;

    struct sigaction action;
    memset(&action, 0, sizeof action);
    action.sa_sigaction = on_fault;
    sigemptyset(&action.sa_mask);
    /* Linux spells `SA_RESETHAND` as 0x80000000, an unsigned value that does
     * not fit the `int` of `sa_flags`. The conversion is made explicitly so
     * the implicit-conversion check does not trap on it. */
    const unsigned flags = (unsigned)SA_SIGINFO | (unsigned)SA_RESETHAND;
    action.sa_flags = (int)flags;
    if (sigaction(SIGSEGV, &action, 0) != 0 || sigaction(SIGBUS, &action, 0) != 0) {
        fail("linea: storage checking cannot install its fault handler\n");
    }
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

static unsigned long checked_alloc(unsigned long size) {
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

static void checked_free(unsigned long at, unsigned long size) {
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

void linea_trap(int kind, const char *file, int line, int col) {
    const char *msg = "unknown failure";
    if (kind >= 0 && (unsigned)kind < sizeof what / sizeof *what) {
        msg = what[kind];
    }
    fprintf(stderr, "linea: %s at %s:%d:%d\n", msg, file, line, col);
    fflush(stderr);
    abort();
}

void linea_panic(unsigned long at, unsigned long len,
                 const char *file, int line, int col) {
    fputs("linea: panic: ", stderr);
    fwrite((const void *)at, 1, len, stderr);
    fprintf(stderr, " at %s:%d:%d\n", file, line, col);
    fflush(stderr);
    abort();
}
