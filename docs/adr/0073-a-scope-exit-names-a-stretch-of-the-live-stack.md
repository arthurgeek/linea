# 73. A scope exit names a stretch of the live stack

Status: Accepted — 2026-08-06; refines 0066

## Context

[0066](0066-a-blocks-state-is-its-dominators-plus-what-it-changed.md) settled how
a block's ownership state is represented, and it set a condition on anything
that would narrow what `.dies` resets: *"the burden is on the change to show
that the ones it drops could not have disagreed — not that the corpus does not
notice."* This is that change, and this record is where the showing lives.

Leaving a scope emitted one `.dies` per binding live in it. A `?` leaves every
scope it sits inside, so a body of n early exits over n live locals built a
graph of n²/2 operations — and every pass that walks the graph paid it again.
It was quadratic in memory before it was quadratic in time, which is what says
the graph itself was the problem rather than a search over it:

| exits | time | peak memory |
| --- | --- | --- |
| 750 | 20ms | 47MB |
| 1500 | 70ms | 154MB |
| 3000 | 270ms | 540MB |
| 6000 | 1110ms | 2384MB |

The cost of an exit was the size of the body around it, and nothing about a
program says those two should multiply.

## Decision

**A scope exit names a stretch of the live stack, and resets the state of the
bindings in it that owe something.**

The live stack is a tree rather than a list that is copied at each exit: one
`Scope { binding, outer, depth, last }` per declaration, minted in the walk's
order. That order is depth-first, so a scope's subtree is the contiguous run
`[i, last]`, and `last` is filled by one backward pass as scopes close. An exit
emits one operation carrying the top of the stack and how much of it survives.

Membership is then two comparisons and no allocation: a binding's scope is in
the stretch when it is deeper than the mark and its index lies within the run
the top names. Depth alone is not enough — a sibling scope sits at the same
height and is reachable across a branch, which `liveFrom` walks — so the run
bound is what makes the answer exact rather than merely usually right.

**The deaths stay in the graph.** An exit still says that these places die
there, and `liveAfter` and `liveFrom` still read it, through one routine on the
graph so the two cannot come to disagree. `[O-CopyDead]` is unchanged.

**What is dropped is the state reset for a binding that owes nothing**, and
0066's burden is discharged by three facts rather than by the corpus staying
green. A binding that owes nothing is named again only where a loop redeclares
it, and the `let` writes before anything reads and reports nothing over a place
that owes nothing. A merge reports only about bindings that owe something. And
`moved_at` is quoted only for a place a consume moved, which a place that owes
nothing never is.

Dropping those resets is not a tidying: a reset per binding is a delta edit per
binding, so keeping them would move the square out of the graph and into the
trail. The scopes that owe something are threaded once for the whole program —
each scope points at the innermost scope at or beneath it whose binding is
linear — so an exit over a body of `UInt8` locals visits nothing at all.

## Consequences

Linear, where a doubling had been costing between 3.5x and 4.1x:

| exits | before | after |
| --- | --- | --- |
| 750 | 20ms / 47MB | 0ms / 9MB |
| 3000 | 270ms / 540MB | 10ms / 25MB |
| 6000 | 1110ms / 2384MB | 20ms / 44MB |
| 24000 | — | 80ms / 168MB |

At 6000 exits that is 55 times faster on a fifty-fourth of the memory, and
6000 through 24000 costs 2.00x and 2.00x in time. The conformance sweep holds
the dimension to the same bound as the other nine rather than printing it.

Verified beyond the suite: every `.lin` under `tests/`, `examples/` and `std/`
run under both compilers for `check` and `emit-ir` — 1734 runs, none differing
in exit status, stdout or stderr.

**It uncovered a defect that predates it.** A block's edits are stated against
its dominator's exit, and that exit rises as the sweeps settle, so an edit
recorded earlier can hold a `was` no block still has. At a loop head the delta
is applied on the way down and undone on the way back, leaving the base a merge
is measured against holding a value nothing wrote — and the merge re-records
the same stale edit forever. The trail is restated against the current base
when a join winds to it. This is latent rather than new: it needs a base that
rises to meet an existing join edit, and removing the resets is what made the
corpus reach it.

## Alternatives considered

**Depth alone as the membership test.** One comparison instead of two, and
wrong: two sibling scopes sit at the same depth, and a branch makes the other
one reachable from where the test is asked. A case pins it.

**Emitting a death only for a binding that can leak.** Smaller still, and it
changes the language: `endScopesTo` also runs at block ends and loop exits, so
a missing death lets `liveFrom` follow a back edge and find a read on a later
iteration — and a `copy` that is dead today would stop being reported.
`[O-CopyDead]` is a rule, not an optimisation.

**Leaving it quadratic and bounding the input.** A body with thousands of `?`
is not written by hand, so the shape looked academic. It is not: a body's exits
and its locals both grow with the body, and generated code is a body. The sweep
now builds exactly that shape, which is how the cost was found.
