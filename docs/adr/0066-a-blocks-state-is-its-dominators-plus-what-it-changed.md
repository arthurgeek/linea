# 66. A block's state is its dominator's, plus what it changed

Status: Accepted — 2026-08-03

## Context

Ownership is a forward dataflow over a function's blocks. Each block carries the
state of every binding at its entry, and the sweep copies that state in, walks
the block's operations, and joins the result into each successor.

The state is a dense matrix: `entry` is `blocks × roots`, and since
[ADR 0063](0063-disposal-is-scheduled-never-inserted.md) a second array of the
same shape carries where each binding was taken, so a second take can say where
the first was. Both are allocated per function and both are copied per block per
sweep.

Two changes have already narrowed what "roots" means. It was every binding in
the *program*, which made a module of many small functions quadratic in memory
before it was quadratic in time; it is now the bindings the function itself
mentions. And the sweep visits blocks in reverse postorder, so a chain of `if`s
settles in two sweeps rather than one per `if`.

What remains is a function whose own size grows both dimensions at once. In the
worst case a body of n statements has O(n) blocks and O(n) locals, so the matrix
is O(n²) and the copying is O(n²) per sweep. Measured on one function of sixteen
thousand locals, `check` takes 1.35 s and grows 3.89× per doubling — an exponent
of 1.96, which is quadratic in the body's own size.

The cost is not what the analysis learns. It is what it carries. Two counts
say how far apart those are, both instrumented on the pass itself:

| | `one_2000` | `one_4000` |
| --- | ---: | ---: |
| cells in the matrix | 7 992 668 | 32 003 333 |
| cells a later operation can name | 7 992 668 | 32 003 333 |
| cells any operation writes | 9 653 | 19 329 |

The middle row is the one that settles the shape of an answer, and it settles it
against the obvious one. **Every cell is reachable information.** A binding is
named again by the `.dies` that ends its scope, `endScopesTo(0)` runs at the end
of the body, and a top-level `let` therefore lives from its declaration to the
function's last block — so at every block, every binding is named at or after
it. Narrowing a row to what is live at its block removes nothing.

The last row is where the room is. The state of a binding changes only where an
operation names it, so a block's row differs from its predecessor's in as many
places as that block has operations. The matrix holds 827 times more cells than
any operation writes at two thousand statements and 1 655 times more at four
thousand — and that multiple doubles with the body, because the edits grow with
the program while the matrix grows with its square.

## Decision

A block's state is the state of the block that dominates it plus the edits
between them, not a row of its own. The measurement above rules out the
alternative that looks obvious first: narrowing a row to the bindings live at
its block saves nothing, because every binding is live at every block.

Against its dominator and not against its predecessor, which is what the title
first said. A block with several predecessors has no single one to be stated
against, and its dominator is the deepest block every path to it passes
through — so it is the deepest state every predecessor shares, which is what a
delta needs and what a predecessor is only sometimes.

**The representation stops being an array a reader can index and becomes one a
reader has to ask.** `entry[block][slot]` meant the same binding for every
block, so a reader holding a slot held an answer. A block's state is now reached
through what it inherits, and the cost of a question depends on where the asker
stands relative to the answer. That is the architectural cost, and it is larger
than the liveness pass this record first proposed: a join between two blocks
reconciles two edit sets against their common ancestor, and `checkMerges`
reports the same disagreements in the same order from a structure that no longer
lays them out in that order.

Three further things constrained the answer, and they are why this was a record
rather than a patch.

**Diagnostics may not move.** `checkMerges` walks the vector and reports the
disagreements it finds, in the order it finds them. The roots are sorted by
binding for exactly that reason. A narrowed row changes which bindings are
compared at a join, and the burden is on the change to show that the ones it
drops could not have disagreed — not that the corpus does not notice.

**The lattice distinguishes dead from never-declared, and must keep doing so.**
`.dies` sets a binding to `uninit` at scope end, which is what stops a binding
declared inside a loop reaching the head twice — once uninitialised and once
moved — and disagreeing with itself. A row holding only live bindings invites
the reading that absence means dead, and that is not the same fact: a binding
absent because its scope ended and one absent because it was never declared are
different states of one lattice, and a back edge is where the difference is
observable. Whatever the representation, it has to say which of the two an
absent column is.

**`.dies` is not a join-uniform event, and that is the hard part.** The obvious
argument for narrowing is that a binding's live range runs from its `let` to its
`.dies`, so a root not live at a join is one whose scope ended on every path
into it and which no later operation can name. That argument does not hold as
written. `endScopesTo` runs on one-sided paths — at a `continue`
(`build.zig:623`), at a `break` (`:668`), at a `return` (`:679`), and per arm
for a match's binders (`:1005`) — so a root can die on one path into a block and
not on another. A narrowing has to say what a row holds for a root that is dead
on one predecessor and live on the other, and show that the answer is the one
the dense comparison gives. Working this out is the substance of the change; the
liveness pass around it is not.

*This dissolved rather than being answered.* It is a question about narrowing by
liveness, and what landed narrows by **what changed**. A `.dies` on one path is
a change, so the slot is among the ones its merge asks about, and the merge
takes the join of what every predecessor actually holds — `uninit` from the path
whose scope ended and `init` from the path where it did not. A slot a merge does
*not* ask about is one no predecessor changed, which is precisely the case where
a one-sided death cannot have happened. Dead and never-declared stay apart for
the reason they always did: both are values a slot holds, and neither is the
absence of one.

**The bound stays asserted.** The sweep count is `blocks * 4 + 1` and
exhausting it is a wrong answer in the accepting direction, out of the pass that
is the whole memory guarantee. A sparse representation changes what one sweep
propagates, so the argument for the bound has to be made again rather than
carried over.

*It holds, because the trail pulls where the rows pushed.* A sweep in reverse
postorder computes a block's entry from every predecessor's exit as it stands.
A forward edge is therefore carried within the sweep, exactly as far as a push
carried it, and a back edge is carried to the next sweep, exactly as a push
was — so the trail is never behind the rows and the bound that was slack for
them is slack for it. It is also not left as an argument: the assertion below
runs both and compares them, and exhausting the bound is what the existing
`!changed` assertion already refuses.

## What the change is

The shape is settled by the two counts above; what follows is the structure they
imply, so that the work starts from a design rather than from the measurement
again.

**One state, positioned rather than copied.** A single `state` array of the
function's roots, and beside it the `state_at` that says where each was taken.
Block `b`'s entry is a position in a trail of edits rather than a row of its
own: each edit records the slot, the value before it, and the value after, so
the trail can be walked in either direction. `runBlock` reads and writes `state`
by slot exactly as it does now, and appends what it changed.

**Joins record their merge as edits.** A block with one predecessor that is also
its dominator needs nothing: its entry is where the trail already stands. A
block with several has an entry state that is on no path, so it is computed and
appended as edits of its own. Every predecessor is dominated by the block's own
dominator, so each differs from that one state — and therefore from every other
predecessor — only in the edits since it, and those slots are the whole of what
the merge asks about.

**`checkMerges` reconciles against a common ancestor.** Two predecessors of a
join differ only in the edits since the last point they shared, so the
disagreements are found by walking those two edit sets rather than two rows.
The bindings must still be reported in binding order, which the edit sets do not
give — so they are collected and sorted before anything is said, and that sort
is over the disagreements rather than over the roots.

**A merge reads the path once, not once per predecessor.** Winding from one
predecessor to the next replaces only the frames the two do not share, so the
frames they do share are read once. Without this, a loop that n `break`s leave
reads the whole body n times, which made that shape three times slower than the
rows it replaced before the walk was made incremental. It is the difference
between a merge costing the edits it reads and costing those edits times the
number of paths in.

**Two details that keep the code small**, found while building the dominators.

A block's edits need no change to `runBlock`. The slots a block can write are
the slots its operations mention, which is the same set `rootsOf` already walks
the operations to collect. Saving those slots before the block runs and
comparing after gives its edits, so the writer stays a writer and nothing has to
journal.

The value a delta is stated against is already on the undo stack. When the
chain from a block's dominator down to it is applied, the first undo record for
a slot holds what that slot was before anything on the chain touched it — which
is its value at the dominator. *In the end this was not needed:* a merge winds
back to its base before it applies its own edits, and once there it reads the
base out of the state directly.

**The trail is rebuilt per sweep, but a block's edits persist.** This is the
one place the design above was wrong, and it is the load-bearing correction.
A sweep in reverse postorder cannot reach a back edge's predecessor, because
that block comes later in the order and this sweep has not run it. Its edits
from the previous sweep are what stands in, so a block's delta is replaced when
that block is recomputed rather than discarded when the sweep begins. Applying
a stale delta on a fresher base is a value at or below the answer and at or
above the last one — it rises and stays under the fixpoint, which is all a
monotone iteration needs.

**The states are recomputed each sweep and the sites are carried forward.**
That asymmetry is the lattice's. States only rise, so a predecessor's exit today
is at least what it pushed on any earlier sweep and joining the old answer in
adds nothing. A site does not rise: once a value arrives already taken, the
operation that took it reports and returns without saying where, so the site the
last sweep settled can be one no predecessor still offers. Keeping the earliest
seen means keeping it.

Finding that took one more change, in its own commit. `.dies` used to set a
binding back to `uninit` and leave its site pointing at wherever the old value
went — unreadable, since a site is only quoted for a place that is `moved` and
the only way back to `moved` is a consume that writes its own. What it could do
was outlive its value and travel, which is a fact about how far the walk got
rather than about the program, and it is the one place the two representations
disagreed on a value neither could ever read.

**How it is checked.** The dense computation is kept beside the delta one in
Debug and ReleaseSafe, and the two are asserted equal at every block. That is
stronger than a corpus differential, which only sees the programs someone wrote:
the assertion runs on the 597 conformance cases, on their metamorphic rewrites,
and on every generated program, and it fails on the first block where the two
disagree rather than on whichever diagnostic happens to move. The dense path
costs nothing in the distributed build, which is the same bargain
`writeTypeRef`'s assertions already make.

It is bounded by the matrix it allocates, because past that size the check would
spend exactly what the representation was changed to stop spending. Every case
in the corpus is far under the bound and only a generated body is over it.

It earned the bargain twice: both places this first got wrong were sites, on
generated programs, on slots whose state was `uninit` — which is to say on
exactly the values a corpus differential cannot see, since nothing reads them.

## Consequences

- Ownership stopped being quadratic in the size of one function, which was the
  last super-linear dimension the compiler had that was not a missing index.
  Measured on one function, against the same compiler with the rows:

  | statements | time | memory |
  | ---: | ---: | ---: |
  | 2 000 | 0.030s → 0.011s | 77 MB → 30 MB |
  | 4 000 | 0.089s → 0.016s | 235 MB → 44 MB |
  | 8 000 | 0.345s → 0.026s | 839 MB → 74 MB |
  | 16 000 | 1.394s → 0.047s | 3 205 MB → 138 MB |

  Both halves are linear: 1.44×, 1.62× and 1.83× per doubling in time and
  1.46×, 1.69× and 1.86× in memory, against about 3.9× in both before. A join
  of many arms is 4.7× faster at four thousand of them; deep nesting, a module
  of many small functions and a loop that many `break`s leave are unchanged.
- A loop that many `break`s leave stays quadratic, and this is not what makes it
  so. That function declares two bindings, so its matrix was never large — its
  memory is flat in both — and the cost is somewhere else in the front end. It
  is the next dimension to measure, and it is not this one.
- Every consumer of ownership state depends on where it stands relative to the
  answer, not only on the state. That is a wider interface than an array a slot
  indexes, and it is what a reviewer of a later patch here should read first.
- The cost became proportional to what the analysis writes rather than to what
  it could write. A body whose operations really do touch every binding at every
  block still costs what it costs, and that is the right answer rather than a
  regression.

## Alternatives considered

**Leave it.** The dense matrix is simple and every rule reads it the same way.
Rejected as a permanent answer, because "a program a person would not write" is
the argument that was made for every super-linear defect found so far, and the
language does not promise to be compiled only from hand-written source.

**Narrow the matrix without narrowing the analysis** — keep a dense row but
store it compressed, or skip blocks whose predecessors did not change. Rejected:
the second sweep is already nearly free under reverse postorder, so this reduces
a constant and leaves the first sweep, which is where the quadratic is.

**A block-local row holding only the bindings live at it.** What this record
proposed first, and what the measurement above rules out: every binding is named
by the `.dies` at the end of the body, so every binding is live at every block
and the narrowed row is the dense one. Recorded rather than deleted, because it
is the answer a reader arrives at from the code alone, and the reason it fails
is not visible there.

**Drop `leaving`.** It is a second `blocks × roots` array holding what each
block leaves behind, and `checkMerges` could recompute a predecessor's from its
entry instead. That is a real halving of the memory and it is worth doing on its
own, but it changes no exponent and is not this decision.

**A worklist instead of sweeps.** Orthogonal: it changes how many times a block
is visited, not how much each visit carries. Reverse postorder already took the
sweep count to two.
