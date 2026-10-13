# 45. Sugar is expanded by one renderer, and it is compiled

Status: Accepted — 2026-07-28

Builds on [0040](0040-conditional-control-flow-has-one-form.md), which defined
`&&`, `||` and `!` in terms of the conditional while keeping the surface form
in the tree, and on
[0026](0026-the-corpus-checks-properties-a-golden-cannot.md), which is how a
claim about the compiler is held to rather than stated.

## Context

The semantics document says `a && b` **is** `if a { b } else { false }`, and
not "behaves like". That sentence was true and unchecked. Lowering has one
function for the operator and another for the conditional, neither reading the
other, and they agreed because they were written to.

An expansion is also something a reader wants to see. `dump-mir` shows it, in a
different language; the source shows nothing. The obvious tool is a dump that
prints the program with its sugar written out.

The obvious implementation is not available. 0040 requires the tree to keep the
surface form, because a tree holding `if a { b } else { false }` could not be
printed back as `a && b` and the formatter would rewrite source that was never
wrong. So there is no expanded tree to print, and there must not be one — which
is where this differs from a compiler that expands into a second tree and
prints that.

Rendering the expansion from the surface tree is therefore the only option, and
a renderer that only prints is a second statement of a definition that is
already stated twice: once in the document and once in lowering. Three
statements of a rule is worse than two.

## Decision

**There is one renderer from a construct to what it is defined to be, and its
output is compiled.**

The corpus rewrites a program by replacing one logical operator with its
definition, compiles both, and requires the same code — not merely the same
answer, because the document says `is`. A rewrite moves the text, so a line is
compared up to whatever source position it carries.

**A dump of the expanded program prints that renderer's output.** It is a
reading of what the corpus already compiles, so it cannot drift from what the
compiler does: the thing being printed is the thing under test.

**Every sugar goes through it.** A construct defined as another construct is
expanded by the renderer and covered by the property. `&&`, `||` and `!` are
its first members; `?` joins them, and so does anything later defined this way
rather than lowered on its own terms.

## Consequences

The property is the first in the corpus that holds the compiler to a definition
rather than to an invariance. Reversing declarations and rotating match arms
change what cannot matter; this changes a program into what the language says
it already was, so a disagreement is the compiler contradicting its own
semantics.

It fails for changes that alter no behaviour. Allocating the conditional's two
arms in the other order leaves every program answering exactly as before and is
caught immediately, which is the difference between checking `is` and checking
"computes the same thing".

A dump of the expanded program is worth building when there is a second sugar
to see, and is worth nothing before then: with one construct it would print
what the property already renders, to no one who could not read the rule.

The renderer lives where both reach it. A rewrite in the corpus that a dump
also prints is one implementation with two callers, which is what stops the
dump from becoming the unverified copy.

## Alternatives considered

**A desugaring pass that rewrites the tree, printed by the dump.** This is the
usual arrangement and the one the tooling wants: the dump reads a pass's output
and cannot be wrong about it. 0040 forecloses it — the formatter needs the surface form,
and a pass that removed it would make `linea fmt` rewrite working source. A
second tree kept beside the first is a representation that discards nothing,
adds no node a side table could not key, and simplifies no pass, which
[0012](0012-immutable-representations.md) asks a new representation to do.

**Compare answers rather than code.** The existing rewrites compare what a
program answered, and that machinery was already there. It would not have
caught the block-ordering change, and a definition that holds only up to
observable behaviour is a weaker claim than the one the document makes.

**State the equivalence only in the semantics document.** It was already stated
there, and the two lowerings agreed because one author wrote both in one
sitting. A document that cannot fail is a document that drifts from the first
change made by someone who has not read it.
