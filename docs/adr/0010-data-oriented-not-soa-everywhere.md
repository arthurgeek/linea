# 10. Data-oriented design is the principle; SoA is one technique

Status: Accepted — 2026-07-24

## Context

Tokens and syntax nodes are stored as structure-of-arrays
([ADR 0004](0004-soa-token-representation.md),
[ADR 0006](0006-typed-per-category-ast.md)), each justified by a specific
access pattern.

Stated as a general rule, "use SoA" would be cargo cult. SoA pays off when many
elements are traversed and each traversal touches a subset of fields. It costs
ergonomics — construction is field-by-field, a single element is never a value
you can pass around, and `MultiArrayList.Slice` has to be threaded through call
sites. Where the payoff is absent, only the cost remains.

## Decision

The architectural principle is data-oriented design: layout follows access
pattern. SoA is applied where that pattern justifies it, and not by default.

A structure is stored SoA when all three hold:

1. instances are numerous — thousands per compilation unit,
2. hot traversals read a proper subset of the fields, and
3. those traversals are on a path whose cost is proportional to program size.

**SoA:** tokens, syntax nodes, and — when they arrive — HIR nodes, MIR
instructions, basic blocks, symbol tables, type tables.

**AoS:** diagnostics (few per compilation, and rendering reads every field of
each), parser state, driver and CLI configuration, `Source`, and any structure
held one at a time.

Plain arrays where a structure has one field: `SourceMap.line_starts` is a
`[]u32`, not a list of single-field structs.

Where a structure's layout is not obvious from these criteria, the reason is
recorded where it is defined.

## Consequences

- Layout is chosen per structure with a stated reason, rather than defended as
  a house style.
- Modules differ in style. `diagnostics/` reads like ordinary Zig; `lexer/` and
  `syntax/` do not. This is intended and reflects a real difference in access
  pattern.
- Each criterion is a judgement call, so borderline structures need a decision
  rather than a lookup. The default for borderline cases is AoS, on the grounds
  that converting AoS to SoA later is mechanical while the ergonomic cost is
  paid daily.
- A structure that outgrows its original access pattern needs revisiting. This
  is expected for symbol and type tables as later passes land.

## Alternatives considered

**SoA universally.** Consistent and requires no judgement. Rejected: it imposes
field-by-field construction and slice threading on structures that are never
traversed in bulk, buying nothing. `Diagnostic` is the clearest case — a few
dozen per compilation, every field read when one is rendered.

**AoS universally, with SoA introduced only after profiling.** The orthodox
advice, and correct for most software. Rejected here on the specific ground
that the token array's access pattern is known in advance rather than
discovered: the parser's lookahead reads tags and nothing else, over the
largest array the frontend builds. Retrofitting SoA onto tokens and nodes would
also mean rewriting every pass that touches them, which is a different cost
profile from an ordinary optimisation.
