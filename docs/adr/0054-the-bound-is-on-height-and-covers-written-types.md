# 54. The nesting bound is on height, and a written type answers to it

Status: Accepted — 2026-07-29

Supersedes [0042](0042-nesting-is-bounded-by-a-stated-number.md), which decided
that an expression nests at most 1000 levels and that the count is kept in one
place. The number is unchanged. What it applies to, and where it is kept, are
not.

## Context

0042 bounded nesting so that a deeply nested program would report rather than
abort, and put the count in `parseUnary` on the premise that every expression
descends through there exactly once. Every expression does. The premise is
true and the conclusion does not follow.

**A form written left to right and meaning something built upwards is not
descended through at all.** Precedence climbing reads `a + b + c + …` in a loop
that never gets more than a level or two down, and folds a tree as tall as the
chain is long. The suffix loop does the same for `.` selections and for calls.
So the count measured the rightmost spine of the tree, which is the part
recursive descent happens to walk, and not the height, which is what every
later pass walks.

The gap is not a constant factor. With a budget of *m* levels the counter
admits a chain of *m* terms whose last operand is itself a chain of *m − 1*,
and so on: a tree of height about *m²/2* was admissible under a budget of *m*.
Ten chains of a hundred terms, nested, is a tree of height 1011 — the bound
now puts it one term per chain over the limit, refusing at ten by ninety-nine
and accepting at ten by ninety-eight, which is 10*k* + 11 — and any count that
took the greatest number of turns any one loop made would have seen 101.

What was left is the failure the rule exists to remove, moved rather than
fixed. `1 + 1 + …` died in the type checker at **8693** terms in a debug build
and **16861** in a release one; `x.f.f…` died in the resolver at **9844** and
**16860**. Two different numbers per shape, two different numbers per build,
and in every case by signal with no diagnostic — which is
[0013](0013-no-undefined-behaviour.md)'s outcome-depends-on-optimisation and
[0003](0003-infallible-frontend.md)'s frontend-that-dies at once, and is the
same argument 0042's own prose makes about an unstated limit.

Written types were a second hole of the same kind. `parseTypeArgs` recurses
once per argument list and consulted no bound at all, so
`Foo[Foo[…[u8]…]]` ran the parser itself out of stack — by signal at **35963**
levels in a debug build and **80417** in a release one, with the whole
backtrace inside that one function. A declared generic reached the type checker
first and died there at **24000**.

## Decision

**The bound is on the height of the tree, and a written type answers to the
same number.** Deeper is `[S-Nesting]`, unchanged at 1000 levels.

Height, not frames, because height is what every later pass spends a frame on.
A count of frames and a count of levels agree wherever a form nests by
descending and part company wherever one is stacked in a loop, and the parser
is the only pass in which they can differ at all.

**The count is therefore kept wherever a level is created, which is not one
place.** `parseUnary` counts descent, as before. `Measure` counts what the two
loops that fold left stack above operands already finished — carrying a
finished operand's height back to the loop building on top of it, so that the
counted number is the tallest operand plus the levels above it rather than the
greater of the two. `parseTypeArgs` counts its own descent.

This is the clause of 0042 that could not hold. "The point every expression
passes through exactly once" is a statement about descent, and **the one place
it named is structurally unable to see height**: at the moment `parseUnary` is
entered for the last term of a chain, the levels the chain will fold above that
term do not exist yet and no frame is open for them. A single site can only
count height if every level is a frame, which is exactly what precedence
climbing exists not to do.

**A written type answers to the same number rather than to one of its own.** It
is read by the same recursive descent, spends a frame per level the same way,
and is walked by the same later passes. A second limit would be a second number
to remember for no difference a program can observe.

**A written type is measured from where it is written, and a chain folded above
it is not part of where that is.** A type nests only by descending, so what is
open above it is already counted by `depth`: a type written five levels into an
expression has 995 of its own left, exactly as a subexpression there would.
What is *not* counted against it is a level that cost no frame — every term of
a left-folding chain — because no pass will spend a frame on those while it is
walking the type. So the type's depth is never carried back as an operand's
height.

## Consequences

**The boundaries are now the shape's, and the same in both builds.** A chain of
`+` is accepted at 1000 terms and refused at 1001; a chain of `.` at 999
suffixes and refused at 1000; a written type at 1000 levels of argument list
and refused at 1001. Every one of those is the same number in a debug build and
a release one, which is what 0042 promised and did not deliver for these
shapes.

**The refusal names the token whose level is over the limit** — the operator,
the `.`, the `(` — rather than wherever the cursor had reached. For a form read
in a loop the cursor is past the whole chain, and a caret on the closing brace
of the function describes nothing.

**`[S-Nesting]` now has two messages**, one naming an expression and one naming
a type, because a caret on a `[` under text that says "this expression" sends a
reader to the wrong construct. The rule name is what a diagnostic is indexed
by, and it is unchanged.

**The count is in three places, and that is a cost.** A form added later that
folds left rather than descending will not inherit the bound by sitting
somewhere; it has to say so. 0042's single site was worth wanting and was
bought with a bound that did not hold — the cost is real, and it is paid to
count the thing the rule is about.

**A program can be refused that the compiler would have survived.** Nothing
written by hand is near 1000 levels, and a generator that produces something
deeper has found a bug in itself, which is the other reason the limit reports
rather than aborts.

## Alternatives considered

**Leaving the count where 0042 put it and raising the number.** No number
works: the admissible height is quadratic in the budget, so the parser accepts
trees the later passes die on at every setting, and lowering the budget far
enough to make *m²/2* safe would refuse ordinary programs.

**Counting turns of each loop and taking the maximum.** Cheap, and wrong by the
same argument at one level down: the height of a chain is its tallest operand
*plus* the operators stacked above it, not the greater of the two. A maximum
would accept a quarter of a million levels built from a thousand chains of a
thousand. Carrying the finished operand's height back is what the maximum
leaves out.

**A second limit for written types.** Rejected because nothing observable
distinguishes the two. A type is read by the same recursion, costs the same
frame, and is walked by the same passes; a separate number would be a second
thing to remember and a second thing to keep in step with the first, in
exchange for no program behaving differently.

**Adding a type's depth to the height of the expression around it.** This is
what the first implementation did, by raising the enclosing measurement from
the type's depth. It is wrong in the direction that matters: a type 700 levels
deep written inside a chain of 400 terms was refused, naming the chain — a
program in which neither construct is within 300 levels of the limit, and a
diagnostic pointing at the one that is not deep. A chain's levels cost the
parser no frame and cost no pass a frame while it is walking the type, so the
two never sum on any stack and must not sum in the count.

**Counting frames rather than height, and bounding the frames honestly.** This
is what 0042 has, described accurately: it bounds the parser and nothing after
it. Rejected because the parser is not where the stack runs out — the measured
deaths above are in the resolver and the type checker, on trees the parser
accepted comfortably. Bounding the producer's recursion protects the producer;
bounding the artefact protects everyone who reads it.

**Rewriting the passes to an explicit stack.** Removes the limit rather than
stating it, at the cost of turning recursive descent and every pass that walks
the same shape into state machines, and it would still need a bound on
allocation. 0042 rejected this and the reason is unchanged; it is recorded
again only because the measurements above are the ones that would justify
reconsidering it, and they do not.
