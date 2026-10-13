# 27. Generated programs are well-typed by construction

Status: Accepted — 2026-07-26

## Context

[ADR 0026](0026-the-corpus-checks-properties-a-golden-cannot.md) holds every
program that records an exit status to rewrites that cannot change what it
means. The properties were right and the supply was not: they applied to twelve
programs and one `match`, because the corpus grows at the pace people write
cases.

A generator is the supply. The reason one is affordable here is that the
metamorphic properties **need no oracle** — a generator normally has to know
what its program should answer, which means a reference implementation, which
means a second thing to be wrong about. Here the program is its own
expectation.

## Decision

**A generated program is well-typed by construction.** Generation is driven by
the type each position demands — `expr(want, scope, depth)` picks only
productions that yield `want` — so nothing is generated and discarded. A
generator that produced text and filtered would spend nearly all of its output
on programs the checker refuses, which tests the checker's error paths over and
over and everything past them not at all.

Three of the language's own rules constrain generation, and each has one answer:

**Every generated name begins with `_`.** An unused declaration is an error, and
a `_` prefix declares one deliberately unused without making it
unreferenceable. Arranging a genuine use for everything declared would bias
every program towards the shapes that are easy to consume.

**A loop decrements its counter before anything else in its body.** A generated
program that does not end is a suite that hangs rather than one that fails, and
decrementing first means a `continue` cannot skip it. For the same reason a
generated function may call only one declared before it: mutual recursion
generates programs that do not end.

**Nothing is generated in a position that expects no type.** A literal has no
type until something gives it one, and constructs settled by their first
sub-expression — a `match`'s arms, an `if`'s arms, a comparison's operands —
inherit that. So a discard carries an annotation, and the left operand of a
comparison is generated as something whose type is already settled.

**Choices are read from bytes rather than drawn from a seeded generator.** One
byte decides one choice, so a mutation changes a program locally instead of
producing an unrelated one, which is what a coverage-guided fuzzer needs to
make progress. Filling the same stream from a seed gives a run that replays,
and seeds are consecutive from zero so a failure names a number and the
outcomes of a passing run stay cached.

## Consequences

**Coverage of the properties multiplied.** Thirty-two generated programs took
the rewrites from 12 programs to 37 and from one `match` to twelve. Raising
`-Dprograms` raises it further at a known cost, and the outcome cache means a
repeated run pays nothing.

**The generator must track the language.** A construct it does not know is a
construct the properties never see, and a language change that makes a
generated shape illegal fails the suite. Both are intended: the second is the
compiler and the generator disagreeing about the language, which is worth
stopping for whichever of them is wrong.

**It generates only what it knows**, and that is not the whole language. The
printed counts are what says how much it reached, so this is visible rather
than assumed.

**The running half cannot be a coverage-guided fuzz target.** The oracle is a
process launch — assemble, link, execute — so it is a budgeted step rather than
something run millions of times. Reading choices from bytes is what leaves an
in-process target, checking only what needs no execution, reachable without a
second generator.

## Alternatives considered

**Generating text or tokens and keeping what compiles.** Rejected. Well-typed
programs are a vanishing fraction of syntactically valid ones, so nearly all
output would be discarded, and what survived would be the shortest and least
interesting programs.

**A reference interpreter as the oracle.** Rejected, and unnecessary. It is a
second implementation of the semantics — a second thing to be wrong about, and
one whose disagreements would have to be adjudicated. The metamorphic
properties ask a question that needs no oracle, which is the whole reason the
generator is cheap.

**Seeding a generator from the fuzzer's bytes.** Rejected. It destroys the
gradient a coverage-guided fuzzer works by: a one-byte mutation would produce
an unrelated program, so nothing the fuzzer learned about the last one would
carry.

**Arranging a real use for every declaration instead of the `_` prefix.**
Rejected. It is possible, and it makes the shape of every program a consequence
of what is easy to consume — the generator would stop producing exactly the
declarations that go unused, which is a shape real programs have and a rule the
compiler has to get right.
