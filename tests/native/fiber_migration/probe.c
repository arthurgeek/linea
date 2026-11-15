#define _GNU_SOURCE
#define _DARWIN_C_SOURCE
#define LINEA_FIBER_MIGRATION_TEST 1
#define LINEA_FIBER_PAUSES 1
#undef NDEBUG
#include "runtime/fiber.c"
#include <assert.h>

#if !defined(__APPLE__) || !defined(__aarch64__) || __has_feature(address_sanitizer) || __has_feature(thread_sanitizer)
#error "the first generated-continuation proof requires unsanitized Darwin arm64"
#endif

/* This fixture replaces only the fiber object while linking the ordinary
 * runtime archive. The Linea body has no extern observation calls. */
static struct linea_fiber *observed_fiber;
static uintptr_t observed_task, observed_mapping;
static struct carrier *observed_carriers[3];
static unsigned entries, transfers;

void fiber_test_pause(enum linea_fiber_pause_point point) {
    assert(!linea_fiber_metadata_held());
    struct carrier *source = current_carrier();
    if (point == linea_fiber_entering) {
        struct linea_fiber *f = source->executing;
        lock_fiber(f);
        if (observed_fiber == NULL) {
            observed_fiber = f;
            observed_task = (uintptr_t)f->argument;
            observed_mapping = (uintptr_t)f->mapping;
            /* Only this fixture's closed-world generated entry is granted. */
            f->proven = 1;
        }
        assert(f == observed_fiber && (uintptr_t)f->argument == observed_task);
        assert((uintptr_t)f->mapping == observed_mapping);
        assert(f->context.sp >= (uintptr_t)f->stack);
        assert(f->context.sp <= (uintptr_t)f->stack + f->stack_bytes);
        if (entries < 3) observed_carriers[entries] = source;
        entries += 1;
        unlock_fiber(f);
    } else if (point == linea_fiber_transfer_ready) {
        assert(transfers < 2);
        struct transfer_claim claim = reserve_ready_runnable(source);
        assert(claim.fiber == observed_fiber);
        assert(source->loop->count == 2);
        struct carrier *target = source == &source->loop->carriers[0] ?
            &source->loop->carriers[1] : &source->loop->carriers[0];
        transfers += 1;
        assert(commit_transfer(&claim, target));
        /* No fiber access after destination publication. */
    }
}

__attribute__((destructor)) static void verify_handoff(void) {
    assert(observed_fiber != NULL && observed_task != 0 && entries >= 3 && transfers == 2);
    assert(observed_carriers[0] != observed_carriers[1]);
    assert(observed_carriers[0] == observed_carriers[2]);
}
