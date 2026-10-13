# 209. A `From` derive converts the variant its source type names

Status: Accepted - 2026-10-07

Extends [0113](0113-structural-derivation-is-library-defined-source.md) and
[0145](0145-closed-attributes-attach-ordinary-derive-requests.md).

## Context

Every program that propagates several errors with `?` writes one
`impl From[X] for Failure` per source, each wrapping the source in the variant
that already declares it. In `examples/` 19 of the 22 hand-written `From`
implementations are that wrapping (8 of them in one file, 40 lines);
in `std/` 7 of 29 are, the others choosing a status or settling a value.
[0162](0162-question-mark-converts-an-error-through-from.md) made `?` convert
through `From`, and said it prefers an implementation where the wrapping is
stated once. [0145](0145-closed-attributes-attach-ordinary-derive-requests.md)
closes the attribute set and [0113](0113-structural-derivation-is-library-defined-source.md)
says a trait's module declares its one template. No record weighs a derive for
`From`.

## Decision

**`@derive(From[S])` on an enum is a request for the implementation
`From[S] for the enum` that wraps the source in the unique variant whose
payload is exactly one field of type `S`.** The opt-in is the entry itself:
only a named source converts. An enum with no such variant, or two, is refused
([T-Derive]) at the entry.

The form is the existing derive grammar and the work is a template in
`std.convert`: `template impl[S] From[S] where reflect.target: enum` whose one
member is `reflect.wrap(source)`. `reflect.wrap(parameter)` is the single new
reflection operation. The derive entry selects the variant by comparing the
parameter's written type, with `S` standing for the entry's argument, against
each one-field variant's written type with the same routine coherence uses for
the arguments of two implementations, so an alias and the type it names select
the same variant, and expansion erases the operation into the variant's
ordinary constructor. A struct or newtype target is refused by
`reflect.target: enum`; a source with no selected variant, or with two, is
[T-Derive] at the entry. Which of the two further opt-in spellings (naming
variants; a per-variant marker) later supersedes the source-type entry is left
open.

## Consequences

- About 26 impls (19 in examples, 7 in std) become one derive entry each.
- A derive generates concrete implementations, so it adds nothing to the
  blanket-`From` deferral of
  [0184](0184-a-failure-holding-an-owned-value-settles-to-its-reason.md) and
  does not depend on where-aware coherence.
- A conversion that carries a decision (a status, a settling) stays handwritten;
  the derive covers only wrapping.
- The template mechanism gains one reflection operation, and the conformance
  step that replaces derives with their generated text keeps 0113's
  equivalence between the derive and the handwritten implementation.
- An alias's written type resolves before derives expand, with the structs and
  enums it may name, so a derive comparing written types reads through
  aliases.

## Alternatives considered

**Convert every single-payload variant.** Unsafe: a `Key(Str)` variant would
make `From[Str]` for the enum, and `?` would convert any `Str` error into it
silently, at a site where nothing says it.

**Name variants, or mark them.** Shorter than restating payload types, and
each costs a construct in the parser, formatter, tree-sitter grammar and
language server (a variant-level marker also extends 0145's closed set). Kept
for after the first form shows whether restated types are the objection.

**`.map_err(Variant)?` only.** Works today and is the one-site idiom;
0162 chose implementations for wrapping stated once.

**One-line impl sugar.** A second spelling of an implementation.
