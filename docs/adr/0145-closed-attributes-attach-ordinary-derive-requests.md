# Closed attributes attach ordinary derive requests

Status: Accepted — 2026-09-21

Partially superseded by [0165](0165-an-attached-derive-requires-each-field-type.md):
an attached generic derive requires each field type rather than using only the
type's written constraints.

Extends [0056](0056-a-modifier-is-refused-where-it-says-nothing.md) and
[0113](0113-structural-derivation-is-library-defined-source.md).

Extended by [0209](0209-a-from-derive-converts-the-variant-the-source-names.md):
for a derive entry whose argument is a source type that selects an enum variant.

## Context

Ownership and visibility policy used bare declaration prefixes while structural
behavior used separate derive declarations. The two forms did not compose into
one readable declaration header, and a concrete derive had to repeat the target
name even though it immediately followed that type. Tooling also needs the
written grouping and comments, while semantic expansion needs one normalized
request independent of surface spelling.

Generic derives sometimes require constraints weaker or stronger than the type
declaration itself. Any attached form must preserve standalone derives for
those independently constrained implementations. Derivation must also remain
library-defined generated source, without a second checker or compiler-known
trait names.

## Decision

A declaration attribute begins with `@`. A single item is written as
`@linear` or `@derive(Trait)`, and a grouped sequence is written as
`@(opaque, linear, derive(Debug, Release))`. The item set is closed to
`opaque`, `linear`, `copyable`, and `derive(...)`. Attributes attach only to the
following struct, enum, or newtype declaration. They precede ordinary
visibility and each group formats on its own line.

The parser retains ordered groups, items, token ranges, comments, and each
written derive trait reference. It normalizes ownership and opacity once onto
the declaration. Unknown or empty items, duplicate policies, incompatible
ownership policies, malformed groups, and attributes on any other declaration
are refused. Trait duplication is checked after resolution, so aliases and
qualified paths cannot request one trait twice under different spellings.

An attached derive uses the annotated type's parameter list and written
constraints. It enters the same structural expansion path as a standalone
derive and produces the same ordinary generated implementation and provenance.
Generated and handwritten implementations occupy the same ordinary coherence
tier, so two rows with an overlapping key conflict. Standalone derive remains
the form for an implementation whose constraints differ from the type
declaration's.

Bare `opaque`, `linear`, and `copyable` prefixes are removed. Standalone derive
syntax remains accepted for independently constrained requests; there is no
compatibility spelling for the removed policy prefixes.

## Consequences

The syntax tree carries one dense attribute-group range per declaration plus
flat group and item tables. Attached trait entries reuse the existing derive
trait table and each annotated declaration records their contiguous range, so
expansion reaches a request in constant time. Group lookup by source token is
logarithmic in the AST's ordered groups. Storage is linear in declarations,
groups, items, and written trait entries.

Expansion still resolves each trait entry and renders ordinary source. Duplicate
identity tracking is expected constant time per request; trait resolution and
template work retain their existing bounds. Formatting can preserve comments
and grouping without reconstructing source from normalized ownership policy.
Materialization removes fulfilled attached derive items while retaining the
nominal declaration and its other attributes.

An attached generic request cannot invent component bounds. If the type's own
constraints do not prove a template requirement, the diagnostic points to that
trait entry and recommends an independently constrained standalone derive.

## Alternatives considered

**Keep policy prefixes and add only `@derive`.** Rejected because declarations
would retain two modifier systems with different grouping and tooling rules.

**Replace standalone derive entirely.** Rejected because one type declaration
cannot express several independently constrained implementations without
strengthening the type itself.

**Lower attached attributes into synthetic source `derive` declarations.**
Rejected because unwritten source nodes obscure comments, navigation, and exact
origins. The resolver instead consumes both written forms through one request
interface.

**Infer component bounds for attached derives.** Rejected because it changes a
type declaration's promises and creates a second constraint-inference rule.

**Accept arbitrary user attributes.** Rejected because Linea has no macro or
reflection contract that could assign them meaning; silently retaining unknown
items would make misspellings inert.
