# 77. Arguments match by name and evaluate by declaration order

Status: Accepted — 2026-08-08. Callback implementation names refined by
[0136](0136-callback-binders-are-local-to-the-implementation.md).

## Context

A call may name the parameter an argument fills, and a trailing `read`
parameter may declare a constant that a caller omitting it receives.

```linea
fn pad(read s: Str, width: UInt8 = 8, fill: UInt8 = 32) -> Str

  pad(name)                       // both defaulted
  pad(name, fill: 46)             // width defaulted, skipped by name
  pad(name, fill: 46, width: 12)  // named arguments in any order
```

Most of the design answered itself. The spelling is the parameter's own
declaration with the type replaced by the value, which is byte for byte what
the parameter hints already render at every call, so the notation was chosen
before the feature existed. Positional arguments forming a prefix follows from
there being nothing else position could mean once names begin. Those are
recorded in the semantics document — `[S-Args]`, `[S-Default]`, `[T-Call]`,
`[T-Default]` — and need no decision record, because there was no second option
anyone would defend.

Two questions had no such answer. Each had a defensible alternative, each was
decided, and four passes now rest on the answer.

The first is **when an argument's expression runs**. While every call was
positional, "the order the arguments are written" and "the order the parameters
are declared" were one sentence. Names separate them, and a language must say
which one it means.

The second is **what a default may be**. Any expression is strictly more
expressive than a constant, and every question that makes it hard — where it is
evaluated, what it can see, who owns what it produces — is a question a language
can answer. The choice was not whether they are answerable but whether they are
worth answering now.

A third thing settled itself while the trait seam was being written, and is
recorded here because it departs from what the original design said. That
design says an implementation's parameter names *equal* the signature's. Plain
equality cannot be implemented: `[N-Unused]` obliges a body that ignores a value
it takes to mark the parameter with a leading `_`, and a `read` parameter offers
a body no other way to discharge that. Held to the letter, an implementation
ignoring one of its arguments could not be written at all.

## Decision

### Argument expressions evaluate in the callee's parameter order

**Whatever order the call spells them.**

```linea
fn log(read a: Str, read b: Str) -> Unit

  log(b: shout(), a: whisper())   // whisper() runs first
```

This is what makes named arguments reorderable at all. Under written-order
evaluation, two spellings of one call become two programs the moment an
argument has an effect, and the freedom to write the names in any order stops
being a freedom and becomes a semantics: `log(b: x(), a: y())` and
`log(a: y(), b: x())` would have to be read as different programs that happen
to pass the same values.

Under declaration order, permuting a call's named arguments provably changes
nothing, and the conformance suite is where that stops being a claim.
Permutation joins the meaning-preserving rewrites beside reversed declarations
and rotated match arms, so every case that names two arguments is compiled
again with them rotated, and there is nothing to accept and no golden to
update — the program is its own expectation.

**The rewrite is held to the emitted code and not to the answer.** Comparing
answers alone would leave the rule unchecked wherever the arithmetic commutes:
`add(a: 40, b: 2)` returns 42 under a lowering that reads written order too.
Holding the two spellings to byte-identical IR is tighter than the rule
strictly demands — a lowering that reordered two arguments it had *proved*
unobservable would be within the rule and would fail here — and that trade is
deliberate. Declaration order is a stated rule rather than an implementation
detail, so the day a lowering wants to depart from it, the departure is what
should be argued for.

The language already leans this way. `[N-Aliased]` exists so that what a callee
receives cannot depend on the order the arguments happened to be evaluated in;
pinning the order to the declaration is the same instinct stated positively.

### A default is a constant expression, on a trailing `read` parameter

**The constant expression the language already defines** — `[T-Const]`, read out
of the one table that answers both questions about one ([ADR 0059](0059-one-table-answers-both-questions-about-a-constant-expression.md))
— **of the parameter's declared type.**

A default therefore has no runtime evaluation site. It is worked out where the
parameter is declared, once, and a call that omits the parameter receives the
value by splice, lowering laying it into the argument list directly. Every
question a computed default would raise is not answered but absent:

| A computed default would need | A constant one |
| --- | --- |
| a run-time evaluation site, at the call or at the declaration | needs neither; the value exists before any call is compiled |
| a scope for the expression to see | sees nothing — a call is not a constant expression, and neither is a sibling parameter |
| an ownership story for what it produces | produces no owned value to account for |
| an `[N-Aliased]` story, since what it produces could overlap another argument's place | has no place to overlap, and the omission evaluates nothing |
| a monomorphisation story, since the expression could mention a type parameter | has nothing to specialise; a parameter of abstract type admits no default at all |

It also makes writing the constant out and leaving it off one program: `f()` and
`f(x: 1)` are the same call when `1` is what `x` declares. What crosses a module
boundary is the value and not the expression, so a default may name a constant
its module never exports and `[M-Vis]` is untouched — no name reached the
caller.

**Only a `read` parameter may carry one.** `inout` names a caller-owned place to
mutate, which a default cannot supply. A `sink` default would construct a fresh
owned value invisibly at some call sites and not others, which is implicit
construction at a distance in a language whose rule is that nothing is
duplicated implicitly.

**Defaulted parameters form a suffix.** Named arguments could reach past a
defaulted middle parameter, so this is chosen rather than forced. It keeps
legal omission a suffix story — what a well-formed call may leave out is always
the tail, never a gap — and keeps a positional caller from landing mid-list on
a parameter the author expected to be skipped.

### A trait member's parameter names are the signature's, up to the marker

**Names and defaults belong to the trait signature and only there.** An
implementation declares each parameter under the name the signature gives it,
and declares no default of its own. Both facts belong to the declaration every
call is checked against: an argument naming the parameter it fills spells what
the trait declares, and a call that omits one receives what the trait declares
for it. A member renaming a parameter declares a name no call can write, and a
member declaring a default declares a value no call can reach.

**Name equality is equality up to a leading `_` on the implementation's side,
and nowhere else.** The two sides are not the same question:

- The implementation's `_` is read as the marker it is. `[N-Unused]` obliges a
  member that does not use a value it takes to write one, and admits no other
  spelling, so a member implementing `width` as `_width` has renamed nothing.
- The signature's spelling is read letter for letter. A signature has no body to
  leave a value unused in, and its spelling is what every call that names the
  parameter writes — so a `_` there is part of the name, and a member dropping
  it names something no call does.
- A member writing `_` alone is refused unless the signature writes `_` alone
  too: nothing is left under that marker, so it is the name of no parameter a
  signature could have declared, except the one declared `_`, which the member
  is then spelling letter for letter.

This is the one place the feature departs from the original design, which said
"equal" and stopped there. `[T-Impl]` states the rule as decided here.

## Consequences

**A line does not execute left to right.** A reader tracing effects through a
call with named arguments must read the callee's signature to know what runs
first. This is the honest cost of the first decision, and there is no version
of reorderable names that avoids it — the alternative does not remove the cost,
it moves it to the reader of the second spelling.

**Adding a required parameter after a defaulted one reorders the signature.**
The suffix rule means an author cannot append it. The reordering was already a
breaking change for every positional caller, so the rule removes no evolution
that was safe, but it does mean the break is now unavoidable rather than
merely likely.

**Every parameter name is API.** Renaming one is a breaking change on the same
terms as renaming the function, with no marker to opt a name out. The hints
already showed every parameter name to every reader at every call site, so this
makes a practice into a rule rather than adding an axis to every declaration —
but a library author who wanted to rename a parameter quietly no longer can.

**A default that wants to be computed has one spelling: a second function.**
`f()` calling `f_with(x: compute())` is the shape, and it is heavier than a
default. This is the cost of the second decision, and it is the thing to watch:
a default that cannot be a constant and cannot be an overload-shaped wrapper is
what reopens it.

**One matcher exists.** The checker settles which argument fills which parameter,
once per call, into a side table keyed by the call; lowering, ownership, the
hints walk and the conformance property all read it, and the positional zips
that predated it were deleted rather than amended. A second matcher is the
defect class this compiler documents ([ADR 0048](0048-one-question-has-one-answer.md)),
and matching is exactly the shape that invites one.

**Nothing below the checker knows the feature exists.** After matching and
splicing, the compiled call is one where every argument was written
positionally in declaration order. The ABI is unchanged, MIR verification is
unchanged, and names and defaults are a fact about source rather than about
compiled code.

**Matching costs a call its own arguments.** A declaration's name-to-index table
is built once per declaration and sized by that declaration's parameters, then
consulted per named argument, so nothing here is sized by the program.

## Alternatives considered

**Written-order evaluation.** The order the reader sees, which is what a reader
tracing effects would guess, and what a language with no named arguments
necessarily has. Rejected because it makes two spellings of one call two
programs the moment an argument has an effect. That is not only a semantics
nobody wants to specify — it unsounds the permutation rewrite, and with it the
only mechanism that would have checked the reordering rule at all. The rule
would then hold by review.

**Computed defaults — an arbitrary expression.** Strictly more expressive, and
common elsewhere. Rejected as a cluster of unrelated design problems bought at
once, per the table above, for a feature whose motivating cases are all
constants. It is
reopened by a default that can be neither a constant nor a wrapper function.

**A default referring to an earlier parameter.** `fn slice(read s: Str, read
from: UInt64 = 0, read to: UInt64 = length(s))` is the shape, and it is the most
tempting of the computed cases because the scope question looks answered — the
earlier parameters are right there. Rejected because the scope is the smallest
of the four problems: `length(s)` still needs an evaluation site at the call, an
ownership story for what it produces, and a place in the evaluation order that
declaration order would have to be extended to describe. It also makes the
parameter list a dependency graph, which is a second thing a reader must
compute from a signature.

**Implementations owning defaults.** Rejected because it makes `x.pad()` mean a
different width per type, and leaves a call through a bound with no default at
all or one chosen by machinery. Restating the signature's default in each
implementation was rejected on the same grounds it is refused in code: one fact
with two spellings that must be compared for equality is the drift this
compiler's defects are made of.

**`.name = expression`, the struct-initialiser spelling.** Available, and
already meaningful to a reader of construction. Rejected because it splits "a
name at a use site" into two notations permanently, with hints rendering one and
construction rendering the other. Construction names the parts of a value; a
call names the parameters of a signature; the hint precedent tips it.

**Plain `name = expression`.** Rejected because `=` in expression position is
assignment. `f(x = 3)` where `x` is a local in scope is a genuine ambiguity,
resolvable only by fiat.

**Separate labels and names, as a language with call-site labels has.** An
author could then rename the internal name freely and keep the API stable, which
is what the names-are-API consequence costs. Rejected as a second axis on every
parameter declaration, paid at every declaration to serve the renames that
actually happen, and as a second name for one thing — which is the shape this
compiler treats as a defect wherever else it appears.

**Opting a name out of the interface.** A marker hiding one name, rather than a
second name for every parameter. Cheaper than labels and rejected for the same
reason at smaller scale: the hints publish every name already, so the marker
would hide a name the tooling still shows. Reopened by library authors
demonstrably needing to rename parameters without a break.

**`sink` defaults.** "Pass an allocator or receive the default one" wants one,
and it is the most concrete request against the constant-only rule. Rejected as
exactly the invisible-construction case: the same source line would construct an
owned value at one call site and not at another. Reopened when the pattern
exists in the library and the wrapper spelling proves too heavy.

**Field defaults, so construction could omit too.** Rejected to keep one
mechanism: `[S-Field]` stands, `.{ }` still gives every field a value, and
construction with omissions is expressible as a function with defaulted
parameters. Reopened by evidence that construction sites routinely restate the
same field values.
