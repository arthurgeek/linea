# 46. The universe of an instantiation is computed

Status: Accepted — 2026-07-28; refined by
[0051](0051-a-part-obliges-when-no-argument-can-remove-it.md), which decides
what a part of a generic declaration obliges before its arguments arrive.

The classification decision is superseded by [0124](0124-copyability-and-settlement-are-independent-capabilities.md).

Refines [0034](0034-ownership-is-positions-and-a-graph.md), which made a value's
obligations a question about positions and a graph rather than about its type.
That argument stands where it applies; this records a case it did not have to
draw.

The observation-boundary ownership rule is refined by
[0123](0123-observations-carry-owner-dependencies-through-callable-contracts.md).

## Context

A declared type says which universe its values belong to, and its author says
so: `linear struct Account` means an account must be consumed exactly once, and
the absence of the word means it need not be. That is a decision someone makes
about what the type stands for — an account is a resource, a point is not.

A generic type has no such decision to make. `Option[T]` is absence or
presence, whatever `T` is. Its author cannot say whether an `Option` must be
consumed, because that depends on what it is holding: an `Option[u8]` owes
nothing and an `Option[Account]` owes exactly what the account does. Writing
`linear enum Option[T]` would make the first wrong, and omitting it would make
the second unsound.

The same question reaches the parameter itself. Inside the declaration, `T` is
not yet anything. A body that consumes a `T` must be checked once and be right
for every instantiation, so the check cannot wait to see which.

## Decision

**A declared type's universe is written by its author. An instantiation's is
computed from its arguments, and an unbounded parameter is Linear.**

An instantiation belongs to the Linear universe when any of its arguments does.
`Cell[u8]` is Free, `Cell[Key]` is Linear, and nothing about `Cell` says so —
substitution does.

A type parameter with no bound is Linear inside the declaration that introduces
it. That is the pessimistic answer, and it is what makes one check of a body
sound for every instantiation: a body that may not drop a `T` may not drop
anything. `[T: Free]` is how an author asks for the other answer, and it
constrains what may be supplied rather than what the body may do.

## Consequences

A declaration is checked once. The alternative — checking a body again per
instantiation — would make an error's existence depend on what else the program
happened to call, so a library would compile until someone used it.

`Option[Key]` leaks under `[O-Leak]` with no rule of its own, because the leak
rule reads the universe and the universe was computed. The standard library
arranges nothing for `Account`, and could not have: `Option` was written before
`Account` existed.

The pessimistic default is felt. `fn take[T](sink a: T)` cannot drop its
argument, so a generic function that discards is a function that says
`[T: Free]`. That is the cost of checking once, and it is paid where the
programmer can see it — at the parameter, next to the word that would relieve
it.

0034 is refined rather than superseded. Its claim is that obligations follow
from positions rather than from types, and that is unchanged: what a position
does to a value is the same question here. What is new is that the universe a
position consults is, for one kind of type, derived rather than declared.

## Alternatives considered

**Infer a declaration's universe from its fields.** A `struct` holding a `Key`
would be Linear without saying so. This was rejected for concrete types when
0034 was written and the reason still holds: a type's obligations are part of
what it means, and a reader should not have to trace its fields to learn them.
An instantiation is different because there is no author to ask — the arguments
arrive after the declaration is written.

**Require a bound on every parameter.** `Option[T: Free]` and a second
`Option` for linear payloads. It doubles every generic type in the library and
answers a question the substitution already answers.

**Default a parameter to Free and check each instantiation.** Bodies would
compile that must not, and the error would appear at a call site in another
module with the declaration nowhere in view. Checking once is what keeps a
diagnostic next to the code that is wrong.
