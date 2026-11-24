# 306. A `where` clause may equate two types

Status: Accepted — 2026-10-18. Extends
[0107](0107-a-trailing-where-predicate-constrains-any-open-type-expression.md)
and [0192](0192-iterator-operations-belong-to-every-sequence.md). Adds the rule
[T-Equal], and drops "type equality" from the [T-Where] sentence of
`docs/linea-semantics.md` that listed what the clause does not add.

## Context

`chain` joins two sequences whose items must be one type, and `unzip` takes
sequences whose item is a pair. Neither can be said today:

- `where B.Item == A.Item` does not parse. The predicate grammar is
  `type_name ":" bounds`, so `==` is `[S-Type]` "expected `:`", and the
  recovery abandons the whole declaration: one wrong predicate on
  `impl … for Chain[A, B]` produced eleven reports, among them `[N-Undefined]`
  for `A` and `Self` inside the body and `[T-For]` at the use.
- Without it, `Chain`'s `next` returning `&self.second.next()` is
  `[T-Mismatch]` "expected `Option[A.Item]`, found `Option[B.Item]`": two
  projections through different bounds are different stand-ins, and nothing
  relates them.

Two encodings work today and were probed: a trait over the item,
`trait Yields[T] { fn pull(inout self) -> Option[T] }` implemented for every
iterator, and a `Pair` trait with `First` and `Second` associated types. Each
makes the reader learn a trait whose only purpose is to state that two types
are the same, and each shows up in every signature and every `[T-Bound]`
report of the operations that use it.

## Decision

**A `where` predicate may equate two types: `where A == B`.** It sits in any
`where` clause that admits a bound predicate, beside bounds and contracts:

```
predicate ::= type_name ":" type_bound ("+" type_bound)*
            | type_name "==" type_name
```

`where X = Y` is `[S-Type]` with the help "write `==` to say two types are the
same", and the parser recovers at the next `,` or the clause's end, so one
malformed predicate is one report.

**Well-formed equalities.** Each side is a type in scope. At least one side is
a projection read through a bound in the declaration's set (`S.Iter.Item`,
`Self.Item`, `B.Item`), as [T-Where] already requires an open subject. An
equality between two plain type parameters, or between a parameter and a type
written without one, is `[T-Equal]`: the declaration has a parameter too many,
and the help says to write the one type for both. An equality whose sides could
never be one type is `[T-Equal]` at the predicate that makes it so: a
projection equated with a type containing it (`I.Item == Option[I.Item]`), or a
class (below) holding two different types that are not projections
(`I.Item == UInt8, I.Item == UInt16`).

**Inside the declaration, equal types are one type.** The equalities of a
declaration, together with those of the implementation that encloses a member,
form classes. Each class has one representative: its member that is not a
projection, when there is one; otherwise the right-hand side of the first
equality that formed the class. Every reading of a projection in a class, in
the signature and in the body, is the representative. So under
`where B.Item == A.Item`, `&self.second.next()` is an `Option[A.Item]`. Bounds
written on any member are bounds on the representative: `S.Iter.Item:
Discardable` with `S.Iter.Item == Self.Iter.Item` lets the body drop a
`Self.Iter.Item`. The relation is symmetric; which side is written first
changes only which name a diagnostic prints when neither side is a concrete
type.

**At a use, the two sides must settle to the same type.** Wherever the
declaration's parameters are settled (a call, a type's instantiation, a
provided operation read at its receiver's `Self`, an implementation chosen for
a key), both sides are read at that settling and must be one type. Otherwise
the use is `[T-Equal]`, naming both settled types and citing the clause, as
`[T-Bound]` cites a `where` clause today:

```
error[T-Equal]: `S.Iter.Item` must be the same type as `Self.Iter.Item`, and this call settles them to `Str` and `UInt64`
  --> receipt.lin:9:28
   |
 9 |     let lines = totals.chain(names)
   |                        ^^^^^ `chain` hands out the second sequence's items as the first's, so both must yield one type; `map` one of them to the other's item first
   ::: std/iter/iter.lin
   |         S.Iter.Item == Self.Iter.Item
   |         ----------------------------- required by this `where` clause
```

The per-operation sentence comes from a table beside the one ADR 0203
introduced for disposals, keyed by `Sequence`'s operations; any other callee
says that both sides must settle to one type. A value built by a use refused
this way is not refused again, for the same two types, where the body uses
it: walking, counting or asking for an item of the `Chain` that
`totals.chain(names)` built would otherwise report that its `Iterator`
implementation does not serve it.

**An equality settles what the call leaves open.** At a call, after the
receiver and the arguments have settled what they settle, a side that still
holds a type parameter of the callee is matched structurally against the other
side's settled type, and the parameters it holds are settled from it. So
`fn unzip[L, R](sink self) where Self.Iter.Item == (L, R)` settles `L` and `R`
from the receiver's items, and `pairs.map(f).unzip()` needs no annotation. A
settling the call's expected type also makes must agree, as any two settlings
of one parameter must. A parameter neither side can settle is `[T-Infer]`, as
today.

**Implementation selection.** An implementation's equality restricts the
instantiations it serves, as its bounds do (ADR 0107): a key whose sides differ
has no implementation there, reported as `[T-Equal]` through the clause,
whether the key is walked or one of the trait's operations is called on it. An
equality does not make two implementations disjoint, so
`impl … where I.Item == UInt8` beside `impl … where I.Item == UInt16` still
overlap (ADR 0148 stands).

**Defaults.** A type written with a parameter's default is filled before its
equalities are checked, and a default that contradicts one is `[T-Equal]` at
the use that took it. At a call, an equality settles a parameter as an
argument does, so a default fills only a parameter that neither the arguments
nor an equality settle: `fn first_of[I: Iterator, T = UInt64](…) where I.Item
== T` over a range of `UInt8` settles `T` to `UInt8`.

**Equalities are judged together.** Two equalities that make a projection hold
itself (`I.Item == Vec[J.Item], J.Item == I.Item`) are `[T-Equal]`, as one
alone is. So is a written side holding a projection another equality settles
(`I.Item == Option[J.Item], J.Item == UInt8`): the help names
`Option[UInt8]`, the type to write, rather than the compiler reading the
written side through a second class. An equality first seen to be malformed
once implementations have settled (`I.Iter.Item` reads as `I.Item` only then)
is refused then, once.

**A trait's own `where` clause equates nothing.** What each implementation
settles is checked where an operation needing it is written, so the equality
goes on that operation or on the implementation; one written on the trait is
`[T-Equal]`.

**What is not added.** No equality inside a bound list (`I: Iterator[Item = T]`),
no inequality, no equality on a trait's associated type declaration, no value
equality.

## Consequences

- `chain` is `where S.Iter.Item == Self.Iter.Item`, and `Chain`'s `Iterator`
  implementation is `where B.Item == A.Item`. `unzip` and `unzip_in` are
  `fn unzip[L, R] … where Self.Iter.Item == (L, R)`; like `collect`, each
  returns its two vectors with the iterator, and on a refused half a failure
  holding them, the pair that half came from, and the reason. Neither `Yields`
  nor `Pair` is introduced.
- `std.http`'s CGI reader walks any `Iterator` whose `Item == env.Entry`, and
  its private `CgiVariables` trait, which existed only to say that, is gone.
- One place reads a projection inside a declaration (`settledAtWithin`, which
  ADR 0192 made the one routine that settles a member for a key holding a
  parameter). It consults the owner's classes after it mints a stand-in, so
  every reader (signature types, bodies, bound subjects, capability
  requirements) sees the representative without a second normalisation pass.
  A body's readings reach it with the body's declaration as the owner: a
  call's result read through `Self`, a walk's item, and an implementation's
  settled type with its arguments substituted.
- The check at a use sits where `[T-Bound]` checks a `where` clause today,
  and the inference step sits in call inference, after receiver settling.
- Display: a type that a class answered prints as its representative. A
  `[T-Mismatch]` in a body that involves a class member adds a note naming
  the clause, so a reader who wrote `B.Item` sees why the message says
  `A.Item`.
- Tooling: the syntax node for a predicate gains its right-hand type; the
  formatter prints `A == B`; the tree-sitter grammar and its corpus, the
  relocation tables and the syntax dump follow. The dump prints an equality
  as written and changes no existing dump, since no case wrote one before.
- Cost: a declaration's classes are built once from its own predicates and
  held in a table keyed by declaration and sized by that declaration's
  equality predicates; a lookup scans that slice, which is bounded by the
  predicates written on the declaration and its enclosing implementation.
  Nothing is keyed or sized by the program.

## Alternatives considered

**A trait that carries the item, `Yields[T]`,** implemented for every iterator
(`impl[I: Iterator] Yields[I.Item] for I`). It compiles today and `chain` runs
with it. Each operation needing an equality would need such a trait, the
reader meets it in the signature, and a refusal is reported as an unmet
`Yields[UInt64]` bound rather than as two types that differ.

**A structural trait for pairs, `Pair { type First; type Second }`.** It works
for `unzip`, and only for `unzip`; the signature names
`Self.Iter.Item.First`, which a reader must decode.

**Rust's associated-type binding in the bound, `I: Iterator[Item = T]`.** It
covers projections only through the bound that declares them, cannot relate
two projections (`B.Item` and `A.Item`) without an extra parameter, and adds a
second grammar inside every bound list. A `where` predicate states both cases
in the clause that already holds constraints.

**Unification across the whole declaration, without classes.** Solving
equalities as general unification would let `(L, R) == (A, B)` settle
`L == A`; nothing in the library needs it, and refusing a class with two
distinct constructed types keeps the rule one sentence.
