# 14. An unused declaration is an error

Status: Accepted — 2026-07-25

## Context

Code that declares something and never uses it is either a mistake — a
misspelled reference, a refactor left half-finished, a binding whose use was
deleted — or debris. Neither improves by being left alone.

Most languages report this as a warning. Warnings occupy an unstable position:
they are either enforced by a flag that turns them into errors, in which case
they were errors all along and the intermediate state only delayed the
decision, or they are not, in which case they accumulate until the output is
noise nobody reads. A project's warning count tends in one direction.

The cost of making it an error lands on exploratory work, where commenting out
a line can cascade into unrelated failures.

## Decision

An unused declaration is an error. This covers bindings now, and functions,
imports, types and parameters as the language acquires them.

The check is static: a declaration is used if some reference to it appears in
the source, regardless of whether execution reaches that reference.

Two cases are exempt, because reporting them would describe one mistake twice
([ADR 0003](0003-infallible-frontend.md), invariant 4):

- a declaration whose name failed to parse, which cannot be referenced by name,
  so being unused is guaranteed rather than informative
- a declaration whose initialiser is poisoned, where the statement is already
  diagnosed and a second complaint concerns the same broken line

A declaration whose name begins with `_` is deliberately unused and is exempt.
`_` alone is the usual spelling; `_x` carries the same exemption while saying
what the value would have been, which is worth having when a declaration exists
to satisfy a shape rather than to be read.

The prefix marks intent and nothing else. Such a name is an ordinary one that
can still be referenced, so a binding is exempt because of how it is named
rather than because of what it can do. Renaming `x` to `_x` is therefore how a
programmer says "I know" — and the diagnostic can suggest exactly that.

## Consequences

- A misspelled reference is caught at the declaration as well as at the use,
  which is often the clearer of the two.
- Commenting out a line to try something can produce errors elsewhere. This is
  the real cost, and it is the price of the diagnostic being unignorable.
- Deleting code is easier, because an unused declaration is proof nothing
  depends on it rather than a hint.
- The check needs the set of references, so it belongs with name resolution.
  The Stage 1 evaluator performs it, and the resolver inherits it along with
  the diagnostic code.
- Redefinition in a single scope is caught as a side effect: the earlier
  binding becomes unused. That is not a substitute for a shadowing rule, which
  is decided when scopes exist to constrain it.
- Every future declaration form must state what counts as a use of it. A
  declaration kind without that definition is not finished.

## Alternatives considered

**Report it as a warning.** Conventional, and it keeps exploratory work
frictionless. Rejected: an unenforced warning accumulates until the output is
ignored, and an enforced one is an error with extra steps. Choosing at the
outset avoids the migration where a codebase turns warnings on and fixes
hundreds at once.

**Error on unused imports and functions, warn on unused local bindings**, on
the grounds that locals are the ones churned during exploration. Rejected: it
makes the rule something to look up rather than something to know, and locals
are where a misspelled reference is most likely to hide.

**Discard at the point of use rather than of declaration**, as Zig's `_ = x;`
does. Marks a declaration used from anywhere, which suits a language where a
parameter must exist to satisfy a signature but has no use in one
implementation. Rejected: it puts the statement "this is deliberately unused"
somewhere other than the declaration it describes, so a reader has to search
for it.

**Exempt only the exact name `_`**, treating `_x` as an ordinary checked name.
Keeps the exemption unmistakable, since one spelling means one thing. Rejected:
it forces a programmer to discard the name in order to discard the check, so a
declaration kept for its shape loses the label describing what it holds.

**No escape hatch at all.** Defensible while every expression is pure, since an
unused binding is then dead code with no compensating purpose. Rejected: the
rule needs an answer for the case where a declaration is required by a shape
rather than wanted for a value, and deferring it would mean the first such case
arrives as pressure to weaken the rule instead of as a use of it.
