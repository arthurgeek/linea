# 121. Typed storage is private and checked

Status: Accepted — 2026-09-08

The reference/address ABI and storage lifetime clauses are superseded by
[0123](0123-observations-carry-owner-dependencies-through-callable-contracts.md).

Extends [0076](0076-a-raw-access-is-a-declaration-lowering-replaces.md) and
[0088](0088-a-projecting-member-is-a-place-not-a-function.md).

## Context

Vec owns live values in an allocator's byte buffer. Linea can express growth,
shifting, failure ownership and release, but cannot express a generic typed
move into bytes or a lendable place within that allocation. A scalar load is
insufficient: returning an aggregate's source address would alias its storage,
and taking a Linear element through an index would leave an unmediated hole.

## Decision

The private `std.mem` operations `slot_stride`, `slot_take`, `slot_put` and
`slot_place` are compiler intrinsics identified by resolved standard-library
declarations. The checker records their identities once in
`Typing.raw_accesses`; instantiation discovery and lowering read that answer.
Their signatures are validated separately from the foreign ABI because they
never call foreign code. Ordinary extern restrictions remain in force.

A `SlotType[T]` witness supplies the type to stride through ordinary generic
inference. Take reads an owner and moves the concrete stored value into
independent result storage. Put receives an inout owner and consumes the value
it places. Their offsets and extents are bytes; the library computes element
offsets and maintains occupied slots. Stride is at least one byte. The private
declarations live in `std/mem/slots.lin`:

```linea
enum SlotType[phantom T] { Type }
extern fn slot_stride[T](read shape: SlotType[T]) -> UInt64
extern fn slot_take[T, R](read owner: R, at: UInt64, len: UInt64, i: UInt64) -> T
extern fn slot_put[T, R](inout owner: R, at: UInt64, len: UInt64, i: UInt64, sink v: T) -> ()
extern fn slot_place[T, R](read owner: R, at: UInt64, len: UInt64, live: UInt64, i: UInt64) -> T
```

`slot_place` is restricted to a projection's tail. Its arguments identify the
owning receiver, buffer address and extent, live count, and index. It is a
checked place, never an ordinary value-returning call or callable value. The
existing projection ceiling and root govern reads and inout lends. A source
index is evaluated once; the live-count check precedes access to backing bytes.
Ordinary computational projection bodies remain refused.

MIR's `storage_addr` records a concrete element `TypeId`, a managed-address
result role, and explicit overflow, bounds and alignment evidence. Its verifier
checks an extent of `max(layout.size, 1)` and alignment independently against the
concrete storage layout. Existing indirect accesses and aggregate copies operate
on the verified address. Raw scalar and typed accesses share address-check lowering.
The backend renders these instructions; it does not know Vec's representation
or decide its live-element invariant.

Every supported concrete layout has alignment at most eight bytes, and Buffer
allocations guarantee eight-byte base alignment. The checked offset alignment
therefore also establishes the element address's alignment. Supporting a layout
with greater alignment requires revisiting that allocation guarantee; changing
the layout table alone would not preserve this storage contract.

The library owns all container policy: allocator selection, checked geometric
growth, element movement order, gap closing, length updates, failure payloads
and terminal calls. No compiler pass recognizes push, remove or release as a
container operation.

## Consequences

The ownership checker proves the vector root's obligations; the private library
implementation maintains which slots contain values. Region dependencies travel
through owner-carrying primitive calls, using the same call rules as other
operations. Mutating calls may not introduce a different region into a binding.

`Vec[T, A]` retains a Free allocator handle of concrete type `A`, alongside
`Buffer[A]` and its live length. Its phantom element parameter imposes no
Release bound. `open`, the inherent operations and the conditional Release
implementation require `A: Allocator + Free`; the Index implementation needs
only `A: Allocator`. Push returns `Result[(), PushFailure[T]]`, whose public
`reason: Oom` and `value: T` fields carry the failure and rejected value; a named
Linea struct expresses the pair without adding tuples. Conditional Release
visits remaining elements in reverse index order and then disposes storage.
Removal plus `finish_empty` provides the
other consuming path, without choosing an element's terminal policy.

## Alternatives considered

Adding Vec operations to the compiler would duplicate ordinary library policy
and make each container change a compiler change. Generic typed loads returning
references would require a new lifetime-bearing language value. General
computational projections would add a broader control-flow construct. Public
raw typed storage would expose the occupied-slot invariant outside its reviewed
module. None is required by contiguous owning storage.
