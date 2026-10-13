# 9. All cross-pass references are stable typed IDs

Status: Accepted — 2026-07-24

## Context

The compiler is a sequence of passes, each producing a representation consumed
by later ones. How a pass refers to data owned by an earlier pass determines
how tightly the two are coupled.

Pointers into another pass's storage create three problems. The earlier pass's
arena can no longer be released independently. Growing a backing array
invalidates every pointer into it. And a representation containing pointers
cannot be serialised, which forecloses caching and incremental compilation
before either is attempted.

The syntax tree already uses typed indices ([ADR 0006](0006-typed-per-category-ast.md)).
This record generalises that from a local choice to a rule spanning every pass.

## Decision

Every reference that crosses a representation boundary is a typed ID, and no
pass stores a pointer into another pass's arena.

```zig
pub const TokenId  = enum(u32) { _ };
pub const ExprId   = enum(u32) { none = ..., _ };
pub const StmtId   = enum(u32) { none = ..., _ };
// as later passes land:
// DeclId, SymbolId, ScopeId, ModuleId, TypeId, HirId, InstId, BlockId
```

- Each ID is `enum(u32)` — a `u32` at runtime, a distinct type at compile time.
- Each representation owns its arrays and is the sole interpreter of its own
  IDs. An ID is meaningless without the table that owns it, so functions take
  the table and the ID together.
- Absence is an explicit `.none` member, never a pointer sentinel.
- A pass may hold a borrowed const view of an earlier representation for the
  duration of its run. It may not store one.

## Consequences

- Any representation can be written to disk and read back without pointer
  fixups, rather than requiring a rewrite of every data structure.

  What that buys is serialisation, and nothing beyond it. "Stable" here means
  stable across passes within one compilation: an ID means in the checker what
  it meant in the parser, and no reallocation moves it. It is a position in a
  dense array built by walking the source in order, so it says nothing across
  two compilations — inserting a declaration shifts every ID after it, and a
  fact stored against the old one describes its neighbour.

  So caching a representation is possible and holding a fact about a
  declaration across an edit is a separate unanswered question, needing
  something the source supplies rather than something the walk assigns. This
  record does not answer it, and nothing depends on the answer yet: no pass
  caches, and no ID is written anywhere as a durable reference to anything.
- Arrays can grow during construction without invalidating references already
  handed out.
- Teardown is a single arena reset per representation, in any order.
- IDs are cheap to compare, hash, sort and store in dense side tables — which
  is how later passes attach types, symbols and ownership facts without
  modifying the representation they annotate.
- A debugger shows an integer where a pointer would have shown a struct. The
  `dump-*` subcommands exist partly to offset this.
- Passing an ID without its table is a latent bug the type system does not
  catch. Accessors are methods on the owning table so that the pairing is the
  path of least resistance.

## Alternatives considered

**Pointers into arena-allocated nodes.** The conventional tree-of-pointers
compiler. Direct to write and to debug. Rejected: it couples arena lifetimes
across passes, breaks on array growth, and makes serialisation impossible.

**Reference counting or a garbage-collected node graph.** Removes lifetime
questions entirely. Rejected: per-node overhead on the compiler's hottest data,
and cycles between representations are easy to create by accident.

**A single global node table shared by all passes.** Would make one ID type
sufficient everywhere. Rejected for the same reason as in
[ADR 0006](0006-typed-per-category-ast.md): it discards the compile-time
distinction between categories, and here it would also merge the lifetime of
every representation into one.
