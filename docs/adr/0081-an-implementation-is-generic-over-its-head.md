# 81. An implementation is generic over its head, and coherence keys on the constructor

Status: Accepted — 2026-08-12

Extended by [0213](0213-a-trait-may-be-implemented-for-a-callable-type.md)
with callable-type heads keyed by shape.

Partially superseded by [0142](0142-construction-derives-expand-to-ordinary-source.md):
ordinary trait implementation binders are recovered from the complete key.

Extended by [0139](0139-default-implementations-follow-ordinary-selection.md)
with explicitly marked default implementations.

The constructor-only ordinary head clause is superseded by
[0148](0148-parameter-heads-match-complete-trait-keys.md); applied-constructor head restrictions remain.

Partially superseded by
[0182](0182-a-types-own-implementation-may-fix-its-type-arguments.md): a type's
own implementation may fix some of its type arguments, so the head rule below
governs trait implementations only.

## Context

An implementation named a head and was not generic over it, so a generic type
could carry no trait at all. Both spellings were refused, and by different
rules:

```
impl Show for Pair[UInt8]   error[S-Brace]: expected `{`
impl Show for Pair          error[T-Bound]: `Pair` takes 1 type argument(s), and was given 0
```

Nothing in `std` implemented a trait for a generic type, because nothing could.
That is why `Option` could not be shown, why a `Result` could not render either
half, and why the original iteration design
rested on a premise that did not hold when it said `Range`'s `Iterator` and
`Sequence` implementations "live in std, which the language already provides
for".

**The question was written down where it was deferred.** The case
`tests/traits/an_implementation_takes_no_type_parameters.lin` held it:

> An implementation names a head constructor and is not generic over it. One
> written `impl[T] Measure for Option[T]` would stand for a family, and which
> member of it a call reaches would be settled per instantiation — so `Self`
> would be an instantiation rather than a declaration, everywhere it is
> substituted. The grammar refuses it here, which is what keeps that question
> unasked. A change that admits it has to answer the question in the same
> commit, and this case is where it will be told to.

This is the record that answers it, and the case it was written on is now
`tests/traits/an_implementation_is_generic_over_its_head.lin`, which pins the
answer rather than the refusal.

Everything below turns on one thing: coherence is key equality and not a
search. Every consumer takes the implementation it finds rather than choosing
among candidates, and the associated types design reads `Self.Item` off that
unique key. A feature that put two implementations in reach of one type would
break both, wherever it put them.

## Decision

**An implementation may declare type parameters, and its head is the
constructor applied to them.** They are written where a function's are and
carry the bounds a function's carry, so `impl[T: Display] Display for Option[T]`
is one implementation standing for a family.

**Each parameter appears in the head exactly once, in the order it was
declared, and nothing else stands in the head's positions.** Four shapes are
refused by that one comparison, all `[T-Impl]`: a partial head
(`impl[T] Show for Pair[T, Int64]`), a repeated parameter
(`impl[T] Show for Pair[T, T]`), one out of order
(`impl[T, U] Show for Pair[U, T]`), and parameters exceeding the head's
(`impl[T, U, V] Show for Pair[T, U]`).

That comparison reads the head's positions against the parameter list by
spelling, which is exact because a declaration declares each type parameter
once — a second of one spelling is `[N-Duplicate]`, on an `impl` as on anything
else. Without that rule `impl[T, T] Show for Pair[T, T]` reads as each
parameter appearing once and in order: both positions hold one parameter, so a
receiver binds it twice and the member is checked and lowered at whichever type
the last position supplied.

**Coherence keys on the head's constructor: one implementation per (trait
declaration, trait arguments, head constructor).** The constructor and not what
the head applies, because an implementation generic over its head stands for
every instantiation of that constructor at once. A second one for `Option` is a
second answer for every `Option[T]` there is, however the two heads are
written, and it is `[N-Duplicate]` where the second is written.

**An implementation's trait arguments are determined by its head.** Where it
declares parameters, each argument it supplies the trait is written from them,
so a receiver settling the head settles the arguments too. `impl[T] Give[T] for
Holder[T]` and `impl[T] Give[Option[T]] for Holder[T]` are both such
implementations; `impl[U] Give[Bool] for Holder[U]` is not, and is `[T-Impl]`
where the argument is written. An implementation declaring no parameters says
nothing this can be about — `impl Give[Bool] for Holder[Bool]` answers at the
arguments it wrote and its key is exact.

This is the same requirement the head carries, one position further out. An
argument independent of the head does not vary across the family: it stands at
`Give[Bool]` for every `Holder` there is, so it meets any other implementation
of that trait for that constructor at whichever member makes the two agree —
two implementations at one instantiation, which is what the key exists to
prevent and what no comparison of keys can see, because a family's arguments
are not settled until a receiver settles them. Stated of the arguments and not
of the text: an argument may name the implementation's parameters freely, which
is exactly what the family this record ships is written from.

**An implementation's own bounds decide which members of the family it answers
for, never which implementation answers.** There is at most one, so a bound
says only whether it applies to the member in hand. `Option[Str]` is `Display`
because `Str` is; `Option[Key]` where `Key` is not simply is not `Display`, and
that is `[T-Bound]` reported at the use rather than at the implementation.

**Those bounds are discharged the way every other bound is: by an
implementation existing, or by a bound already in scope.** `[T-Bound]` reads a
bound two ways everywhere else, and a head's parameters are held to both — so
`fn wrap[T: Show](read h: Holder[T])` handing its `Holder[T]` to an operation
bounded by `Show` is admitted, because `T: Show` is what
`impl[T: Show] Show for Holder[T]` asks for and is declared right there. The
universe half of the same demand already read it that way, four lines from the
trait half, and one demand read two ways is one rule with two implementations.

The reading is at the top of the argument and not within it: each position of
the head is asked what the type standing there promises, which is a lookup
rather than a search over the argument. Without it the family this record ships
is unusable one level up — a generic function forwarding an `Option[T]` rather
than a concrete `Option[Str]` is the first thing anything built on `std` does.

**`Self` inside such an implementation is the head — an instantiation with the
implementation's own parameters free.** A member writing the head out longhand
writes the same type, and each call binds those parameters from the receiver,
so `Self` is `Option[Str]` at one call and `Option[UInt8]` at the next. That is
the deferred case's question answered: `Self` is an instantiation rather than a
declaration, everywhere it is substituted.

**Finding an implementation stays one routine.** A concrete head binds no
parameters and discharges no bounds, so it is the degenerate case of the
general one rather than a path beside it — the invariant
[0048](0048-one-question-has-one-answer.md) keeps paying for.

## Consequences

**`std` can implement traits for generic types, and does.**
`impl[T: Display] Display for Option[T]`, `impl[T: Debug] Debug for Option[T]`
and `impl[T: Display, E: Display] Display for Result[T, E]` are the first three,
so the feature is exercised through the corpus rather than through cases
written for it alone.

**One member of a family cannot be special-cased.** There is no
`impl Display for Option[Str]` beside the generic one, because that is the
second implementation for `Option` this record refuses. The honest answer is a
different trait or a different type.

**"A pair of two of the same things" is not expressible.**
`impl[T] Show for Pair[T, T]` is a real thing to want and is refused, because
it is a pattern in the position that has to stay a constructor.

**A restriction on heads is where the ambiguity is stopped, rather than a
ranking further down.** Nothing ranks candidates by specificity anywhere in the
compiler, and nothing needs a rule for what to do when two rank equally.

**Known coherence limitation: open implementation families whose settled keys
can coincide are not detected. Where several such implementations match,
selection order determines the winner. This is accepted only because resolving
it requires a new overlap and unification mechanism; it is not intended
language semantics.**

The current coherence mechanism compares implementation keys. That is
sufficient for concrete and structurally distinct keys, but it does not
determine whether two open implementation families overlap. Determining that
requires unification and overlap analysis, and is deferred.

The restriction above is necessary for the key model and is not sufficient for
coherence. Three counterexamples, each of which satisfies it — every trait
argument in each is written from that implementation's own head parameters —
and all of which the compiler accepts:

```linea
impl[T] Give[Pair[T, T]] for Holder[T] { … 3 … }
impl[T] Give[Pair[T, Bool]] for Holder[T] { … 8 … }
```

Both settle to `Give[Pair[Bool, Bool]]` at `T = Bool`. `check` exits 0, and a
program calling `Give.give` on a `Holder[Bool]` with a `Pair[Bool, Bool]` runs
the first, exiting 3.

```linea
impl[T, U] Give2[T, U] for Pair[T, U] { … 3 … }
impl[T, U] Give2[U, T] for Pair[T, U] { … 8 … }
```

Both settle to `Give2[Bool, Bool]` at `T = U = Bool`. `check` exits 0, and the
call runs the first, exiting 3. Exchanging the two declarations and changing
nothing else makes the same program exit 8. That is the whole of the
observation: the meaning of the program is its declaration order, and no rule
in this record or in the semantics document says it should be.

```linea
impl[T, U] Give[T] for Pair[T, U] { … 5 … }
impl[T, U] Give[U] for Pair[T, U] { … 9 … }
```

Both settle to `Give[UInt8]` at `Pair[UInt8, UInt8]`. `check` exits 0, and a
call passing a `UInt8` runs the first, exiting 5; exchanging the two
declarations and changing nothing else makes it exit 9.

This one is inside the boundary rather than outside it, and it is where the
boundary moved. `refuseTraitArgumentsTheHeadDoesNotSettle` asks that every
trait argument be written from the head's parameters, which both of these are:
each supplies a different position of one head. The rule the compiler could
state before this record — that two implementations of one trait for one
constructor are one implementation whatever their arguments — refused the pair
outright, so the widening is this record's and is recorded here as its cost.

For a while the pair failed loudly rather than silently, and it did so for a
reason that says nothing about coherence: both members mangled to one symbol,
because a symbol spelled the trait's arguments as the declaration wrote them
and both wrote a bare parameter. A symbol spells what the receiver settled
instead, so two implementations that really are two get two names — and this
pair, which really is one answer written twice, gets one body reached and the
other never instantiated. The exit status stopped being 70 and became the
first-match choice above. Nothing about the overlap changed; what changed is
that it is no longer reported by accident.

These are recorded here as prose and not as conformance cases. A case says what
the language means, so a golden asserting any of these exit statuses would make
first-match a dispatch rule by writing it down as one — and the corpus rewrites
a case under a reversal of its own declarations, which is the rewrite these
programs do not survive. What is written down instead is that the boundary is
here, so a reader of the restriction above cannot conclude that overlap between
generic families was solved.

**`Range` is not among what `std` gained.** A generic range iterator needs
`self.lo < self.hi` and the next value after `lo`, and neither is reachable from
an unbounded `T`. That is the milestone
that makes a comparison a trait call, and
`impl[T: Comparable + Steppable] Iterator for Range[T]` is the
first line needing both records.

## Alternatives considered

**Coherence by unification — the stated future extension.** Decide overlap by
asking whether two implementation families have a common instantiation, rather
than by comparing keys. It is what closes the limitation recorded above, and it
is what this record defers: it needs substitution, structural unification over
nested applications, the interaction between several parameters of one head,
and a notion of same-family for the diagnostic to point at both declarations —
and none of it is needed to make the language coherent for what `std` and the
corpus write today, which is families whose trait arguments are their head's
parameters or nothing.

The condition that triggers it is stated so it is recognised when it arrives:
**if Linea later wants implementation families whose trait arguments are not
determined by their heads, coherence must acquire unification and overlap
checking.** The restriction this record makes is what holds the key model up
until then, and lifting it without the mechanism puts declaration order back in
the position of deciding which body a call runs.

**Overlap ordered by specificity — specialization.** A general
`impl[T] Display for Option[T]` beside a specific
`impl Display for Option[Str]`, the specific one winning. It needs two things
this compiler does not have and would have to acquire together: a *total* order
on specificity, so that any two implementations in reach of one type are
comparable, and a guarantee that every call agrees on which implementation it
reached. The second is exactly the ambiguity constructor-headed coherence was
introduced to remove, and it is the property the associated types design rests
on when it reads `Self.Item` off a unique key — with two candidates, `Self.Item`
is two types and which one a signature means depends on which implementation the
reader ranked first.

Every language with this feature made the same choice. Rust refuses overlap
(`E0119`) and has kept specialization unstable since 2015 over soundness against
lifetimes — the ranking can be changed by a lifetime that is erased before the
code runs, so a program's meaning depends on information the back end does not
have. Swift refuses a redundant conformance outright and writes the conditional
case as `extension Optional: Equatable where Wrapped: Equatable`, which is this
record's shape with different spelling. Haskell requires a pragma to overlap and
its own documentation treats it as a wart. Nothing here is a first attempt at
the problem, and the languages that shipped it shipped it as an escape hatch.

**A head that is a pattern.** Admit `impl[T] Show for Pair[T, Int64]` and rank
by specificity only where two heads collide, on the argument that this is
narrower than specialization. It is not narrower — it is specialization written
in a different position. `Pair[T, Int64]` beside `Pair[Int64, U]` both answer
for `Pair[Int64, Int64]`, neither is more specific than the other under any
ordering that reads positions independently, and so specificity ordering returns
through a position nobody was watching. Refusing the pattern is what keeps the
coherence rule checkable by comparing a key rather than by proving that no two
heads can be instantiated to the same type — which is unification, and which the
compiler does nowhere.

**A bound that decides which implementation answers.** Let the bounds on two
implementations be disjoint — `impl[T: Display] … for Option[T]` beside
`impl[T: Debug] … for Option[T]` — and pick by which bound holds. Two
implementations are then in reach of one type whenever a type carries both
bounds, so this is overlap with the ambiguity moved into the bounds, where it is
harder to see and where adding an unrelated implementation elsewhere in the
program can change which body an existing call runs.

**Refuse the whole family and require a concrete implementation per
instantiation.** `impl Display for Option[Str]`, `impl Display for Option[UInt8]`,
one per type anyone uses. It keeps every key exact and needs no new rule at all,
and it is what the language had. It scales with the product of types and traits,
it cannot be written at all for a type in another module, and it puts the
library in the position of guessing which instantiations a program will want.
