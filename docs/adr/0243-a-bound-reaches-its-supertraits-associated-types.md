# 243. A bound reaches the associated types its supertraits declare

Status: Accepted — 2026-10-18. Extends
[0187](0187-a-bound-brings-its-traits-operations-into-reach.md), which brought
a supertrait's operations into reach of a bound, to the types those
operations are written in. Changes the [T-Where] sentence of
`docs/linea-semantics.md` that read "Resolving an associated name requires a
declaring bound in that set".

## Context

`trait DoubleEnded: Iterator { fn next_back(inout self: Self) -> Option[Self.Item] }`
is the natural declaration of a reversible iterator. Before this record it was
refused, and so was any use of it:

```
error[T-Impl]: `Countdown` declares no `Item`
  --> p5.lin:28:51
   |
28 | fn first_of[I: Countdown](sink it: I) -> Option[I.Item] where carries(.Some: it), I: Discardable {
   |                                                   ^^^^ declare it on the trait, or name one it declares
```

The same report appeared for `Self.Item` inside the subtrait and inside an
implementation of it. A supertrait already brings its operations into reach
(ADR 0187: `it.next()` works under `I: Countdown`), so a bound reached the
supertrait's operations but not the types those operations are written in. No
trait in the standard library inherits one with an associated type today
(`Settle: Release`, `Close: Release`, `Key: Hash` and `Decode[A]: Release`
inherit none), which is why nothing had needed it.

## Decision

**An associated name read through a bound resolves in the bound's trait and,
when that trait does not declare it, in its supertraits, transitively.** The
resolved member is the supertrait's: `I.Item` under `I: DoubleEnded` is the
key (`Iterator`, `Item`, `I`), the same one `I: Iterator` reads, so the two
bounds name one type and no equality is needed between them. The supertrait is
read at the arguments the requirement chain gives it: under
`trait Fancy: Lookup[UInt64]`, `T.Elem` with `T: Fancy` is `Lookup[UInt64]`'s
`Elem`.

Inside a trait, and inside an implementation of it, `Self.Item` resolves the
same way through the trait's own supertrait list. In an implementation the
type is settled by the supertrait's implementation for the same type: `impl
DoubleEnded for Up` settles no `Item`, and its `Self.Item` is what `impl
Iterator for Up` settled.

The search stops at the nearest declaration on each supertrait path. Which
declarations count:

- **One trait reached twice is one declaration.** `trait Window: Countdown +
  Sized`, with both requiring `Iterator`, reaches `Iterator`'s `Item` along two
  paths, and `I.Item` under `I: Window` is that one type. So is `I: Countdown
  + Iterator`.
- **Two traits declaring the name is [N-Ambiguous]**, as two bounds declaring
  it already were. Under `trait Both: Left + Right`, where `Left` and `Right`
  each declare `Item`, `T.Item` with `T: Both` and `Self.Item` inside `Both`
  name neither. The language has no qualification that picks one, so the edit
  the report suggests is the one that works today: read the name through a
  parameter bounded by one of them alone, `fn from_left[T: Left](t: T) ->
  T.Item`, which a `T: Both` value satisfies.
- **One supertrait required at two argument lists is [N-Ambiguous]** for the
  same reason: `T: Fancy + Lookup[Text]` holds two implementations of `Lookup`,
  each settling its own `Elem`.
- **A subtrait declaring the name itself answers first.** It is a different
  declaration that nothing equates with the supertrait's; reading through the
  subtrait reaches its own.

A name no trait on the closure declares keeps the report it had, naming the
trait the bound wrote: "`Countdown` declares no `Size`". A name a supertrait
declares as an operation is refused by naming that supertrait: "`Iterator`
declares `next` as an operation".

## Consequences

- `std.iter` can declare `DoubleEnded: Iterator`, and `rev`, `fold_right` and
  the `DoubleEnded` implementations of the adapters read `I.Item` under one
  bound.
- `resolve.traitDeclaringMember` is the one rule for which declaration a name
  reaches through a trait; the resolver's selection and the checker's
  `boundDeclaring`, `Self` reading and refusals all call it, and the type is
  settled through `Builder.settledAtWithin` as every other settled reference
  is.
- An implementation of a subtrait whose supertrait is not implemented is
  already refused by [T-Bound] ("`Countdown` requires `Iterator`, and `Up`
  does not implement it"); its `Self.Item` then settles to nothing and adds no
  second report.
- Cost: resolving a name not declared by the bound's trait walks that trait's
  supertrait closure, which is declared and short, once per written reference;
  nothing is sized by the program.

## Alternatives considered

**A trait over the item, `Backward[T]`, bounded as `I: Iterator +
Backward[I.Item]`.** It compiles and runs, but every signature and every
`[T-Bound]` report then shows the encoding, and the reader has to know why
`Backward` takes the item its own `Iterator` bound already fixes.

**A type equality predicate instead.** `trait DoubleEnded[T] { … }` with
`where Self: Iterator, Self.Item == T` would need a parameter that only
restates `Item`, and the equality could not be written at all until the
subtrait can name `Self.Item`, which is this record's question.

**Restate the associated type in the subtrait.** `trait DoubleEnded: Iterator
{ type Item }` declares a second `Item` that nothing equates with the first,
and the language has no equality predicate to do it.

**Pick one declaration in a diamond by declaration order.** The first
supertrait written would decide, so reordering `Left + Right` would change
what `T.Item` means with no report. Ambiguity costs one helper function, and a
qualification syntax can be added when a program needs to read both.
