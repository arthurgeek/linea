# 3. The lexer and parser never fail

Status: Accepted — 2026-07-24

## Context

Linea is intended to support a formatter and a language server. Both consume
source that is syntactically invalid most of the time it is read: an editor
requests a tree on every keystroke, and a keystroke is usually mid-token or
mid-expression.

A frontend that returns an error instead of a tree gives such tools nothing to
work with — no outline, no completion, no hover — precisely when they are most
needed. Separately, a compiler that reports one error per invocation forces the
programmer into a fix-and-recompile loop.

## Decision

Neither the lexer nor the parser has an error path. Both report problems by
appending to a diagnostic sink, which is data flowing sideways rather than
control flow propagating upward, and only the driver decides to stop — between
passes, by consulting the sink's error count.

The lexer returns tokens only. An unrecognised byte produces an `.invalid`
token covering it, and lexing continues.

The parser obeys four invariants.

**1. Never fail.** Every input produces a complete `Ast`.

**2. Never invent valid syntax.** A missing construct becomes an `err` node,
never a guessed replacement. `1 +` parses as `add(1, err)` — not `add(1, 0)`,
not `1`, and not by reaching past the operator for something that might serve
as an operand.

**3. Recover at the smallest grammar production whose end can be identified
without speculation.** Preserving enclosing structure beats replacing it with
an `err` node: `a + * b` should yield `add(a, err)` rather than a single `err`
covering the statement, because a tool can still resolve `a`.

"Without speculation" is defined by a **follow set** per production — the
tokens that may legitimately terminate it. An `err` node ends at the nearest
token in the follow set of an enclosing production. Where a delimiter bounds
the hole, the `err` is exactly that hole; where none does, the `err` widens to
the enclosing production's terminator. This is what makes the invariant
mechanical rather than a judgement at each call site.

**4. Each `err` node is diagnosed exactly once.** Later passes may traverse an
`err` subtree when they need the surrounding context, but must not emit a
diagnostic whose cause is already represented by that node.

The mechanism is poison propagation: an `err` node yields a poisoned value — an
error type, an unresolved symbol — poison propagates through any operation
consuming it, and no pass diagnoses a poisoned operand. This turns the
invariant into a data-flow property rather than a discipline. In `call(foo,
err)` the resolver still resolves `foo` and still reports it if undefined,
while the poisoned argument suppresses any arity or type complaint.

Allocation failure remains a Zig error and is unrelated to source validity.

## Consequences

- Every input yields a tree, so tooling has something to operate on
  unconditionally.
- One invocation reports many errors.
- `.invalid` and `err` are ordinary values on the normal path, so callers do not
  branch on a result union at every step.
- Recovery quality becomes a correctness property that has to be tested rather
  than an emergent behaviour. `tests/recovery/` asserts both the recovered tree
  and the diagnostics for malformed input.
- Downstream passes must tolerate `err` nodes and must carry a poisoned value
  through any operation that consumes one. The cost is a poison case in every
  pass that computes a value; the benefit is that one typo produces one
  diagnostic rather than one per pass that notices it.
- Recovery is bounded by the grammar's follow sets, so each new production
  added to the language brings a recovery obligation with it. A production
  whose follow set is not stated has no defined recovery behaviour.
- Preferring the smallest recoverable production means more recovery paths than
  a single statement-level synchronisation point, and each is a place the
  parser could invent structure. Invariant 2 is what keeps that in check, and
  `tests/recovery/` is what proves it.

## Alternatives considered

**Error unions — `fn next() !Token`.** Rejected: stops at the first bad byte,
so tooling gets nothing and the programmer gets one error per run.

**A result union — `union(enum) { token, err }`.** Reports many errors and
allows continuation, so it satisfies the diagnostic requirement. Rejected: it
carries the same information as an `.invalid` token while forcing every caller
to branch, and callers that only want to skip trivia or match a tag are
obstructed by a distinction they do not care about.

**Panic on malformed input, validate separately.** Rejected: two passes over
the same grammar drift apart, and the language server needs a tree from the
invalid input rather than a verdict about it.

**Synchronise only at statement boundaries.** One recovery point, almost no
machinery, and every malformed statement becomes a single `err` node. Rejected:
it discards structure that was parsed correctly. `foo(1,,3)` loses the fact
that a call was written at all, and `a + * b` loses a resolvable `a` — exactly
the context an editor needs from the region around a mistake.

**Insert the token the parser expected, as rustc does** for missing commas,
semicolons and braces when confidence is high. Produces better messages for
common typos, and is a reasonable trade for a compiler with a large diagnostics
effort behind it. Rejected: a wrong guess produces a tree the programmer did
not write, and every later pass then reports errors about syntax that does not
exist. Swift's error expressions are the closer model.
