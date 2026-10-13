# 6. Syntax nodes are typed SoA arrays per category, storing token ranges

Status: Accepted — 2026-07-24

## Context

The syntax tree must be index-based rather than pointer-based: contiguous
storage, stable identifiers, arena-allocated, passes transforming arrays rather
than mutating a graph.

Within that constraint the open questions are how strongly indices are typed,
and whether each node's source extent is stored or computed.

## Decision

One `MultiArrayList` per syntactic category, each with its own index type.

```zig
pub const TokenId = enum(u32) { _ };
pub const ExprId  = enum(u32) { none = std.math.maxInt(u32), _ };
pub const StmtId  = enum(u32) { none = std.math.maxInt(u32), _ };

pub const Expr = struct {
    tag: Tag,
    main_token: TokenId,
    token_range: TokenRange,
    data: struct { lhs: ExprId, rhs: ExprId },
};
```

`enum(u32)` with an open tag is a `u32` at runtime and a distinct type at
compile time, so passing a `StmtId` where an `ExprId` is expected, or an index
where a token is expected, does not compile.

Each node stores its full token range rather than deriving it.

Absence is the explicit `.none` member rather than `?ExprId`. Every bit pattern
of an open enum is inhabited, so the optional would cost a separate tag byte
per field.

Linea is expression-oriented, so a block is an expression and a program has a
block's shape: a statement sequence with an optional trailing expression.
`Ast.root` is therefore a `block` expression rather than a pair of fields on
`Ast`, which lets program and block parse through one routine.

A block's statement list does not fit in an expression's fixed payload, so
`Expr.data` is a bare union discriminated by `tag`, and the list lives in a
typed side array. Accessors gate each variant on its tag; no pass reads the
union directly.

## Consequences

- Category and token/node confusion are compile-time errors rather than
  runtime misbehaviour, and the checking is free at runtime.
- Node extents are direct lookups, which makes diagnostic underlines,
  formatter trivia queries and cursor hit-testing trivial, and removes the
  recursive `firstToken`/`lastToken` traversal a compact encoding requires.
- Storing the range costs eight bytes per node.
- Variable-length payloads live in typed side arrays — `[]StmtId` for a
  block's statements, `[]ExprId` for call arguments when they arrive — never a
  `[]u32` of indices whose meaning depends on the referring tag.
- A new category means a new array, a new index type and new accessors. This is
  the recurring cost, paid at each new syntactic category rather than once.
- Code cannot be lifted directly from Zig's `Ast.zig`, since its encoding
  differs.

## Alternatives considered

**A single flat node array with `{ tag, main_token, lhs: u32, rhs: u32 }` and
an `extra_data: []u32` overflow array**, as in the Zig compiler. Maximally
compact, proven at scale, and it would let `Ast.zig` and `zig fmt` be adapted
almost directly — which carries real weight given that a formatter and language
server are goals. Rejected on two grounds. First, `lhs` and `rhs` are untyped
`u32` whose meaning varies per tag, so reading a node index as a token index
compiles cleanly and fails at runtime; the safeguard is a documented tag table
enforced by attention. Second, its principal advantage over per-category
arrays — density — is what forces extents to be computed rather than stored,
and storing them is what makes the tooling cases cheap.

**A flat array of Zig tagged unions.** The most readable option and the hardest
to misuse. Rejected: every node is sized to the largest variant and the tag
interleaves with the payload, so it is index-based without being
data-oriented — it gives up the cache behaviour that motivated an index-based
tree in the first place.

**One array, but with `Index` and `TokenIndex` as distinct enums.** Eliminates
the confusion the flat encoding actually produces, at no runtime cost, while
staying Zig-shaped. Rejected: it leaves within-category confusion uncaught and
still cannot store extents.
