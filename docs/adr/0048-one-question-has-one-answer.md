# 48. One question has one answer, and one place that computes it

Status: Accepted — 2026-07-28

Builds on [0012](0012-immutable-representations.md), which gives a later pass a
side table rather than a way to write back, and on
[0045](0045-sugar-is-expanded-by-one-renderer.md), which reached the same
conclusion for one construct: a renderer with two callers rather than a
definition stated twice.

## Context

Every defect this compiler has demonstrated has been one rule with two
implementations that drifted apart.

Which implementation a trait call reaches was computed by the checker to
discharge a bound and again by lowering to find a body, once by type identity
and once by the spelling of a name — so a call could reach an implementation
the bound never admitted. A member's namespace was decided by the resolver's
member table and, separately, by what the syntax tree dump printed, so two
programs that compile differently rendered identically. A symbol was keyed on
`(type, member)` while coherence keys an implementation on `(trait, type)`, so
two traits declaring one operation for one type produced one symbol twice. A
declared type was named by `mangledName` at every use and by its own spelling
at its declaration, so two modules' `Thing` printed as one name twice.

None of these were sloppy. Each second copy is individually plausible, passes
review, and passes the tests — because the tests exercise the first copy. The
disagreement surfaces only on the input nobody wrote: a re-exported name, two
modules declaring one name, a generic instantiated twice, an `impl` in a file
other than its type's.

The common shape is that a question had no owner. A pass needed an answer,
nothing recorded one, and working it out locally was the shortest path.

## Decision

**A question the compiler answers has one owner and one implementation.**

A pass that needs what an earlier pass decided reads it. Where nothing records
it, a side table is added — which [0012](0012-immutable-representations.md)
already makes the way a later pass annotates an earlier representation, so this
adds no mechanism.

Where two callers genuinely ask at different times, they call one routine
rather than keeping a copy each. Discharging a bound happens before
instantiation and finding the body happens after it; the question is the same,
so the lookup is one function with two callers.

**A dump reads what the pipeline decided.** It is not a second opinion about
the program. Where a dump cannot obtain an answer without recomputing it, that
is a missing side table rather than a licence to compute it.

**The driver composes; it does not decide.** A responsibility with no home
lands in the orchestrator, because the orchestrator is the one place that can
reach everything. That reachability is why nothing imports `driver/` — and why
a rule found there is nearly always one that belongs to a pass.

## Consequences

The test at review is a sentence: if the same sentence describes two functions,
one of them is the bug. That is cheap to apply and catches the case where the
two implementations look nothing alike, which is the case that gets through.

Side tables grow. Recording what a pass settled, so a later one need not
re-derive it, costs memory and a table to keep in step — and the table is
keyed by the earlier representation's own IDs, so it stays serialisable.

Some duplication survives deliberately and must be recognised as different:
`editor-support/` holds two grammars written independently on purpose, held
together by four gates. Independence checked by a gate is not an unowned
question; it is one answer with a second reading held to it, which is the
arrangement [0045](0045-sugar-is-expanded-by-one-renderer.md) describes.

The rule is stated here and not enforced anywhere. Prose that cannot fail
drifts from the first change made by someone who has not read it, which is the
objection [0029](0029-a-suite-must-be-able-to-fail-for-what-it-omits.md) raises
against exactly this. The strongest available mechanical form is narrow, and
narrower than it first looked.

A property that two programs the compiler distinguishes never produce identical
dump output now runs over four renderings — the syntax tree, the source with
what the checker settled written into it, the program with its generics gone,
and the code that will be generated. Of the four defects above it reaches one:
the member whose namespace the tree dump decided a second time, which is a pair
of programs differing in one `impl` line and in nothing else. The other three
need a pair that differs in which implementation a call runs, in which of two
traits declares an operation, or in which module declares a name, and no change
to one file's text produces such a pair while leaving both halves compiling.

So the claim the property actually holds is the weaker one, and it is worth
having on its own terms: a dump is a reading of what a pass decided, and one
that stopped printing what tells two programs apart fails on every case at once
rather than going quiet. Closing the rest means a distinction that changes
which body a call reaches, which is a change to a program the corpus supplies
rather than a rewrite of one.

## Alternatives considered

**Leave it to review.** This is what was happening. Every one of the defects
above was written, reviewed and merged, because a second implementation of a
rule reads as ordinary code — there is no diff in which it looks wrong.

**Forbid a pass from computing anything an earlier pass could have.** Too
strong to be true. A pass legitimately computes what it is for, and the line is
whether the question is already *answered* elsewhere, not whether it *could*
be. A rule that cannot be applied without judgement is better stated as the
judgement.

**A shared utility module every pass imports.** This attacks the symptom. Two
copies of a rule are a problem because two answers exist, not because two
functions do; moving both into one file leaves both. It also runs against
[0002](0002-project-structure.md)'s layering, in which a pass imports the
representation it consumes rather than a common pool of helpers.

**Record it only in CLAUDE.md.** That file says what to do; this says why, and
carries the alternatives. A reader who wants to know whether the rule survives
contact with a case it makes awkward needs the reasoning, which is what a
record is for.
