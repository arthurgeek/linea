# 186. A type reaches the operations of the traits it implements

Status: Accepted — 2026-09-27. Extends
[0160](0160-a-postfix-call-reaches-the-types-own-operation-first.md), whose
`Reach` now answers a call written after a type's name as well as a postfix
call. Replaces the rule of the generics design
that a
trait's operation is reached through the trait and never through the type.
Extended by
[0187](0187-a-bound-brings-its-traits-operations-into-reach.md).

## Context

A trait's operation had exactly two spellings: through the trait,
`Default.default()`, and, where its first parameter takes `Self`, the postfix
form `x.op()`. The type's own name reached only what the type's `impl` blocks
declared, so `Limits.default()`, `Money.from(1250)`, `UInt16.parse("8080")`
and `T.default()` under `T: Default` were all refused, the first three as
[N-Undefined] with the help "a trait's operation is reached through the
trait".

The rule was chosen so that adding an implementation could never change what
`Account.` means. The cost showed once `Default` entered the prelude
([ADR 0179](0179-the-prelude-holds-the-core-vocabulary-and-yields-to-a-module.md))
and structure literals took a base
([ADR 0183](0183-a-structure-literal-may-take-its-other-fields-from-a-base.md)):
`Limits { connections = 4, ..Default.default() }` names the trait at the one
place a reader wants the type, and a constructor with no argument, such as
`default()` or `parse(text)`, has no postfix form at all. Inside a generic
body `T.default()` is what a reader writes first and it did not compile. The
decision was to allow the spelling Rust uses, `Limits::default()`, written
with Linea's dot.

The postfix form already answered the question this raises. ADR 0160
settled which operation `x.op()` runs when the type and a trait both declare
the name, and which is ambiguous when two traits do, in one routine, `Reach`,
read through `NameReach.reaches`. A second lookup for `Type.op()` would be a
second reading of that rule.

## Decision

**A name written after a type's name reaches, where the type's own namespace
does not hold it, the operation of a trait in scope that the type implements.**
`Limits.default()` is `Default.default()` with `Self` settled to `Limits`;
`Money.from(1250)` is `From.from(1250)` at `Self = Money`; `UInt16.parse(text)`
is `Parse.parse(text)` at `Self = UInt16`. The type names `Self`, so no
argument or expectation has to.

**The type's own operation comes first, where the call may take it.** A type
that declares `default` itself reaches its own through `Tank.default()`, and
`Default`'s through `Default.default()`. The own operation is admitted by the
rule the postfix form holds it to, less the receiver: it must be one this
module may name under [M-Vis]. A private `close` declared in another module
does not stand in the way of `Shut.close`, so `door.Door.close(d)` reaches the
trait's as `d.close()` does, and is refused for the privacy of the own
operation only where no trait answers. An enum's variants and the type's
constants are settled by the resolver as before; a name is never both.
[N-Shadowed] keeps its meaning.

**One routine decides.** `Reach.namespaced` enumerates the type's own
operations, then the operations of the traits the call's module sees that the
type implements, whatever their first parameter takes, and
`NameReach.reaches` picks the one that runs:

- the type's own operation answers, and the call runs it;
- one trait answers, and the call runs its operation;
- two or more traits answer, and the name is [N-Ambiguous], naming each trait
  and writing each spelling, `Starter.blank(…)` and `Empty.blank(…)`, or
  `Starter.blank` where the name is not called;
- none answers, and the call is [N-Undefined], naming a trait in scope that
  declares the name as the one to implement, or [T-UnknownOperation], naming
  the `use` that brings a trait out of scope that would answer.

**A type parameter reaches what its bounds promise.** `T.default()` under
`T: Default` is `Default.default()` at `Self = T`, through the same routine:
a bound is the evidence `Reach` already reads for a postfix call on a value of
type `T`. A parameter whose bounds declare no such operation is
[T-UnknownField], as before.

**The selection is also a function value.** `Crate.default` without a call is
`Default.default` with `Self` fixed, so `restock(3, Crate.default)` passes a
`fn() -> Crate`.

**A generic type is instantiated by what the call is expected to produce.**
`let empty: Option[UInt8] = Option.default()` settles `Option[UInt8]` first and
then asks which traits it implements. A generic type named where nothing
expects an instantiation is refused as a template, as any other use of one is.

**A literal argument takes the type the one implementation names.** A trait
parameter an argument stands at, which no argument that decides its own type
and no expectation settled, is taken from `Self`'s implementation of the
trait when there is exactly one. `Money.from(1250)` converts from the one
integer type `Money` implements `From` for, where the literal alone would have
been the default integer. The count is over every implementation for `Self`'s
head and every bound on it, and an implementation whose trait arguments
`Self` leaves open counts as many; where several answer, the literal takes its
default type as before. The rule is the call's, not the spelling's, so it
holds for `x.op(1)` and `Trait.op(x, 1)` as for `Type.op(x, 1)`. A parameter
no argument stands at is not filled this way, so a trait parameter written
only in the result still needs an expectation.

The resolver records a selection it leaves to the checker in a side table,
`Resolution.trait_selections`: a name after a type parameter, or after a type
whose namespace holds it as nothing but an operation, or not at all, and
whose name some trait in the program declares. A name no trait declares is
settled or refused by the resolver as before.

## Consequences

- `..Limits.default()`, `Money.from(cents)` and `T.default()` read as the
  type they build. The prelude's `Default` and `From` are written through the
  type throughout the examples and the standard library.
- The import hazard [N-Ambiguous] exists to report, which the postfix form
  already carries, reaches this form too: importing a trait that declares an
  operation of the same name for the type makes an existing `Type.op()`
  ambiguous, and the call is then written through the trait. A trait being
  imported can never change which operation runs silently, and it can never
  displace the type's own operation, which is settled before any trait is
  asked. That is the hazard ADR 0160 accepted for the postfix form, and it is
  accepted here on the same terms.
- Adding an implementation can now change what `Account.` offers, though not
  what any name the type declares means. An editor offers the implemented
  trait operations after `Account.`, from `Reach.namespaced`.
- The two forms differ in one clause only: the written form passes no
  receiver, so `Door.close(3)` reaches `fn close(code: UInt8)` where
  `door.close()` does not. Privacy is held the same way in both, as Rust holds
  it: rustc sets an inaccessible inherent item aside in path and method
  lookup alike. Rust also sets aside an inherent block that does not apply
  to the instantiation; the written form here does not, because it names a
  type, and a generic type named with no expected instantiation has none to
  hold the block to.
- Adding a second implementation can change which body a literal argument
  picks: with only `impl Scale[UInt8]`, `m.scaled(2)` runs the `UInt8` body,
  and adding `impl Scale[Int64]` makes the literal fall back to `Int64` and
  run the new one, with no diagnostic. Rust's integer-variable fallback has
  the same property. An accepted program cannot otherwise change meaning:
  acceptance before this record required the default type's implementation
  to exist, and a sole implementation is then that one.
- A type written with its arguments, `Option[UInt8].default()`, is not a
  qualifier: brackets after a type's name in an expression still index it.
  Rust's `Option::<u8>::default()` has no spelling yet; the expected type or
  an annotation says which instantiation is meant.
- Brackets after the name hold the operation's own type arguments,
  `Crate.packed[UInt8](7)`, and never `Self`, which the type before the dot
  settles.
- A call written through a type costs one lookup of the traits the module sees
  under the name and one applicability question per such trait, which is
  the postfix form's cost; the resolver's decision to defer is one hash
  lookup of the name among trait operations.

## Alternatives considered

**Keep the rule.** It protects `Account.` from implementations, and nothing
else: an import already changes what `x.op()` reaches, and nobody has
reported that as a hazard since [N-Ambiguous] makes it loud. It costs every
constructor without a receiver its natural spelling, and it made `T.default()`
unwritable in the generic code that most wants it.

**The trait's operation wins over the type's own.** Then implementing
`Default` for a type that declares `default` would change what `Tank.default()`
runs, which is the silent change [N-Ambiguous] and ADR 0160 exist to prevent.

**A separate lookup for the written form.** The resolver could have searched
implementations by the type's name. That would be a second reading of which
traits are in scope and which a type implements, beside the one the postfix
form uses, and it could not answer for a type parameter, whose evidence is its
bounds rather than an implementation.

**Refuse a literal at a trait parameter several implementations answer.**
That removes the silent switch when an implementation is added, and refuses
`m.scaled(2)` beside `Scale[UInt8]` and `Scale[Int64]`, which compiled before
this record and chose `Int64`. Refusing a program that ran is the larger cost,
and it would still leave the one-implementation case to decide.

**Settle a trait parameter from the one implementation everywhere.** That
would also settle a parameter written only in a signature's result, which a
call is refused for so that no body is picked by nothing
([T-Bound]). The literal is the case this record needs, so the rule reaches
only a parameter an argument waits on.
