# 59. One table answers both questions about a constant expression

Status: Accepted — 2026-08-01; extended by [0140](0140-aggregate-constants-retain-checked-construction-plans.md)

Supersedes [0058](0058-a-constant-declaration-is-a-binding-the-definition-covers.md),
which decided that a constant declared by a module or by an `impl` is a binding
the last clause of [0020](0020-a-constant-expression-is-defined.md) covers, and
that membership and folding could be two routines. The first half is unchanged
and restated here. The second is what this overturns.

## Context

0058 kept two routines over one definition: one deciding whether an expression
is a constant expression from its shape, one folding it to a value. It said the
duplication was tolerable because the two could only drift loudly — *a form
admitted but not folded is a constant with no value, which lowering cannot
emit*.

That sentence was never true of the compiler it described. A constant has no
storage, so lowering emits one by emitting its initialiser wherever the name is
written. A form the shape test admitted and the folder did not fold is emitted
as an ordinary run-time computation, and nothing anywhere says so.

The drift then happened, in the shape a reader of the record would not have
looked for. The folder filled its table by sweeping the constants in the order
they were declared, so a constant naming one written below it folded to
nothing, while the shape test — which follows names in either direction —
admitted it. Given

```
pub let a: UInt8 = b + 200
pub let b: UInt8 = 200
```

the compiler accepted the program and let it trap at run time; with the two
declarations exchanged it reported `[T-Overflow]`. Two meanings for one
program, decided by writing order, against a language in which nothing orders
one declaration against another.

0058's *Alternatives considered* weighed reading the fold table for membership
and rejected it, correctly, for the table it had: a fold that fails leaves no
value, so an expression already refused for `[T-Overflow]` would be refused
again for not being a constant expression. What it did not weigh is a table
that records *why* a value is absent.

## Decision

**A constant declared by a module or by an `impl` is a binding the last clause
of [0020](0020-a-constant-expression-is-defined.md) covers**, and a reference to
one is a constant expression however it is spelled. `UInt8.max` and a local
`let` bound to a literal are the same clause of the same definition. What the
clause turns on is that the binding cannot be assigned again, not where it was
written. This is 0058's decision, carried forward unaltered.

**One table answers both questions, and every expression has an entry in it.**
An entry is one of three things:

- **not a constant expression** — the definition does not admit the form;
- **no value** — there is nothing for the expression to be worth. The
  definition admits the form and the value does not exist: an operation with no
  result in its type, a literal outside it, a division by zero, a ring of
  constants each waiting on the next. Or the expression was refused outright,
  and asking whether the definition admits a form that was already rejected has
  no answer worth having;
- **a value.**

Membership is *the entry not being the first of those*. `[T-Const]` is said
where an initialiser's entry is the first, and nowhere else; the middle case
was reported where it was written, so nothing is said about it twice.

*Every* expression means every one, and the middle entry is what makes that
affordable. An entry no rule fills is an expression the table answers for by
accident, and the only accident available is the first entry — which is the one
`[T-Const]` is said about. So a refused region takes the middle entry rather
than none, and a constant naming one is told nothing further: what is wrong
there is what was already said about the name it reaches.

Each entry is decided from the form and its operands' entries as the checker
reaches the node, which is the same syntactic rule
[0020](0020-a-constant-expression-is-defined.md) states, computed once. A form
the definition admits over operands that are not constant expressions is not
one either; a form it admits over operands that are gets the middle entry when
the value does not exist. Which programs are valid therefore still does not
depend on how much folding a compiler manages — that was
[0020](0020-a-constant-expression-is-defined.md)'s reason for defining
membership syntactically, and it survives, because what is syntactic is the
rule filling the table rather than a second walk beside it.

**A constant's initialiser is taken when something first needs its value, and
taken once.** A name reaching a constant takes that constant first, so what the
name is worth does not depend on where the declaration sits. The constants are
still walked in the order they were declared — something has to reach the ones
no name reaches — but that walk decides nothing: every constant it arrives at
has either been taken already or is taken there, and the two are the same
answer. The order it goes in is visible only in where a ring is reported, which
is the reference that closes it. A constant reached from its own initialiser
closes a ring; the ring is refused, reported once where it closes, and named as
a ring rather than as members that each separately fail to be constant.

**The walk over names is not bounded by a number.** 0058 bounded it, because a
ring had to stop the walk somehow and a depth count was what it had. A ring is
now recognised exactly, so the bound has nothing left to catch and refused
programs the definition accepts — a chain of 66 constants was rejected for its
length. Nothing about how long a chain may be is stated anywhere, and nothing
enforces a length.

## Consequences

The definition is recursive across declarations rather than within one body. A
constant naming a constant naming a literal is a constant expression, and the
walk that decides it follows names between declarations in whichever direction
they lead.

A constant has no storage. Lowering emits what it is bound to wherever the name
is written, and there is no slot for a constant to live in and no order in
which constants are initialised. That lowering re-derives the initialiser is no
longer a place two answers can disagree, because there is only one answer to
disagree with.

The stack is what a chain of constants now spends, at a few frames per link,
and this is the only walk in the compiler whose depth is the length of a chain
of declarations. Every other recursion goes down a written form, which
[0042](0042-nesting-is-bounded-by-a-stated-number.md) bounds and states a
number for. So nothing else gives way first: a chain of 8 000 constants is
checked, and one of 50 000 exhausts the stack and crashes — not a diagnosed
error and not the exit status a refused program gets, which is exactly what
[0042](0042-nesting-is-bounded-by-a-stated-number.md) exists to keep off
well-formed source.

This record takes that on knowingly rather than by not having looked. The
lengths involved are far past anything a program is written with, and the price
of the alternative is a number in the language that says how many constants may
name one another — a rule about the language to pay for a property of the
implementation. What is owed is a bound stated in the semantics document beside
the other stated bounds, on the day a chain that long appears; what is not owed
is the number before then.

## Alternatives considered

**Keep the two routines and fix only the ordering.** The order-dependence goes
away and the duplication stays, with its stated justification now known to be
false: the two can still disagree and lowering will still emit the disagreement
silently. Rejected because the second routine is exactly the shape of defect
this compiler keeps producing — one rule with two implementations, the second
individually plausible, disagreeing only on the input nobody wrote.

**Keep the two routines and make lowering fail loudly instead**, by emitting a
constant from its folded value rather than from its initialiser. This makes
0058's sentence true, and it is a real improvement on its own terms. Rejected
as a substitute: it converts a silent divergence into a loud one without
removing the divergence, and it makes lowering unable to emit a constant of any
type the folder does not produce values for, which is a restriction the
language does not state.

**Bound the chain of names and state the number**, keeping the walk otherwise
as it was. Rejected: the bound existed to stop a ring, and once rings are
recognised the number buys nothing that would justify a rule saying how many
constants may name one another. A stated bound is better than an unstated one,
and no bound is better than either where nothing needs one.
