# 194. An alias names a type that exists

Status: Accepted — 2026-09-28. Extended by
[0206](0206-allocator-spelling-is-shortened-by-alias-never-by-default.md); path
clause for a generic alias superseded by
[0211](0211-a-generic-alias-heads-a-path-and-the-call-settles-its-parameters.md).

## Context

A stored closure is spelled with its whole signature and its allocator:

```linea
struct Rule {
    name: Str,
    apply: mem.Closure[fn(cents: UInt64) -> UInt64, mem.SystemAllocator],
}
```

A struct field has no inference, so every field, parameter and container that
holds such a closure writes the signature out again. The standard library's
router wrote its route signature, contract included, twice:
`Vec[mem.Closure[fn(inout state: S, request: Request[P]) -> Result[Response[P], Error[P]] where carries(request), P], P]`.

Linea had no way to name an existing type. `type X = T` declares a nominal
newtype: a distinct type with `T`'s representation and its own identity, so
`type Pricing = fn(cents: UInt64) -> UInt64` cannot stand as `Closure`'s
signature ([T-Bound]) and is not callable. `use` binds a declaration another
module holds, and a written type is not a declaration.

## Decision

**`alias Name = T` declares another name for the type `T`. Writing the alias
writes `T`: same identity, same capabilities, interchangeable with `T`
wherever a type is written.**

```linea
use mem.Closure
use mem.SystemAllocator

alias Pricing = fn(cents: UInt64) -> UInt64

struct Rule {
    name: Str,
    apply: Closure[Pricing, SystemAllocator],
}
```

The allocator stays in the field: the idiom aliases the signature, which is the
contract, and leaves where the storage comes from written where storage is
declared. Nothing forbids aliasing the whole `Closure[…]`, but the examples do
not.

- `alias` is a contextual word, read only at the top of a file where a name
  follows it, as `type` is. `pub alias` publishes the name; `use m.Name` and
  `m.Name` reach it as they reach any type. It declares no representation, so
  `opaque`, `export` and the type attributes are refused.
- The name is a type's name for [N-Case].
- An alias reaches no further than the declarations its type is written with,
  the rule a re-export already follows: `pub alias Leak = Secret` over a
  private `Secret` is [M-Vis], or another module could build a structure it
  cannot name.
- An alias may declare type parameters with bounds:
  `alias Route[P: Allocator, S] = fn(inout state: S, request: Request[P]) -> … where carries(request)`.
  Applying it substitutes the arguments, which must meet the bounds. The
  argument count is checked as a structure's is, every parameter must appear
  in `T`, and `phantom` is refused: an alias has no identity to brand.
- The alias is the same type everywhere its target's name could be written,
  except an `impl` or `derive` head:
  - named literals and patterns: `Spot { … }`, `let Spot { … } = p`;
  - calls: `Points(3)` constructs through an alias of a newtype, and
    `Cents(x)` converts through an alias of a primitive;
  - paths: `Maybe.Some(3)`, `Spot.origin()` and `Bytes.open(allocator)` reach
    what the named type holds, at the alias's arguments. A path gives a
    generic alias no arguments, so it is refused by [T-Bound];
  - callable bounds: `F: Step + Release`, `F: units.Step`, and generic ones such as
    `H: Route[P, S] + Release`. A bound through an alias of a non-function
    type is refused.
- An `impl` or `derive` head through an alias is refused with the type the
  alias names offered: an implementation is written against the declaration,
  which keys coherence and `opaque`. The refused implementation adds nothing,
  and the refusal is its only report: a call to an operation it declares is
  not reported missing as well (`Resolution.refused_operations`).
- An alias that reaches itself through `T` — directly, inside an argument, or
  through another alias — is refused once per cycle ([N-TypeAlias]).
- A diagnostic reports the type an alias names; where an expectation was
  written as an alias, the label at that annotation names both.

### One answer

The resolver binds an alias's name under its own kind, `type_alias`, so a
type position reaches it through the same tables a declared type is reached
through (`type_in_module`, `typeNames`, qualified lookup), and every value,
call, path, bound and `impl` position meets a kind it must decide about rather
than one that silently reads as a structure. After the annotation walk it
refuses cycles and aliases wider than what they name, and records in
`Resolution.alias_heads` the type name each alias's written type is headed by,
followed through aliases. A call, a path and completion after a dot read that
one table (`throughAlias`) to reach the declaration.

The checker's `aliasedType` is the one place an alias becomes a type: it reads
what the alias wrote, in the alias's module with the alias's parameters in
scope. Every written name reaching an alias, bare or through its module, is
answered there by `appliedAlias`, which reads the arguments into a run of its
own and substitutes them with the same `substitute` a generic call uses. A
path's type, a variant's, a callable bound's signature (`boundSignature`) and
a call's settled implementation head all read that answer. Nothing below the
checker ever meets an alias: the pool holds the named type and no alias type
exists. The answer is kept per alias, separately before and after callable
effects are settled, since a callable read earlier is interned without its
contracts, and handed to tooling as `Typing.aliased`.

The declared-parts measures run before any type is minted, since minting a
growing part does not terminate. There the alias is its declaration: a node
whose one part is its written type, so the measures read aliases through the
same graph and not through a second evaluator.

## Consequences

- Transparent means the alias adds no type. Two aliases of one type, and an
  alias and its type, are the same `TypeId`; no conversion, no coherence
  question and no layout question is new.
- An alias cannot be an implementation's head. A program writes the type's
  own name there.
- Parts written through an alias are held to the polymorphic-recursion and
  layout measures: an alias is a node in the declared-parts graph, with its
  written type as its one part, so a cycle through an alias is a path in the
  graph a part written out would draw.
- Nothing prints an alias's name in place of the type it names except the
  expectation label, so a type error inside a large alias still reads in the
  expanded type.

## Alternatives considered

**`type` as an alias for function types, a newtype for everything else.** One
keyword would mean two things decided by what follows it, and the same line
would move between nominal and transparent as its right-hand side changed
shape. A newtype over a function type is a real, useful declaration (a
distinct callback type), and it would become unwritable.

**`use Name = T`.** `use` already binds a name that preserves identity, which
made it look like the right word. But `use` imports: its right-hand side is a
path to a declaration in another module, checked for visibility and re-exported
by `pub use`. Admitting a written type there gives one keyword two grammars,
makes `pub use` rename for one form only, and leaves "what does this `use`
bring in" answerable only by reading past the `=`.

**No aliases; shorter names instead.** `use mem.Closure` and
`use mem.SystemAllocator` already shorten each spelling, and putting both in the
prelude would shorten them everywhere. Neither removes the repeated signature,
which is the part a reader has to compare between two fields to know they hold
the same thing.

**Inferring a local's element type from a later `push`.** It would reverse the
rule that a local's type is not inferred from its later uses, adds deferred
inference across statements, and helps only locals; fields and signatures, where
the spelling is repeated, would be unchanged.

**Generic aliases refused.** The generic form costs one substitution through the
existing `substitute`, and the router's route signature, the motivating case in
the library, is generic in its allocator and state. Refusing parameters would
have left that case unaliased.

**An alias usable only where a type is written.** Refusing calls, paths and
bounds through an alias would have kept those positions keyed by declarations
alone. It breaks the promise that writing the alias writes the type: a literal
and a pattern already reach the declaration through an alias, and `opaque`
holds there, so construction adds no new route to a representation, and the
alias of a container exists precisely to shorten `Rules.open(…)`. The one
position that stays refused is an implementation's head, where a second
spelling would name the same coherence key two ways.
