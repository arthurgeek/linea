# 191. The caller chooses every allocator, a test instrument's included

Status: Accepted — 2026-09-28. Extends
[0095](0095-the-system-allocator-is-named-rather-than-received.md) and
[0098](0098-a-container-names-its-allocator-in-its-type.md). Its clause that
every allocating API takes its allocator from its caller is superseded by
[0220](0220-a-function-that-allocates-pairs-a-system-form-with-an-in-form.md).

## Context

[0095](0095-the-system-allocator-is-named-rather-than-received.md) makes
allocation explicit at the operation: the call names the allocator it uses.
[0098](0098-a-container-names-its-allocator-in-its-type.md) makes an
allocating container generic in that allocator, so the same `Vec` runs over
the system allocator or an arena. The standard library's containers, readers,
JSON documents, logger and server follow both.

Three of the library's own test instruments did not:

- `testing.Recorder.of(a: SystemAllocator, bytes)` accepted only the system
  allocator, so no test could record output into an arena.
- `mem.AllocationLog.open(refuse_at)` acquired its own words from
  `mem.system()`, and `mem.RefusingAllocator` forwarded every acquisition it
  accepted to `mem.system()`. A failure walk could therefore never run over an
  arena, although an arena is what a request handler, a parser under limits
  and every arena-backed container actually allocate from.
- `testing.each_allocation_failure(body)` opened those logs itself, so it
  inherited the same hidden choice.

These are public (`std.testing` re-exports the log and the allocator) and
sit in non-test library code. [0171](0171-the-standard-library-is-an-ordinary-library.md)
makes `std` an ordinary library, so it gets no exemption a user library would
not: an API that allocates and picks the allocator itself is the same defect
in either.

## Decision

**Every standard-library API that allocates takes its allocator from its
caller, and works with any `Allocator`, including an arena handle. A test
instrument is no exception.**

```linea
@(opaque, derive(Release))
struct Recorder[A: Allocator] { ... }

impl[A: Allocator] Recorder[A] {
    pub fn of(allocator: A, bytes: UInt64) -> Result[Recorder[A], Oom] where carries(.Ok: allocator)
}

@(opaque, linear)
struct AllocationLog[H: Allocator] { buffer: Buffer[H], backing: H }

impl[H: Allocator] AllocationLog[H] {
    pub fn open(backing: H, refuse_at: UInt64) -> Result[AllocationLog[H], Oom] where carries(.Ok: backing)
    pub fn allocator(self: Self) -> RefusingAllocator[H] where borrows(self)
}

@(opaque, copyable)
struct RefusingAllocator[H: Allocator] { log: borrow AllocationLog[H] }

pub fn each_allocation_failure[H: Allocator, E: Discardable, F: inout fn(allocator: RefusingAllocator[H]) -> Result[(), E], R: inout fn(error: E) -> Bool](backing: H, sink body: F, sink is_refusal: R) -> Result[UInt64, Failure]

pub fn refused(said: Str) -> Failure
impl Failure { pub fn is_refusal(self: Self) -> Bool }
pub fn oom_is_a_refusal(error: Oom) -> Bool
```

The log keeps its backing and reaches it through the borrow every
`RefusingAllocator` already holds: `acquire` forwards to the backing, and
`dispose` rebuilds a `Buffer[H]` with the backing's own obligation
(`RefusingAllocation[H]` carries `H.Obligation`) and releases it there.

**`AllocationLog.open` returns `Result`**, as the library's allocating
constructors do, because a backing the caller chose can refuse the log's own
words. `each_allocation_failure` answers such a refusal with a
`Failure` naming it, not a panic.

**A walk checks what a refused run answers, not only what it settles.** A
refused run may complete, when the refused allocation was optional, or return
an error the caller's `is_refusal` accepts. Any other error fails the walk and
names the attempt, so a body's assertions hold in every run, not only in the
run with nothing refused. The caller states what a refusal is with a
predicate over the body's own error. Each error type a walk returns answers
that once, with an `is_refusal` method beside its declaration that is not
public API (`mem.Oom.is_refusal`, `LineError.is_refusal`,
`FsFailure.is_refusal`, true only for the variant or primary error that
carries an allocation refusal), and every walk inside the library passes the
method. A caller outside the library cannot name those methods, so
`testing` offers the public counterpart for the one error type a user body
commonly returns: `testing.oom_is_a_refusal` takes only `mem.Oom` and
answers with `mem`'s own classification. It takes no other type, so an
asserting body cannot pass it and have its assertions bind only the
unrefused run. A body that asserts returns `testing.Failure`, reports its refusal
with `testing.refused(...)` and passes `testing.Failure.is_refusal`. The unrefused run must attempt at least one
allocation, and the walk returns the attempts it made, so a walk of an
operation whose only allocations are scratch pins that count and notices
scratch taken from anywhere else.

`mem.system()` stays the ordinary choice in tests; what changes is that the
test says so.

## Consequences

**A failure walk can run over an arena.** An arena's `dispose` reclaims
nothing, so each run's log (8240 bytes) and allocations stay in the arena until
it is released or rewound: a walk over an arena needs an arena sized for every
run. The tests beside `each_allocation_failure` and `AllocationLog.open` state
that size.

**Spelled types gain an argument.** A test that names the allocator's type
writes `RefusingAllocator[mem.SystemAllocator]`; a lambda handed to
`each_allocation_failure` leaves its parameter type to inference from
`backing`. `Recorder.of(mem.system(), n)` is unchanged at the call, and
`Recorder`'s derived `Release` is now generic in `A`.

**Every direct `AllocationLog.open` in a test ends in `.unwrap()`.** That is
the cost of the `Result`; a test that wants to report the refusal matches it
instead.

**The survey rule is mechanical.** Outside `test fn` blocks, `mem.system()`
and `SystemAllocator` appear only in the system allocator's own declaration,
in documentation examples that are themselves callers, and in non-`pub`
helpers that only tests call.

## Alternatives considered

**Keep `open(refuse_at) -> AllocationLog` and panic when the backing refuses
the log.** It avoids an `.unwrap()` at each direct test use, and the log
already panics when its capacity is exceeded. Rejected because it makes the
one allocating constructor in the library that panics on refusal. Capacity
exhaustion is a misuse of the instrument by the test; a backing's refusal is
an ordinary answer from an allocator the caller chose, and a small arena is
exactly where a caller would expect to see it.

**Defer the refusal, as `Arena.open` does.** An arena whose slab was refused
still opens and refuses every later acquisition, which suits an arena: nothing
distinguishes its refusals from ordinary exhaustion. Rejected for the log
because a log without words cannot count attempts: the backing's refusal
would surface only as a walk reporting that its body attempted no
allocation, which names the wrong cause.

**Open the log's words from the system allocator and forward only the
recorded allocations to the backing.** The log would stay infallible and a
walk could still exercise an arena. Rejected because it keeps the hidden
choice this record removes, in a smaller form: `open` would still allocate
from an allocator nobody passed it.

**Exempt test instruments.** They exist for tests, and tests may name
`mem.system()`. Rejected because the exemption is about who calls, and the
instruments are public library API that user tests call too. A user testing an
arena-backed container needs the walk over an arena, which the exemption
denies.

**A convenience constructor over the system allocator** (`open_system(n)`,
or `each_allocation_failure` without a backing). Rejected: it is a second
spelling of one operation whose only content is the hidden choice, and
[0095](0095-the-system-allocator-is-named-rather-than-received.md) already
makes naming the system allocator one call.

**A `testing.Refusal` trait bounding the body's error**, with `Oom` always a
refusal, each library error a refusal in its `Allocation` variant, and a
`Failure` built by `testing.refused`. It needs no argument at the call.
Rejected because the trait would have to be public, and so would every
implementation of it: `testing` cannot hold those implementations, since
every module imports it, so `collections`, `io`, `fs`, `json`, `http` and the
rest would each publish a test instrument's vocabulary on their error types.
A predicate needs only a method each module keeps to itself, or to the
library for `Oom`, `PushFailure` and `ReadAllError`, which other modules walk.
The cost is that a walk may pass a predicate too broad for its error type,
which a trait bound would rule out; naming one method per type keeps that to
one place to read.

**Accept any error from a refused run.** Rejected because a body's
assertions would bind only the unrefused run: a refused run whose answer is
wrong, such as a 503 lost to a reset, would pass as a refusal.

**Erase the backing behind a closure so `RefusingAllocator` keeps no type
parameter.** It would leave spelled types unchanged. Rejected because erasure
allocates storage for the closure
([0173](0173-a-capturing-closure-is-erased-into-allocator-owned-storage.md))
and dispatches indirectly on every acquisition, to save an argument in a type
that inference usually supplies.
