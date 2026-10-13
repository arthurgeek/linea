# 26. The corpus checks metamorphic properties, not only recorded outputs

Status: Superseded by [0134](0134-conformance-compiles-ordinary-cases-once.md) — 2026-07-26

## Context

[ADR 0008](0008-golden-conformance-suite.md) makes the corpus the primary
correctness artifact: a `.lin` input beside the outputs someone read once and
accepted. That catches every change to what the compiler produces, which is
what it was built for.

It does not catch a compiler that is confidently wrong in a way the recorded
output happens to agree with. Five bugs of one shape reached a green suite: a
handle read from the wrong place, type-correct at every boundary, producing a
program that built and ran and answered. In each case the golden agreed because
the golden was generated from the same wrong code.

The most recent read a `match` arm's variant index from the scrutinee's symbol,
so every arm compared against tag `0` and the first arm always won. The corpus
writes arms in declaration order, so the first arm *was* the right answer for
the case that existed, and both the `.ssa` and `.exit` goldens agreed.

## Decision

**A case that records an exit status is also checked under rewrites of its own
source that cannot change what it means.** The program is its own expectation:
the rewrite is compiled and run, and its answer must equal the original's.

Two rewrites exist today.

**Declarations reversed.** A declaration is entered before any body is walked,
so a name is visible to every declaration whatever the order. What the order
does decide is the order types enter the pool, the order functions reach the
backend, and the order diagnostics are reported — and a program may observe
none of those.

**Match arms rotated.** An arm's pattern selects it, so an exhaustive cover of
distinct patterns answers the same however the arms are written. An arm bound
to `_` is excluded: it is defined to come last, so moving it forward is a
different program rather than the same one rewritten.

**Each rewrite is deterministic**, and **each reports how many programs it ran
on**. A random rewrite would find more and would also fail on a different case
each run, which is how a suite stops being believed. A property that quietly
stops applying to the whole corpus is otherwise indistinguishable from one that
applies and agrees, and both are green.

**Only the answer is compared** — the first line of what the program did, not
the trap message that may follow it. A rewrite moves the lines, and the
location a trap reports is not the answer.

## Consequences

**Every case that records a status is a case for this, and one added tomorrow
is one for free.** That is what a golden cannot do: a golden checks the one
thing someone wrote down, and this checks a property of every program the
corpus already holds.

**A rewrite the compiler rejects is a failure of the compiler**, reported with
the diagnostic it produced. Nothing in the rewrite changed what the program
says, so nothing in it can justify a diagnostic.

**The suite builds each rewritten program.** The outcome cache is keyed on
emitted IR, so a rewrite that lowers identically costs nothing and one that
does not is built once and recorded.

**Coverage is visible and currently small** — a rewrite applies only where the
corpus records a status and the program has the shape it needs. The counts
printed each run are what says so, and they grow as the corpus does.

## Alternatives considered

**A generator of valid programs, driven by the fuzzer.** The stronger form, and
where this goes. Rejected as the first step: it needs a generator that produces
programs the checker accepts, which is a component in its own right, and the
corpus is already a supply of valid programs that grows with the language. The
generator is additive — it feeds the same properties.

**Comparing the emitted IR instead of running the program.** Cheaper, and
wrong: every one of these rewrites changes the IR by construction. Deciding
which differences are permitted would require an equivalence relation over MIR,
which is a second implementation of the semantics and a second thing to be
wrong about.

**Comparing the whole recorded outcome, not just the answer.** Rejected. A
trapping program prints where it trapped, and a rewrite moves the lines, so the
property would fail on programs that behaved identically.

**Random permutations rather than a fixed rewrite.** Rejected for the suite;
it belongs with the generator, where a failing seed is reported and can be
replayed. A conformance run that fails on a different case each time is one
people learn to re-run.
