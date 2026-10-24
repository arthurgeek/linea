# 246. A call holds what it lends until it runs

Status: Accepted — 2026-10-24. Extends
[0034](0034-ownership-is-positions-and-a-graph.md),
[0204](0204-mir-verification-re-derives-storage-safety.md) and
[0228](0228-a-granted-module-calls-c.md).

## Context

Ownership walks a call's arguments in the order they are evaluated, and a
reading position emits a read where it is written. A callee does not read its
parameters there: it reads them after every argument has been evaluated, while
it runs. Nothing in the graph said so, so a take written after a lend of the
same place was accepted:

```linea
fn both(a: mem.Vec[UInt8], sink b: mem.Vec[UInt8]) -> UInt8 {
    b.release()
    a[0]
}

both(v, v)
```

`both` reads `a` after releasing `b`, which is the same storage: the program
compiled, and read freed memory that a later allocation had reused. Written with
the parameters the other way round, `both(v, v)` was refused as a use after a
move ([O-Move]). The same hole opened for every shape of take that runs after a
lent argument: `f(v, g(v))` with `g` taking `v`, a `let` inside a block
argument, a structure literal's field, a lent field beside its sunk whole
`f(s.items, s)`, a lent receiver `b.take(b)`, and a C handle passed `read` and
`sink` to one `extern`. A view or a capture passed beside its owner was already
refused, because the dependency analysis asks at the call whether each
argument's observations survived what the other arguments did
([O-Borrow]); the place an argument names was the one thing nothing asked.

The MIR verifier ([0204](0204-mir-verification-re-derives-storage-safety.md))
missed the direct form for the same reason in its own representation. It
checks a call's argument reads against the state before the call and applies
the call's moves after, so a read address and a `sink` address of one slot in
one `call` passed. The nested forms are separate instructions, and it refused
those as a compiler defect.

## Decision

**A call lends every argument it does not take, and its receiver, until the
callee has run.** After evaluating such an argument the ownership graph holds
each place the argument's value names — through grouping, `&`, and the branches
of a conditional, block or `match` — pending on the call, and the call's
completion ends the hold. A whole-binding take of a held root before then is
[O-Move]: the callee would read or write a value that was given away. It is
judged where the call is reached, so a take on a path that leaves first, a
branch of an argument ending in `return` or a `let … else` that returns, is
judged by where that path goes. An operator is a call of its trait's
operation, `a == b` being `equals(a, b)`, so its operands are held the same
way, and the dependency analysis asks at the operation what each operand
observes, as it asks at a call. A scalar
snapshot lends nothing, two lends of one place share it, and `f(p, copy(p))`
lends `p` beside a copy of it.

The rule is ownership's because whether an expression takes a value is decided
by its position, and ownership is where positions are computed: a `sink`
argument, a nested call's `sink` argument, a `let` initialiser in a block, a
literal's field and a consuming `match` all take, and the one rule covers them
all. Both orders of `both(v, v)` are now [O-Move], one as a take of what is
held and the other as a use of what was taken.

Which argument *mutates* a place another names remains [N-Aliased], answered
from the argument list by the checker
([0053](0053-exclusivity-is-triggered-by-mutation.md)). A handle an `extern`
takes without `read` is one such mutation, decided in the same routine as `&`
and assignment rather than by a check of its own, so a handle lent to change
inside a nested call is seen as well as one at the top of the list.

**The verifier refuses a lent address into a root a `sink` argument of the
same call moves.** That is a refusal ownership now also makes, so it meets
0204's admission condition.

## Consequences

`both(v, v)` and its relatives are refused before they run. A program that
meant one of them writes `copy` where the value is copyable — the diagnostic
offers the edit — or gives the value away after the call.

`f(p, copy(p))` was refused by [O-CopyDead] because the graph saw no read of
`p` after the copy; the hold is that read, so the program is accepted.

A conditional argument holds each place its branches name on every path, so
`f(if c { v } else { w }, v)` with the second parameter `sink` is refused even
where `c` would pick `w`. The hold is carried as the open transfers are, by
union at a join, and that is the answer they already give.

The soundness matrix gains a dimension for an observation and a move met in
one call.

## Alternatives considered

**Count a `sink` argument as a mutation in [N-Aliased].** It answers the
top-level form from the argument list, as the user-facing rule reads. The
nested forms need to know which positions take, so the checker would have to
classify positions a second time, beside ownership; a take inside a block or a
literal would be answered by one pass and a `sink` argument by another, two
answers to one question.

**Make every lent argument an observation in the dependency analysis.** The
argument's place would then be a fact the call's stale check asks about, and
the report would be [O-Borrow] like a view's. It seeds a fact for nearly every
call of every function, where the analysis today runs only for functions that
hold observations, and the move it reports is already the move checker's
question.

**Leave the verifier as it is.** The direct form would then rest on ownership
alone, which is the position 0204 was written to leave.
