# 204. MIR verification re-derives the storage safety ownership promised

Status: Accepted — 2026-10-02. Extended by
[0246](0246-a-call-holds-what-it-lends-until-it-runs.md), which refuses a lent
address into a root a `sink` argument of the same call moves.

Extends [0049](0049-generated-code-is-verified-before-it-is-emitted.md): the
verifier that holds the emitter to the layout table now also holds lowering to
what ownership decided. Extends
[0050](0050-the-layout-rule-has-a-second-implementation.md): it takes the
same bounded exception to [0048](0048-one-question-has-one-answer.md), under
the three conditions that record states and one more this record adds, for a
second reading of ownership rather than of layout. Reads
[0034](0034-ownership-is-positions-and-a-graph.md),
[0104](0104-release-is-optional-and-never-scheduled.md),
[0114](0114-ownership-records-the-disposal-plan.md),
[0121](0121-typed-storage-is-private-and-checked.md),
[0123](0123-observations-carry-owner-dependencies-through-callable-contracts.md),
[0193](0193-a-closure-may-hold-a-place-lent-inout.md) and
[0066](0066-a-blocks-state-is-its-dominators-plus-what-it-changed.md) for
what it checks and how it walks.

## Context

The ownership pass decides what is sound. It builds its own `Cfg` over the
expanded syntax tree, tracks moves by position, carries observation
dependencies through callable contracts, and refuses a program that uses a
value after moving it, mutates an owner while an observation of it is live, or
leaves a linear obligation unsettled on some path. Nothing downstream asks any
of those questions again. Lowering trusts the program it is handed; the MIR
verifier ([0049](0049-generated-code-is-verified-before-it-is-emitted.md))
holds the emitter to the layout table and the calling convention, and says
nothing about lifetimes.

So when one of ownership's paths drifts, nothing notices. A `for` over a
vector's slice let the body push into that vector, and the loop's next pass
read the elements through storage the push had freed. The program compiled,
linked and ran. What found it was a person reading generated code, not a gate.
The defect was in one branch of the dependency analysis — the `Cfg` abstracts
a `for` into a `.element` projection, and that projection was not asked
whether the loop's next pass still needed the walked value's observation —
and that branch is individually plausible: it passed review, it passed every
case that exercises the other branches, and it disagreed only on the input
nobody had written.

That is the bug class [0048](0048-one-question-has-one-answer.md) names, and
its usual remedy is to have one implementation. Here that remedy is what leaves
the gap: ownership *is* the one implementation, and the one implementation has
no second opinion. A second reader of the same `Cfg` would need the same
missing knowledge — that the projection is a `next` call on every pass — that
the first reader lacked. A second reading over a *different representation*
would not. MIR is that representation: it is what the program will actually
do, after monomorphisation and after every position, contract, loop form and
schedule has been turned into a call, a blit or a store. There is no `for` in
MIR. The walk is `call iterate`, a move into a slot, and in the loop header an
`inout` argument to `call next` — an ordinary call on an ordinary back edge,
which needs no notion of a loop form to be seen. Every front-end "one rule,
two syntaxes" drift (`for` against its hand-written loop, `?` against `match`,
`else |_|` against `match`) collapses to one shape here.

What MIR carries today, read from `src/mir/mir.zig`, `src/mir/lower.zig` and
`src/mir/verify.zig`, decides how much of that is possible:

- **Roots are visible.** Every aggregate binding is a slot whose value is its
  address (`addr_of`); a lent parameter is a managed-address slot; an aggregate
  a callee returns is a managed address the caller's storage backs. The
  verifier's `Place` domain already attributes every address to one of these
  (`slot`, `lent`, `returned`) or to `heap` and `static`.
- **Moves through a call are visible.** A sink argument is the source slot's
  own address, `call f(%addr_of $s)`, and the callee copies out of it; the
  convention is read from the callee's signature, which the module's type
  table carries in `CallableSignature`. A release is such a call and nothing
  more: [0104](0104-release-is-optional-and-never-scheduled.md) makes every
  disposal a written `release()`, and the scheduled ones lower to the same
  call at each exit.
- **Contracts are visible.** `CallableSignature.contracts` holds each
  signature's normalised `borrows`, `carries` and `retains` clauses, with
  adopted trait contracts copied in, in the pool the module carries.
  `Slice.iterate` is written without a clause and its interned signature
  carries the trait's `carries(self)`; a hand-written loop over it is refused
  by ownership through that clause.
- **A move into a binding is not visible.** `let q = p` and `copy(q)` both
  lower to `copy_value %dst, %src`; the one difference — that `p` is dead
  afterwards and `q` is not — is a fact only lowering had, and it did not
  write it down.
- **An address that became an integer carries nothing.** A `Slice` is two
  `UInt64` fields, `at` and `len`; `address_bits` and `slot_span` produce the
  integer and `storage_addr` consumes it. The owner an intrinsic such as
  `slot_place(owner, at, len, …)` names is dropped when lowering emits the
  checked access, and `as_slice`'s own body loads two words and adds: it
  holds no `borrow` of the vector it lends.

The check this record introduces is admissible only as a verifier. It decides
nothing about the language: it never changes what a program means, never
feeds an answer to checking or lowering, and a disagreement is a compiler
defect under exit 70, never a user diagnostic. A false positive here is a
user with a valid program and a compiler that will not build it, which is a
strictly worse failure than a red corpus. So the record has to say which
facts it re-derives, why re-deriving them rather than reading ownership's
tables is the point, and what bounds the refusals it may make.

## Decision

**The MIR verifier re-derives, from instructions and signatures alone, that
no path uses an observation after its owner's storage changed, and that no
path reads an aggregate after it was moved out, and refuses a module that
breaks either.** It runs inside `verify` for every function on every
emission, as the phase after `escapes`, and it reads no table ownership
produced: not the `Cfg`, not the dependency facts, not the disposal plan.

### The invariant that bounds it

**Every refusal this pass makes is one ownership would also make on the same
program.** The pass is an under-approximation of ownership's refusals. It may
accept what ownership refuses — a miss is a bounded loss of coverage — and it
may never refuse what ownership accepts. It is an independent second line
behind ownership rather than a second proof of it: it refuses some programs
ownership refuses and accepts others ownership refuses, and what it guarantees
is two things. It refuses nothing ownership accepts, which every corpus case
and every generated program holds it to, since each is a program ownership
accepts. And it refuses the slice-walk class — a borrowed element or view of a
`Vec` or an array that is used after the storage grew, was freed or was written
through the owner — with ownership bypassed
(`a_slice_walk_keeps_its_vector_from_growing` and its array twin), so that
class does not rest on ownership alone. The first guarantee is a measurement
over the programs written, not a proof, which is why a refusal is triaged below
as a defect and not as a category. This is a fourth admission condition
beside [0050](0050-the-layout-rule-has-a-second-implementation.md)'s three,
and it decides the direction of every deliberate difference below: a
difference may only widen what the verifier *accepts*. It also fixes what a
refusal is. There are three kinds — a defect in ownership, a defect in
lowering, a defect in the verifier — and no fourth; "a coarsening to refine"
is not a category, because a refusing-side coarsening is a verifier defect.

### What it re-derives, and from what

| Fact | Read from |
| --- | --- |
| The roots of a function: owned aggregate slots, lent parameter slots, returned temporaries | `locals`, `slot_roles`, `param_count`, and each `call`/`call_indirect` whose result role is a managed address |
| Which root an address points into, at what offset, and within what span where a step is computed | the verifier's one attribution walk (`attribute`), which every phase reads: `addr_of`, `load` of a managed-address slot, `field_addr` with a constant offset, `check`; a `field_addr` with a computed offset keeps the constant prefix and the size of the aggregate it indexes as the span the address lands in. This phase adds one rule of its own: `load_indirect` of an aggregate is the address it loads from, because the value is where it lives |
| Which carrier an address was derived from | the same walk's carrier column: the slot behind `addr_of` or a lent `load`, the pointer value behind `observe`, the call behind a returned temporary, inherited through `field_addr` and `check` — kept because `Place` maps `observe` to `heap` and drops the pointer |
| Where a value is moved out of a root | a `sink` argument whose address is a whole owned root or returned temporary (convention from the callee signature's `CallableParam`); `move_value`, the instruction this record adds, with such a source |
| Where a root is written | `store`, `store_indirect`, `copy_value`/`move_value` destination |
| Where a root is lent for writing | an `inout` argument whose address is rooted |
| Where an observation is created | `borrow` of a rooted address; `address_bits` of one |
| How a call's result and `inout` arguments depend on its arguments | the callee signature's `contracts`: `borrows(p)`, `carries(p)`, `retains(d: s)` with a `.parameter` root |

Every one of these is an instruction shape or a signature. The independence
this buys is stated narrowly: **the pass is independent of ownership on
control flow, positions and desugaring, and dependent on the same contract
clauses and the same containment table.** Ownership reads
`CallableSignature.contracts` in its call-result rule and this pass reads
the same table, so a wrong clause — a `where carries()` mistakenly written
on `as_slice` — passes both readers, and for integer-addressed storage no
callee body can contradict it; both read the type table's containment fact
to say which reads can hold a dependency, so a type wrongly recorded as
unable to carry makes the same read a non-use for both. A third input is
shared with lowering and not re-derived: which blit is a copy of a place the
program reads again. Lowering reads that from ownership's `DisposalPlan` (a
place use recorded as read or taken), so a drift there is ownership's, and
it is caught in one direction only. If ownership records a use as taken and the
program reads the place afterwards, lowering emits `move_value` and the read
after it is refused by this pass. If ownership records a use as read where the
program takes the value, lowering emits `copy_value`, which this pass treats
as a plain copy: the duplicated owner is not refused here, and no compile-time
check refuses it. Only a program run under the checking runtime
(`run --check-storage`, which the checked-storage cases use) shows it, as a
double free or a leak. The verifier itself reads no plan. The half that is
independent is the half the motivating defect was in.

Ownership's own outputs are what this pass must not read: reading them would
verify that lowering copied ownership's answer, and the `for`-over-a-slice
defect was an answer ownership got wrong.

### The two properties, stated over MIR

A **root** is one of: an owned aggregate slot (storage representation
`bytes`, whether a local or a `sink` parameter the prologue copies in), a lent
slot (a managed-address parameter), or a returned temporary (a managed-address
call result). Scalar slots are not roots; scalar value positions are snapshots
([0125](0125-scalar-value-positions-take-snapshots.md)). A **carrier** is any
instruction value or slot: a root is also the carrier of what it holds, and a
value or slot of data-pointer representation carries what it points into.

**P2 — nothing uses an observation after its owner changed.** A carrier's
dependencies are a set of `(owner root, byte range of the owner, byte range
of the carrier where it is held)`. The held range is what makes a read of
one part of a carrier use only the observations stored in that part, which
is ownership's own precision: a struct holding borrows of two places, one
place changed, the other borrow read, is an accepted program. A dependency
is created by `borrow` and `address_bits` of a rooted address — the owner
range is the address's offset and the observed type's size — held relative
to the pointer's referent; and by a call whose signature says `borrows(p)`
(the bytes argument `p` covers of its root, plus what those bytes hold) or
`carries(p)` (what the bytes hold), held whole. They travel with the value:
a `load` of a slot inherits the slot's set; a `load_indirect` of a data
pointer, and a `borrow`, take what is held in the bytes read, re-based to
the referent; a `store` gives a slot what the value holds; a `store_indirect`
puts what a register value holds at the bytes written — a data pointer's
observation, or the integer `address_bits` made of an array's address, which
is how a view over an array reaches the `Slice` that holds it; a blit moves
the parts held in the copied bytes to the same places in the destination;
`retains(d: s)` puts what `s` holds at the bytes argument `d` covers of its
root — the field passed as `&h.kept`, not the whole of `h`.

A dependency is either **held** by its carrier — a view stored in some part
of it — or the **view** a pointer value has of the place it points into, which
`borrow`, `address_bits` and a `borrows` clause create. A read through a
pointer, whether a `load_indirect` or the source of a blit, carries what the
bytes it reaches hold and never the pointer's own view of them: `copy(*big)`
is a value of its own, and a later write to the place `big` borrows does not
make it stale, while a borrow stored in the copied bytes is held and does.
A pointer made from an aggregate holds what the aggregate holds, so the views
of pointers stored in it become held; a pointer made from a pointer, and a
value moved whole, keep views as they are; a view stored into memory stays a
view, which is how a pointer loaded back out of a field is still told apart
from what it points at. Any case this cannot tell apart is carried as held,
so the model is never more lenient than it was before views were told apart
from holdings.

Reading through a pointer is one rule with four sites: a `load_indirect`, the
source of a blit, an argument a `carries` clause reads, and an argument a
`borrows` clause reads (which holds, rather than drops, the views stored in the
aggregate it lends). The rule repaired three false positives, each a program
ownership accepts: a copy of a borrowed value (`copy(*big)`) followed by a write
to the place borrowed; a borrow loaded back out of a holder through a borrow of
that holder, followed by a rewrite of the holder
(`a_copy_read_through_a_borrow_of_a_holder_outlives_a_rebinding_of_what_it_held`);
and a result a `carries` clause took from bytes read through a borrow, followed
by a write to the place borrowed
(`a_carried_argument_read_through_a_borrow_outlives_a_write_to_its_source`).
The first has a case per place the borrow can sit (a local, a field, an array
element, a struct field, a returned borrow, a loop), and each rule has a
hand-built MIR test in `storage.zig` that fails when the rule is removed.

A root is **invalidated** over the bytes a write, an `inout` lend, a `sink` or a
`move_value` covers. Invalidation marks stale, in every carrier observing
those bytes, the dependency that observes them, naming the instruction. A use
on any path of a part of a carrier holding a stale dependency — a read
through an address rooted in or derived from it, a `borrow` or
`address_bits` of such an address, passing the carrier or such an address to
a call under any convention, or returning it; a value used whole uses every
part, a read through an address uses the bytes the address covers — is a
defect, provided what is read can hold a dependency at all: the type table's
containment fact says which types can, and a read of a scalar `Err` payload
out of a result whose `Ok` payload carries a view reads no observation,
which is what ownership says of it too.

**The bytes an address covers.** An address every step of which was a
constant covers a range. An address computed steps reached covers one part
of every element at every level: the strided set `array + k0 · elem0 + at1 + k1 · elem1 + … + inner`,
`len` bytes each, where each `ki` ranges over the elements of the array step
`i` indexed, `ati` is where that array sits inside the element step `i - 1`
chose, `inner` is what the constant steps after the last computed one added
and `len` the width accessed — ownership tracks which field an access names
and not which element, and this is that set. `t.b[i] = 9` writes the `b` part
of every element and nothing of the sibling `a`; `*cells[i].right` reads every
`right` and no `left`; `*rows[i][j].left` reads the `left` of every element of
every row, because the second step's stride composes with the first's and
does not merge into the bytes of the array it indexed; `*outers[i].arr[j].left`
does the same across the constant step between the two. The address records
three computed steps; one past the third is taken at element zero, which
covers fewer bytes than ownership counts and so refuses nothing it does not,
and the fourth step of `cs[i][j][k][l]` is an enumerated miss. A dependency
made or stored through such an address is recorded at the part of the first
element at every level, which misses the other elements and so refuses
nothing; a blit from such an address places each part at its offset within
the element, and a part lying across an element's boundary covers the whole
destination.

**P1, the part P2 needs — nothing reads a root after it is moved out.** An
owned slot or a returned temporary is moved by a whole-root `sink` argument
or a whole-root `move_value` source. A read of a may-moved root — the same
reads P2 names — is a defect; a `sink` of one is the double settlement.
Moves of a part of a root have no state: the pass holds roots whole, and a
part move is a miss, not a refusal. A lent root is never marked moved: an
`inout` parameter may be moved from and must be refilled before the callee
returns, and whether it was is the settlement question this record does not
check.

**Kills.** Every transfer is gen/kill over may-bits, and the kills are what
keep accepted programs accepted. Any write to a root kills `moved` and
`stale`: a loop that initialises an aggregate part by part into the same
slot on every pass, then sinks it, is an accepted program, and so is one
that rebuilds, field by field, a binding holding a view of something the
previous pass lent — a `let` of a literal is a sequence of part writes, and
MIR cannot tell it from one field assigned into a value holding a stale view
elsewhere, so both are accepted. A whole write replaces the set; an exact
part write drops the dependencies held within the written range, since the
value there is a new one, and adds what the new value holds there, so the
parts not written still mark the root stale when their owners change; a
write through a computed address drops nothing, because which part it
replaced is unknown. The definition of an instruction value — a call result,
a `borrow`, a `load` — kills `stale` and `moved` for that value, because a
loop re-executes the same instruction and a view re-created on each pass is
a fresh view.

The `for`-over-a-slice defect is P2, caught in the loop's function at the
instruction the record predicts: `as_slice` is `borrows(self)`, so the
returned `Slice` carries the vector's root; `iterate` takes it by `sink` and
is `carries(self)`, so its result carries the same set, and `move_value` puts
it in the iterator's slot; `push` lends the vector `inout`, which marks the
iterator stale; the loop header passes the iterator `inout` to `next` on the
next pass, which is a use of a stale carrier on the back edge, reported on
the second pass over the header. The array case reaches the same rule
through `address_bits`, whose integer the `Slice` slot receives by
`store_indirect`, and the element write that invalidates it; ownership
refuses it through a different branch of its own, so it is not the case that
reproduces the defect.

### The dataflow

One forward walk of the function's dominator tree, children in reverse
postorder, to a fixpoint, on an explicit stack: a dominator tree is as deep
as a function has sequential conditionals. The state is per root one
may-bit, `moved`, with the moving instruction; per carrier one
dependency-set handle for what it holds and one for its marks, each mark a
held dependency with the instruction that changed its owner. A transfer is
gen/kill, so it is monotone and a loop converges in at most the lattice
height of passes; two in practice, one for the body and one for the back
edge. An edge into a loop at a block that does not dominate its source —
flow structured lowering never emits — is refused as a defect before any
walk, because a walk of the dominator tree joins only at headers.

State is held as [0066](0066-a-blocks-state-is-its-dominators-plus-what-it-changed.md)
holds it: one vector, and a trail of changes. Entering a block rolls the
vector back to its immediate dominator's exit and applies the join of what
each predecessor changed after that dominator — the last value each
predecessor's trail segment gave an entity, OR-ed for the bits and unioned
for the sets, over the entities any predecessor touched — so a join costs the
predecessors' deltas and never the width of the state. A back edge's
predecessor is walked after the header, so the header's join is recomputed
when its subtree finishes and the subtree is walked again while the join
changes. A build with runtime safety — Debug, which the corpus runs, and
ReleaseSafe — computes the same fixpoint densely, one state per block, and
asserts it equal to the trail's at every block entry, naming the function,
block and entity first; it runs while the matrix holds at most `2^20`
cells, as 0066 bounds its own dual, and while instructions times entities
is at most `2^26`, because the dense invalidation scans every entity and
its work is that product rather than the matrix. `-Drelease` is ReleaseFast,
so the dual is off in the shipped compiler and the check is on, as 0049
asks; the Debug corpus walk and the suite's ReleaseSafe root run it. That
is how 0066 found the two defects
in its trail, and it found one in this one: a join that OR-ed the
dominator's value into an entity every predecessor had rewritten.

Dependency sets are shared lists sorted greatest first — by held offset,
with whole-held elements leading, then by root, then by the owner range —
with every `(element, tail)` pair interned, so two sets with the same
content are the same handle, a comparison at a join or in the dual is one
of handles, and copying a set is copying a handle. Adding an element
rebuilds only the elements greater than it in front of the chain it shares:
a root created later has the larger entity, so a holder growing by
`retains` takes each new view in one step, and a literal built in field
order adds each part past the parts already held in one step. A union
merges the two chains down to the first tail they share and rebuilds what
came before it, so two sets differing in a few elements cost those few. A
projection — what a range of a carrier holds, placed in a pointer, a result
or a destination range — walks the set once, and is the set itself when
nothing moves: a result carried whole out of a holder whose dependencies
are all whole, a blit of a whole root. Each node caches whether every
dependency below it is held whole, which is what lets a projection of an
all-whole set return it unchanged.

Marks are a set of their own, apart from the live dependencies: the same
records, so marking is adding a record and nothing else — a dependency
marked twice is marked once, the marks on two paths join by union, and the
transfer is monotone, which is what lets the dense dual and the trail agree.
The set is a treap ordered as dependencies are, greatest first, whose
priorities are a hash of the dependency, so its shape depends on its content
alone, and every `(dependency, left, right)` is interned: equal marks are one
handle however the owners ended. A mark costs the depth of the tree in nodes
whatever order the owners end in, and a union costs that depth for each
element the two sets do not share. A carrier holding a mark in the bytes
read is refused, the first by the dependency order; a carrier holding nothing stale is one empty handle. Every
mark leaves on any write to the root. The instruction a refusal names comes
from the owner's own chain of events — each change to its storage, latest
first, one step to add — as the latest event over the bytes the stale
dependency observes.

An index answers which carriers an invalidation must mark: under each root,
entries naming one dependency on it and either the carrier holding it or a
set holding it, whose holders are the carriers. A carrier whose set grew by
parts — a literal built in field order, a holder taking one more retained
view — enters each new part under its root, one step each; a carrier taking
a set it did not grow enters the set once, and however many carriers share
that set they are its holders, one step each. Invalidating bytes of a root
walks that root's entries, marking in each carrier or holder the dependency
the entry names, so a carrier observing another root is never visited; a
carrier whose every dependency is marked leaves the index, because nothing
is left to mark, and returns when a write gives it fresh dependencies.

**Bound.** Per function, with `I` instructions, `R` roots and `U` set
unions: time `O(I + Σ_joins (|segments replayed| + Σ_preds |touched|) +
Σ_unions |divergent prefix| + Σ_projections |set| + Σ_entries +
Σ_invalidations (|entries met| + |holders marked|) +
Σ_uses of a partly stale carrier |marks|)` per pass, and at most a constant
number of passes per loop nesting level; memory `O((I + R + U + entries + marks) log
marks + trail)`: one node and one interning entry per element an
insertion, a union or a projection rebuilds, one index entry per part a
carrier grew by or per dependency of a set some carrier took whole, `marks`
treap nodes, one per mark added and `log marks` for each, and one trail record
per carrier changed in each block, because a block that changes a carrier
again rewrites the record it logged, which keeps the old values a rollback
restores and the last ones a join reads. `n` carriers holding one set of `n`
dependencies, each marked as the owners end, make `n²` (carrier, dependency)
marks, which is time — the `holders marked` term — and `n` records and `n`
tree nodes; memory holds one mark per distinct set of marks, not one per
pair, and the distinct sets can number `n²` in the two shapes declared below. A carrier's marks are recorded as which dependency is stale rather than
that the carrier is, which costs nodes and refuses nothing. A mark never
re-enters the index, so the entries a carrier holds are the same whatever
order its owners end in. The entry terms are the ones the shapes below hold: a struct of `n` views whose owners are then lent in
turn is `n` entries and `n` marks of one step each; `n` views retained in
one holder are `n` entries, and the `n` carriers taking the holder's set
share its entries; `n` views of one place lent `n` times are one set with
`n` holders, each marked once and gone. A carrier whose set is replaced
rather than grown — a field reassigned in a struct of many views — re-enters
its whole set, which is that set's size per replacement. A join costs the segments on
its predecessors' chains up the dominator tree, each replayed once however
many predecessors share it, plus one entry per value a segment gives an
entity, credited with the predecessors below that segment and debited by a
deeper one that overrides it; and whether a block dominates another is a
comparison of the numbers one walk of the dominator tree gave them. The
dominators come from semidominators over a depth-first numbering, each
predecessor's contribution found with path compression and then one walk up
the tree per vertex, so a block that many deeper blocks enter — the exit of
a loop with `n` conditional exits, the header of a loop with `n` `continue`
arms — costs one walk and not one per predecessor; the walk per vertex is
bounded by the tree's depth, and over the function by the sum of the
distances from each vertex's parent to its dominator.
`n` borrowed views retained into one
holder build sets of size `1, 2, …, n` in `n` steps, because each view is
of a newer root than the set holds; the `n` carries of the holder share one
handle; and the `n` lends of the holder visit nothing, because no carrier
observes the holder. Nothing is sized by the module: every table is keyed by
this function's instructions, slots or roots
([0100](0100-a-per-element-table-is-keyed-and-sized-by-its-domain.md)), and a
join reads deltas rather than states. The release sweep holds three
dimensions to the clock: one function taking `n` views of one place, reading each and lending the place for writing, whose
sets are singletons, and one struct of `n` views whose owners are lent in
turn, in the order the struct holds them and against it. The growing shape — `n` views
retained in one holder and carried out `n` times — is held by a unit
property on the phase's own allocation between `n = 200` and `n = 1600`,
beside the three, and not by the sweep: the front end is quadratic on it in
ownership's fact store, before this pass runs, so a timed dimension reads
that and not this phase. `n` copies of the struct whose owners then end make `n²` marks, so they are
quadratic in time by the `holders marked` term and no dimension can hold
them; a unit property holds the phase's allocation and its state records
linear on them between `n = 100` and `n = 800`, and the owners lent against
the struct's order are held by the same kind of property and by one on the
index's entries.

Two shapes are quadratic in memory, and the bound above does not hide it: its
`entries` and `marks` terms are themselves `n²` on them, because what the
carriers logically hold is. They are declared limits of this design, not
properties it holds.

- A holder retaining one more view at each of `n` stages with a carry taken
  at each stage — `keep(&holder, view(box_i))` then `first(holder)` — gives
  `n` carriers holding `n` different sets, each a prefix of the next. A
  carrier taking a set whole enters every dependency of it under the set, so
  the index holds `1 + 2 + … + n` entries, and when the owners then end,
  carrier `i` holds a different subset of marks after each, so the marks make
  `n²` distinct sets. The verifier adds about 72, 244 and 928 MB at `n` = 500,
  1000 and 2000 when the owners end in the order the views were taken, and 97,
  329 and 1529 MB in the opposite order, on a front end that is itself
  125, 232 and 603 MB there.
- A literal that copies a wide struct into two of its fields — `Outer { w =
  copy(w0), g = copy(w0) }`, `n / 4` of them over a struct of `n` views.
  Each literal takes the set whole for `w` and then grows it by `g`'s `n`
  parts, which is a grown set and enters those parts under the carrier's own
  name, so the `n / 4` literals enter `n²/4` entries although the final set
  is one interned handle all of them share. The verifier adds 40, 135 and 534
  MB at `n` = 500, 1000 and 2000, and `entries` reads 10.6K, 41K and 162K at
  `n` = 200, 400 and 800.

Neither has a small repair inside this design. The first needs a set to be
indexed as the extension of one already registered, so that an invalidation
reaches the holders of every extension, and the marks of a carrier derived
from the owners ended and the set held instead of recorded per carrier. The
second would register the grown set once when a second carrier arrives at the
same handle, which makes two parallel builders of one literal field by field
quadratic where they are linear now. The measured memory is what the unit
properties above do not bound for them.

### What MIR must carry

One thing, and it is not a new representation under
[0015](0015-when-to-introduce-a-representation.md): a fact lowering already
has at the instruction it emits.

**A `move_value` instruction beside `copy_value`.** Same binary payload, the
same blit in the backend, and the same treatment in every existing verifier
check. What differs is what the source is afterwards: `move_value` leaves it
moved out, `copy_value` leaves it held. Lowering emits `copy_value` at
exactly the three sites that duplicate — the explicit `copy(e)` in `copyExpr`,
a Copyable interpolation piece that names a place (a name, a path or a
constant), which the literal holds as a copy of that place, and the arm of a
join that yields a place ownership did not take, because the join sits in a
reading position, as `sum(if c { lit } else { kept })` does for a read
parameter — and `move_value` everywhere else: `storeLocal`, `storeExprIn`, `writeThrough`,
pattern binders, payload extraction, array element stores, and a piece
computed on the spot, which is built into the literal. The corpus found the
second site: three text cases read a place again after interpolating it, and
the phase refused them until the piece was a copy. The fuzz job found the
third: a join arm that names a place, read by a call argument or a field
selection, was blitted as a move and the place read again afterwards. Whether
the arm is taken is the question ownership already answered when it walked
the position, so its disposal plan carries the places the program takes and
lowering asks it rather than working the position out a second time.
A `move_value` whose source is read-only static data moves nothing, because
nothing owns a constant; one whose source is a checked heap element
(`slot_take`) moves nothing this pass tracks. Both are fine as they are, and
no rule is owed to either. A fact on the instruction rather than a side
table, because the producer is lowering itself and the instruction's own tag
is where its meaning lives, as `result_role` is.

The tag reaches every exhaustive switch over `Inst.Tag` — `mir.zig`,
`edges.zig`, `dump.zig`, `lower.zig`, `verify.zig`, the conformance coverage
table — and the backend's return peephole, which recognises a final call
copied into the owned result slot before `ret` and must recognise the move
the same way, or every aggregate return regains a temporary and the emitted
MLIR of most programs changes. The dump prints the tag, so the `.mir` goldens
holding an aggregate move regenerate; that commit changes nothing else, and
the `emit-mlir` differential over the corpus is empty.

Nothing is added for capabilities: the sealed pool updates its capability
facts as the first statement of `finish`, and the module's table already
covers every lowered type. Nothing is added for integer addresses:
`storage_addr` keeps its certificate of bounds and alignment
([0121](0121-typed-storage-is-private-and-checked.md)) and gains no owner.
The verifier holds the *carriers* — the `Slice`, the `Storage`, the iterator
— to their owners, and the integer inside a carrier is the snapshot the
language says it is.

### Where it runs

On every emission, for every non-external function, inside `verify`. Not a
build mode and not a flag, for the reason
[0049](0049-generated-code-is-verified-before-it-is-emitted.md) gives: a
check that runs only in the corpus establishes that the compiler was right
about the corpus on the day it ran, and a precondition establishes that it is
right about the file in front of it. `check` and the editor never emit, so a
user meets this refusal at `build` or `run`, as they meet every other
verifier refusal. The cost is one more phase whose bound is stated above,
linear in the function on every shape the sweep holds, in a pass that is
already linear, and the corpus, every metamorphic rewrite and every
generated program run through it for free.

A refusal is an uncoded `compiler defect:` error naming the function, the
using instruction and the instruction that moved, lent or wrote the storage,
under exit 70, with the note that the program is well formed. It is never a
rule name: no program can provoke it.

### What it costs to test

The verifier's own tests build modules by hand through a `Harness` that
synthesises each function's signature from its slots, with no contracts. This
pass reads contracts, so the Harness grows one thing: a per-function shape a
test may supply, naming each parameter's convention and the signature's
contracts, defaulting to what the Harness guessed before. Every existing site
is unchanged.

## Consequences

**Ownership gains a second reading, and the second reading decides nothing.**
Under [0050](0050-the-layout-rule-has-a-second-implementation.md)'s three
conditions and this record's fourth: (1) nothing under `src/` reads the
verifier's answer — a disagreement stops emission and a person adjudicates;
(2) it is an independent derivation on control flow and positions — over MIR
values and signatures rather than syntax places and the `Cfg`, sharing no code
with `src/ownership/` — and a shared reading of contract clauses, said so
above; (3) where the two readings deliberately differ, the differences are
enumerated here, not discovered as failures and patched in one at a time; (4)
every difference widens what the verifier accepts.

**The differences, enumerated.** Each is a miss.

- *Roots are held whole.* A field moved out and read again is not reported,
  and a `sink` or `move_value` of a part of a root moves nothing.
- *A lent root is never moved.* A value moved out of an `inout` parameter
  and read before it is refilled is not reported; the refill is what
  settlement would check.
- *Any write clears staleness.* A field assigned into a value that holds a
  stale view elsewhere makes the value fresh; MIR cannot tell that from the
  part-by-part initialisation a `let` of a literal is, and ownership
  accepts the latter on every pass of a loop.
- *A read that cannot hold a dependency is not a use.* The containment
  fact of the type table decides; a scalar read through a stale pointer, or
  a scalar payload of a stale enum, is not reported.
- *What a loaded pointer holds is held at its own width.* A pointer stored
  in a root and loaded back holds its dependencies at the first bytes of
  its referent, so a read through it past those bytes is not a use; a read
  of the whole value, a pass and a return still are.
- *An observation made through a computed step belongs to the first
  element.* `borrow cells[i].right` observes element zero's `right` here;
  a write to another element's `right` does not end it. So does a value
  stored through a computed step. Ownership, element-insensitive, refuses
  either.
- *A fourth computed step is taken at element zero.* The address records
  three; `cs[i][j][k][l].left` reads the `left` of every element of the
  fourth level's first array only, so a stale `left` in another one is not
  a use. Ownership, element-insensitive, refuses it.
- *A carrier every dependency of which is marked is not marked again.* It
  leaves the index, so a dependency it later gains without a write — none
  today — would go unmarked; a write clears its marks and re-enters it.
- *Every projection is inlined, and an inlined body is library code in the
  caller.* `Vec`'s `at(inout self)` lowers at the use site to two loads of
  the vector's words, a bounds check, `storage_addr` and a store: `values[i]
  = x` lends nothing and invalidates nothing, and `s[i]` or `*e` of a scalar
  through a stale view reads two words and a scalar, which carry nothing.
  So in user code the pass catches a stale carrier reaching a call, a
  `borrow` or `address_bits`, a blit or a `ret` — which every `for` has, on
  its back edge — and not a hand-written loop whose body only indexes.
  Ownership catches both: the element write in a walk through `.walked`,
  the element read through `.used`.
- *A call through an erased closure lends and carries nothing.* The callee
  of such a `call_indirect` is the closure's entry, a callable whose
  signature takes the environment as integer words under `read` and carries
  no clause, so the pass reads a signature that moves, lends and carries
  nothing. Direct closure calls carry the environment parameter in their
  signature and are modelled. Ownership refuses every use after a lend
  through an erased call, since it reads the closure's own contracts.
- *Contract paths are not followed.* A clause whose source or destination
  names a field path contributes nothing. A clause whose result target names
  a variant payload attaches the dependency to the whole enum result, which
  is what ownership's use rule reads too — a `match` on the result is a use
  of the value; a target naming a struct field contributes nothing, because a
  read of a sibling field is not a use ownership refuses.
- *Closure roots are not modelled.* A clause rooted at a capture
  (`ContractRoot.capture`) or at the callee's environment
  (`ContractRoot.callee`), which a call through an environment produces,
  contributes nothing. The environment's own fields are carriers and their
  `borrow`s are visible, but a closure's `inout` capture lowers as the same
  `borrow` a read capture does
  ([0193](0193-a-closure-may-hold-a-place-lent-inout.md)), so the exclusive
  lend ownership makes at closure creation is not seen here.
- *A borrow of a slice element is not observed.* `let s = values.as_slice();
  let e = borrow s[0]` followed by `Vec.push(&values, x)` and a read of `*e`
  is accepted by the verifier with ownership bypassed, and is a use after free
  under the checking runtime ("storage was used after it was freed"). It
  falls under the next entry: the element is reached through the integer
  address words the `Slice` holds, which carry nothing, and the slice-walk
  refusal comes from a carrier reaching a call or a back edge, which `e` does
  not. Ownership refuses it with `O-Borrow`, so the program never reaches the
  verifier. Closing it means giving an integer address word a provenance the
  model can follow, which is a design this record does not make.
- *Integer addresses carry nothing.* `address_bits` of an array creates a
  dependency and the `Slice` built from it holds one, but an integer read
  back out of a view carries nothing: a library body that reads
  `storage.at`, grows the storage, and uses the old integer is invisible here
  as it is to ownership; and the callee side of a contract is not checked,
  because for integer-addressed storage there is nothing in the body to check
  it against, and for carried dependencies it would need a symbolic "what
  parameter `p` carried" element this record does not define.
- *Scalar-represented values are snapshots.* A linear newtype over a scalar
  is moved by `load`, which is also how it is read.
- *Zero-width values move with no instruction.* `writeThrough` emits nothing
  for a part of no bytes, so a linear zero-width value leaves and arrives
  unseen.
- *A leak is not checked.* Settlement on every path needs to know which
  variant a linear enum holds on each edge of a `branch` — the corpus's own
  `Vec.filled(…) else |_| { return 1 }` returns while the `Err` payload, a
  scalar, is loaded and not moved — and that is a design this record does not
  make. It is a separate record when it exists.

**A refusal is one of three things, and the triage is fixed.** A defect in
ownership: write the corpus case ownership should refuse, watch it go red
under the verifier and green under ownership, fix ownership, and keep the
case. A defect in lowering — a `copy_value` where the source is consumed, a
missing scheduled release — fix lowering, case first. A defect in the
verifier: a refusal of a program ownership accepts is a rule of this pass
refusing on the wrong side; fix the rule with a hand-built MIR test that fails
first, and if the fix is a new difference, add it above. What is never done: a
suppression list, a flag, or a read of ownership's tables to decide.

**Every new way to observe storage lands here too.** A language change that
adds a way for a value to depend on storage must be classified in this record
before it ships — modelled, or enumerated as a miss — or the verifier is
wrong about it. Under the invariant, wrong means a miss, never a refusal; the
cost is coverage, not a broken build.

**Lowering's move/copy decision becomes a fact the dump shows and the
verifier holds.** Every `copy_value` in MIR now means the source stays held,
and the `.mir` goldens say so. A site that duplicates an aggregate has to say
`copy_value` deliberately, and P1 refuses it if it does not — which is how
the interpolation site was found.

**Cost.** One more phase over each function, with the bound above,
allocated from the allocator `verify` is handed and freed on the way out;
three sweep dimensions read its slope through the whole compile — `n` views
of one place taken, read and lent in turn, and `n` views held in one struct
whose owners are then lent in turn, in the order the struct holds them and
against it — and a unit property holds the phase's own allocation and state
records on those shapes and on the retained one between `n = 200` and
`n = 1600`, and on `n` copies of the struct between `n = 100` and `n = 800`.

**What this does not close**, said so the record claims no more than the
mechanism delivers: the enumerated misses above; a wrong contract clause,
which both readers share; anything after the verifier — LLVM, the linker, the
runtime allocator; and the layout table both readings sit on, which is
[0050](0050-the-layout-rule-has-a-second-implementation.md)'s.

## Alternatives considered

**Read ownership's side tables and check that lowering honoured them.** A
verifier that reads the disposal plan and the dependency facts, and confirms
each scheduled release was emitted where the plan says and each observation
ends where the facts say. Cheaper to write, and it verifies nothing this
record is for: the `for`-over-a-slice defect was a fact ownership recorded
wrongly, and a check that reads the record confirms the record. It is
[0050](0050-the-layout-rule-has-a-second-implementation.md)'s transcription
failure, exactly.

**A second traversal inside ownership, over its own `Cfg`.** The `Cfg`
abstracts the walk into a `.element` projection op, so a second reader of
that op needs the same knowledge the first reader lacked — that the
projection calls `next` on every pass. MIR has the call. The independence is
in the representation, not in who writes the second reader.

**Restate all three ownership properties, settlement included.** The first
draft of this record did, and lowering a dozen programs against it found that
settlement over MIR refuses the corpus's most common idiom (the `else |_| {
return 1 }` above) and that a callee-side contract check needs a domain
element MIR does not have. The record now states only what the mechanism
delivers; the rest returns as its own record when it has a design.

**Check at run time.** A sanitizer, a quarantine in the runtime allocator, or
a poison word written at release.
[0049](0049-generated-code-is-verified-before-it-is-emitted.md) measured the
sanitizers as vacuous over code `cc` did not generate. A checking allocator
linked into `linea test` and the conformance run catches a use of freed heap
storage when it executes, and only then: it cannot see a slot read after a
move, a lent root written under a live borrow, or a path the input did not
take. A generated soundness matrix enumerates a finite set of shapes. The
verifier is the only net that runs on the program in front of the user, on
every path, over storage that is not heap. The three complement each other;
this one is worth its price only under the invariant above.

**Annotate `storage_addr` with its owner.** Carry the `owner` argument of
`slot_place` and `slot_span` through to the access, so an element read is a
use of the owner. It would sharpen P2 inside library bodies. Rejected for
now: the integer is what the language makes a snapshot, the certificate on
the access already holds it in bounds of the length it was handed, and every
defect this record is written against is caught at the carrier. Revisit if a
corpus refusal names an intrinsic body.

**A debug-only or corpus-only gate.** Rejected on
[0049](0049-generated-code-is-verified-before-it-is-emitted.md)'s argument;
the pass is linear and the shipped compiler is the one that must be right.

**A per-block state matrix.** The obvious dataflow representation, and the
one [0066](0066-a-blocks-state-is-its-dominators-plus-what-it-changed.md)
measured at exponent 1.96 on one function of sixteen thousand locals. The
trail is the answer that measurement already produced, and the dense matrix
survives only as the Debug dual that checks the trail.
