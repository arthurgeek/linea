# 36. Formatting is comma-driven, and never rewrites a token

Status: Accepted — 2026-07-27

Builds on [0005](0005-lossless-token-stream.md), which is what lets a formatter
read structure from the tree and text from the tokens at the same time.

## Context

A formatter has to decide where lines break. Almost every formatter decides by
measurement: it is given a target width, and a construct is laid out flat if it
fits and broken if it does not.

Measurement has a property that is easy to miss until it bites. A construct's
shape then depends on things that have nothing to do with it — renaming a
binding three levels in can push a line past the limit and reshape a call at the
top. The programmer cannot predict the output without doing arithmetic, and a
diff can contain lines nobody touched.

It also needs a layout algebra: groups, nesting, measured widths, a solver to
choose among them. That is a substantial amount of machinery, and every one of
its decisions is a place the output can surprise someone.

Linea already has a marker the author writes deliberately and can see: the
trailing comma. `examples/hello.lin` uses both forms in one file — a flat
`enum Step { Half, Whole, Exactly(u8) }` beside a broken `struct Plan` — which
is evidence that both are wanted and that the author is the one who knows which.

## Decision

**A delimited list's layout is decided by its trailing comma.** With one, each
element goes on its own line; without one, the list is flat. Nothing is
measured, and there is no line-width limit anywhere in the formatter.

**The comma decides only among layouts that are possible.** An element that
cannot be rendered on one line forces the break whatever the commas say. Two
things cannot: a `//` comment, which runs to end of line, and a non-empty block,
because a block always breaks. An empty block is flat, so `{}` forces nothing.

**A block always breaks.** One statement per line, closing brace on its own.
Only an empty block stays flat.

**Whenever a list breaks, its trailing comma is written**, including where the
author omitted it. This is what makes the output a fixed point: the next run
reads an ordinary comma-driven list and re-derives nothing about why it broke.

**One token is dropped, and only because the tree does not hold it.** The
parser eats a semicolon written before a closing brace without recording it, so
`{ e; }` and `{ e }` are one tree and one program. There is nothing in hand to
write back, and writing one anyway would mean inventing which of the two
spellings the author used.

**Nothing else about a token is rewritten.** Lexemes are copied verbatim —
literal casing, leading zeros and the bytes between a string's quotes are the
author's. Declarations, imports, fields, variants and arms keep their order.
Redundant parentheses are kept.

Together these mean the formatter changes the gaps between tokens, inserts a
comma where it breaks a list, and drops a semicolon the tree never held. That
is the whole of what it does to a file.

## Consequences

A construct added to the language later inherits a layout rule by having a
comma list or not having one. No new decision is needed, and no new case in a
solver.

A long flat list stays flat. Two hundred columns of arguments are left alone
until their author adds a comma. This is the cost of the author owning breaks,
and it is not a defect to be fixed later by adding a width — a width would take
the decision back.

The preservation property gains two exceptions, and they have to be stated
precisely because they run in opposite directions: the output may hold a comma
the input did not, and the input may hold a semicolon the output does not.

Each allowance applies to one side only. Made symmetric, the first would forgive
the formatter deleting a comma the author wrote and the second would forgive it
inventing a semicolon they did not — and a rule that forgives either is not a
preservation property. Stating it as a subsequence rather than by normalising
both sides is what keeps the directions apart.

Because layout never depends on width, a renamed binding cannot reshape code
around it, and a diff contains only lines someone changed.

`if c { 1 } else { 2 }` becomes six lines. Blocks having one rule rather than a
rule and an exception is what buys that: the moment a block's shape depends on
what is inside it, adding a statement changes the shape of the code around it.

## Alternatives considered

**A width limit with a Wadler-style layout algebra.** The conventional answer,
and the one most formatters implement. Rejected because it measures: a
construct's shape becomes a function of names and nesting elsewhere in the file,
which is exactly the unpredictability the trailing comma avoids. It is also
several hundred lines of solver whose decisions are hard to explain to the
person reading its output.

**"Contains a newline" as the marker.** Layout follows whether the author had
already broken the list. Rejected because a newline is not a character anyone
can see — the marker becomes invisible history rather than a deliberate mark,
and a list that was broken once stays broken for reasons nobody can point at.

**One fixed shape per construct.** Every struct one field per line, every enum
flat. Deterministic and needs no marker at all. Rejected as arbitrary: it forces
a long enum flat and a two-field struct broken, and offers no way to say
otherwise short of an escape hatch used constantly.

**Normalising literals.** Canonicalising digit casing or grouping alongside the
layout. Rejected because a formatter that rewrites a constant can change what a
program computes through a bug nobody would think to look for, and the benefit
is a consistency no reader has ever asked for.

**Sorting imports.** Common, and it removes a class of merge conflict. Rejected
because it would make `import` the one construct the formatter treats specially,
and because order that cannot affect meaning carries only intent — which is
what a formatter must not discard.
