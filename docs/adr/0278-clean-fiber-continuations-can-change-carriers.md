# 278. Clean fiber continuations can change carriers

Status: Accepted — 2026-11-17. Supersedes 0265's fixed-carrier execution
requirement in §7; implements its proposed phases 6 and 7. Final platform
regression results and measurements remain implementation acceptance gates.

## Context

A loop's idle carrier cannot help a busy carrier's runnable backlog when every
fiber is permanently assigned to its first carrier. Moving a saved continuation
requires more than saving registers: native calls can leave thread-local state,
and a completed wait can still have references owned by its original poller.
`Owned`, `Shareable` and `Isolated` do not prove the absence of these dependencies.

The same lifetime boundary governs Linux completion I/O. A deadline can request
cancellation, but cannot return a lent buffer while the kernel can still use it.

## Decision

### Execution eligibility and affinity

A complete compiled executable marks canonical compiled task bodies whose
execution paths use native-entry guards. Object-only output and unproven entry
pointers receive no eligibility by linking a runtime later. Internal native
contracts live in the compiler's runtime-symbol registry; no manifest field,
audit sidecar, validation file or runtime configuration grants permission.

Unknown native execution binds the actual current fiber to its executing
carrier before native effects. The restriction is monotonic until retirement,
including effects reached through indirect calls, callbacks and release paths.
Instrumentation preserves native error state. System-thread tasks have no fiber
restriction. Active foreign frames prohibit fiber switching even on one carrier.
Returning from native code does not undo a restriction.

Migration safety applies to the whole continuation: generated cleanup, native
effects, logical task state and saved runtime frames. Audited operations may
remain neutral only when their complete paths preserve that invariant. Unknown
scheduler callbacks cannot infer an executing fiber and remain ineligible.

A foreign resource requiring one OS thread stays in an explicitly selected
system-thread owner, using 0265 §9's restricted-client pattern. Holding a client
does not bind its caller. Carrier observations establish neither resource
ownership nor a permission to transfer an arbitrary foreign handle.

### Exclusive scheduling and source retirement

One loop metadata mutex protects actionable queue membership, carrier assignment,
claims and notification publication. Existing source locks precede it; the
scheduler does not acquire source locks while holding it. A notification has one
publication path. A transfer cannot independently advance a second fiber state
machine or create a second runnable entry.

Only saved, nonexecuting Runnable contexts without foreign restrictions or live
source claims can transfer. The source retires carrier-specific timers,
registrations and references before publishing transfer readiness. Logical wait
cleanup may resume with the fiber where it does not depend on the old carrier.
An operation's original poller identity never changes, even if its retired
continuation transfers repeatedly before dispatch. Publication and acquisition
under the mutex order saved-context writes before the destination reads them.

Carriers keep local and clean stealable queues. An idle carrier scans a bounded
number of rotating victims and claims clean work without requiring the source
to execute again. Untouched eligible contexts can also be stolen before first
execution. Local and stealable work both receive dispatch opportunities; peers
are awakened when new clean work becomes available. Completion is published only
after execution and protected scheduler references retire, before join reclaims
the stack.

Logical task state and ABI execution state follow the fiber. Carrier TLS,
signal masks, thread-directed pending signals and alternate signal stacks remain
with their OS thread. Dispatch installs the destination's current-fiber lookup;
guard records and sanitizer fiber-switch state follow the runtime protocol.
Supported migration backends are Darwin arm64 without sanitizers, and Linux
arm64/x86-64 including ASan and TSan. Other variants retain pinned execution.

### Linux completion ownership

Each Linux carrier attempts one direct-kernel io_uring setup and opcode probe.
Unavailable or denied rings retain readiness execution. Slots use generation
cookies rather than kernel-held fiber pointers. Exhausted generations are not
reused; unsigned ring counters wrap deliberately. Eventfd joins CQ readiness to
the existing poller. Only the owning carrier consumes its completions.

The backend submits socket reads, writes and accepts. Connect readiness watches
an already-started nonblocking handshake, then uses the shared socket-error
settlement path. Shared native socket preparation and descriptor cleanup apply
to both backends. Unsupported operations or capacity shortages fall back only
when no kernel reference can survive.

A published request owns its operation and buffer until its original CQE and
all submitted cancellation controls retire. Partial submission and interrupted
enter calls retain ownership. Deadline expiry requests asynchronous cancellation;
it does not complete the Linea operation. A real result such as bytes or an
accepted descriptor wins a concurrent expiry. Timeout is reported only after
the original completion confirms cancellation and every kernel reference has
retired. Late generation cookies cannot dereference reclaimed fiber storage.

## Consequences

Idle carriers can execute new and already-started eligible work. Native affinity
and borrowed-buffer lifetime remain conservative. The mutex, wakeups and
migration can add contention and damage cache locality; matched pinned,
placement-only, forced-transfer and stealing controls measure those costs.
Eligibility and refusal populations come from separate untimed companion
invocations of the same workloads and controls. They are reported separately,
and do not claim to describe every interleaving of an uninstrumented trial.
Work stealing cannot interrupt running code that never yields or rescue a
carrier blocked inside arbitrary native code.

Unknown harmless native calls can permanently reduce eligibility. No public
neutrality assertion, compiler-inserted preemption, stalled-carrier monitor,
automatic blocking offload or reusable blocking executor is introduced.

## Alternatives considered

**Steal only unstarted tasks.** Useful placement, but cannot rebalance work after
it starts. Both new-work and saved-continuation regressions are required.

**Infer safety from zero foreign depth or ownership traits.** Neither accounts
for persistent thread-local native effects.

**Lock-free stealing first.** Adds reclamation and ordering complexity before
establishing a correctness reference. The single-mutex protocol is deliberate.

**Return on cancellation submission.** The kernel may still access the buffer.
Only retirement of all submitted references permits return or migration.
