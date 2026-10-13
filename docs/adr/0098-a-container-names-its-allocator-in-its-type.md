# 98. A container names its allocator in its type

Status: Accepted — 2026-08-20

Extended by [0133](0133-empty-typed-storage-needs-no-allocation.md),
[0173](0173-a-capturing-closure-is-erased-into-allocator-owned-storage.md),
[0191](0191-the-caller-chooses-every-allocator.md) and
[0206](0206-allocator-spelling-is-shortened-by-alias-never-by-default.md),
which records that the allocator is shortened by an alias and never by a
default type argument.

## Context

The first-version bar, the target set for the first public version, leaves
the container step an open question:

> Whether the allocator is a second type parameter or rides in the value.

It has to be answered before `Vec` is designed, because `Vec` grows, growing
allocates, and so the allocator is part of `Vec`'s design whether or not it
appears in `Vec`'s type.
[0095](0095-the-system-allocator-is-named-rather-than-received.md) left it
open deliberately: with one facility there was nothing to abstract over.

There are three shapes, and one of them is unavailable here.

## Decision

**An allocator is a trait, and a container that allocates names it as a type
parameter.**

```linea
Vec[T, A: Allocator]
```

Monomorphised like any other bound. `Vec[File, System]` and `Vec[File, Pages]`
are different types, and a function written over both is generic in `A`.

### Why not a closed enum

A tagged union of the allocators the library knows about --
`Allocator { System, Pages }` -- gives one `Vec[T]` type and dispatches on the
tag with no indirection. It also makes the standard library the owner of the
universe of allocators.

That is the wrong contract. An arena is not another implementation detail of
`std.mem`: it is exactly the allocator a program should be able to define for
itself. Under the enum, that is not a thing the language could later permit --
the abstraction would mean *one of the allocators Linea already knows* rather
than *anything that can allocate*, and no amount of later work reopens it.

Extensibility foreclosed that way is not recoverable. The ergonomic cost of the
type parameter is.

The trait does not deliver that extensibility today, and this record should not
be read as claiming it does. `Buffer` is `opaque`, so only `std.mem` can build
the `Buffer[Self]` an implementation must answer with, and the tag is not
convertible, so one cannot be obtained by wrapping another allocator. So
implementations are `std.mem`'s for now. What the trait buys here is that the
question stays open: a representation can change, a closed enum's contract
cannot.

### Why not an allocator value behind an interface

The shape C++ retreated to. `std::pmr` demotes the allocator from a template
parameter to a runtime-polymorphic `memory_resource*` stored in the container,
which restores one container type and keeps the set of allocators open.

It is unavailable here, and not by preference.
[0047](0047-instantiation-is-a-backend-concern.md) rejects erasure because
*"[0028](0028-a-type-is-a-pool-handle-and-layout-is-a-table.md) makes a type's
layout a table the module carries, and an erased `Cell[T]` has no layout to put
in it. A systems language that made every generic container indirect would be
paying for a feature its users would then avoid."* An allocator behind a
pointer is that feature. The escape other languages use is closed by the layout
model.

### The cost, accepted rather than argued away

Allocator choice becomes part of container identity, so `A` propagates through
the signature of anything generic over a container:

```linea
fn consume[T, A: Allocator](sink v: Vec[T, A]) -> ()
```

This is the defect the field has documented. It is what motivated `std::pmr`,
and Rust's `allocator_api` has sat unstable since 2019 with the refinement that
would escape it postponed since 2020.

Linea accepts it, for three reasons. The alternative forecloses user-defined
allocators permanently. The escape hatch those languages reach for is
unavailable. And the tax is smaller here than the citations suggest: **the
parameter is inferred at call sites**, so a caller writes `consume(v)` and one
generic function accepts every instantiation. What is paid is a parameter on
generic *declarations* that manipulate containers, not an annotation at every
use.

### What the type parameter buys

The allocator is not incidental once there is more than one. A `Vec` released
through `System` and one released through `Pages` return their storage by
different means, and with the allocator in the type the compiler sees which:

```
Release for Vec[T, A]
       |
   A's release
```

statically, monomorphised, with no dispatch. Under a value-held allocator that
same abstraction needs the runtime dispatch 0047 refuses.

## Consequences

**`Buffer` is affected and this record does not settle how.** It is the thing
`Vec` allocates through, and whether it becomes `Buffer[A]`, stays concrete, or
is replaced by something typed is the allocator trait's own design.

**`Vec` cannot be designed before the trait's operations are.** What `Allocator`
declares -- allocate, release, whether growth is a member or built from the
other two -- is undesigned, and `Vec`'s API rests on it.

**Two implementations are wanted as evidence, not as a precondition for
designing the trait.** That bar asks for `System` and `Pages` *"so the
interface is designed against evidence rather than against one caller"*. That
is a validation requirement on the trait, and it does not require `Pages` to be
finished before `Vec` is specified.

## Alternatives considered

**Design `Vec[T]` over the concrete `SystemAllocator` now, generalise later.**
Smaller, and it reaches the release-and-elements machinery -- what rung 2 is
judged on -- soonest. Rejected because the later change is not mechanical: it
alters the identity of every `Vec`, every signature naming one, construction,
growth, release, and the goldens. It would also make `Vec` the experiment that
silently decides the question this record exists to answer.

**Leave it open until `Vec` forces it.** What the bar did, and correct
when it was written. It is no longer correct: the answer determines `Vec`'s
type, so `Vec` cannot be specified around it.

## What this does not decide

The trait's operations. `Pages` and its runtime contract. The growth policy,
which [0064](0064-heap-memory-is-a-linear-value-from-an-explicit-allocator.md)
left open on purpose. Whether an arena fits this shape at all -- an arena owns
storage its allocations point into, which is
[0069](0069-a-view-is-a-value-rooted-at-a-place.md)'s question and still
Proposed.

**How a program writes an allocator of its own.** Choosing a type parameter
keeps that reachable; it does not make it reachable yet, and nothing here
decides how storage would be obtained or tagged. It does not weaken `Buffer`'s
`opaque` representation, and it adds no way to mint one from an address a
caller holds.
