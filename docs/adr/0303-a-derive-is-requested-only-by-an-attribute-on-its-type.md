# 303. A derive is requested only by an attribute on its type

Status: Accepted — 2026-11-21. Supersedes the standalone-derive clauses of
[0145](0145-closed-attributes-attach-ordinary-derive-requests.md) ("Standalone
derive remains the form for an implementation whose constraints differ from
the type declaration's", "Standalone derive syntax remains accepted for
independently constrained requests", the recommendation of a standalone
derive in its Consequences, and the rejected alternative "Replace standalone
derive entirely"), the clause of
[0165](0165-an-attached-derive-requires-each-field-type.md) "The standalone
form is unchanged … it remains the form for bounds other than the field
types'", the derive-binder clauses of
[0142](0142-construction-derives-expand-to-ordinary-source.md) ("Each derive
entry … must determine all its implementation binders. A target application
and a trait application have separate mappings: target parameters select the
derive binders written in the target positions"), and the clause of
[0272](0272-two-applications-of-one-type-may-each-implement-a-trait.md) that
names the standalone derive "that declares no parameter and applies the target
to types" as the request for one application. Extends 0145, 0165 and 0272.

## Context

A derive could be requested two ways: `@derive(Trait)` attached to a struct,
enum or newtype, and a standalone declaration
`derive[T: Bound] Trait for Type[T] where …`. ADR 0145 kept the standalone
form because one type declaration could not express several independently
constrained implementations, and ADR 0165 kept it for bounds other than the
ones the field types imply. ADR 0272 then used it for the request of one
application, `derive Score for Mark[UInt8]` beside `… Mark[UInt16]`.

Two spellings of one request cost more than their grammar. The resolver,
expansion and checker each carried an `attached` flag deciding where a
request's parameters, head and environment came from; the formatter, the
language server, the tree-sitter grammar and the program generator each knew
two forms; and a reader met the same implementation written in two places
that look nothing alike. The library wrote most of its derives standalone
(`derive[T: Equatable] Equatable for Option[T]`) although the attached form,
since 0165, infers exactly those bounds. The owner decided the attached
attribute is the only request, and every other spelling a compile error.

What the standalone form could say, case by case:

- **Bounds equal to the field types'.** The common case in `std`: each
  parameter bounded by the derived trait, the way 0165 infers it.
- **Bounds stronger or weaker than the field types imply.**
  `derive[T: Equatable + Copyable] Equatable for Cell[T]` asks more than the
  body needs; `derive[T: Copyable] Release for Tagged[T]` asks less, because a
  derived `Release` discards a component its environment proves discardable.
  A standalone request stated its whole environment and inferred nothing.
- **One application of a generic type.** `derive Score for Mark[UInt8]`, and
  several applications each with their own request.
- **A request written away from the type's declaration.** Allowed in another
  file of the type's module; a request in another module was already refused
  ([T-Derive], "this derivation requires a target declared in the same
  module").
- **A parameter only a trait argument determines.**
  `derive[A] Count[A] for Plain`, one implementation for every `A` of a type
  that has no `A`.

## Decision

**A derive is requested only by a `derive(...)` item attached to the struct,
enum or newtype it is for.** An item names its traits, may write binders
before them, and may end with one clause; binders and clause apply to every
trait it names:

```linea
@derive(Equatable, Debug)
struct Point { x: UInt8 }

@derive(Equatable where T: Equatable + Copyable)
struct Cell[T] { value: T }

@derive(Score for Mark[UInt8])
@derive(Score for Mark[UInt16])
struct Mark[T] { value: T }

@derive[A](Count[A])
struct Plain { value: UInt64 }
```

**Binders name only parameters the type does not have.** `[A]` after
`derive` declares a parameter of every implementation the item requests,
written after the type's own: `@derive[A](Count[A])` on `Plain` requests
`impl[A] Count[A] for Plain`, one implementation for every `A`. The type's own
parameters are already in scope in the attribute, so a binder spelled as one
of them is [T-Derive] at the binder, and is read as that parameter so the
request still expands; its help carries a fix (`drop_derive_binder`) that
removes it, and the `[...]` it would leave empty. Each trait of the item names every binder in its
arguments, since an implementation's parameters are recovered from its key;
a trait that names none is refused as an implementation whose parameter
cannot be recovered ([T-Impl]). Bounds on a binder are written on it,
`@derive[A: Allocator](Build[A] where T: Field[A])`.

- **No clause** requests the implementation for every application, conditional
  on its field types as 0165 decides.
- **`where P: B, …`** requests it for every application under the environment
  it states: the type's own bounds and the predicates written, with nothing
  inferred from the fields. This is the standalone form's environment, so a
  stronger bound and a weaker one are both written here, and a derived
  `Release` decides each component under it.
- **`for Type[Args]`** requests the implementation for that one application.
  The head is the annotated type applied to types, as many as it declares and
  none of them its own parameters; any other head is [T-Derive] at the head.
  Two items naming two applications are two requests, as 0272 decides.

An item writes at most one clause, after its last trait and before its `)`;
its binders sit between `derive` and `(`.
`for` and `where` do not combine: every type in an application is written, so
a predicate beside one is true or false once, at the derive, which the
request's own components already are. The type's own parameters are in scope
in the clause, as in the type's declaration.

**A standalone `derive … for …` is refused with [S-Derive].** The parser reads
the whole declaration so the report covers it, and its help writes the
attribute that requests the same implementation. Where the file declares the
type, the help carries a `Fix` (`attached_derive`) that writes the attribute
on its own line above the declaration and removes the standalone request's
line. A request applying its head to its own parameters is the family, with
each of them read as the type's parameter in that position and spelled by the
type's name for it; a parameter its head does not apply is a binder; its
bounds and `where` predicates become the item's `where` clause, less each
bound the type's declaration already writes on that parameter (compared bound
by bound, since the environment is the type's bounds and these together, and
a bound written twice is [T-Bound]), and an item left with none has no
clause. A request declaring no parameter that applies its head is `for`. A
trait the type's attributes already request the same way is left out of the
attribute and reported as the repeated request it is ([T-Derive]); a request
left with no trait is answered by removing it, and a plain one, with neither
binders nor a clause, adds its traits to the type's plain item rather than
writing a second. Where the type is declared in another file, the help names
the declaration and carries no fix. A request for a primitive or unit is told
that a derive targets a concrete declaration, and one for a name nothing
declares names no declaration, since [N-Undefined] reports the name. A request naming an application beside a `where`, and one
whose binder the type's own parameter would shadow, have no attribute the
help can write, and the help says what to write instead.

**A refused request still requests what it spells.** Where its type is a
struct, enum or newtype of its own module, the request expands as its
attribute would without its environment (the traits for every application,
or for the application its head writes) and the bodies it generates are not
checked. A use of what it would derive, and an import only it names, then
report nothing: the refusal is the one report, as an implementation refused
for its head keeps its row. A request with a trait-only parameter, or with
an environment for one application, requests nothing. Every request has its
names read, in its bounds, its predicates and its traits' arguments, so an
import only it names is used and a name it misspells is reported.

**One request path.** Expansion walks the type declarations that carry
`derive(...)` items, and each trait entry carries its item's clause: no other
declaration requests a derive, and nothing asks which form a request was
written in. The checker reads one fact per entry, whether its clause states
its environment, where it read a declaration's tag.

## Consequences

- `std`, the examples, the guide and the corpus are migrated. Most standalone
  requests in `std` restated the bounds 0165 infers and became plain
  `@derive(...)` on the type; the generated headers now carry the inferred
  predicates (`impl[T] Equatable for Option[T] where T: Equatable`) rather
  than inline bounds, which a report about an unmet bound names the same way.
- **A parameter only a trait argument determines is a binder.**
  `@derive[A](Count[A])` requests what `derive[A] Count[A] for Plain`
  requested, and the recoverability rule 0142 states for derive parameters
  holds for binders: the generated header declares them, and an entry whose
  arguments do not name one is refused as an implementation with an
  unrecoverable parameter.
- **A request sits on the declaration.** Placing it in another file of the
  module was the only freedom the standalone form gave; the declaration is in
  the same module by [T-Derive]'s own rule, so the attribute can always be
  written there, and a reader finds every derived implementation where the
  type is declared.
- **Diagnostics.** A report about generated code points at the trait entry in
  the attribute, as an attached request's always did. A message the clause
  already said inside its item is not repeated for the generated header.
- **Cost.** Each trait entry stores its item's clause beside it: a keyword, a
  head and a predicate range, constant per entry. Expansion reads the clause
  in constant time and copies its tokens once per entry; resolution reads each
  clause once per item. The fix scans the file's declarations once to index
  its types by name, then each refused request's own tokens and, per trait and
  per bound it writes, the attributes and header of the one type it names.
- **Tooling.** The formatter writes an item with a clause on one line,
  continued one level in after a line comment inside it. The
  tree-sitter grammar has no standalone derive node and parses the clause.
  The language server's navigation over derive entries reads the attribute
  items alone.

## Alternatives considered

**Binders that re-declare the type's parameters,
`@derive[T: Equatable + Copyable](Equatable)`.** It mirrors the standalone
header. It lost as the way to bound the type's parameters because the type
already declares them, so the list re-declares them: a reader has to match
`[T: …]` to the type's `T` by position, a different name is a second spelling
of one parameter, and the application case still needs a written head.
Bounds on the type's parameters belong where every other declaration writes
extra predicates, in a `where`; binders are kept for the parameters the type
does not have, which nothing else can declare.

**No binders; write a trait-only family with `impl`.** The first form of
this record. It lost because the implementation is generated code: writing
it by hand means writing the template's bodies again for one type, which is
the work a derive exists to remove.

**A clause per trait, `@derive(Equatable where T: Copyable, Debug)`.** It
reads ambiguously: after `where`, a comma separates predicates, so `Debug`
would be a predicate missing its bound. Putting the clause last and letting
it cover the item's traits has one reading, and an item per environment
(`@derive(Debug)` beside `@derive(Equatable where …)`) says the rest.

**A `where` that adds to the inferred predicates.** It reads like a function's
`where`, which adds requirements. It lost because it cannot weaken: a derived
`Release` decides discard under its environment, and inferred predicates in
that environment prove `Release` of the very component the written bound says
to discard. Replacing the inference keeps one rule per item, the one the
standalone form had.

**`for` beside `where`.** Every type of an application is written, so a
predicate there is decided at the derive; the request's components are
already checked there. Admitting it adds a combination with nothing to say.

**Keep the standalone form for the cases the attribute does not cover.** Two
forms of one request were the cost this record removes; keeping one for a
case no library uses keeps every reader and tool on both.
