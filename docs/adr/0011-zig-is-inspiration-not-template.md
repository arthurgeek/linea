# 11. Zig is an inspiration, not a template

Status: Accepted — 2026-07-24

## Context

Linea's compiler architecture is explicitly modelled on the Zig compiler:
structure-of-arrays storage, index-based references, arena allocation, flat
data structures, stable identifiers, data-oriented design.

That creates a standing question at every design decision — *should we do what
Zig does?* — and several choices already answer it in the negative. Without a
stated position, each divergence looks like an oversight, and "Zig does it this
way" becomes an argument that ends discussion rather than one that has to earn
its conclusion.

## Decision

Zig's **principles** are adopted. Zig's **encodings** are evaluated case by
case against Linea's own requirements.

"Zig does X" is evidence that X is workable at scale. It is not by itself a
reason to do X. Every borrowing and every divergence is justified on Linea's
requirements and recorded.

| Zig's approach | Linea | Where |
| --- | --- | --- |
| Data-oriented layout, SoA for hot arrays | Adopted, with explicit criteria | [0004](0004-soa-token-representation.md), [0010](0010-data-oriented-not-soa-everywhere.md) |
| Index-based references, arena allocation | Adopted, and strengthened into a compiler-wide invariant | [0009](0009-stable-ids-across-passes.md) |
| Frontend recovers rather than failing | Adopted | [0003](0003-infallible-frontend.md) |
| One universal node array, `lhs`/`rhs` + `extra_data` | Diverged — typed tables per category | [0006](0006-typed-per-category-ast.md) |
| Node extents computed by `firstToken`/`lastToken` | Diverged — extents stored | [0006](0006-typed-per-category-ast.md) |
| Comments discarded, re-scanned by the formatter | Diverged — comments are tokens | [0005](0005-lossless-token-stream.md) |
| Tokens store `start`, end recovered by re-lexing | Diverged — spans store both ends | [0004](0004-soa-token-representation.md) |

The divergences are not scattered. Every one traces to a requirement Zig does
not share in the same form: **formatter and language-server fidelity is a goal
from the first commit rather than a capability added to a mature compiler.**
Zig's encodings are tuned for a large node vocabulary and a formatter written
afterwards against an AST that had already been designed. Linea has a small
vocabulary and a fidelity requirement that predates the parser, so the trade
lands differently — three of the four divergences buy exact source extents,
which is precisely what tooling consumes.

## Consequences

- Divergence needs a reason, and so does imitation. Neither is the default.
- Zig's compiler is a reference to read, not a codebase to port. Anything taken
  from it is translated rather than copied, and the translation cost is real.
- Linea does not track Zig's internal changes. `Ast.zig` evolving is not a
  reason for Linea to change.
- The divergence table is a maintenance burden: it has to be revisited when a
  new representation lands, or it becomes stale and misleading.
- Where Zig's approach is adopted, its practical experience applies —
  `MultiArrayList` ergonomics, arena patterns, recovery strategies — and that
  is a genuine and continuing benefit.

## Alternatives considered

**Copy Zig's frontend encodings wholesale.** Maximum leverage: `Ast.zig`,
`zig fmt` and the incremental-reparse machinery become directly adaptable
rather than merely instructive, which matters given that a formatter and
language server are goals. Rejected: those encodings are answers to Zig's
requirements, and the two projects differ precisely where the encodings are
load-bearing — node vocabulary size, and whether tooling fidelity was a
founding constraint or a later one.

**Treat the resemblance as incidental and design from first principles.**
Rejected: the principles are proven at scale by a compiler solving a
recognisably similar problem, and rediscovering them independently would be
slower and worse.
