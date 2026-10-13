# 103. Linear constrains consumption; Release grants one way to consume

Status: Accepted — 2026-09-08

Extended by [0124](0124-copyability-and-settlement-are-independent-capabilities.md).

Extends [0104](0104-release-is-optional-and-never-scheduled.md) with the
deferred container decisions. ADR 0104 supersedes
[0097](0097-release-is-named-never-scheduled.md) and extends
[0063](0063-disposal-is-scheduled-never-inserted.md); their active decisions
stand unchanged.

Extended by [0138](0138-hash-maps-preserve-entry-ownership.md) for hash-map key and ownership contracts.

## Context

ADR 0097 introduced an ordinary `Release` trait so a `Vec[T]` could release
elements through a bound. It made the trait total over every type to give every
vector one release implementation.

That totality conflates two properties. A Linear value must be consumed exactly
once, but the type may deliberately require a caller to choose among terminal
operations. A transaction may be committed or rolled back. A promise may be
fulfilled with a value or cancelled with a reason. Neither has one
context-free terminal action, and choosing one as `release` weakens the
protocol the type exists to enforce.

An owning container does not make that choice disappear. `Vec[Transaction]` is
a meaningful owner even though it cannot decide how each transaction ends. It
can transfer its elements to its caller, which then performs the terminal
operations their types provide.

## Decision

**`Linear` constrains consumption; `Release` grants one particular way to
consume. Neither implies the other.**

`Release` is an optional ordinary trait:

```linea
pub trait Release {
    fn release(sink self: Self) -> ()
}
```

The trait is declared in the dedicated `std.release` module and is not part of
the prelude. It does not live under memory because a context-free terminal
fallback need not release memory. It does not live under Linear because Free
types may implement it and Linear types may omit it. No syntax requires every
program to name it, so modules write `import std.release` and
`use release.Release` through the ordinary library mechanism.

A type implements it when one context-free terminal disposition is valid for
every value. A type whose terminal transition requires a policy choice or
additional context does not implement it. A Linear type without `Release` is
well formed, and implementing `Release` does not make a type Linear.

`Arena[H]` implements `Release` because it carries the backing handle needed to
return its slab. The trait member contains that operation directly and is the
Arena's sole public terminal operation. There is no inherent `Arena.close` and
no private forwarding helper. Linea is unreleased, so existing call sites are
migrated rather than preserved through a compatibility alias.

The compiler attaches no universe meaning to the trait. It checks its
implementations, bounds, and calls through ordinary trait machinery. It keeps
no `TypeId -> Release` table and inserts no invocation.

Capabilities constrain the operations that need them, not storage that does
not. `Vec` therefore declares an unrestricted element parameter and places the
bound on its conditional implementation:

```linea
impl[T: Release, A: Allocator] Release for Vec[T, A] {
    fn release(sink self: Self) -> ()
}
```

This operation releases each remaining element in reverse index order and then
disposes the backing storage. The order is this library operation's contract,
not a language-wide aggregate release order.

`Vec[T, A]` remains valid where `T` has no `Release`. It provides consuming
operations that transfer element obligations outward. `remove` transfers one
element and closes the gap. `finish_empty` consumes an empty vector and disposes
its backing storage; when elements remain, it returns the still-owned vector
unchanged:

```linea
fn remove(inout self: Self, i: UInt64) -> Option[T]
fn finish_empty(sink self: Self) -> Result[(), Self]
```

Returning `Self` on failure preserves the obligation the unsuccessful operation
could not discharge.

`defer tx.rollback()` and `commit(tx)` are ordinary consuming calls. ADR 0063
places the written rollback and ownership cancels it on the path where commit
moves the transaction. The compiler does not select either operation.

Free types are not required to implement `Release`. Whether primitive or
prelude types provide trivial implementations is library policy, not a
consequence of their universe.

## Consequences

The absence of `Release` is meaningful API design. `Transaction` and `Promise`
can restrict callers to terminal operations carrying the policy or context the
transition needs.

A Linear container need not have one operation that destroys it and everything
inside it. Where elements lack a context-free fallback, the container must
transfer them before its backing storage can be disposed.

Generic bounds stay local. `T: Release` appears on an implementation or
operation that calls release, never on `Vec[T, A]` merely because it stores a
`T`.

Derived release remains possible, but only where a declaration asks to derive
the optional capability and every part supplies it. Linearity alone never asks
for derivation.

Manual release implementations execute their written order. Structural field
order remains Rung 3's decision; this record settles only the reverse-index
contract of `Vec.release`.

Ownership, MIR, and the backend gain no mechanism. Ownership sees consuming
positions and written schedules. Lowering sees ordinary calls, including Unit
results and `sink` arguments, through the existing computation and storage
representations.

## Alternatives considered

**Require `Release` for every Linear type.** Rejected because it gives every
protocol a context-free terminal escape, even where selecting the terminal
transition is what the protocol requires its caller to decide.

**Bound the `Vec` declaration by `T: Release`.** Rejected because storage does
not call release. It would prohibit `Vec[Transaction]` and `Vec[Promise]` even
though removal and draining can transfer every obligation without losing one.

**Synthesize release for Linear aggregates.** Rejected for this rung because
structure cannot choose a transaction policy or supply a promise's terminal
context. Derivation remains a requested capability in Rung 3, not a consequence
of the Linear universe.

**Let `finish_empty` consume a nonempty vector and return only an error.**
Rejected because the error would report an outstanding obligation while
returning no owner for the elements or backing storage. Failure returns `Self`.

**Declare `Release` in `std.mem`.** Rejected because the capability does not
say that its operation releases memory. Memory-backed owners may implement it,
but so may any type with one context-free terminal fallback.

**Declare `Release` in `std.lifecycle`.** Rejected because the library has no
broader lifecycle abstraction. An umbrella module would promise a category of
capabilities where only one has been designed.

**Declare `Release` in `std.linear` or `std.linearity`.** Rejected because the
module path would imply the relation this record separates. Free types may
implement `Release`, and Linear types may omit it.

**Keep `Arena.close` public beside `Release.release`.** Rejected because the two
names would perform one transition and expose no distinct capability. Existing
source does not justify a compatibility alias in an unreleased language.

**Keep `Arena.close` private and forward `Release.release` to it.** Rejected
because no second caller needs the helper. The trait implementation can own the
slab-return operation directly.
