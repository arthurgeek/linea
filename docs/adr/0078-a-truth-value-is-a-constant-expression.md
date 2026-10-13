# 78. A truth value is a constant expression

Status: Accepted — 2026-08-08; numeric truth-value representation superseded by [0127](0127-constants-retain-distinct-values-and-infer-their-types.md)

Extends [0020](0020-a-constant-expression-is-defined.md), whose list of
admitted forms this adds one entry to. Nothing else about that record changes:
the definition is still syntactic, still decides which programs are valid, and
is still answered from the one table [0059](0059-one-table-answers-both-questions-about-a-constant-expression.md)
built.

## Context

0020 enumerates what a constant expression is, and every clause of the list it
wrote reaches integers only. That was not a decision about truth values — the
record is about conversions that cannot succeed, and integers are what such a
conversion is between. The consequence went unstated until two features asked
for it in the same week.

A parameter may declare a constant its callers receive by omission
([0077](0077-arguments-match-by-name-and-evaluate-by-declaration.md)), and the
value is worked out where the parameter is declared because nothing runs at a
call that omits it. So `fn f(read on: Bool = true)` was refused: `true` is not
on the list. A module may declare a constant, which is a binding the last
clause covers, so `let FLAG: Bool = true` was refused by the same list through
a different rule.

Both refusals are the same missing entry, and neither is explicable to a
programmer. `true` is worked out without running anything — it is the shortest
expression in the language for which that is true — and the rule it fell foul
of exists to keep validity from depending on how much a compiler manages to
prove. Nothing has to be proved here.

The available shortcut was to admit a truth value where a default is written
and nowhere else, which is one sentence of code in the pass that folds
defaults. That is a second definition of "constant expression" living beside
the first, disagreeing with it on `let FLAG: Bool = true`, and it is precisely
the defect shape 0059 was written to remove.

## Decision

**A truth value is a constant expression.** `true` and `false` join the list in
[0020](0020-a-constant-expression-is-defined.md), which is the whole of the
change: every rule reading that list reads the new entry, so a default, a
module constant, an `impl` constant, and a name reaching any of them are
admitted together and by one table.

A folded value is a number and carries no type — a truth value is 1 or 0 in it,
as it is in the emitted instruction — and which type a value belongs to is the
declared type's to say, exactly as it already is for an integer literal. So
nothing about how a constant is recorded, spliced or lowered changes.

**The literal is admitted, and nothing built over it.** `!ready` and
`ready && ready` are not constant expressions, and neither is a variant of an
enum. Each of those is a further entry on the list, and the list grows when
something demands it grows rather than in anticipation. What the definition
must not become is a claim about what an implementation can work out: `!ready`
is trivially foldable, and that is not the reason to admit it — the reason
would be a program that needs it, which is the same standard every existing
entry met.

**A count is a number, and being a constant expression is not enough to be
one.** An array's length is folded from a constant expression, and the fold is
a number with no type attached, so `[UInt8; true]` would have read as a length
of 1. [T-ArraySize] therefore asks what the length *is* before it asks what it
is worth. This is the one place in the compiler where the type a fold came from
had been left implicit, because until now there was only one.

## Consequences

A constant no longer holds an integer and nothing else, which is a sentence the
semantics document made explicitly and now retracts. `Bool` is the second type
a constant may hold, and a third arrives by this list growing again.

A `Bool` default crosses a module boundary as its value, like every other
default: what a caller receives is 1 or 0 spliced at the call, so a default may
name a constant the module never exports.

The refusals that remain are refusals of *form*, not of type. A program told
`[T-Const]` about `!ready` is told the same thing a program is told about a
call, and for the same reason: the definition is a list, and this is not on it.

## Alternatives considered

**Admit a truth value only where a default is written.** Rejected: it is a
second definition of a constant expression, answering differently from the
first on a module constant, and the two would be maintained by different
people at different times. 0059 removed one such pair and recorded why.

**Admit the logical operators at the same time.** `!` and `&&` over constants
fold in one line each. Rejected: nothing asked for them, and every entry on
this list is on it because a program needed it. Admitting forms because they
are easy to fold is how a definition turns into a report of what the compiler
manages, which is what 0020 exists to prevent.

**Admit an enum variant at the same time.** Rejected for the reason above and
one more: a variant carries values ([0030](0030-a-variant-carries-several-values.md)),
so admitting one means deciding what a constant of an aggregate type is worth,
what the fold table holds for it, and what lowering emits where the name is
written. A truth value asks none of those questions — it is a number in the
table already.

**Give `Bool` its own table entry rather than the number 1 or 0.** Rejected:
the fold table records what an expression is worth and the type table records
what type it is, and a value knowing its own type would be the second answer to
a question that already has one. The instruction stream carries a truth value
as 1 and 0 for the same reason.
