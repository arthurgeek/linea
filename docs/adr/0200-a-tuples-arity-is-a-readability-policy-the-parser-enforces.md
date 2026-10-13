# 200. A tuple's arity is a readability policy the parser enforces

Status: Accepted — 2026-10-04

Extends [0199](0199-tuple-syntax-denotes-a-positional-aggregate-with-a-prelude-identity.md).

## Context

The language has no variadic generics, so each arity is one declaration with
its own rows for every trait, and the tuple surface is arities times traits.
The compiler cost of eight arities is inside noise. The reason for a bound is
readability: a product with more positional parts is a struct with its names
withheld.

## Decision

**A tuple has two to eight components.** The parser refuses any other count as
[S-Tuple], in a literal, a type and a pattern alike, and refuses `(x,)`; `(x)`
groups and `()` is unit. The bound is `node.max_tuple_arity`, with
`node.isTupleArity` as its one statement, and the prelude gate holds the
library's `Tuple2`..`Tuple8` to it.

A head the parser refused registers nothing for an `impl` or a derive, so a
refused arity produces one report and no secondary ones.

## Consequences

- A nine-tuple is a syntax error that names the rule.
- Raising the bound is one constant, one more declaration and its trait rows
  in `std/tuple/tuple.lin`, and the gate entry.
- The checker never indexes `tuple_decls` outside the bound: a count the
  parser admits that the prelude lacks is [T-Literal], one it refused is
  poisoned.

## Alternatives considered

**No bound.** The library would stop at some arity regardless, and the cliff
would be a failure on a type the language accepted.

**Refuse in the checker by the absence of a declaration.** One place instead
of two, but the report arrives after resolution and names a missing
declaration rather than the rule, and a tool working from a tree that never
reached the checker would accept the nine-tuple.
