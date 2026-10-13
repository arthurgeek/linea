# 53. Exclusivity is triggered by mutation, not by the marker

Status: Accepted — 2026-07-29

Supersedes the exclusivity clause of
[0025](0025-mutation-through-a-parameter-is-marked.md). The rest of that record
stands: `inout` is still a convention on the parameter rather than a type, `&`
is still required at the call site and forbidden anywhere else, and an address
is still what is passed.

## Context

0025 made the representation of an argument the compiler's to choose, and
rested the whole of that freedom on one rule: a place passed `&` may not
overlap any other argument's places. The reasoning is exact — if no program can
observe whether an argument was handed over as an address or copied in and
copied back, the backend may pick either.

The rule names the marker. Mutation is what it is about, and `&` is not the
only way an argument mutates a place. A block is an expression, so an argument
may be one, and a block holds statements:

```
fn pair(read a: P, b: u8) -> u8 { a.x + b }

var p: P = .{ .x = 1, .y = 2 }
pair(p, { p.x = 9
          0 })
```

Nothing is marked anywhere, and the first argument's value depends on which
representation the second argument's write is racing. The compiler passes a
`read` aggregate by address and a `read` scalar by value, so the same source
shape answered `9` for a struct and `1` for a `u8` — the layout table deciding
a program's meaning, which is the one outcome 0025 exists to prevent. `f(&x, x)`
was rejected because "the callee would observe its storage changing through an
argument nobody marked"; `f(x, { x = 9  0 })` is that sentence with the marker
removed.

## Decision

**Exclusivity is triggered by mutation. An argument mutates a place two ways:
passing it `&`, and assigning to it.** A place either one mutates may not
overlap any other argument's places, whether that argument mutates it too or
merely reads it.

Everything else about the rule is unchanged. It is still checked per call site
from the argument list alone, a mutation still counts wherever it sits inside
an argument rather than only at its top, and overlap is still a shared root
with one path a prefix of the other.

This widens the language: programs that were accepted are now rejected. That is
the direction a soundness rule may move on its own, because the rule's promise
is about what cannot be observed, and every program it now rejects was one that
could observe it.

## Consequences

**One predicate answers "does this argument mutate that place".** It is asked
once per pair of arguments and reports the same diagnostic, `[N-Aliased]`, for
both shapes; only the wording of the label differs, because a reader sent to
the other argument needs to be told whether to look for a mark or a write.

**The freedom 0025 claimed is real for the first time.** Until now, a `read`
aggregate passed by address and the same value passed by copy gave different
answers for a program the compiler accepted, so the choice was observable and
the premise licensing it was false. The by-address representation of a `read`
aggregate is what depended on this, and it is now supported by the rule it
cites.

**Within a single argument nothing changes.** Evaluation order inside one
argument is sequential and visible in the source, so `f({ p.x = 9  p.y })`
means what it reads as. The rule is about the order arguments run in, which is
the order nothing states.

## Alternatives considered

**Copy a `read` aggregate in, so both representations answer `1`.** Rejected.
It buys agreement by paying for a copy of every aggregate a function merely
reads — the copy 0025 explicitly reserved the right not to make — and it buys
it only for this shape. Nothing would then stop an argument mutating a place
another argument passed `&`, which is the case the rule already covers, so the
copy is a second mechanism answering a question the first already answers.

**State an evaluation order for arguments and let programs rely on it.**
Rejected. It makes the answer defined, but it defines it as whatever the
compiler does today, and it hands the representation choice back: once a
program may depend on seeing the write, passing that argument by copy is a
different program. The rule that keeps the choice open is worth more than the
programs it rejects, all of which are one binding away from saying what they
mean.

**Treat it as an ownership rule rather than a naming one.** Rejected. The
ownership pass answers questions about a value's history across a whole body;
this one is answered from an argument list, with no state and no flow. Putting
it where the flow analysis lives would suggest it needs the flow analysis,
which is exactly the impression [N-Aliased] is written to avoid.
