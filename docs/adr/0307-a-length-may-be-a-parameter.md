# 307. A length may be a parameter: `let n: UInt64`

Status: Accepted — 2026-11-10. Extends
[0061](0061-an-array-is-a-value-of-a-fixed-size-type.md),
[0083](0083-an-arrays-length-is-part-of-its-type-everywhere-it-is-written.md),
[0181](0181-a-call-may-name-its-type-arguments.md) and
[0189](0189-a-names-case-is-part-of-its-kind.md); supersedes the
compiler-supplied view rows of
[0166](0166-an-array-compares-through-its-slice-view.md).

## Context

An array's length is part of its type
([0061](0061-an-array-is-a-value-of-a-fixed-size-type.md),
[0083](0083-an-arrays-length-is-part-of-its-type-everywhere-it-is-written.md)),
and it had to be a constant written where the type is. A function could be
generic over an array's element but not over its count, so code over arrays
fixed the count or took a `mem.Slice[T]`:

- `examples/cash_register.lin` took `[T; 3]`.
- `std/net/scripted.lin` made every caller pad a script to exactly four
  entries.
- Twenty callers of the release log wrote
  `log.holds([UInt64(10)].as_slice())`.
- A form filler over `[Field; N]`, needed by a guest-book demo, could not be
  written.

ADR 0083 left open whether a length is a parameter an implementation can bind.
[0166](0166-an-array-compares-through-its-slice-view.md) rejected a library
implementation for `[T; _]` because "the body would need arrays of a symbolic
length in the type system", and had the compiler supply `Equatable`,
`Equivalent`, `Comparable`, `Ordered`, `Hash` and `Debug` for every array
through its slice view instead.

In the type pool an array was `{ element: TypeId, count: u32 }`, and
substitution moved only the element. Every argument channel carries
`[]const TypeId`: type arguments, instance keys, inference vectors, selection
keys and implementation arguments.

## Decision

**A generic parameter list may declare a length parameter, `let n: UInt64`.**
Structs, enums, aliases, functions and implementations may declare one; a
trait may not. The name is lowercase, because a length parameter is read as a
value and ADR 0189 makes a value's name lowercase. The type is written and
must be `UInt64`, the type of `length()` and of an index. Any other type, and a
length parameter on a trait, is [T-LengthParameter].

**A length position holds a constant expression or a length parameter in
scope.** `[T; n]` may appear in parameter, result, field, payload, alias and
local types, and as a generic argument (`Ring[T, n]`). An expression that
computes with a parameter is [T-ArraySize], and so is a local initialised from
`n`. In a value position `n` is a `UInt64` holding the instance's length. It is
not a constant expression, as `T.max` is not while `T` is symbolic.

**A length is settled like a type parameter.** It is inferred by matching
parameter and result types against arguments and the expected type, at any
depth. It may also be written by position in the bracket list beside type
arguments: `total[3]`, `Ring[UInt8, 16]`. An argument that starts with a
lowercase name or a number is a length; the case rule makes that exact. A type
where a length is declared, or a length where a type is declared, is
[T-Bound]. Two positions settling different lengths are [T-Mismatch].

**A length parameter can have a constant default.** `struct Ring[T, let n: UInt64 = 16]` lets a written type omit the
trailing length, under the rules a type parameter's default follows
([T-ArgumentDefault]). A function uses its default when its call leaves the
length unsettled. A struct or enum may declare a phantom length.
`phantom let n: UInt64` declares a length no field
mentions, under [T-Phantom]; a function's length parameter cannot be phantom.

**A generic body is checked once, for every length, zero included.** An index
into a `[T; n]` is checked when the program runs, even where its value is
known, and so is a range place: `xs[0..2]` over a `[T; n]` is a `[T; 2]` that
traps when two elements do not fit. An array literal cannot initialise a
`[T; n]` ([T-ArrayLength]); `mem.filled[T: Copyable, let n: UInt64](value: T)
-> [T; n]` builds one. Ownership treats a symbolic count as possibly nonzero
and as more than one element.

**In the type pool, a length is a `TypeId`.** A concrete length is an interned
`.length { value }` entry. A length parameter is a `.parameter` marked as a
length. An array is `{ element, length: TypeId }`. Substitution, inference,
instance keys, symbols and relocation carry lengths in the channels that
already carry types. `Typing.arrayCount` is the one answer to "what is this
array's count", and returns null for a symbolic length. A length is not a type,
and a position expecting a type refuses one ([N-NotAType], [T-Bound]).

**An array may head an implementation in the trait's own module.** The array
constructor belongs to no module, so only the module declaring the trait may
write `impl[T: Equatable, let n: UInt64] Equatable for [T; n]`, as for a
callable type. `std.cmp` implements `Equatable`, `Equivalent`, `Comparable`
and `Ordered` for arrays this way, `std.hash` implements `Hash` and `std.fmt`
implements `Debug`. The compiler no longer supplies these six through the
slice view, and the machinery that did is deleted. `Index` stays
compiler-supplied: direct indexing and its checks are the language's.

**Arithmetic in a length is an open question.** `[T; n + 1]` is refused today.
Admitting it needs one normal form for length expressions shared by inference
and the overlap check, a growth measure so [T-PolyRec] still bounds instance
discovery, and a way to state the lower bound subtraction needs (`n - 1` is
ill-formed at zero). None of these is decided.

## Consequences

- Functions, structs and aliases over arrays of any length can be written. The
  examples above take `[T; n]`, and their callers drop the padding and the
  `.as_slice()` conversions.
- Derived implementations of a struct with a length parameter copy
  `let n: UInt64` into their parameter list, and ADR 0165's field requirements
  reduce `[T; n]: Equatable` to `T: Equatable` through the library's array
  implementation.
- Substitution's array special case ("the length is written down and
  substitution cannot touch it") is gone; arrays substitute like every
  constructor. Inference, header binding and matching compare lengths as
  `TypeId`s or bind them as parameters.
- Instance discovery needs no new termination measure. Without arithmetic a
  length argument is a parameter passed through or a constant from the source,
  so the lengths a program reaches are finite and written.
- Cost:
  - The binary holds one instance per distinct length reached. A body called
    at fifty lengths is emitted fifty times. The guide says when to take
    `mem.Slice[T]` instead.
  - Compile time adds one interned `TypeId` per distinct length. Layout and
    symbol spelling are O(1) and O(digits) in the length, and no pass walks an
    array's elements one at a time.
- The compiler-supplied `Index` rows keep a witness type and skip the header's
  length: they have no declaration to own parameters, and every array reaches
  them whatever its length.
- `Release` for arrays stays absent, for the reason 0166 gives.
- A length argument above 4294967295 is [T-ArraySize].

## Alternatives considered

**A compile-time value parameter in the ordinary parameter list.** This is how
Zig writes `comptime n: usize`. A later parameter's type would depend on an
earlier argument's value, so checking a call would evaluate arguments, and
named arguments, which evaluate in declaration order (ADR 0077), would have to
set the compile-time ones apart. The body would be checked per value, which
ADR 0047 rejects: a generic body is checked once.

**`const n: usize`**, as Rust writes it. This adds a reserved word for one
position. `let` already declares constants, and Swift's integer generic
parameters use it in the same place.

**The kind chosen by case alone, `[T, n: UInt64]`.** This reads as `n` bounded
by `UInt64`, and it needs the parser to choose a production by case. The habit
of the other languages, `N: UInt64`, would parse as a type parameter bounded by
an unknown trait.

**Inference only, with a binder in the type (`[T; let n]`, or `[T; _]` in a
signature).** There would be no name to write at an explicit instantiation, in
a struct's list or in an `impl` head. `_` already means "count this literal"
([0149](0149-local-array-literals-infer-written-lengths.md),
[0198](0198-array-literal-bindings-infer-written-lengths.md)).

**Arithmetic in types decided now.** Type equality would need a normaliser and
a solver shared by inference, coherence and implementation matching
([0048](0048-one-question-has-one-answer.md)); `[T; n - 1]` needs either a
value predicate `where` does not have or an error at instantiation, which ADR
0047 forbids; and `f[n]` calling `f[n + 1]` would be invisible to
[T-PolyRec]'s height measure. Rust's `generic_const_exprs` has remained
unstable over the first two. The base feature does not depend on any of it.

**Represent a symbolic count inside `Type.array` as a union of `u32` and a
parameter index, and carry lengths beside the type arguments.** Every argument
seam would need a second channel: inference, instance keys, closure keys,
selection keys, implementation arguments, symbols and relocation. As a
`TypeId`, a length rides in the existing one.

**Keep the six viewed rows compiler-supplied once array heads exist.** Two
mechanisms would then answer whether an array implements `Equatable`, and the
compiler would carry rows that exist only because library code could not be
written ([0048](0048-one-question-has-one-answer.md)).

**Move `Index` into the library too.** Direct indexing, its projection plans
and compile-time bounds checks are defined for arrays by the language; a
library `Index` for arrays would be a second answer to which element `xs[i]`
names.

**A repeat literal `[value; n]`** instead of `mem.filled`. It reads like the
array type in expression position, which the bracket's double reading would
have to tell apart, for an operation a library function names plainly.
