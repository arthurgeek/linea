Run without a GPU or Vulkan loader:

```sh
nix develop --command zig build test-gpu-runtime
```

Only Vulkan headers and the existing ordinary runtime archive are required.
The native build uses production C99 warnings and trapping instrumentation. It compiles
one executable; `main.c` includes the actual `runtime/gpu.c`. Typed Vulkan
functions are substituted through its dynamic-loader boundary. Narrow wrappers
inject CPU allocation, device mutex initialization, pthread attribute and
completion-thread creation failures. The actual archive supplies park, fiber,
task and session implementations unchanged.

The isolated cases check:

- A standard platform Vulkan loader with the build-host path absent; a
  build-pinned fallback only when the standard loader cannot be opened; no
  fallback after an opened loader fails symbol validation.
- Every dynamic symbol lookup and discovery result call; each discovery CPU
  allocation; missing/unsuitable devices and compute queues; device mutexes.
- Buffer creation, allocation, bind and mapping failures. Failed output handles
  are poisoned, so publishing a failed constructor's output fails immediately.
- Arena physical caps, rounded memory requirements, aligned view ranges and
  zero-byte descriptors. Recoverable preferred-block host/device allocation
  failures retry the exact extent; a failed retry publishes no arena state.
  Device loss, other API errors and invalid extents do not trigger a retry.
- Shader, descriptor layout, pipeline layout, pipeline, descriptor pool/set,
  command pool/buffer, begin/end, fence and QueueSubmit failures. Pipeline error
  outputs include both null and a valid partial pipeline needing destruction.
- Submission allocation, pthread attribute and completion-thread failures;
  restored host access after failed submission; transfer errors; device loss.
- Synchronous upload/download bit copies, zero-byte and out-of-bounds access;
  failed invalidation leaves the destination unchanged. Whole-mapping flush
  and invalidation ranges are checked, together with host-write/compute-read,
  compute-write/compute-read and compute-write/host-read barrier masks and order.
- Map/reduction count and initial-bit narrowing, every matrix dimension even
  in otherwise empty shapes, and each matrix dimension-product overflow.
- Pending map/reduction/matmul resources, including aliased left/right operands
  and owners dropped before completion. Resource registries reject duplicate,
  poisoned or premature destruction. Pool-owned objects are accounted for when
  their pool is destroyed.

Fresh state is installed only after authoritative cleanup: all GPU handles,
tracked CPU allocations, device mutexes, attributes and loader ownership have
settled. This also covers QueueSubmit failure returning before its detached
completion worker has finished.

The carrier test opens one real `linea_loop_open(1)`. A GPU-awaiting task
publishes that it is about to call real `linea_gpu_wait`; only then does main
queue the CPU task. Fake WaitForFences cannot complete until that CPU task
signals its condition. Both callbacks assert the same loop identity and OS
carrier thread. Thus CPU progress requires the awaiting task to release its
carrier. Both task handles are joined and every GPU owner is settled. The loop
itself is process-lifetime, as defined by the runtime API.

The arena teardown test holds command-pool destruction after fence completion.
Reset and release each run on a real single-carrier loop and must stay parked
until another task on that carrier opens the gate. Before that task opens it,
it checks that the arena is draining, its pending pins and view metadata remain
intact, and its cursor and committed bytes have not changed. Same-arena native
allocation/submission return Busy, while a second arena on the same device can
allocate. After reset or release returns, the retained public job has no buffer
pins; it is settled only after the arena metadata is released. These native
Busy checks do not add a source operation: public borrowing still forbids reset
or release across a live arena observation.

Review replays checked the corresponding pre-gate assertions with isolated
premature-rewind, cursor-reuse and partial-pin-detachment mutants. Production
source was left unchanged by these negative-control runs. The harness does not force every
cross-arena fence-completion order or simultaneous resets of one owner, and the
host-copy race uses system buffers rather than claiming a reset/host-copy race
through invalidated arena handles.

Arena-specific repeated-input tests assert occurrence-based accounting: a zip
reading the same view twice holds two input pins, one output pin and three
arena pending occurrences. Completion must clear every occurrence and all job
view references before reset/reuse. A two-arena test uses individually gated
fences: one cross-arena job completes while a repeated-input job in the other
arena remains blocked. Both arena orderings are exercised. The completed arena
can reset, allocate and release while the other retains exactly its own three
pins; both arenas outlive the original device handle. This proves those two
controlled orders, not every cross-arena schedule.

Indeterminate fence timeout and host-allocation failure also run in isolated
arena subprocesses. The fake driver keeps queued resources pending for those
answers. A test-only wrapper observes the actual production abort boundary in
ordinary thread context, checks unchanged arena view metadata/cursor, all three
pins, live job references and the pending fence, then calls real abort. The
parent requires SIGABRT, so neither an ordinary error return nor successful
settlement/reuse is accepted. Isolated production-source mutants that deduplicate
an alias pin, omit an alias detach, rewind before abort, treat indeterminate
completion as success, or miss cross-arena detach fail the corresponding
permanent assertions. These mutants never replace production source.

Synchronization uses predicates and condition variables, with ten-second
operation deadlines and a native thirty-second watchdog. There are no arbitrary
sleeps. The watchdog also bounds unexpected joins or constructor deadlocks.

Build integration is provided by `build/gpu_fault.zig`:

```zig
const faults = @import("build/gpu_fault.zig").add(
    b,
    ordinary_runtime_archive, // std.Build.LazyPath
    vulkan_headers_root,     // []const u8
    runtime_flags.items,
);
// Attach faults to the ordinary test graph. It also names test-gpu-runtime.
```

This tests host failure/lifetime behavior and pending-completion scheduling.
The fake driver does not execute shader instructions, validate SPIR-V or prove
numerical GPU behavior. It does not replace or fault-inject the park/task/fiber
implementations, and does not exhaustively search thread interleavings.
No ASan or TSan result is claimed.
