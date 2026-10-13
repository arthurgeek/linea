# 39. Formatting is a normal form, checked by perturbation

Status: Accepted — 2026-07-27

Builds on [0026](0026-the-corpus-checks-properties-a-golden-cannot.md), which
established that the corpus checks properties rather than only recorded
outputs, and on [0036](0036-formatting-is-comma-driven.md).

## Context

The obvious property for a formatter is idempotence: `fmt(fmt(x)) == fmt(x)`.
It is easy to check and it is much weaker than it looks. A formatter that
preserved the author's indentation width would be perfectly idempotent — it
would settle immediately — and perfectly wrong. Idempotence says formatting
*settles*; it does not say it settles in the same place for two inputs that
should agree.

There is a second problem, in the machinery rather than the property.
`Transform.apply` returns null where a rewrite "applies to no effect", and that
convention exists so a transformation which quietly stops applying is visible
rather than green. A transform that simply *formatted* each case would return
null on every case already formatted. So the tidier the corpus became, the less
the transform would cover — and it would report success the whole way down. The
suite would get quieter as it got weaker, which is the failure mode 0029 exists
to prevent.

## Decision

**The correctness claim is a normal form**: two sources differing only in what
the formatter does not preserve format to the same bytes.

**The transform perturbs before formatting.** It mangles the source
deterministically and then formats the result, so it always has work to do
whatever state the corpus is in. Two things fall out of one rewrite: the
program still answers what it answered, and `fmt(perturb(x))` equals `fmt(x)`.

**What may be perturbed is exactly what the formatter does not preserve** —
indentation, and the spacing between tokens on a line. A run of two or more
blank lines may be made longer, because every such run collapses to one.

**Nothing else may be touched.** The trailing comma that decides a list's
layout, the line a comment sits on, whether a blank line separates two
statements, and the contents of an `off` region are all preserved by the
formatter deliberately. Changing any of them changes the formatting
*legitimately*, so the equality would fail on a formatter that was working.

**The perturbation is deterministic.** A random one would find more and would
also fail on a different case each run, which is how a suite stops being
believed.

## Consequences

The property is strictly stronger than idempotence and subsumes it in practice:
a formatter that leaked its input's spacing into its output would satisfy
idempotence and fail this.

Coverage cannot silently decay. The rewrite applies to every case that parses,
so the count reported by a run means what it says.

The perturbation is bounded by what the formatter preserves, which makes it a
second, independent statement of the formatter's contract. If a layout rule is
added that consults something new in the source, the perturbation must learn to
leave that alone — and until it does, the property fails loudly. That coupling
is deliberate: it is cheaper to have two places that must agree than one place
that can drift.

The escape hatch has to be routed around. Text inside `// linea fmt: off` is
copied verbatim by the formatter, so mangling it would survive into the output
being compared and fail on the first file using the feature.

A rewrite that changed nothing would make the property vacuous, so the tests
assert that the perturbed source differs from its input before comparing.

## Alternatives considered

**Idempotence alone.** One line to check and no perturbation to write. Rejected
for the reason above: a formatter can settle immediately and still be wrong, and
the class of bug it misses — input spacing leaking into output — is exactly the
class a formatter is most likely to have.

**A plain `format` transform, with the corpus deliberately left unformatted.**
Simpler, and it always has work to do so long as nobody tidies anything.
Rejected because coverage then depends on how messily each case happens to be
written: a tidy new case contributes nothing, and "do not format the corpus" is
a rule every future contributor has to be told and none can see.

**Perturbing more aggressively** — joining lines, moving comments, flipping
trailing commas, as an earlier draft of this design proposed. Rejected once the
comma rule landed: all three are things the formatter reads. Flipping a trailing
comma changes which layout the author asked for, so `fmt(perturb(x))` would
differ from `fmt(x)` on a formatter behaving exactly as specified. The
perturbation must stay inside what the formatter ignores.

**No transform, verifying formatting syntactically only.** Cheapest. Rejected
because the failure that matters most — formatting changing what a program
computes — would then be the one thing nothing tested, while the machinery to
test it already existed and cost one enum variant to use.
