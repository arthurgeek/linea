# 92. A settled type parameter flows inward

Status: Accepted — 2026-08-18. Partially superseded by [0152](0152-an-integer-literals-type-is-settled-by-its-uses.md).

Extends [0018](0018-the-integer-model.md), whose "literals typed by context" is
the clause this widens.

## Context

`[T-Literal]` says an integer literal takes the type that flows into it, or
`Int64` where nothing does. A parameter's declared type flows: `concrete(a, 6)`
where the parameter is a `UInt8` types the literal as one, and nothing about
that is remarkable.

A type parameter did not, even once another argument had settled it:

```linea
fn same[T: Equatable](read a: T, read b: T) -> Bool { a == b }

same(n, 1)          // T-Mismatch: `T` was already settled as `UInt8`, and this is a `Int64`
same(UInt8(3), 1 + 2)   // the same, for arithmetic over literals
same(p, .{ .x = 4 })    // T-Infer: the type of this literal cannot be determined
```

Every concrete equivalent of those three compiles. So this was not a rule about
literals — nothing flowed from a settled type parameter, and three kinds of
expression failed with two different diagnostics.

Neither was it a decision anything recorded. The call that settles type
parameters checked each argument with no expectation, because at that point it
has none to give; the type it settled was then never handed back to the
arguments that had waited for it. The rule said one thing and the checker did
another, in a case the rule does not carve out.

The cost was ordinary generic code. `expect_eq(doubled(3), 6, ...)` — the shape
every test over a number wants — required `UInt8(6)`, and the reason was not
something a programmer could read anywhere.

## Decision

**A type parameter another argument settled is a type like any other, and flows
inward the same way.**

Which argument settles it follows a division §4 already draws: an expression
either determines its own type or waits for one. Those that determine settle the
parameter; those that wait are checked against what was settled, exactly as they
would be against a written type. Where nothing settles a parameter, the ones
that waited fall back on what they do when nothing flows — so `same(6, 6)`
remains a call over `Int64`.

**This is not a conversion.** A literal typed `UInt8` is a `UInt8` from the
start; nothing is widened, narrowed or reinterpreted, and 0018's ban on implicit
conversion between integer types is untouched. What changes is which types are
allowed to reach an expression that was waiting for one.

**Position does not decide.** `same(n, 1)` and `same(1, n)` mean the same thing.
That is the property that ruled out the smaller change of letting an already
settled parameter flow while leaving the settling itself in argument order:
under that rule the first compiles and the second does not, and a language where
argument order decides whether a call is accepted is harder to explain than one
refusing both.

## Consequences

The checker gains `determinesItsOwnType`, which is where §4's sentence acquires
a referent. It is structural — a literal or a shorthand waits, a name or a call
or a conversion answers, a group or a negation says what its operand says, and
arithmetic answers if either operand does.

**It is an approximation, and safe in both directions.** Answering "waits" for
something that would have determined its own type leaves the parameter for
another argument, and where none settles it the second pass settles it from this
one anyway — which is what happened before. Answering "determines" for something
that waits reproduces the old behaviour for that form. Neither answer yields a
wrong type; the failure modes are a diagnostic that was already there.

That matters because the predicate is a second place that knows about type flow,
and this compiler's recurring defect is one rule with two implementations
([0048](0048-one-question-has-one-answer.md)). The mitigation is not vigilance:
it is that a disagreement degrades to the previous behaviour rather than to an
accepted program with the wrong types.

**Structural rather than measured**, because measuring is not available. Asking
whether an expression determines its own type by checking it and seeing what
happened would report diagnostics for a probe: the sink appends and has no
rewind, so a check made speculatively cannot be taken back.

The settling walk runs twice over the arguments. Both passes are over one call's
arguments, which is bounded by what the callee declares and not by the program.

## Alternatives considered

**Leave it, and write `UInt8(6)`.** Explicit, and consistent with an integer
model that refuses inference elsewhere. Rejected because the inconsistency is
the defect rather than the verbosity: `concrete(p, .{ .x = 1 })` compiles and
`same(p, .{ .x = 1 })` does not, and no rule states why. Requiring the
conversion in both would have been coherent too, but it would break every call
that passes a literal to a concrete parameter.

**Let a settled parameter flow, without reordering the settling.** The smaller
change: once settled, later arguments see it. Rejected because it makes argument
order decide acceptance — `same(n, 1)` compiles, `same(1, n)` does not — which
is a worse rule to explain than the one it replaces.

**Letting the expectation settle a parameter before a waiting argument falls
back on its default.** `let narrow: UInt8 = pick(8)` reads as though the
annotation should decide, and the change is small: run the expectation between
the two passes. Rejected because it is already decided the other way. Inference
runs forward from what was passed, and
`tests/generics/an_annotation_does_not_reach_back.lin` records the reason: a
parameter settled from the expectation lets an argument's type depend on the
call's, and the two can disagree.

The distinction is worth stating, because the code holds both. An expectation
may settle a parameter **no argument reaches** — that is what makes a function
with no arguments over a parameter callable. What it may not do is override
what an argument would have defaulted to, which is a different question wearing
the same clothes.

**Full unification across the argument list.** Collect constraints from every
argument and solve. Rejected as a much larger change to a checker that is
deliberately a single forward walk, for a problem that does not need it: the
division between expressions that determine their type and those that wait is
already in the language, and using it settles this without a solver.
