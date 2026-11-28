# 312. Array swizzles gather values and scatter distinct components

Status: Accepted — 2026-11-27.

## Context

Numeric arrays serve as mathematical vectors. Named component rearrangements
should preserve their ordinary storage, ownership and scalar semantics. A
selection such as `v.yx` is not a contiguous view of the original array.
Treating it as one would permit a callee to mutate the wrong memory.

## Decision

Numeric fixed arrays support one to four component letters from one of `xyzw`
or `rgba`. A single component selects the corresponding scalar place.
Multiple components gather a new fixed array; repeated components are valid
reads. Every selected component must exist.

Assignment scatters into distinct destination components. Snapshot the entire
right-hand side before evaluating the destination base, once each, and finish
all source reads before stores. Compound assignment follows the same ordering.
A gather cannot be borrowed or lent as a contiguous mutable place; an unmarked
`inout` argument may instead mutate its independent temporary.

Record component identities in typing. Ownership, alias checks and lowering
consume those identities. `v.x`, `v.r` and `v[0]` identify the same component;
disjoint component sets do not overlap. Existing borrow, mutability and scalar
bit-copy rules apply unchanged.

## Consequences

Rearrangements and swaps require no wrapper type or new ownership mechanism.
Scatter cannot overwrite an unread source component. At most four scalar
reads and writes implement a swizzle, independently of the source array size.
The retained typing row costs only actual numeric selections.

## Alternatives considered

**Make every swizzle a projection.** A contiguous pointer cannot describe an
arbitrary rearrangement, and an `inout` callee expects contiguous array storage.

**Allow repeated write destinations.** The result would depend on an arbitrary
store order. Rejecting repetition makes assignment unambiguous.

**Treat component names as record fields in alias checking.** Different names
can select the same array element. Names must resolve to component identities
before checking overlap.
