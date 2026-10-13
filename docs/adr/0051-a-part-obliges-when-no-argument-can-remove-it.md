# 51. A part obliges when it is Linear for a reason no argument can remove

Status: Accepted — 2026-07-29

Superseded by [0124](0124-copyability-and-settlement-are-independent-capabilities.md).

Refines [0046](0046-the-universe-of-an-instantiation-is-computed.md), which
decided that a declared type's universe is written by its author, an
instantiation's is computed from its arguments, and an unbounded parameter is
Linear inside the declaration that introduces it. All three stand unchanged.
What this record adds is the question 0046 left to the implementation: what
`[O-Universe]` asks of a *generic declaration's* part, before any argument
exists.

## Context

`[O-Universe]` says a Free type may not contain a Linear one, because a Free
type holding a linear part would be droppable by construction, which is the one
thing linearity exists to prevent. For a concrete type the check is direct:
walk the parts and ask each one's universe.

For a generic declaration it cannot be, and 0046 is the reason. An unbounded
`T` is Linear inside the declaration, so `struct Cell[T] { v: T }` is a Free
type holding a Linear part by the letter of the rule, and asking the question
directly would refuse every generic container anyone writes. Something has to
separate *Linear because of what the argument turns out to be, which the
instantiation settles* from *Linear already, whatever the argument is*.

The separation in the compiler is the question **does a parameter appear
anywhere inside this part** — if one does, the part obliges nothing. That is
wrong in one direction, and it is the unsafe direction:

- `Pair[Key, T]` mentions `T`, so `struct Bad[T] { p: Pair[Key, T] }` passes
  `[O-Universe]`, and inside a `[T: Free]` body the universe of `Bad[T]`
  computes to Free. A `Key` is then copied and both halves read, or
  destructured out of both halves and passed to a consuming function twice —
  the double-consume shape itself, not merely the leak shape.
- `struct Outer[T] { b: Box[Cell[T]] }` fails the same way one level further
  down. A guard added for the shallower case asks only whether the part's own
  *head* is declared `linear`, so it sees `Box` and not the `Cell` inside it.

The compiler disagrees with itself about these programs, which is the cleanest
statement of the defect: it accepts the generic form and rejects the hand
monomorphisation of that same form at `T = u8`, with `[O-Universe]` reported
against the very part it excused.

The predicate is not a diagnostic. A null answer sets the instantiation's
recorded universe to Free, so every rule downstream that asks about copying,
moving or leaking is answered wrongly, from one place.

## Decision

**A part of a generic declaration obliges that declaration unless some argument
its parameters admit makes the part Free.**

The rule is about the *admissible* arguments, and the default is to oblige. A
part is excused only by an argument that can actually be supplied, and the
compiler must be able to name one.

**Where a Free type is admissible at every parameter the part mentions,
substituting one decides the question outright.** The computed universe of
0046 reads nothing about an argument but its universe, so every Free argument
gives the same answer and which one is chosen does not matter; and a Linear
argument only ever adds linearity, so no argument makes a part Free that a Free
one leaves Linear. So if the part is Linear under the witness, it is Linear at
every admissible argument, and if it is Free under the witness, an admissible
argument exists that excuses it. That is a decision procedure, not an
approximation.

That case is every bound the language has today. An unbounded parameter admits
anything. A `[T: Free]` one admits a Free type by construction. `[T: Linear]`
is also an accepted spelling — `src/sema/resolve.zig` classifies both universe
names as bounds and rejects every other name as an unknown trait — and it
constrains nothing: `checkArgumentBounds` in `src/sema/typecheck.zig` refuses
an argument only where the parameter's own universe is `.free`, so a Free
argument is admissible under `[T: Linear]` too. A Free witness is therefore
admissible everywhere a parameter can appear, and the procedure answers the
rule exactly.

**Where the compiler cannot name a Free type a parameter admits, the part
obliges.** This is not a caveat for later; it is what keeps the rule sound when
the bound language grows. `resolve.zig` already reads an unrecognised bound as
a trait not yet declared, and under a trait bound the admissible arguments are
the types implementing that trait. If none of them is Free, the part is Linear
at every admissible argument and obliges — by the rule, not by caution. If the
compiler cannot decide whether a Free type is admissible, it obliges anyway.

Both answers err in the same direction on purpose. Obliging refuses a
declaration, which is an over-rejection a programmer can see and argue with.
Not obliging computes a Free universe for a type that owes something, which is
the under-rejection `[O-Universe]` exists to prevent and which shows up as a
double consume with no diagnostic. **A Free witness is a way of answering the
question when a Free argument is admissible; it is never a licence to excuse a
part when one is not.**

| part | with a Free witness | obliges, under this rule | obliges today |
| --- | --- | --- | --- |
| `T` | the witness, Free | no | no |
| `Box[T]`, `Box` free | Free | no | no |
| `Cell[T]`, `Cell` declared `linear` | Linear | yes | yes |
| `Pair[Key, T]` | Linear, from `Key` | **yes** | no |
| `Box[Cell[T]]` | Linear, from `Cell` | **yes** | no |
| `T` under a bound admitting no Free type | no admissible witness | **yes** | n/a |

The rule subsumes the head test rather than sitting beside it: `Cell[T]`
obliges because `Cell[witness]` is Linear, not because a special case names
`Cell`.

**The two halves are jointly complete, and each keeps its half.** A part that
is Linear at every admissible argument obliges at the declaration and is
reported there. A part that is Linear at some admissible arguments and not
others obliges nothing at the declaration and is caught at the instantiation by
0046's computed universe, with the argument in hand. Nothing falls between the
two, and the split is exhaustive by construction: either some admissible
argument makes the part Free or none does.

## Consequences

**The language rejects strictly more, and that direction is the point.** Every
program this refuses is one that today copies or drops a linear value with no
diagnostic. Nothing accepted today for a good reason becomes an error: the rule
reduces to the current answer for `T`, `Box[T]` and `Cell[T]`, which are the
containers the excusal exists to protect, and the table above is what pins
that. A change in the other direction would retire `[O-Universe]` rather than
complete it.

**A diagnostic arrives at the declaration rather than at a use.**
`struct Bad[T] { p: Pair[Key, T] }` is refused where it is written, whether or
not anything instantiates it. That is the trade 0046 already made when it chose
to check a declaration once: an error's existence must not depend on what else
the program happened to call.

**The predicate walks a type tree and mints types, so it needs instantiation to
terminate.** Substituting into `Pair[Key, T]` interns `Pair[Key, witness]`. A
declaration whose field instantiates the declaration itself at a growing
argument makes that walk unbounded — which is a defect on its own terms, and is
refused by `[T-PolyRec]`, the rule 0047 names as what makes lowering's queue
finite. This rule may not land before that refusal covers a declaration's
fields as well as a call's arguments, or the compiler hangs on a program it
should have rejected.

**A `Free`-bounded parameter stops disabling the check.** Today any parameter
anywhere excuses the part, including one that could not contribute linearity
under any argument. Under the witness rule such a parameter contributes
nothing, which is what its bound means, and the part is judged on what remains.

**A trait bound arrives with an obligation on this predicate, not a revision of
it.** Whoever lands trait bounds must make the predicate ask the bound for a
Free type it admits, rather than assume one exists. A bound whose admissible
set is empty of Free types answers "obliges"; a bound the compiler cannot
answer for answers "obliges". Nothing about the rule changes — the rule was
never about the witness — but code written as `substitute(Free) and ask` is
code that silently switches to the wrong default the day a second kind of bound
exists. The predicate's failure mode must be to oblige.

**Cost is one substitution and one universe query per part, at declaration
time**, on generic declarations only. A concrete part answers from the pool as
it does now. A bound that must be searched for a Free witness costs whatever
that search costs, and until traits exist there is nothing to search.

## Alternatives considered

**Keep the head test and add a level of nesting to it.** The smallest change,
and it is what the previous fix in this area did once already. Rejected because
it closes `Box[Cell[T]]` and leaves `Pair[Key, T]` open — the two reports have
nothing to do with depth. A rule stated as a number of levels is answered by
the next program with one more.

**State the rule as the substitution: a part obliges exactly when the Free
substitution is Linear.** Shorter, and it is what the implementation will do
while `Free` and `Linear` are the only bounds. Rejected because it is a
statement about one type rather than about the language, and it is wrong in the
unsafe direction the moment a bound admits no Free type: the substitution names
an instantiation nobody can write, finds it Free, and excuses a part that is
Linear at every argument anyone can actually supply. A rule whose soundness
depends on the bound language never growing is a rule that will be wrong
without anyone editing it.

**Read a parameter as Linear and drop the excusal entirely**, taking 0046's
pessimistic default literally at a part as well as at a body. Sound, and it
refuses `struct Cell[T] { v: T }` — every generic container in the standard
library. This is precisely the reading the excusal exists to avoid.

**Infer a generic declaration's universe from its parts**, so `Bad` becomes
Linear rather than an error. Rejected for concrete types when 0034 was written
and the reason still holds: a type's obligations are part of what it means, and
a reader should not trace its fields to learn them. 0046 drew the line where it
belongs — an instantiation has no author to ask, and a declaration does.

**Check each instantiation and let the declaration through.** Rejected by 0046
for the universe, and the same argument covers the part: a library would
compile until someone used it, and the diagnostic would appear in another
module with the declaration nowhere in view. Worth noting that today's
behaviour is a partial version of exactly this. The fixpoint over concrete
instances does catch `Outer[u8]` and does catch a use of `Bad` at a concrete
argument, which is why the hole is visible only from inside a generic body —
and why it went unnoticed. The cost is the one 0046 named: the diagnostic is
nowhere near the mistake, when it appears at all.
