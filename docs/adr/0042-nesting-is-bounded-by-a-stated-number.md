# 42. Nesting is bounded by a stated number

Status: Superseded by [0054](0054-the-bound-is-on-height-and-covers-written-types.md) — 2026-07-28

Builds on [0013](0013-no-undefined-behaviour.md), which requires every
operation to produce a defined result or a diagnosed error, and on
[0003](0003-infallible-frontend.md), which requires the frontend to return a
complete tree from any input.

## Context

The compiler reads a program by recursive descent, and every later pass walks
the tree the same way. Each level of nesting therefore costs a stack frame, and
the stack is a resource the language does not describe.

Nothing bounded it. A deeply nested expression aborted with SIGABRT — between
ten and fifteen thousand levels in a debug build, and somewhere else in every
other build, because frame size depends on optimisation and on whether a
sanitiser is present. The same file was a program under one build and a crash
under another.

That is a limit enforced by running out. It has three faults. It is not a
number anyone can be told. It is not the same number twice. And it is reported
by the process dying, which no diagnostic can be attached to and no tool can
recover from — a formatter or a language server handed such a file dies with it.

## Decision

**An expression nests at most 1000 levels. Deeper is `[S-Nesting]`, an
ordinary diagnostic.**

The number is chosen an order of magnitude below where any build mode runs out
of stack, so it is the same everywhere rather than a property of how the
compiler was built. A rule with a number in it is worse than a rule without
one, and better than a rule whose number depends on the build.

The count is kept in one place — the point every expression passes through
exactly once. A form that nests without a delimiter, such as a chain of unary
operators, is bounded by the same rule rather than by a second one that has to
be remembered. **Bounding the tree in the parser bounds every later pass**, each
of which walks the same shape: the printer, the resolver, the type checker and
lowering all inherit the bound without knowing it exists.

At the limit the parser refuses to descend and steps over what it would have
read, **balanced**, so the delimiter the caller is waiting for is still where it
expects one. Returning an error node without consuming would leave a thousand
frames each reporting the brace it could not find, which describes one mistake
a thousand times. One diagnostic is emitted, and the tree is complete.

## Consequences

**A pathological file is now a diagnostic.** Half a million levels reports and
exits 1 in every build mode. Tooling built on the frontend survives input it
previously died on, which is what [0003](0003-infallible-frontend.md) asks for
and what the abort denied.

**The printer's own limit is no longer reachable.** It recurses per node as the
parser does, so it is never handed a tree deeper than the parser accepted. The
formatter test that nested deeply asserted this against the stack; it now
asserts it against the stated number.

**The number is now a compatibility surface.** Lowering it rejects programs
that used to build. It is high enough that nothing written by hand approaches
it, and a generator that produces something deeper has found a bug in itself —
which is the other reason the limit reports rather than aborts.

## Alternatives considered

**Stating the bound without enforcing it** — documenting the observed limit and
leaving the abort in place. This was the original proposal from the formatter
review. Rejected because a documented number that the code does not check is a
number that drifts: it was measured in one build mode and is wrong in the
others, and nothing fails when it changes.

**Growing the stack, or moving the parser to an explicit one.** An explicit
stack removes the limit rather than stating it, at the cost of rewriting
recursive descent as a state machine — and every later pass with it, since they
recurse over the same shape. That is a large change to make a pathological
input work, and it would still need a bound on allocation. Reconsidered only if
a real program is ever refused.

**Counting bracket depth in the lexer instead.** Cheaper, and wrong: it counts
delimiters rather than frames, so a chain of unary operators — which nests with
no bracket at all — would still abort.
