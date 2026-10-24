# 47. Instantiation is a backend concern

Status: Accepted — 2026-07-28. Extended by
[0142](0142-construction-derives-expand-to-ordinary-source.md) with the
finite-height proof for generic call cycles. The ordinary-fields clause
superseded by [0248](0248-an-instantiation-holding-a-parameter-is-written-when-read.md):
an instantiation holding a type parameter has its fields written when read.

Builds on [0028](0028-a-type-is-a-pool-handle-and-layout-is-a-table.md), which
made a type an interned handle, and on
[0012](0012-immutable-representations.md), which asks a new representation to
justify itself.

## Context

Generics are usually a pass. A monomorphisation stage walks the program,
stamps out a copy of each generic declaration per instantiation, and hands a
generic-free program to everything downstream. That is a representation, a
traversal and a set of invariants of its own.

Linea needed none of it, and the reason is that the questions divide cleanly.
*What does this declaration mean* is a question about one declaration, answered
once, before anything is instantiated. *Which copies of it exist* is a question
about what the program reaches, and reachability is already what the backend
decides — nothing is lowered that `main` cannot reach.

The type pool made the middle piece cheap. A type is a handle, and
substitution produces a handle: `Cell[u8]` is interned the same way `u8` is, so
an instantiation is an ordinary declared type with ordinary fields and an
ordinary layout. Nothing downstream needs a case for it.

## Decision

**Generics add no pass and no representation. A generic declaration is checked
once, and instantiation happens at lowering, driven by reachability from the
entry point.**

Lowering drains a work queue. `main` is wanted; lowering a body claims a handle
for every instantiation it calls, and the queue grows behind the cursor until
nothing new is reached. A function is emitted once per distinct set of type
arguments, under a symbol carrying them.

**The pool is an append-only intern table, not a pass's output.** Lowering
interns instantiations the checker never saw — a body may name a type no
written annotation does — and that is allowed because the pool only grows:
entries never change and handles never move.

## Consequences

A generic declaration nothing calls costs nothing. It is checked, and then no
code is generated for it, because the queue never reaches it.

The set of instantiations must be finite, and that is a language rule rather
than a limit. `[T-PolyRec]` refuses a recursive call that instantiates its
callee with arguments larger than the ones it was given, which is what makes
the queue terminate. Without it a program stands for infinitely many functions
and lowering runs until it runs out of memory — an implementation limit
standing in for a rule, which is what the rule exists to avoid.

Every structural question the lowerer asks must see the pool as lowering
extended it, not as the checker left it. Asking the checker's own pool about a
type minted since is an index past its end, and that is exactly the bug this
arrangement invites.

The correspondence is recorded rather than recomputed. A lowered function
carries the declaration and arguments it came from, so a tool can report which
copies exist without working out reachability a second time — which would put
that rule in two places.

## Alternatives considered

**A monomorphisation pass before lowering.** The conventional answer, and it
would produce a representation that discards nothing, adds no node a side table
could not key, and simplifies no pass — the three things 0012 asks a new
representation to do. It would also have to answer reachability, which lowering
answers already.

**Erasure: one copy, values boxed or passed behind a pointer.** It removes the
termination question and costs an indirection on every generic operation. It
also breaks the layout story: 0028 makes a type's layout a table the module
carries, and an erased `Cell[T]` has no layout to put in it. A systems language
that made every generic container indirect would be paying for a feature its
users would then avoid.

**Instantiate in the checker, keeping a list of every instantiation in the
program.** The checker would answer a question about the whole program rather
than about one expression, and would have to decide reachability to avoid
emitting copies nothing calls. The checker records what one call settled; which
copies exist is decided where code is emitted.
