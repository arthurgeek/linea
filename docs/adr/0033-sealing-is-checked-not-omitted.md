# 33. Sealing is checked, not omitted

Status: Accepted — 2026-07-27

Builds on [0032](0032-a-module-is-a-directory.md), which decided what "outside"
means, and on [0023](0023-one-symbol-space-and-two-phase-resolution.md), whose
two-phase resolution is what lets a name cross a module boundary at all.

## Context

`opaque` exports a type's name without its representation. In most languages
this is an omission: a constructor is resolved by looking a name up in a scope,
so leaving it out of the exported scope is the whole implementation. Nothing
has to be checked, because nothing can be reached.

That reasoning does not hold here, and the reason is a feature decided long
before modules existed. Linea resolves `.Forged(7)` and `.{ .id = 1 }` against
**the type the context expects**, not against a scope. There is no name to
leave out. A sealed type reached by a function's return value can be taken
apart by a `match` that names nothing, and a sealed type expected by a
parameter can be built by a literal that names nothing.

The trap is that the omission version *looks* like it works. Most programs that
try to breach a seal do name something — `vault.Key.Forged` — and a visibility
rule on qualified access rejects those. The forms that need no name are exactly
the forms nobody writes by accident, so a suite of hand-written cases finds
them last.

## Decision

**`[M-Opaque]` is an active check, at every site that reaches a
representation.** Six sites: a variant named from context, a variant named
through its type, a structure literal, a `match`, a field read, a field
assigned. Four are in the type checker, which is the pass that knows what type
the context expects; two are in the routine that resolves a name through a
namespace.

**One predicate, six call sites.** `sealedHere(ty)` answers whether a type's
representation is sealed against the module being checked. Writing the rule six
times is how five of them stay right and one drifts.

**`opaque` is a visibility, not a modifier.** It occupies the same slot as
`pub`; `pub opaque` is not a spelling. Private, exported, and exported-sealed
are three answers to one question — whether what is written here is reachable
from outside, and if so how much of it. A boolean would need a second flag
beside it that could disagree with it.

**The seal is boundary-relative.** Inside the declaring module a sealed type is
an ordinary one. A seal that also bound the declaring module would be a way to
forbid a type's own code from touching it, which is a different and useless
feature.

**A `match` is checked on the scrutinee's type**, not on what its arms name.

## Consequences

**A catch-all does not defeat the seal.** `match k { _ => 0 }` names no variant
and so needs nothing from the sealed type, which makes it the obvious
exemption. The exemption is precisely how the seal would be defeated: it would
become the way to learn that a `k` is a `k`. Keying on the scrutinee is what
makes a pattern form added later inherit the rule instead of needing its own.

**The vault chain closes.** A value whose type is sealed can be disposed of
only by destructuring it, destructuring needs the representation, and the
representation is reachable only inside the declaring module. So the module
that mints a linear value is the only one that can consume it. Stage 5b is
built on that, and it is why sealing had to be checked rather than assumed.

**Six conformance cases, one per site.** Named for the site rather than for the
program, because what each holds is that *that* site checks — a case that
happens to be rejected by a different site would leave one unguarded and stay
green.

**A member's visibility is separate from its type's.** A declaration written
inside a sealed type is subject to `[M-Vis]` on its own. Sealing a
representation and exporting what is written beside it are two decisions.

## Alternatives considered

**Omit the constructor from the exported namespace.** The standard
implementation, and unimplementable here for the reason above: there is no
namespace the inferred forms consult. Recorded because it is what a reader who
knows other module systems will expect, and because the moment type-directed
inference is removed the cheaper version becomes available again.

**Seal at the type rather than at the site.** Mark the type's representation
unavailable in the pool outside its module, so any operation needing a layout
fails. Rejected because it fails too much and says too little: passing a sealed
value needs its size, so the layout has to be available, and the error a caller
sees would be about a missing layout rather than about a seal.

**A separate keyword for a sealed export, orthogonal to `pub`.** `pub sealed
struct`. Rejected with the two-flag argument above; the third state is not
orthogonal to the first two, it is one of them.

**Check only the named forms and document the inferred ones as a hole.** Would
have shipped, and the hole is one line of a program away. A rule with a
documented breach is not a rule.
