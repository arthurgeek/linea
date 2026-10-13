# 67. A compound assignment updates a place through itself

Status: Accepted — 2026-08-03

## Context

`a = a + b` names `a` twice, and a reader has to compare the two spellings to
see that they are the same place. Every language with assignment eventually
grows `a += b`, and the reason is legibility rather than brevity: one name, so
there is nothing to compare.

Linea has assignment and four arithmetic operators, and no way to combine them.

The obvious implementation is to desugar in the parser: read `a += b`, build
the tree for `a = a + b`, and let every pass below stay as it is. Nothing new
reaches the checker, ownership, or lowering.

That is wrong twice.

**It rewrites the programmer's source.** The tree is what the formatter prints
back, and a tree holding `a = a + b` prints `a = a + b`. This is the rule that
already makes parentheses a node:
[ADR 0005](0005-lossless-token-stream.md) keeps syntax in the tree where a
formatter requires it and the semantics have no use for it, and
[ADR 0036](0036-formatting-is-comma-driven.md) says the same from the
formatter's side, where a redundant parenthesis is kept and no token is ever
rewritten. It is also why `a.of()` does not come back as `Measure.of(a)`. A
formatter that normalises one spelling into another is editing rather than
printing.

**It evaluates the place twice.** `a` is a name today, but a place is a path,
and arrays landed one milestone ago. `xs[next()] += 1` desugars to
`xs[next()] = xs[next()] + 1`, which calls `next` twice and updates whichever
element the second call names. The bug is silent, it is a wrong answer rather
than a diagnostic, and it appears the moment anyone writes an effectful index.

The two objections are not one objection twice. Parentheses survive into the
tree because the formatter needs them and for no other reason; compound
assignment survives because the formatter needs it *and* because lowering does.
A spelling that carries evaluation order was never sugar to begin with, and this
is the first construct in the language where both reasons apply at once.

## Decision

`+=`, `-=`, `*=` and `/=` are four expression kinds of their own —
`add_assign`, `sub_assign`, `mul_assign`, `div_assign` — carrying the place and
the operand, exactly as the four binary operators carry their two operands.

**The left operand is a place, not a value.** This is the first arithmetic in
the language defined over one, and it is what makes compound assignment a
construct rather than a spelling. `a + b` evaluates two expressions to two
values; `a += b` evaluates its left side to a location and its right side to a
value, and both the read and the write happen through that one location. Every
rule below follows from that sentence.

**So the place is evaluated once.** Lowering takes its address, reads through
it, applies the operation, and writes back through the same address. There is no
step at which the path is walked a second time, so an effect written in an index
happens once and the element updated is the element read.

**The arithmetic is the operator's**, with the check the operator already has:
`a += b` overflows exactly where `a = a + b` overflows, and traps the same way.
`/=` divides by zero exactly where `/` does. No arithmetic rule is added and
none is changed.

**The operands are held to `[T-Operands]`**, the rule `+` already reports: both
sides are the same numeric type. A `Bool` is refused on either side by the rule
that already refuses it, and a Linear value has no arithmetic to do.

**The operand is read, not taken.** It is an operand of the operator, and
operands are read, so `a += b` leaves `b` where `a = a + b` leaves it. This is
the one thing the construct must *not* copy from `=`, whose right-hand side is
a consuming position — and copying it is the mistake that was made and caught
while writing this: `a += b` marked `b` moved, and every later use of it became
[O-Move].

**A binding only ever updated this way is still unused.** [N-Unused] asks
whether anything observes a binding, and the read this does feeds only the
write back to the same place, so nothing does. `var total = 0` with `total += 1`
and nothing else is refused, and that is the shape worth refusing: a total
accumulated and never returned. Permission and usedness are both the question
`=` asks.

**It has type Unit**, by [T-Assign]. An assignment yields nothing rather than
the value it wrote, and a compound assignment is an assignment; no rule is added
to say so.

**Permission belongs to the binding**, as it does for `=`. `a += 1` on a `let`
is `[N-Immutable]`, reported by the routine that reports it for assignment,
because the question — may this binding be written — is the same one.

## Consequences

Four tags rather than one with the operator recorded beside it. The operator is
recoverable from `main_token`, so one tag would work; four are chosen because
adding a tag breaks every exhaustive switch over `Expr.Tag`, and that list is
how the sites needing them are found. One tag would compile everywhere on the
day it was added and mean something new in each place.

The tag is also where the category lives, and not only where an exhaustive
switch finds it. `add_assign` and the `logical_and_assign` this record refuses
are not two settings of one construct — one always evaluates its operand and
the other would not — and a single tag with the operator read off the token
would lay them out as two rows of one table. Four tags say that the four which
exist are the four that can exist.

Lowering gains one routine and reuses two. `placeAddress` already answers
"where does this path live" for assignment and for `&`, and `readThrough` and
`writeThrough` already move a value across an address. A compound assignment is
those three in a row, which is why the place is naturally evaluated once: there
is only one call that could evaluate it.

The ownership graph sees three operations: a read of the place, a read of the
operand, and one write of the place. It emits those same three for `a = a + b`,
which is why no ownership rule changes and no diagnostic moves. What changes is
where the read of the place comes from — the construct's own walk rather than an
expression the parser invented. For a part it comes from `assigned` already,
which reads the binding a path reaches through before it writes; a whole binding
gets it from the walk.

`%=` is not added, because `%` does not exist. `&&=` and `||=` are not added:
they would short-circuit, so the right side is not always evaluated, and an
assignment whose operand sometimes does not run is a different construct
wearing the same syntax.

## Alternatives considered

**Desugar in the parser.** Rejected for the two reasons above — it rewrites the
source the formatter prints back, and it evaluates the place twice. The second
is not hypothetical: `xs[next()] += 1` is expressible today.

**One tag, operator read from the token.** Rejected because it adds a form that
every existing switch accepts silently. The four-tag version fails to compile
until each pass has said what it does, which is how this compiler has found the
sites for every construct added since `defer`.

**An operation of its own.** Some languages define `x += y` as a call —
`add_in_place(x, y)`, a trait method, an intrinsic — which makes `+=` mean
whatever a type says it means. Rejected: it would be the only arithmetic in the
language whose meaning is not its operator's, and there is no operator
overloading here for it to be consistent with. Compound assignment introduces no
arithmetic operation; it is the operator that already exists, applied between one
load and one store.

**Desugar in lowering rather than the parser.** This fixes the formatter
objection — the tree holds what was written — but not the evaluation objection,
because lowering the desugared shape walks the path twice for the same reason
the parser's version does. Computing the address once is the whole mechanism,
and it is only available to code that knows it is looking at one construct.
