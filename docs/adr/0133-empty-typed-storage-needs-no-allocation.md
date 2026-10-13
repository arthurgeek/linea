# 133. Empty typed storage needs no allocation

Status: Accepted — 2026-09-14

Supersedes the mandatory backing-buffer shape of
[0123](0123-observations-carry-owner-dependencies-through-callable-contracts.md).
Its logical element containment and dependency-preservation rules remain in
force. Extends [0098](0098-a-container-names-its-allocator-in-its-type.md).

## Context

An empty vector needs an allocator for future growth but no element storage.
Requiring a buffer makes empty construction fallible and forces iterator
collection to expose a separate failure before it can examine the source.
That allocation carries no initialized value and adds an unnecessary resource
obligation to empty construction.

## Decision

Private, move-only `Storage[T, A]` has exactly these fields in this order:

```linea
buffer: Option[Buffer[A]],
allocator: A,
at: UInt64,
len: UInt64,
```

The type checker certifies this shape and continues to account for logical
out-of-line `T` contents. Hidden element dependencies survive extraction and
reconstruction of the optional backing owner. The library maintains occupancy
and keeps the flat address and byte extent consistent with that owner. An
unallocated value has no buffer and zero address and extent. Checked typed
accesses retain their bounds, overflow and alignment checks.

`Allocator` requires `Copyable`, allowing empty storage to retain its allocator
and growth to obtain another handle without consuming the container's handle.
Allocator observations remain live even before the first buffer exists.

`Vec.open` returns `Vec[T, A]` directly; `String.open` returns `String[A]`
directly. Both are allocation-free. First growth acquires storage; a refused
push returns its rejected item and preserves the initialized prefix. Empty
storage release performs no allocator disposal. `Allocator.acquire(0)` still
requests an ordinary `Buffer`; its allocation contract is unchanged.

The internal `vector_into_buffer` transfer returns `Option[Buffer[A]]`.
Consumers preserve absence rather than allocate a substitute buffer.

## Consequences

Empty iterator collection succeeds without allocation. Collection has one
failure record containing its vector, advanced iterator and `PushFailure`.
The next-then-push loop yields an item before allocation can fail; a first-push
failure therefore recovers that item rather than promising an untouched source.
No item or callback is replayed or implicitly settled.

Storage carries an optional-owner tag and a separate allocator alongside flat
address fields. The library must keep these fields consistent; the compiler
checks the representation shape, not each allocation transition. Slot access
continues to use the flat address and extent without unpacking the owner.

## Alternatives considered

Keeping fallible empty constructors would preserve an allocation with no
storage purpose and an unnecessary collection failure variant. Making zero-byte
`Buffer` allocation special would change a separate explicit allocation API.
Deriving the allocator only from a present buffer cannot support first growth
without allocating at construction. Unpacking optional ownership at every slot
access would spread empty-state handling through element operations; the flat
address and extent preserve their existing checked interface.
