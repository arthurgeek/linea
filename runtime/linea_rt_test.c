#define _GNU_SOURCE
/* Assertions execute test setup, checks, and cleanup in every build mode. */
#undef NDEBUG
#include <assert.h>
#include <pthread.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/wait.h>
#include <unistd.h>

unsigned long linea_alloc(unsigned long size, unsigned long align);
void linea_free(unsigned long at, unsigned long size, unsigned long align);
void linea_set_args(int argc, char **argv);
unsigned long linea_arg_count(void);
unsigned long linea_arg_at(unsigned long i);
unsigned long linea_arg_len(unsigned long i);
unsigned long linea_env_count(void);
unsigned long linea_env_at(unsigned long i);
unsigned long linea_env_len(unsigned long i);
void linea_trap(int kind, const char *file, int line, int col);
void linea_panic(unsigned long at, unsigned long len, const char *file, int line, int col);
void linea_storage_extent(unsigned long at, unsigned long len);

/* Runs `body` in a child and checks it aborted after writing `expected` to stderr. */
static void aborts_saying(void (*body)(void), const char *expected) {
    int err_pipe[2];
    assert(pipe(err_pipe) == 0);
    pid_t pid = fork();
    assert(pid >= 0);
    if (pid == 0) {
        dup2(err_pipe[1], 2);
        body();
        _exit(0);
    }
    close(err_pipe[1]);
    char said[512] = {0};
    size_t have = 0;
    ssize_t n;
    while ((n = read(err_pipe[0], said + have, sizeof said - 1 - have)) > 0) have += (size_t)n;
    close(err_pipe[0]);
    int status = 0;
    assert(waitpid(pid, &status, 0) == pid);
    assert(WIFSIGNALED(status) && WTERMSIG(status) == SIGABRT);
    assert(strcmp(said, expected) == 0);
}

/* Runs `body` in a child and checks it exited cleanly. */
static void exits_cleanly(void (*body)(void)) {
    pid_t pid = fork();
    assert(pid >= 0);
    if (pid == 0) {
        body();
        _exit(0);
    }
    int status = 0;
    assert(waitpid(pid, &status, 0) == pid);
    assert(WIFEXITED(status) && WEXITSTATUS(status) == 0);
}

/* A page of the host's own, inaccessible until the host's fault handler
 * makes it readable, and how many faults that handler took in it. */
static char *host_page = 0;
static unsigned long host_page_bytes = 0;
static volatile sig_atomic_t host_faults = 0;

/* The host's fault handler: it answers a fault in its own page by making the
 * page readable, so the faulting load runs again and succeeds. */
static void host_on_fault(int signal, siginfo_t *info, void *context) {
    (void)signal;
    (void)context;
    char *address = info->si_addr;
    if (address < host_page || address >= host_page + host_page_bytes) _exit(3);
    host_faults += 1;
    if (mprotect(host_page, host_page_bytes, PROT_READ) != 0) _exit(4);
}

static void host_on_pipe(int signal) { (void)signal; }

/* A process that runs Linea code beside its own, as a host calling an
 * exported function does, keeps the handlers it installed: the runtime leaves
 * SIGPIPE as the host set it, and hands a fault that is not Linea's to the
 * host's handler. */
static void host_handlers_survive(void) {
    struct sigaction fault;
    memset(&fault, 0, sizeof fault);
    fault.sa_sigaction = host_on_fault;
    fault.sa_flags = SA_SIGINFO;
    assert(sigemptyset(&fault.sa_mask) == 0);
    assert(sigaction(SIGSEGV, &fault, 0) == 0 && sigaction(SIGBUS, &fault, 0) == 0);
    struct sigaction pipe_action;
    memset(&pipe_action, 0, sizeof pipe_action);
    pipe_action.sa_handler = host_on_pipe;
    assert(sigemptyset(&pipe_action.sa_mask) == 0);
    assert(sigaction(SIGPIPE, &pipe_action, 0) == 0);

    char name[] = "host";
    char *argv[] = {name, NULL};
    linea_set_args(1, argv);

    struct sigaction now;
    assert(sigaction(SIGPIPE, 0, &now) == 0 && now.sa_handler == host_on_pipe);
    host_page_bytes = (unsigned long)sysconf(_SC_PAGESIZE);
    host_page = mmap(0, host_page_bytes, PROT_NONE, MAP_PRIVATE | MAP_ANON, -1, 0);
    assert(host_page != MAP_FAILED);
    assert(*(volatile char *)host_page == 0);
    assert(host_faults == 1);
}

/* A sanitized runtime leaves faults to the sanitizer, which reports a wild
 * load in its own words and exits rather than ending by the signal. */
#if !defined(LINEA_SANITIZED)
/* Sets SIGSEGV and SIGBUS to `handler` with `flags`, starts the runtime, and
 * loads from address 16, which lies in the unmapped low pages both Linux and
 * macOS keep. */
static void wild_load_after(void (*handler)(int), int flags) {
    struct sigaction action;
    memset(&action, 0, sizeof action);
    action.sa_handler = handler;
    action.sa_flags = flags;
    assert(sigemptyset(&action.sa_mask) == 0);
    assert(sigaction(SIGSEGV, &action, 0) == 0 && sigaction(SIGBUS, &action, 0) == 0);
    char name[] = "wild";
    char *argv[] = {name, NULL};
    linea_set_args(1, argv);
    (void)*(volatile char *)16;
}

/* A wild load in a process that inherited SIGSEGV and SIGBUS ignored still
 * ends it with the fault's signal, as it does where they were never set. */
static void ignored_fault_ends_the_process(void) { wild_load_after(SIG_IGN, 0); }

/* A shell can leave `SA_SIGINFO` set beside the default action; the fault
 * still takes the default action. */
static void default_with_siginfo_ends_the_process(void) { wild_load_after(SIG_DFL, SA_SIGINFO); }

/* Runs `body` in a child and checks it was ended by SIGSEGV. */
static void ends_by_fault(void (*body)(void)) {
    pid_t pid = fork();
    assert(pid >= 0);
    if (pid == 0) {
        body();
        _exit(0);
    }
    int status = 0;
    assert(waitpid(pid, &status, 0) == pid);
    assert(WIFSIGNALED(status) && WTERMSIG(status) == SIGSEGV);
}
#endif

static void over_aligned(void) { (void)linea_alloc(8, 16); }
static void free_nothing(void) { linea_free(linea_alloc(8, 8), 0, 8); }
static void trap_overflow(void) { linea_trap(0, "t.lin", 3, 7); }
static void panic_message(void) { linea_panic((unsigned long)"boom", 4, "t.lin", 1, 2); }

static void allocation(void) {
    unsigned long zero = linea_alloc(0, 1);
    assert(zero != 0 && zero % 8 == 0);
    linea_free(zero, 1, 1);
    unsigned long eight = linea_alloc(24, 8);
    assert(eight != 0 && eight % 8 == 0);
    linea_free(eight, 24, 8);
    assert(linea_alloc(1UL << 47, 8) == 0);

    /* Below that bound, a request is refused exactly when the C allocator
     * refuses it, whichever allocator this runtime holds. The probe calls
     * calloc through a volatile pointer: the optimiser assumes a calloc whose
     * result is only compared and freed succeeds, and would answer the
     * comparison without asking the allocator. */
    void *(*volatile probe_calloc)(size_t, size_t) = calloc;
    void *probe = probe_calloc(1, 1UL << 46);
    unsigned long large = linea_alloc(1UL << 46, 8);
    assert((probe != 0) == (large != 0));
    free(probe);
    if (large != 0) linea_free(large, 1UL << 46, 8);
}

static void arguments(void) {
    char a[] = "prog", b[] = "two words";
    char *argv[] = {a, b, NULL};
    linea_set_args(2, argv);
    assert(linea_arg_count() == 2);
    assert(linea_arg_at(1) == (unsigned long)b);
    assert(linea_arg_len(1) == 9);
    assert(linea_arg_at(2) == 0 && linea_arg_len(2) == 0);
}

extern char **environ;

static void environment(void) {
    /* The environment is recorded with the arguments, entry for entry. */
    assert(setenv("LINEA_RT_TEST", "a=b", 1) == 0);
    char a[] = "prog";
    char *argv[] = {a, NULL};
    linea_set_args(1, argv);
    unsigned long count = 0;
    while (environ[count] != NULL) count += 1;
    assert(linea_env_count() == count);
    int found = 0;
    for (unsigned long i = 0; i < count; i += 1) {
        assert(linea_env_at(i) == (unsigned long)environ[i]);
        assert(linea_env_len(i) == strlen(environ[i]));
        if (strcmp(environ[i], "LINEA_RT_TEST=a=b") == 0) found = 1;
    }
    assert(found);
    assert(linea_env_at(count) == 0 && linea_env_len(count) == 0);
}

#if defined(LINEA_CHECK_STORAGE) && LINEA_CHECK_STORAGE
/* Runs `body` in a child and checks it was killed by `signal` without writing anything. */
static void dies_by(void (*body)(void), int signal) {
    pid_t pid = fork();
    assert(pid >= 0);
    if (pid == 0) {
        body();
        _exit(0);
    }
    int status = 0;
    assert(waitpid(pid, &status, 0) == pid);
    assert(WIFSIGNALED(status) && WTERMSIG(status) == signal);
}

static unsigned char load(unsigned long at) { return *(volatile unsigned char *)at; }
static void store(unsigned long at, unsigned char v) { *(volatile unsigned char *)at = v; }

static void read_after_free(void) {
    unsigned long at = linea_alloc(16, 8);
    linea_free(at, 16, 8);
    (void)load(at);
}

static void write_after_free(void) {
    unsigned long at = linea_alloc(16, 8);
    linea_free(at, 16, 8);
    store(at + 15, 1);
}

/* Allocates and frees until the process ends, so the checking allocator's
 * table is being changed when another thread faults. */
static int churning = 0;

static void *churn(void *arg) {
    (void)arg;
    for (;;) {
        linea_free(linea_alloc(64, 8), 64, 8);
        __atomic_store_n(&churning, 1, __ATOMIC_SEQ_CST);
    }
    return 0;
}

/* A fault on freed storage is reported while another thread is changing the
 * allocator's table, not lost to the default action. */
static void write_after_free_beside_allocation(void) {
    unsigned long at = linea_alloc(16, 8);
    linea_free(at, 16, 8);
    pthread_t other;
    assert(pthread_create(&other, 0, churn, 0) == 0);
    while (__atomic_load_n(&churning, __ATOMIC_SEQ_CST) == 0) {
    }
    store(at + 15, 1);
}

/* A view into a vector's storage kept across a growth that moves it: the
 * view still names the old storage, which the growth freed. */
static void view_across_growth(void) {
    unsigned long storage = linea_alloc(4, 8);
    store(storage, 7);
    unsigned long view = storage;
    unsigned long grown = linea_alloc(8, 8);
    store(grown, load(storage));
    linea_free(storage, 4, 8);
    (void)load(view);
}

static void freed_twice(void) {
    unsigned long at = linea_alloc(16, 8);
    linea_free(at, 16, 8);
    linea_free(at, 16, 8);
}

static void freed_inside(void) {
    unsigned long at = linea_alloc(16, 8);
    linea_free(at + 8, 8, 8);
}

static void freed_short(void) {
    unsigned long at = linea_alloc(16, 8);
    linea_free(at, 8, 8);
}

static void read_past_end(void) {
    unsigned long at = linea_alloc(16, 8);
    (void)load(at + 16);
}

static void store_in_rounding(void) {
    unsigned long at = linea_alloc(13, 8);
    store(at + 13, 1);
    linea_free(at, 13, 8);
}

static void store_before_start(void) {
    unsigned long at = linea_alloc(16, 8);
    store(at - 1, 1);
    linea_free(at, 16, 8);
}

static void system_call_on_freed(void) {
    unsigned long at = linea_alloc(64, 8);
    linea_free(at, 64, 8);
    linea_storage_extent(at, 64);
}

/* A system call handed more bytes than the allocation holds is stopped
 * before it runs, even where the excess would stay in mapped pages. */
static void system_call_past_end(void) {
    unsigned long at = linea_alloc(13, 8);
    linea_storage_extent(at, 14);
}

static void system_call_before_start(void) {
    unsigned long at = linea_alloc(16, 8);
    linea_storage_extent(at - 8, 16);
}

/* A fault outside the allocator's regions ends the process as it would
 * without the checking allocator. Address 16 lies in the unmapped low pages
 * both Linux and macOS keep. */
static void wild_load(void) {
    linea_free(linea_alloc(8, 8), 8, 8);
    (void)load(16);
}

/* Beyond the live allocations that get pages of their own, allocation still
 * answers zeroed storage, and a second disposal is still refused. */
static void many_live_then_twice(void) {
    enum { count = 20000 };
    static unsigned long live[count];
    for (unsigned long i = 0; i < count; i += 1) {
        live[i] = linea_alloc(24, 8);
        assert(live[i] != 0 && live[i] % 8 == 0 && load(live[i] + 23) == 0);
    }
    for (unsigned long i = 0; i + 1 < count; i += 1) linea_free(live[i], 24, 8);
    linea_free(live[count - 1], 24, 8);
    linea_free(live[count - 1], 24, 8);
}

#if defined(__linux__)
/* Lines in /proc/self/maps, one per mapping the kernel holds for the process. */
static unsigned long mapping_count(void) {
    FILE *maps = fopen("/proc/self/maps", "r");
    assert(maps != 0);
    unsigned long lines = 0;
    int c;
    while ((c = fgetc(maps)) != EOF) lines += c == '\n';
    fclose(maps);
    return lines;
}

/* Retired pages merge with the guard pages beside them, so the mappings a
 * process holds follow its live allocations, not every allocation it made. */
static void mappings_follow_live_allocations(void) {
    enum { window = 1000, rounds = 100000 };
    static unsigned long live[window];
    for (unsigned long i = 0; i < window; i += 1) live[i] = linea_alloc(32, 8);
    for (unsigned long i = 0; i < rounds; i += 1) {
        linea_free(live[i % window], 32, 8);
        live[i % window] = linea_alloc(32, 8);
    }
    assert(mapping_count() < 4 * window + 64);
    for (unsigned long i = 0; i < window; i += 1) linea_free(live[i], 32, 8);
}
#endif

static void checked_allocation(void) {
    unsigned long first = linea_alloc(40, 8);
    assert(first != 0 && first % 8 == 0);
    for (unsigned long i = 0; i < 40; i += 1) assert(load(first + i) == 0);
    store(first + 39, 9);
    linea_free(first, 40, 8);
    /* A freed address is never answered again. */
    unsigned long second = linea_alloc(40, 8);
    assert(second != first);
    linea_storage_extent(second, 40);
    linea_storage_extent(second + 39, 1);
    /* Bytes the allocator does not hold, such as a constant's, pass. */
    linea_storage_extent((unsigned long)"constant", 8);
    linea_free(second, 40, 8);

    unsigned long large = linea_alloc(100000, 8);
    assert(large != 0 && load(large + 99999) == 0);
    linea_free(large, 100000, 8);
}

/* The fault handler is told the faulting address, and stays installed after
 * a fault it passes on, so it is not reset to the default action.
 * `SA_RESETHAND` does not fit an `int` on Linux, so the flags are compared
 * unsigned. */
static void fault_handler_stays_and_is_informative(void) {
    static const int faults[] = {SIGSEGV, SIGBUS};
    for (unsigned long i = 0; i < sizeof faults / sizeof *faults; i += 1) {
        struct sigaction installed;
        assert(sigaction(faults[i], 0, &installed) == 0);
        assert((installed.sa_flags & SA_SIGINFO) != 0);
        assert(((unsigned)installed.sa_flags & (unsigned)SA_RESETHAND) == 0);
    }
}
#endif

int main(void) {
    /* First, so the host's handlers are in place before the runtime installs
     * its own in that child. */
    exits_cleanly(host_handlers_survive);
#if !defined(LINEA_SANITIZED)
    ends_by_fault(ignored_fault_ends_the_process);
    ends_by_fault(default_with_siginfo_ends_the_process);
#endif
    allocation();
    arguments();
    environment();
#if defined(LINEA_CHECK_STORAGE) && LINEA_CHECK_STORAGE
    checked_allocation();
    fault_handler_stays_and_is_informative();
#if defined(__linux__)
    mappings_follow_live_allocations();
#endif
    aborts_saying(read_after_free, "linea: storage was used after it was freed\n");
    aborts_saying(write_after_free, "linea: storage was used after it was freed\n");
    for (int i = 0; i < 32; i += 1) aborts_saying(write_after_free_beside_allocation, "linea: storage was used after it was freed\n");
    aborts_saying(view_across_growth, "linea: storage was used after it was freed\n");
    aborts_saying(system_call_on_freed, "linea: storage was used after it was freed\n");
    aborts_saying(system_call_past_end, "linea: an access reached outside its storage\n");
    aborts_saying(system_call_before_start, "linea: an access reached outside its storage\n");
    aborts_saying(freed_twice, "linea: storage was freed twice\n");
    aborts_saying(freed_inside, "linea: a disposal named storage that is not allocated\n");
    aborts_saying(freed_short, "linea: a disposal named the wrong size: 8 bytes of a 16-byte allocation\n");
    aborts_saying(read_past_end, "linea: an access reached outside its storage\n");
    aborts_saying(store_in_rounding, "linea: a store reached outside its storage\n");
    aborts_saying(store_before_start, "linea: a store reached outside its storage\n");
    aborts_saying(many_live_then_twice, "linea: a disposal named storage that is not allocated\n");
    dies_by(wild_load, SIGSEGV);
#endif
    aborts_saying(over_aligned, "linea: the runtime cannot honour 16-byte alignment\n");
    aborts_saying(free_nothing, "linea: a disposal named no extent to release\n");
    aborts_saying(trap_overflow, "linea: integer overflow at t.lin:3:7\n");
    aborts_saying(panic_message, "linea: panic: boom at t.lin:1:2\n");
#if defined(LINEA_CHECK_STORAGE) && LINEA_CHECK_STORAGE
    puts("native runtime: checked allocation, arguments, environment and aborts passed");
#else
    puts("native runtime: allocation, arguments, environment and aborts passed");
#endif
    return 0;
}
