# 40. Conditional control flow has one form

Status: Accepted — 2026-07-28

Builds on [0034](0034-ownership-is-positions-and-a-graph.md), which made a
conditional move a question the ownership CFG answers, and on
[0013](0013-no-undefined-behaviour.md), which requires every operation to be
defined.

## Context

Linea had `bool`, comparisons that produce one, and `if` and `while` that
consume one — and no way to operate on one. The only negation was `x == false`
and the only conjunction a nested `if`. `!`, `&&` and `||` close that.

`&&` and `||` are ordinarily primitive: a language gives them their own typing
rule, their own evaluation order, and their own lowering. That is three answers
to questions the conditional has already answered, and three answers that must
keep agreeing with it.

The agreement matters more here than in most languages. Short-circuit
evaluation means the right operand runs on one path only, so a value consumed
there is consumed on one path only — which is the ownership question Linea
takes most seriously, and which the CFG already answers for an `if` arm. A
second construct with conditional evaluation would be a second place that
answer has to be right.

## Decision

**Conditional control flow has exactly one semantic form in Linea: the
conditional expression. Every construct that evaluates an operand
conditionally is defined in terms of it.**

```
a && b   is   if a { b } else { false }
a || b   is   if a { true } else { b }
```

Not "behaves like". That is the definition the semantics document gives, and it
is what the compiler produces: lowering emits the conditional's branch, its
join and its slot.

`!e` is an ordinary unary operator over `bool`, and lowers to `e == false` —
no instruction, because a comparison against a constant already says it.

**The syntax tree records what was written.** `logical_and` and `logical_or`
are tags of their own; lowering, not parsing, is where they become the
conditional. Between the two, the type checker and the ownership pass reach the
conditional's own handling rather than repeating it.

## Consequences

Ownership needed no rule for the new operators. The arm they supply — a `false`
or a `true` — consumes nothing, so this is the shape the CFG already builds for
an `if` with no `else`, and `ready && release(k)` is rejected under `O-Merge`
with the same message the nested `if` produces.

The type error is `T-Condition`. The left operand of `&&` *is* a condition, so
the diagnostic a user sees is the conditional's, and no rule name was added.

MIR cannot tell the two apart, which is the point: the code generated for
`a && b` is the code generated for the `if` it stands for.

**The tree keeps the surface form, and must.** A tree holding
`if a { b } else { false }` could not be printed back as `a && b`, so the
formatter would rewrite source that was never wrong. This is the same reason
`grouped` is a node rather than being dropped at parse time.

Adding these tags was not a change one pass at a time. Every switch over
`Expr.Tag` is exhaustive on purpose, so the compiler named each pass that had to
classify them before it would build — the parser, the resolver, the type
checker, ownership, lowering, the formatter, the dump, and the generator's
coverage table. That is the intended cost of the exhaustiveness, and it is what
makes a new construct impossible to half-add.

A future construct that evaluates an operand conditionally — a coalescing
operator, say, once there is something to coalesce — joins this rather than
growing a lowering of its own.

## Alternatives considered

**First-class operators with their own typing, ownership rule and lowering.**
The usual design. Rejected because it puts three answers beside the
conditional's that must agree with it forever, and the ownership one is the
answer Linea can least afford to get wrong twice.

**Non-short-circuiting operators, evaluating both operands always.** Simplest
semantics, and no conditional moves at all. Rejected because it breaks the
idiom every programmer expects, and leaves no way to guard an operand that
traps — which matters in a language where arithmetic traps rather than wraps.

**Desugaring in the parser.** The tree would hold the conditional directly and
no pass would need a new tag. Rejected because the formatter could not then
reproduce the programmer's source, which is a cost the language has already
refused to pay for parentheses.

**A `not` instruction in MIR.** Rejected as unnecessary: `e == false` is what
`!e` means, the comparison already exists, and the backend already lowers it.

**Bitwise operators alongside.** `&` `|` `^` `~` `<<` `>>` were considered and
deferred, on the grounds [0018](0018-the-integer-model.md) gave for deferring
wrapping arithmetic: they are wanted for hashing and bit manipulation, and
Linea can express neither. Three decisions would have to be guessed without a
use case to settle them — what a shift by more than the width does, whether a
signed right shift is arithmetic or logical, and how a binary `&` reads beside
the `&x` that marks an argument. They should arrive with wrapping arithmetic,
since bit manipulation that traps on overflow is not bit manipulation.
