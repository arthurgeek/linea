# 166. An array compares, hashes and prints through its slice view

Status: Accepted — 2026-09-24

Extends [0061](0061-an-array-is-a-value-of-a-fixed-size-type.md) and
[0137](0137-arrays-expose-checked-borrowed-slices.md).

## Context

`[UInt8; 4]` implemented no `Equatable`, `Debug` or `Hash`, so `a == b` on two
arrays was refused, `{a:?}` printed nothing, and a struct holding an array
field could derive none of those traits. `net.Address` holds its octets in
`[UInt8; 4]` and wrote `Equatable` and `Debug` by hand, and tests compared
arrays one element at a time.

Array syntax cannot form a source implementation head: an array's length is
part of its type and no implementation can be generic over it. The compiler
already supplies `Index` for the array constructor for that reason.

The operations themselves are ordinary library algorithms. `Debug` writes
through a generic `Writer` and propagates its error; `Hash` feeds the library's
`Hasher`. Written once in Linea, they are checked, tested and read like any
other library code.

## Decision

**The compiler implements `Equatable`, `Equivalent`, `Comparable`, `Ordered`,
`Hash` and `Debug` for every array through its `mem.Slice` view.** The standard
library implements each for `Slice[T]` where `T` does. An array row applies
exactly where its view's implementation applies, which is decided by the one
lookup that decides every implementation, so the two cannot disagree.

Selecting such a row selects the view's implementation. The recorded choice
keeps the array as the receiver the call is typed with, names the view as the
type the implementation runs for, and a call passes the view of each
whole-`Self` argument: the address of the array's elements and its length, with
no copy. Comparisons, explicit trait calls, generic bodies and interpolation all
read that one recorded choice.

The slice implementations define the behaviour: equality compares lengths and
then elements in index order; `less` orders by the first element pair that
differs, stops at an incomparable pair as a derived structure does, and puts a
prefix first; `Hash` covers the length and each element's hash in order; `Debug`
writes `[1, 2, 3]`.

`Release` is not supplied. Releasing a view settles none of its elements, so an
array of elements that need settling would be released without settling them.

## Consequences

- `a == b`, `a < b`, `{a:?}` and `Hash.hash(a)` work on arrays whose element
  type supports them, and so do generic bounds such as `T: Equatable` at
  `T = [UInt8; 4]`.
- A struct or enum with an array field derives `Equatable`, `Equivalent`,
  `Comparable`, `Ordered`, `Hash` and `Debug`. Its derived `Release` discards
  an array of discardable elements, as ADR 0165 decides for any discardable
  component without `Release`; an array of elements that must be settled, such
  as `[Vec[UInt8, A]; 2]`, still has no `Release`, and a type holding one
  writes its release by hand.
- `Slice[T]` compares, orders, hashes and prints by content in its own right.
- Cost: each distinct array element type selected through a view mints one
  `Slice[T]` instance and records one more selection, so the work is linear in
  the array types a program uses. A call adds two instructions per viewed
  argument to build the view.

## Open question

An element-by-element `Release` for arrays whose elements implement it would
let `[Vec[UInt8, A]; 2]` release. It needs a consuming walk lowered by the
compiler, since the view cannot release what it observes. Nothing in the
library needs it yet.

## Alternatives considered

**Lower each operation directly in the compiler.** An element loop calling the
element's implementation serves equality, but `Debug` needs writer calls and
error propagation and `Hash` needs the library's hasher. The compiler would
carry a second copy of each library algorithm.

**Allow implementation heads over arrays of any length**, such as
`impl[T: Equatable] Equatable for [T; _]`. The body would need arrays of a
symbolic length in the type system: indexing, iteration and layout over a
length no instantiation has settled. That is a type-system feature of its own.

**Forward every trait whose receivers are whole `read` parameters through the
view**, as observations forward through `borrow T`. Arrays would then implement
any library or program trait implemented for `Slice`, which makes a closed set
of compiler-provided array implementations open-ended, and the sealed type pool
would need an index from each array type to its view for lookups made after
checking. The listed traits are the ones structural derivation needs.

**Supply `Release` through the view as well.** Rejected because the view's
release discards only the view; a consuming element-by-element release would
need its own lowering.
