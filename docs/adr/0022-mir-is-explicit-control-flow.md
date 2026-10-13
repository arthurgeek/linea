# 22. MIR is the first representation whose control flow is explicit

Status: Accepted — 2026-07-26

## Context

[ADR 0015](0015-when-to-introduce-a-representation.md) requires a new
representation to name what it discards, adds, or simplifies, or the need is
met with a side table keyed by an existing representation's IDs. MIR was built
in Stage 2b without that record.

It could not have been written correctly then. The Stage 1 design reserved the
sentence "MIR is the first representation whose control flow is explicit" for
this record, and until Stage 3a it was false: `jump` and `branch` were tags the
representation could express and lowering never produced, and the edge table
said so. A function had one block. The sentence became true when conditionals
and loops arrived.

## Decision

MIR is a machine-independent control-flow graph: a function is a list of basic
blocks, each an instruction range and exactly one terminator.

**What it discards.** The nesting that implied evaluation order, which becomes
a sequence. The names the resolver bound, which become slots. The parentheses
the tree kept for a formatter, which have no run-time meaning.

**What it adds.** Blocks that correspond to no syntax — the join of a
conditional, a loop header, the block control falls into after a `break`. This
is what rules out a side table: a table keyed by syntax IDs can annotate the
nodes that exist, and a control-flow graph needs nodes that do not.

**What it simplifies.** The backend becomes a walk over blocks and
instructions, with no recursion and no notion of scope. Every operation that
can fail is already followed by an explicit `check`, so emission never decides
where a trap belongs.

### Consequences that are part of the decision

**A terminator is stored apart from the instruction range**, so a block has
exactly one and "is this block terminated?" is a lookup rather than an
inspection of the last instruction. Lowering relies on it: a body that ended in
a `break` has already jumped, and the code that would close the loop asks
before overwriting.

**Instruction results are single-assignment; named storage is not.** Every
instruction defines its result exactly once and is referred to by handle. A
binding is a slot, written with `store` and read with `load`, and a value
produced on two paths is stored to a slot by each and loaded after the join.
Such a slot is a lowering device, not storage the program can observe: nothing
in the language can take its address.

This is the shape of rustc's MIR and of LLVM before `mem2reg`, and the
distinction matters — the open question is not whether MIR is in SSA form but
whether *named storage* is, with phis where paths meet. It is not; see the
alternatives.

**Every edge answers for a fixed set of disciplines**, recorded in a table that
is an exhaustive switch over terminator tags, so adding a terminator without
answering for each fails the build. The table is checked in both directions:
an edge naming a witness must be produced by it, and an edge calling itself
reserved must be produced by nothing.

**Trap kinds are numbered, and the numbering is an interface.** A generated
program names a failure to its runtime by integer, so a kind is added at the
end and never renumbered.

MIR is immutable once produced, by
[ADR 0012](0012-immutable-representations.md), and lowering is a function from
representations to representations, by [ADR 0016](0016-passes-are-functions.md).

## Alternatives considered

**Emit QBE directly from the typed tree.** This is what Stage 2b could have
done, and for straight-line arithmetic it would have been shorter. Rejected
because the backend would then own control-flow lowering, and a second backend
would own it again — and because there would be nowhere for an optimisation
pass to run.

**A side table over the typed tree.** Rejected by the rule above: a graph needs
blocks that no syntax node corresponds to.

**Put named storage in SSA form, with phis where paths meet.** Rejected, for
one reason that is decisive and two that are merely true.

The decisive one is that it would settle a question this project has
deliberately left open. Where ownership is represented is deferred, and the
two references split precisely here: Rust borrow-checks on a MIR whose locals
are *not* in SSA form, because its ownership model is about **places** —
storage locations, assigned repeatedly, with lifetimes; Swift's Ownership SSA
is in SSA form because its model is about **values** and their forwarding.
Adopting SSA now would not answer "does ownership conflict with what
optimisation needs from MIR?", which is the question on record. It would
quietly answer a different one — "is ownership about values or places?" — by
making the places model the expensive option. A decision that large should be
made in a record, not fall out of a representation chosen for other reasons.

The two lesser reasons: QBE runs `mem2reg` and promotes these slots itself, so
constructing SSA here hands the backend something it builds anyway; and by
[ADR 0015](0015-when-to-introduce-a-representation.md) there is no consumer,
because no optimisation pass exists.

The usual argument against SSA does *not* apply here, and saying so is part of
the decision. Phis are normally rejected because every pass that edits a
control-flow graph must maintain them. Under
[ADR 0012](0012-immutable-representations.md) no pass edits MIR in place — a
transformation produces a new representation — so SSA could be constructed
fresh rather than repaired, and the maintenance cost that sinks it elsewhere is
largely absent. What remains is that it is not needed yet and would prejudge
ownership.

If an optimisation arrives that needs def-use chains over named storage, or
ownership settles on a value model, this is a decision to revisit with a record
that supersedes this one.

**Make MIR the ownership representation as well.** Deliberately left open: the
Stage 1 design records the question that settles it as *does ownership conflict
with what optimisation passes need from MIR?*, and nothing yet answers it.
