# 12. Representations are immutable once produced

Status: Accepted — 2026-07-24

## Context

Later passes learn things about earlier representations. The resolver learns
which binding each name refers to; the type checker learns each expression's
type; the ownership checker learns where values are moved and dropped.

That knowledge has to be stored somewhere. The two options are to write it back
into the representation it describes, or to keep it beside the representation
in a separate table.

Writing back is the path of least resistance, and it has a specific failure
mode: a field's contents come to depend on how far the pipeline has run. "What
is in `Expr.symbol`?" stops having an answer and becomes "which pass are you
asking after?" Diagnostics, dumps and tests then depend on pipeline position
rather than on data.

## Decision

A representation is mutable only while the pass that produces it is building
it. Once that pass returns, the representation is immutable for the rest of the
compilation.

- Construction happens through a builder that owns its arrays. Freezing is the
  builder returning the finished representation.
- Later passes take a const view. They may read it; they may not write to it.
- A pass that learns something records it in a **side table** — a dense array
  indexed by the representation's own IDs
  ([ADR 0009](0009-stable-ids-across-passes.md)) — and that table becomes part
  of its own output.

```zig
// resolution is output, not a mutation of the tree
pub const Resolution = struct {
    // indexed by ExprId; .none where the expression names nothing
    name_targets: []const SymbolId,
};
```

A pass that needs a structurally different tree lowers to a new representation
rather than editing the one it was given. That pressure is what eventually
justifies HIR ([ADR 0001](0001-staged-compiler-evolution.md)).

## Consequences

- A field means one thing regardless of when it is read, so dumps and golden
  tests are reproducible and independent of pipeline position.
- Passes can be re-run, reordered where the dependency graph allows, or run
  concurrently over a shared const view.
- Annotations are droppable. A side table consumed by one pass and needed by no
  other is freed at that point, rather than occupying a field in every node
  forever.
- The typed-ID invariant and this one reinforce each other: IDs make dense side
  tables the natural representation for annotations, and side tables are what
  make immutability practical rather than merely aspirational. rustc's
  `TypeckResults`, keyed by `HirId`, is the same shape.
- An annotation costs an array sized to the representation, even when only a
  few elements carry information. Sparse facts use a hash map keyed by ID
  instead; the choice follows [ADR 0010](0010-data-oriented-not-soa-everywhere.md).
- Reading an annotation is an indirection rather than a field access.
- Passes take more parameters, since a consumer needs the representation and
  each side table it depends on. This is a visible dependency rather than a
  hidden one, and is treated as a benefit.

## Scope and limits

This governs whole-unit compilation, which is the only mode that exists.
Incremental compilation eventually wants to patch a representation in place
rather than rebuild it, and that will need its own record — a rebuild-and-swap
model preserves this invariant, while in-place patching does not. Deferred
until incremental compilation is attempted.

## Alternatives considered

**Mutate representations in place as passes learn things.** Fewer data
structures, no indirection, and each node carries everything known about it.
Rejected: it makes every annotated field's meaning depend on pipeline position,
which is unanswerable from the type alone and turns "when is this populated?"
into recurring archaeology. It also forecloses re-running or parallelising
passes.

**Optional fields on nodes, populated as passes run.** A middle path that keeps
one structure while making the unpopulated state explicit. Rejected: it has the
same phase-dependence problem with extra ceremony, and it spends memory in
every node on facts only some passes produce — directly against
[ADR 0010](0010-data-oriented-not-soa-everywhere.md)'s criteria.

**Version the representation — each pass produces a new copy with annotations
folded in.** Preserves immutability. Rejected: copying the whole tree per pass
is the cost this architecture exists to avoid, and it buys nothing a side table
does not.
