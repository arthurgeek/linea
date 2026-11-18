# 286. Tests allocate through `testing.TestAllocator` and `testing.SharedTestAllocator`

Status: Accepted — 2026-11-18. Supersedes the instrument
[0191](0191-the-caller-chooses-every-allocator.md) declares,
`AllocationLog.open(backing, refuse_at)` with its `allocator()` handing out a
`RefusingAllocator[H]`; 0191's decision that the caller chooses the
instrument's backing allocator stands.

## Context

A test that walked allocation failures used one of two instruments with four
public names, `AllocationLog` with `RefusingAllocator`, and
`SharedAllocationLog` with `SharedRefusingAllocator`, declared in `mem` and
re-exported by `testing`. Both took `refuse_at: UInt64`, where 0 meant "refuse
nothing", so every test that only counted wrote a sentinel. Neither checked
anything when it was released, so a test that forgot `all_disposed()` could
leave a live allocation unnoticed. The sequential log kept one flag word per
acquisition in a buffer of fixed size and panicked past 1,024 acquisitions;
the shared log kept a `Vec[Bool]` that grows in its owning task and refused
the acquisition it could not record, which a walk would read as the refusal
it was testing.

The flags existed to tell a buffer disposed twice. A buffer carries its
allocator's obligation, which is linear: only `acquire` makes one, and the
type system lets it be settled once. A buffer cannot be disposed twice in a
program the compiler accepts, so the counts alone answer whether everything
was disposed: as many disposals as acquisitions and no bytes live.

## Decision

- **`testing.TestAllocator[H]`** counts through its `handle()`, a
  `testing.TestHandle[H]`, and is `@unshareable`.
  **`testing.SharedTestAllocator[H]`** keeps the same counts in an owning task;
  its `testing.SharedTestHandle[H]` is `Shareable` when `H` is. Sharing is a
  property of a type, so the two stay two types; neither is chosen by a flag.
- **`open(backing, fail_at: Option[UInt64] = .None)`**: a test that only
  counts writes `open(backing)`, and one that injects a failure writes
  `fail_at: .Some(n)`, counting from one; `.Some(0)` stops the program, as
  there is no acquisition 0. `fail_at(.Some(n))` and `fail_at(.None)` change
  it later; the shared one also has `fail_from`, `fail_size_at` and
  `fail_size_from`.
- **Releasing either checks `all_disposed()`** and stops the program when an
  allocation it handed out is still live.
- **No record per allocation, so no cap.** Each handle's buffer carries its
  backing's own obligation, and the counts are acquisitions, disposals, live
  and peak bytes.
- Both are declared in `mem`, because they build and take apart buffers of
  their backing and write their counts through the raw stores `mem` declares
  privately, and `testing` re-exports them. The raw-access tables name their
  members, as they named the logs'.

## Consequences

- Every test in the library, the examples, the guide and the corpus migrates:
  `open(backing, 0)` becomes `open(backing)`, `open(backing, n)` becomes
  `open(backing, fail_at: .Some(n))`, `allocator()` becomes `handle()`, and
  `refuse_*` becomes `fail_*`.
- A test may make any number of allocations; one makes two thousand.
- The shared instrument no longer allocates per acquisition, so a refusal a
  walk observes is always the one it asked for.
- A buffer disposed twice would no longer be named by the instrument. Only a
  compiler defect could produce one; the checking runtime reports a double
  free of system storage.

## Alternatives considered

**One generic type with a runtime switch for sharing.** `Shareable` is decided
by a type's structure, so a flag cannot make some values of one type
shareable.

**Grow the sequential record in storage of the backing.** It keeps a check
the obligation already makes, at the cost of a second buffer kept in typed
slots and grown through a `read`, and a growth failure that has no honest
answer: refusing the acquisition looks like the injected failure.
