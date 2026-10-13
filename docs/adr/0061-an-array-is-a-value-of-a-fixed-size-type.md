# 61. An array is a value of a fixed-size type

Status: Accepted — 2026-08-02. Extended by
[0207](0207-linea-converts-nothing-implicitly.md),
[0118](0118-unobserved-array-initializers-are-omitted-during-lowering.md) and
[0137](0137-arrays-expose-checked-borrowed-slices.md). Length inference for
local bindings initialized with array literals is added by
[0149](0149-local-array-literals-infer-written-lengths.md) and extended to
constants by [0198](0198-array-literal-bindings-infer-written-lengths.md). Comparison, hashing and
formatting through the slice view are added by
[0166](0166-an-array-compares-through-its-slice-view.md). An array's `length()`
is added by [0172](0172-an-array-reports-its-length.md).

## Context

Linea has no references ([0025](0025-mutation-through-a-parameter-is-marked.md)),
so the first indexable thing it gains cannot be a pointer to a run of elements.
It has to be a *value* — something a binding holds, a parameter takes by a
convention, and a structure contains — with a size the type carries.

Three shapes were available for the first one. Only one of them can be written
in a language without references.

## Decision

**`[T; N]` is a type. A value of it holds `N` elements of `T` laid out
contiguously, and `N` is part of the type.**

`[u8; 4]` and `[u8; 5]` are different types. There is no coercion between them
and no way to write a type that stands for "some array of `T`" — that is a
slice, it needs a length that is not in the type, and reaching one without a
reference is what R4's `Vec` is for.

`N` is a **constant expression** in the sense
[0020](0020-a-constant-expression-is-defined.md) already defines: syntactically
determined, so whether a type is well-formed never depends on how much a
compiler manages to fold. This is the first place a constant expression appears
inside a *type*, and it needs no new notion of one.

An array's universe is **computed from its element**, exactly as a structure's
is ([0046](0046-the-universe-of-an-instantiation-is-computed.md)): `[Key; 4]` is
Linear because `Key` is, and `[UInt8; 4]` is Free. Nothing about the array
introduces an obligation; it carries the one its elements carry.

## Consequences

**An array is copied where a structure is copied, and moved where one is
moved.** It is an aggregate: it lives in a slot, it is reached by address, and
`copy` over one is a blit of `N × sizeof(T)` bytes. No pass learns a new kind of
value.

**A large `N` is a large value.** `[u8; 1_000_000]` is a megabyte in a frame,
and nothing here prevents writing one. That is the same exposure a large
structure already has, and it is bounded by the same thing: nothing, today. A
frame-size limit is a separate decision and is not taken here.

**There is no array literal shorthand for repetition** in this record — `[e; N]`
as an *expression* meaning "N copies of e" would duplicate a value implicitly,
which the language refuses outright for Linear elements and which
`copy` exists to make visible for Free ones. What R1 delivers is a listed
literal; a repetition form is deliberately open, below.

**Indexing is a separate decision** and is [0062](0062-an-indexed-place-is-a-place-and-every-index-is-checked.md).

## Alternatives considered

**A slice or pointer type first.** `[]T` reaching a run of elements is what
every systems language has, and it is what makes an array useful across a call
boundary without copying. Rejected because it *is* a reference — a value naming
storage it does not own — and 0025 removed those on purpose. Reaching interior
storage across a call is what the `read`/`inout` conventions do, and reaching an
*element* across one is what R3's projecting members will do. A slice is the
answer to a question this language answers differently.

**A length that is not part of the type.** `[T]` with the length beside the
value would let one function take arrays of any size. Rejected for R1 because
the length then has to travel — either in the value, which is a slice by another
name, or as a second parameter, which is a convention the compiler cannot check.
`Vec[T]` carries its own length and is the right home for that; it needs the
heap, which is R2.

**A built-in growable array.** Skipping fixed-size arrays and going straight to
`Vec` would reach the useful thing sooner. Rejected because `Vec` needs the
heap, an allocator, and `Index`, and each of those is a decision worth taking on
its own evidence. A fixed-size array needs none of them, and it is what makes
the indexing *surface* — the bracket, the check, the trap, the place — testable
before anything can allocate.

## Deliberately open

**A repetition literal, `[e; N]`.** Left out of R1, but expected back quickly:
`[0; 1024]` is a natural thing to write and listing a thousand zeroes is not.

The objection is that `[e; N]` duplicates, which `copy(p)` exists to make
visible. That objection is weaker than it first looks, because it depends on
what `e` may be. **The likely resolution is to require `e` to be a constant
expression** in [0020](0020-a-constant-expression-is-defined.md)'s existing
syntactic sense:

- a constant has no identity, so repeating one duplicates nothing — there is no
  place being copied and nothing for `copy` to have made visible;
- it cannot be Linear, because no constant expression produces a Linear value,
  so the awkward case is unwritable rather than diagnosed;
- it evaluates once by definition, so `[expensive(); 1000]` never arises and the
  "evaluate once or N times" question never has to be answered.

That serves the motivating case exactly and costs no new machinery. What it
does not serve is `[Key.new(); 4]` — four independent Linear values — and the
question that settles *that* is whether N evaluations of one expression is a
form the language wants at all, which is a question about evaluation and not
about arrays.

**A frame-size bound.** Nothing limits how large a local may be, here or
already. The question that settles it is whether a program is ever refused for
its stack usage rather than crashing at run time — which is a question about the
whole language and not about arrays.
