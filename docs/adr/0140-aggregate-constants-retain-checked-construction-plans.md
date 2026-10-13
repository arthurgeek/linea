# 140. Aggregate constants retain shared data and checked construction plans

Status: Accepted — 2026-09-21; materialization clause superseded by [0178](0178-a-constant-is-a-static-place.md); unit-expression clause superseded by [0188](0188-the-unit-value-is-written-as-its-type.md)

Extends [0020](0020-a-constant-expression-is-defined.md),
[0059](0059-one-table-answers-both-questions-about-a-constant-expression.md)
and [0127](0127-constants-retain-distinct-values-and-infer-their-types.md).

## Context

An options record could be assembled at runtime but could not be a named
constant or a parameter default. Enum policies needed forwarding functions to
supply an ordinary choice. A JSON limits record exposes the same general gap as
filesystem permissions and application rate tables.

Defaults participate in callable identity and implementation coherence before
all contextual aggregate types are fully checked. A checker-only aggregate
folder would leave earlier comparisons using another constant domain. Replaying
an initializer during lowering would also evade the shared-value decision in
0059 and repeat type/name work after checking.

Aggregate aliases can share a large amount of data. Expanding each alias into a
tree during folding, printing or symbol generation makes source-sized input
produce exponentially larger compiler work even when no runtime value is emitted.

## Decision

**Admit immutable compound data, not arbitrary execution.** The unit expression
`{}`, structure literals, fixed arrays and enum constructions join the constant
domain when their components are constant and their concrete type is Copyable
without owned obligations or runtime observations. A payload-free variant stores nothing,
so it qualifies whenever its enum owes no settlement, even where a sibling's
payload leaves the enum affine
([0146](0146-payload-free-variants-are-constant-expressions.md)). Static literal-backed Str is
eligible; resource owners and runtime views are not. Empty arrays contain no
owned elements. Existing integer, Bool and text rules remain. Ordinary calls,
nonempty blocks, Float64 constants and symbolic default types remain excluded.

**Keep one shared folder.** It decides membership, values and cycles for named
constants, aliases and every form of parameter default. Resolution supplies name
and enum-constructor classification. Type checking owns contextual validation,
concrete capability eligibility and opacity. Early value comparison does not
replace later type checking.

**Intern a flat graph with typed edges.** Records use canonical field-label order;
arrays and enum payloads retain order. Exact interning compares complete keys.
Hash collisions never make distinct values equal. Nominal identity remains in
the compared type. Retained-library attachment and reopening preserve the graph
prefix and its identities before adding new values. All storage follows the
producing pass allocator and outlives its consumers.

**Record checked construction separately from value shape.** Materialization
plans associate a graph value with its concrete type and retain declaration-order
fields and enum ordinals. Named references and omitted arguments share one MIR
materializer using these plans and ordinary layout/storage operations. No later
pass replays initializer syntax, resolves fields or variants again, invokes a
constructor function or schedules disposal.

**Keep symbols independent of pool insertion order.** Callable identity uses the
same exact graph values; rendering and mangling receive the graph explicitly.
Symbols use compact graph encoding; human-facing names use bounded, readable
values. Neither expands shared aliases exponentially.

## Consequences

Libraries can use one options-record default and expose named overrides.
`save_atomic` takes a Copyable SavePermissions policy defaulting to `.Preserve`;
its policy-only forwarding wrapper is removed. Programs can copy a constant rate
card, edit the copy and keep the published default intact.

The compiler retains aggregate data and typed construction plans, with explicit
lifetime and reopening obligations. A record of k fields costs O(k log k) to
canonicalize; graph interning and memoized validation share repeated subvalues.
Emitting an actual aggregate still costs its materialized size. These costs are
part of the feature rather than a claim of free compile-time computation.

## Alternatives considered

- **Six scalar JSON defaults or a policy-only wrapper.** They encode one logical
  configuration as repeated parameters or duplicate public operations. They do
  not address the same need in other libraries and applications.
- **General compile-time function execution.** It adds evaluation semantics,
  resource questions and a much larger implementation surface than immutable
  data needs.
- **A separate typed aggregate evaluator.** It duplicates membership and value
  semantics used by early callable/coherence comparison.
- **Retain initializer expressions for emission.** It repeats computation and
  semantic decisions after checking instead of retaining the checked answer.
- **Tree copies or digest-only equality.** Tree copies lose sharing; digest-only
  equality makes a collision a semantic error. Exact interning keeps both
  bounded storage and correct identity.
