# 29. A suite must be able to fail for what it omits

Status: Accepted — 2026-07-26

## Context

[ADR 0026](0026-the-corpus-checks-properties-a-golden-cannot.md) added rewrites
that preserve meaning, so a program is its own expectation.
[ADR 0027](0027-generated-programs-are-well-typed-by-construction.md) added a
generator, so the programs those rewrites run over are not only the ones
someone thought to write. Both are about finding a compiler that answers
wrongly.

Neither can find a compiler that does not ask. Two bugs shipped behind a green
suite of 797 tests, and both were invisible to every mechanism then in place.

A variant named through context — `.Red` rather than `Colour.Red` — was never
looked up. The qualified form has always checked that the name is a variant of
the enum; the inferred form recorded whatever was written and lowered it to a
tag the enum does not have, so the `match` it fed matched no arm, fell out of
every test and answered with whatever its slot held. Accepted, compiled,
silently wrong.

No rewrite could reach it. A rewrite runs on a program the compiler accepted,
and on such a program every variant name is already correct; rewriting one
correct program into another correct program cannot show that a check is
missing, because both are wrong in the same way and therefore agree.

The second bug is why the first was reachable at all. An annotation naming a
type was not counted as a use, so `let c: Colour = .Green;` reported `Colour`
unused and the inferred form could not be written without also writing the
qualified one somewhere. That is an `[N-Unused]` bug, and the generator could
not have caught it under any amount of coverage: every name it wrote began with
an underscore, which declares a binding deliberately unused, so no generated
program could ever be rejected as unused. A whole rule was outside what the
generator was able to observe, and nothing said so.

Both failures share a shape. The suite was not wrong about anything it checked.
It had no way to fail for something it was not doing.

## Decision

**A property may assert rejection.** A mutation is a change built to make a
program ill-formed, paired with the rule it must break. The mutated program is
compiled and must be refused, citing that rule — a rejection for some unrelated
reason is a different question answered, and fails.

Nothing records an expectation, because there is nothing to record: the
mutation is ill-formed by construction, so silence is the failure. It needs no
golden, no toolchain and no linking, which is why it runs over every accepted
program in the corpus and every generated one rather than over a chosen few.

**Coverage of the language is stated and checked, not assumed.** Two tables say
what the generator reaches, on the axes the compiler already switches over
exhaustively: syntax nodes, and the instructions lowering produces. An entry is
`generated` and held to it, `impossible` with the reason nothing here could
produce it, or `missing` with what would close the gap.

Both are checked against a real run, in both directions. A construct called
generated that no generated program contains is a failure. So is a construct
the tables call absent that turns up — a note that has gone stale hides the
next gap behind it.

**A name the generator writes is exempt from the unused rule only where being
exempt is the point.** Bindings stay exempt: arranging a use for every one
would bias every program towards the shapes easiest to consume. A type is not a
binding, and `main` names each declared one, so types are spelled without the
underscore and the rule applies to them.

## Consequences

The two axes catch different things, and the second is the reason there are
two. Payloads added no syntax — a variant carrying a value is built with the
call and variant nodes that already existed — so nothing about the tree changed
when they arrived. Lowering gained two instructions, and that is what the
instruction table sees.

Seven constructs are recorded as missing today, each with what it would take.
Writing them down is the point: a gap nobody records is a gap nobody closes,
and the previous state of affairs was that gaps were not visible at all.

Every property here was checked by putting the bug back. Restoring the
unchecked variant name turns the mutation red on the program that names its
variant through context and leaves it green on the program that qualifies it,
which is the distinction it exists to draw. Restoring the unused-annotation bug
now fails `every generated program is accepted`. Removing the payload
production from the generator names five instructions that went dark. A
property nobody has seen fail is a property nobody has tested.

The cost is a table that has to be maintained, and a class of test whose
failure mode is a false alarm: a mutation that produces a program which is
ill-formed for a second reason would cite the wrong rule and fail. That is why
a mutation names one rule rather than merely asserting rejection.

## Alternatives considered

**Write a corpus case for each missing check.** A `.stderr` case asserting
`.Bogus` is rejected is one line, and one was added. Rejected as the whole
answer because it only ever covers the check someone thought of — which is the
same limitation [ADR 0026](0026-the-corpus-checks-properties-a-golden-cannot.md)
was written against, and the bug it was written about had a corpus case for the
qualified form sitting beside the unchecked one the entire time.

**Generate ill-formed programs directly.** A generator that produces programs
the compiler should refuse, checked against a model of what is ill-formed.
Rejected because that model is a second implementation of the type checker, and
a disagreement between the two says nothing about which is right. A mutation of
a program already accepted needs no model: the original compiled, and exactly
one thing about it changed.

**Measure coverage rather than assert it.** Print which constructs generated
programs reach and let a reader notice. Rejected because nobody reads a number
that does not fail, and the failure mode this exists to prevent is precisely
that nobody noticed.

**Drop the underscore from every generated name.** That would put `[N-Unused]`
within reach for bindings too. Rejected because the generator would then have
to arrange a use for everything it declares, which biases every program towards
the constructs that consume values and away from the ones that do not — and the
bias would be invisible, which is worse than the gap.
