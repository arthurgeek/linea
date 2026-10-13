# 15. A new representation must discard, add, or simplify

Status: Accepted — 2026-07-25

## Context

The architecture names five representations beyond tokens: AST, HIR, a
post-semantic form, MIR, and QBE IR. [ADR 0001](0001-staged-compiler-evolution.md)
says each is introduced when it solves a named problem, but does not say what
counts as one. "The AST has become cumbersome" is a feeling, and a feeling is
not a threshold.

The failure mode is well documented in other compilers: representations
multiply, each lowering is nearly the identity, and every language change has
to be threaded through all of them. The cost is not the memory. It is that a
new construct must be designed once per representation, and that a bug can
live in any of the translations between them.

There is a cheaper alternative that is easy to overlook. A pass that needs to
know something a representation does not record can record it *beside* the
representation, in a side table keyed by its ids
([ADR 0012](0012-immutable-representations.md)). Side tables cost one array and
no lowering.

## Decision

A new representation is justified only when at least one of these is true, and
the record introducing it must say which:

1. **Information must be discarded.** Consumers are repeatedly stepping over
   detail that no longer means anything — the syntactic nodes a formatter needs
   and semantics do not.
2. **Information must be added that has no key.** A side table needs ids to
   attach to. When the new facts are *nodes* rather than annotations —
   temporaries, basic blocks, drop points — there is nothing to key on, and a
   representation is the honest answer.
3. **Invariants become simpler.** The new form can state something the old one
   cannot: every value assigned once, every block ending in a terminator, every
   drop explicit.
4. **Passes become simpler in aggregate.** More than one consumer wants the
   same normalisation, so doing it once beats doing it in each.
5. **Backend independence improves.** The new form removes a dependency on
   either the source language or the target.

If none holds, the need is met with a side table.

Concretely, for the two representations most likely to be introduced
prematurely:

**HIR** arrives when any of: a semantic pass repeatedly skips syntax-only nodes;
two desugarings duplicate logic; more than one consumer wants the same
normalised tree; or the parse tree has diverged far enough from the semantic
structure that reading a pass requires knowing the grammar.

**MIR** arrives because it is the first representation with **explicit control
flow** — basic blocks and terminators rather than nested expressions — along
with explicit temporaries, explicit ownership operations, and independence from
both the source language and the target. That sentence is the boundary: a
representation that does not make control flow explicit is not MIR, whatever
else it does.

## Consequences

- Introducing a representation is a reviewable claim rather than a preference,
  and the record names which criterion it meets.
- Side tables become the default answer to "this pass needs to know X", which
  is the cheaper answer more often than it looks.
- Two representations that both satisfy a criterion may still be one
  representation with two invariants — Swift's Ownership SSA is a mode of SIL
  rather than a separate IR. The criteria justify a boundary; they do not
  require one.
- A representation introduced under criterion 1 will accumulate pressure to
  retain what it discarded, from tooling that wanted it. That pressure is
  answered by keeping the earlier representation, not by weakening the new one.
- The criteria are about the representation, not the pass. A pass that is hard
  to write is evidence, but the question remains what the new form would let it
  state.

## Alternatives considered

**Introduce the representations the reference architecture lists, on schedule.**
Predictable, and each is well understood from other compilers. Rejected: it
designs every intermediate form against a language that does not exist yet,
which is what [ADR 0001](0001-staged-compiler-evolution.md) exists to prevent.

**Decide case by case without written criteria.** What the architecture did
until now, and it works while one person holds the whole design. Rejected:
"cumbersome" is unfalsifiable, so the decision cannot be argued about, only
asserted.

**Never introduce another representation; annotate the AST forever.** Keeps one
structure and no lowerings. Rejected: it fails criterion 2 at the first pass
that needs new *nodes* rather than new facts, and encoding basic blocks as
annotations on a tree is a representation with extra steps.
