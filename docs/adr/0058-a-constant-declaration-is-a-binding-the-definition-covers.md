# 58. A constant declaration is a binding the definition already covers

Status: Superseded by [0059](0059-one-table-answers-both-questions-about-a-constant-expression.md) — 2026-08-01

Extends [0020](0020-a-constant-expression-is-defined.md), which defined a
constant expression and closed its list with a clause about bindings. Reads
[0013](0013-no-undefined-behaviour.md) for why the definition is syntactic at
all.

## Context

[0020](0020-a-constant-expression-is-defined.md) ends its list with *a reference
to a binding whose initialiser is a constant expression*. When it was written
there was one kind of binding: a `let` inside a block. A module declared
functions and types, and nothing else, so the clause needed no words about where
the binding was written — there was one place it could be.

A module and an `impl` now declare constants. The clause has to say whether one
of those is a binding it covers, and the question is not decorative. The
primitive bounds are written as constants of the type they bound, so
`UInt8.max` is a name the standard library publishes; a conversion of it —
`Int16(UInt8.max)` — folds only if its operand does, and its operand is a
reference reached through a type rather than a bare name.

Read narrowly, the clause covers a local `let` and nothing else, and every
bound the library publishes stops being a constant expression at the point of
use. Every conversion table written against them would be checked when it runs,
which is exactly the information [0020](0020-a-constant-expression-is-defined.md)
exists to say the frontend already has.

## Decision

**A constant declared by a module or by an `impl` is a binding the last clause
of [0020](0020-a-constant-expression-is-defined.md) covers**, and a reference to
one is a constant expression however it is spelled. `UInt8.max` and a local
`let` bound to a literal are the same clause of the same definition.

This adds no clause. It says what the existing one means now that a binding can
be written somewhere it could not be when the record was made — which is why
this extends [0020](0020-a-constant-expression-is-defined.md) rather than
superseding it: nothing 0020 decided has changed, and its list is unaltered.

What the clause turns on is unchanged too, and it is not where the binding sits:
it is that the binding cannot be assigned again. A constant cannot — there is no
syntax that writes to one — so it qualifies for the reason a `let` does and a
`var` does not.

**A constant's initialiser is held to the definition, and that is [T-Const].**
Nothing runs where a constant is declared, so an initialiser outside the
definition has no value to bind. The membership test is on the shape of the
expression and never on what the checker managed to fold, for the reason
[0020](0020-a-constant-expression-is-defined.md) gives: a rule that accepted
whatever folded would make the valid programs a function of analysis quality.

## Consequences

The definition is now recursive across declarations rather than within one body.
A constant naming a constant naming a literal is a constant expression, and the
walk that decides it follows names between declarations. A constant that names
itself, directly or around a ring of them, is refused: the walk is bounded, and
past the bound the name is not a constant expression. Nothing orders one
declaration against another, so a cycle is written rather than caught by a
scope, and something has to stop the walk.

A constant has no storage. Because its initialiser is a constant expression,
lowering emits what it is bound to wherever the name is written, and there is no
slot for a constant to live in and no order in which constants are initialised.

Membership and folding are two questions about one definition, asked by two
routines. They can drift, and the direction they would drift in is visible: a
form that folds but is not admitted is a program refused for a rule the document
states, and a form admitted but not folded is a constant with no value, which
lowering cannot emit. Both fail loudly, which is why the second routine is
tolerable and the fold table is not read for membership.

## Alternatives considered

**Decide membership by asking whether the checker folded the expression.** One
routine instead of two, and it was the first thing tried. Rejected: a fold that
*fails* — an overflowing literal, a division by zero — leaves no value behind,
so a constant already refused for [T-Overflow] would be refused a second time
for not being constant, which reports one mistake twice. It also inverts
[0020](0020-a-constant-expression-is-defined.md): the definition would become
whatever the folder happens to do.

**Restrict the clause to local bindings and give constants their own rule.**
Rejected: it makes `UInt8.max` and `x` two kinds of name in a definition whose
whole subject is what a name reaches. The clause is about a binding that cannot
be assigned again, and where the binding was written is not part of that.

**Leave the clause as it stood and let it be read either way.** Rejected: the
narrow reading and the wide one differ on every conversion in the standard
library's bounds, and a definition that decides which programs exist cannot have
two readings.
