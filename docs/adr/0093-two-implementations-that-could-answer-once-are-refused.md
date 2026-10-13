# 93. Two implementations that could answer for one instantiation are refused

Status: Accepted — 2026-08-17

Extended by [0213](0213-a-trait-may-be-implemented-for-a-callable-type.md)
with callable-type heads keyed by shape.

Superseded by [0139](0139-default-implementations-follow-ordinary-selection.md)
for explicitly marked default implementations. Ordinary coherence rules remain.

The constructor-only coherence partition is superseded by
[0148](0148-parameter-heads-match-complete-trait-keys.md); the structural overlap rule remains.

## Context

[ADR 0081](0081-an-implementation-is-generic-over-its-head.md) made an
implementation generic over its head and keyed coherence on the head's
constructor: one implementation per `(trait, trait arguments, head
constructor)`. To make that key trustworthy it also required every trait
argument to be written from the implementation's own head parameters —
`impl[T] Give[T] for Holder[T]` and `impl[T] Give[Option[T]] for Holder[T]`
are such implementations, `impl[U] Give[Bool] for Holder[U]` is not and was
`[T-Impl]`.

That record named its own boundary. Its Consequences section recorded, with
counterexamples, that the restriction is *necessary* for the key and is *not
sufficient* for coherence: two families that both satisfy it can still name
the same arguments at one member of each family, and nothing refused them.

```linea
impl[T] Give[Pair[T, T]] for Holder[T] { … 3 … }
impl[T] Give[Pair[T, Bool]] for Holder[T] { … 8 … }
```

Both settle to `Give[Pair[Bool, Bool]]` at `T = Bool`. The compiler accepted
both, and a call reached whichever the implementation-collection order put
first — 3 as declared, 8 with the two declarations exchanged and nothing else
changed. `impl[T, U] Give2[T, U] for Pair[T, U]` beside
`impl[T, U] Give2[U, T] for Pair[T, U]`, and `impl[T, U] Give[T] for Pair[T,
U]` beside `impl[T, U] Give[U] for Pair[T, U]`, are the same shape: two
families, both written from their own heads, agreeing at one instantiation
with no rule saying which body a call there runs. 0081 recorded this as
accepted only because closing it needs "a new overlap and unification
mechanism" it deferred.

Meanwhile the work to make a bound say what it means
needed the restriction lifted outright. R4 writes
`impl[T, A] Index[UInt64] for Vec[T, A]` beside
`impl[T, A] Index[FromEnd] for Vec[T, A]` — both write a trait argument
independent of `T` and `A` — which the restriction refused wholesale, with no
way to say that `UInt64` and `FromEnd` can never collide. Lifting the
restriction without answering 0081's open question would have put declaration
order back in charge of every program like it, R4's included.

## Decision

**This retires the clause of 0081 that required a trait argument to be
written from its own implementation's head parameters, and replaces it with
the overlap question that clause was standing in for:**

> Two implementations of one trait overlap when there exists a substitution
> for the type parameters of *both* declarations at once that makes their
> heads structurally equal and their trait arguments structurally equal. Two
> implementations that overlap are refused.

This is an existence question about one substitution moving both
declarations' parameters, not a comparison of one implementation against the
other and not a test of which is more specific. The two declarations'
parameters are never identified with each other by being spelled alike — each
declaration's own parameters are what the substitution may send anywhere,
independently of what the other's send. `impl[T] Give[T] for Holder[T]`
beside `impl[U] Give[Bool] for Holder[U]` is read as
`(Holder[T₁], Give[T₁])` against `(Holder[T₂], Give[Bool])`: the heads agree
at `T₁ = T₂`, and `Bool` is then what both answer.

**Ground** is what a substitution cannot move: a primitive, a name from
another module, or a constant like an array's length. A parameter of either
declaration under comparison is not ground. **A settled reference is not
ground either**, and the reason is its own clause below.

**An equation demanding a type contain itself has no solution.** Unifying
`Give[T] for Holder[T]` against `Give[Box[U]] for Holder[U]` gives `T₁ := T₂`
from the heads and `T₂ ≡ Box[T₂]` from the arguments; every Linea type is
finite, so nothing satisfies that and the two do not overlap. The occurs check
is what reaches that answer instead of looping, and is required rather than
defensive — `impl[T] Give[Box[T]] for Holder[T]` is a real implementation, and
an implementation reaching its own declaration through its own parameters is
[T-PolyRec]'s question, not this one.

**Overlap is checked at declaration time, over every implementation in one
`(trait, head constructor)` chain**, whether or not a program instantiates
either one — coherence is a property of the declarations, so a program that
compiled cannot start failing because a call was added. The head restriction
0081 keeps is what makes this checkable at all: because every head names its
constructor outright, `(trait, head constructor)` partitions every
implementation in the program into chains, two implementations with different
head constructors can never unify, and overlap is a comparison inside one
chain rather than a search over every implementation of the trait — the same
partition that already keeps selecting an implementation at a call a lookup
rather than a search.

**Argument lists that are both ground unify by equality**, which the exact key
already computed — a container with many settled index types costs nothing new
from this record. Unification runs only where at least one side is open.

## Consequences

**This closes 0081's limitation.** `Give[Pair[T, T]] for Holder[T]` beside
`Give[Pair[T, Bool]] for Holder[T]` unify at `T = Bool` and are now refused,
along with the other two counterexamples 0081 recorded. Which of two bodies a
call would have reached is no longer a question the language leaves to
declaration order — it is a question the compiler now answers at the
declaration, before any call is written.

**This is a new refusal.** Programs 0081 accepted, and that record's own
counterexamples, are `[T-Impl]` now. That is the cost of the rule and not an
oversight: two implementations answering one instantiation had no meaning
this project ever defined, so what goes red was never a program whose
behaviour was described anywhere.

**The restriction 0081 kept on writing trait arguments independently of the
head is lifted.** `impl[T, A] Index[UInt64] for Vec[T, A]` beside
`impl[T, A] Index[FromEnd] for Vec[T, A]` are both admitted: the arguments are
ground and distinct, so no substitution makes the two agree, and this is what
that work
needed to write `Vec`'s two `Index` implementations at all.

**A settled reference, as a trait argument, is possibly equal to every type,
because nothing at the declaration knows what an implementation will settle
it to** — a trait's declared types are settled independently, so nothing
stops one implementation settling two of them alike. Unification therefore
cannot prove a settled reference distinct from anything, and treats "cannot
prove distinct" as "possibly equal", which is the sound direction for a rule
whose job is to refuse what it cannot rule out. **The consequence: a trait may
carry at most one implementation for a given head whose trait argument is a
settled reference, whatever member it names.** `impl[T: Pair] Give[T.A] for
Holder[T]` beside `impl[T: Pair] Give[T.B] for Holder[T]` overlap on this
reading even though `A` and `B` are different declared types, because nothing
rules out some `T: Pair` settling both to one type. This is a real
restriction the language now has, not a limitation left open for later
unification to close — there is no unification left to do here that would
change the answer, because the thing being compared is a name the trait's own
declaration leaves open on purpose.

**Coherence is no longer purely a key comparison.** Where both argument lists
are ground it still is, at no new cost; where either side is open it is
pairwise unification against the rest of its chain. The quadratic term this
introduces is over the open implementations of one chain, never over the
chain's ground members and never over the program.

## Alternatives considered

**Widening the recorded limitation instead of closing it.** Leave 0081's
Consequences section as the last word and continue documenting that two
implementations can answer one instantiation with the winner decided by
declaration order. This is the state the record itself called unsound enough
to name and counterexample rather than merely note — two implementations
answering one instantiation with no defined choice is exactly the situation
coherence exists to prevent, so widening the documented exception is
documenting the defect rather than fixing it.

**Refusing a group that mixes constant and parameter-derived arguments.**
Keep comparing keys, but add a coarser rule: refuse a chain where one
implementation's trait argument is written from its head's parameters and
another's is not, without unifying either. It needs no unifier, which is real
savings, but it refuses harmless mixtures — `Index[UInt64]` beside
`Index[FromEnd]` on one `Vec` is exactly this shape and the two never collide
— and it leaves 0081's limitation open, because two families that are each
fully written from their own heads, like the `Give[Pair[T, T]]` pair, mix
nothing by this rule's own test and would still pass through unrefused.

**A specificity ranking between overlapping implementations.** Let the more
specific of two overlapping implementations win, the way some languages let a
concrete implementation override a generic one. It needs a *total* order on
specificity so that any two implementations in reach of one type are
comparable, and a guarantee that every call agrees on which one it reached —
which this project does not have and does not want to build, for the same
reason 0081 refused a head that is a pattern: nothing here ranks candidates by
specificity, and nothing needs a rule for what happens when two rank equally.
Which implementation a call reaches would depend on an order this project
does not define, rather than on the program being coherent or not.

## Relation to 0081

This record extends 0081 rather than superseding it: 0081's head rule — a
declared parameter appears in the head exactly once, in the order it was
declared, and nothing else stands in the head's positions — still stands, and
this record depends on it to keep overlap-checking local to one chain. What
this record retires is the one clause built on top of the head rule, stated in
0081's Decision under "An implementation's trait arguments are determined by
its head" — the requirement that every trait argument be written from the
implementation's own head parameters. It closes the "Known coherence
limitation" that clause's own Consequences recorded, where "the restriction
above is necessary for the key model and is not sufficient for coherence," and
its three counterexamples. 0081 is marked `extended by 0093`.
