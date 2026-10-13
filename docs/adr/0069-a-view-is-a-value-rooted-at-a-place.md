# 69. A view is a value rooted at a place

Status: Superseded by [0123](0123-observations-carry-owner-dependencies-through-callable-contracts.md) — 2026-09-08. The original proposal follows.

## Context

Three features appeared to arrive from three directions and stop at the same
place. **A buffered writer** must hand its sink the bytes it has staged.
**`slice`** must return a `Str` over part of another `Str`. **`from_bytes`**
must build a `Str` over storage a program computed — the omission that is the
whole reason
the text milestone shipped printing over literals alone.

**Two of the three do not survive inspection, and this record says so before it
argues anything.** `slice` needs to read a byte, and a byte read is a
bounds-checked `extern` like the one
[0068](0068-a-declaration-may-name-a-symbol-the-runtime-provides.md) landed —
over a `Str` whose storage is static, which is every `Str` today, the returned
view needs no new rule at all. Buffering ultimately wants to expose the filled
prefix of its storage, but its immediate blocker is fixed-size arrays and const
generics, and the view appears only at the flush.

What is left is **one unbuilt feature**: text over storage a program computed.
That is a thin motivation for a semantic addition, and it is why this record is
Proposed rather than Accepted.

Framed as *how does a program obtain an address of storage it owns*, this looks
like a missing primitive, and it is not. An address is easy: `Str` is already an
address and a length, and `std/text/str.lin` computes one arithmetically. The
question is narrower and harder:

> **How can a program safely expose a view of storage it owns?**

The difficulty is the lifetime of what is built from the address. Ownership
tracks the buffer and not the view, so a `Str` outliving the storage it points
into is accepted today. Slicing propagates it — `slice(s, 1, 3)` views whatever
`s` viewed — so whether a `Str` is safe is not a property of an expression but
something that flows through a program.

This is half of the third question
[the index](README.md#open-questions) records as unscheduled.

### An address is not enough, and that is the whole finding

The reason this looked like a primitive is that *address* and *provenance* were
being treated as one thing. They are independent information. An address is a
number; it says where, and nothing about whether the storage there is still
alive or who is responsible for it. Provenance is the second fact, and no amount
of arithmetic on the first produces it.

Once separated, the design space changes shape. An address can stay entirely
untracked — `Str.at` is a `UInt64` today and the checker knows nothing about it,
which is fine — provided the provenance is carried *beside* it by something the
ownership graph already understands. The mistake was looking for a kind of
address that carries its own safety. There is no such thing; there is only an
address plus a witness.

Everything below is one proposal for what the witness is. The separation stands
whether or not the proposal does, and it is the part worth keeping.

## Proposal

**A view is a value that records the place it is rooted at.** The root lives in
the ownership graph, not in the type. A place may not be disposed, moved, or
reassigned while a view rooted at it is live.

### Rooting is an edge in a graph that already exists

[ADR 0034](0034-ownership-is-positions-and-a-graph.md) makes ownership positions
and a graph. A root is one more edge: from a value to the place its storage
belongs to. Nothing about the representation changes — a view is an ordinary
struct of an address and a length, so
[0031](0031-fields-are-packed-at-their-natural-alignment.md) and
[0028](0028-a-type-is-a-pool-handle-and-layout-is-a-table.md) need no clause,
and MIR and the backend see a struct.

A value's root is a **set of places**, empty for static storage. A literal is
rooted at nothing, because static storage outlives every program point, so the
empty set imposes nothing and every `Str` written to date carries it. A struct
holding views is rooted at the union of theirs.

### A view is derived from a projection, and is not one

R3's *projecting member* — one whose body is a place, whose call site is
therefore a place — supplies the place a view is taken over. It does not become
one. A projection yields a place **of type `T`**: one element, at one address. A
view describes **a region of `N` bytes**. The two are not the same shape, and
the text design was right to say so rather than assume it away.

So the relation is one-directional and narrow: **a view is a value constructed
from a place, by a constructor a view type declares, recording that place as its
root.** The projection names storage; the constructor is what turns naming into
a value.

Nothing here makes a projection *become* a value. Field projection, array
indexing and every other place expression stay exactly what they are — places,
usable where places are usable — and none of them acquires a second reading as a
view. A view exists only where a view type's constructor made one, which is why
`Str` gaining this costs no other place expression anything.

```linea
impl Buffered {
    proj staged(read self: Self) -> Str { self.bytes[0..self.len] }
}
```

The result is a `Str` rooted at `self`. Handing it to a sink is a call; the sink
consumes the bytes and does not keep them; the view dies at the end of the
statement and the root is discharged.

### The root propagates through signatures, and is computed rather than written

`slice(read s: Str, from: UInt64, to: UInt64) -> Str` roots its result wherever
`s` is rooted. That is what makes the property flow: a slice of a literal is
static and free, a slice of a buffer's view is rooted at the buffer, and neither
call site says anything.

The rooting of a function's results is **inferred from its body** and recorded
in its summary, in call-graph order, as a fixed point over recursion. It does
not appear in a signature. This is the whole of the asymmetry against a region
discipline, which must appear in one.

### A view is not a reference, and 0025 stands

A view can be read and cannot be written through, and it cannot be re-rooted.
That is strictly less than a reference, and it is what keeps
[ADR 0025](0025-mutation-through-a-parameter-is-marked.md) intact: its argument
is that nothing can observe whether an argument was passed by address or copied
in and back, and a read-only view observes neither. `&` remains a call-site mark
for mutation.

A **mutable** view would break that, and is not decided here.

### The rule

`[O-Rooted]`: a place may not be disposed, moved, or reassigned while a view
rooted at it is live.

The one genuinely new thing is that a borrow now outlives its call. A `read`
position today ends at the call boundary; a rooted value extends it to the
value's liveness, which the graph already computes. The rule reuses the
machinery that refuses a move of a borrowed place — it changes when that borrow
ends, not what it means.

## Consequences

**Nothing written so far changes.** `Str` stays a struct, `slice` stays a
function returning one, `Display`, `Writer` and every impl over `Str` stand
unaltered. That was the test the three candidates were compared on and the
reason this one wins.

**Ownership gains a root per value of a view type and one rule.** No other pass
is touched. Type checking does not see a root; lowering does not; the backend
does not.

**It needs a call-graph traversal.** Rooting is interprocedural, so a callee's
summary must exist before its callers are checked. Linea compiles whole programs
and this is free today. If separate compilation ever arrives, the summary
becomes part of a module's interface and must then be written rather than
inferred — which is the point at which roots would start appearing in
signatures.

**`from_bytes` becomes ordinary**, and heap-backed text with it: a view over a
buffer from [0064](0064-heap-memory-is-a-linear-value-from-an-explicit-allocator.md)
is rooted at the linear handle, so freeing while the view lives is refused by
`[O-Rooted]` rather than by a new analysis.

**Buffering's eventual view is covered**, though not its actual blocker: the
staged prefix would be a view rooted at the writer, discharged inside the flush,
and `[O-Leak]` keeps its role in forcing that flush. Fixed-size arrays and const
generics are what buffering is waiting on, and this record does not supply them.

## What acceptance requires

**This adds a third semantic object.** Linea has values and it has places. A
value that carries a place is neither, and calling it a small refinement of
[0034](0034-ownership-is-positions-and-a-graph.md) understates it. The edge is
cheap; the *category* is not, and every question below is one this record does
not answer:

- When does rooting begin, and when does it end?
- Does moving a rooted value move its root?
- May two views share a root, and may a view be rooted at a view?
- Does matching on a rooted value duplicate the root into each arm?
- What happens to a root at a join where the arms disagree — the question
  [0066](0066-a-blocks-state-is-its-dominators-plus-what-it-changed.md) had to
  answer for state, asked again for roots?
- Does a rooted value carried out through
  `?` keep
  its root past the early return, and if so rooted at what?

None of these is obviously hard. All of them are surface area, and surface area
answered in advance of a caller is surface area answered wrongly.

**The bar for accepting this is one built feature that needs it.** Text over
computed bytes is that feature, and the honest reading of everything above is
that it is the *only* one — `slice` needs an `extern`, buffering needs arrays,
interpolation and derive need neither. A single unbuilt consumer is not enough
evidence to freeze a semantic category, and this record exists so that whoever
builds that consumer starts from a worked proposal rather than an open question,
not so the proposal can be adopted before them.

## Alternatives considered

**Two levels of region**, static and local, propagated by the checker. Nothing
becomes unwritable, and the cost is permanent visibility: buffering exists
precisely so a writer can pass a *local* view, so `Writer.write_str` must accept
one, so the region reaches a trait method and from there every impl of it. A
second analysis beside the ownership graph, in the signatures, forever.

**A view is not a value** — the `&` precedent, passable and never stored. It is
right for parameters and fatal for a library type: `slice` and `from_bytes` both
return a view, so both become unwritable, and `Str` would stop being something a
program can bind, return, or hold in a field. The precedent is real but it was
only ever a claim about parameter position.

**A first-class reference with a lifetime discipline** answers this and much
more, and supersedes 0025 rather than refining it. It is the largest of the
four and the three motivating features need none of its power: each wants to
expose storage for the duration of a statement, not to name a lifetime.

## Deliberately open

**How a view type is declared.** `Str` is the only one, and a marker on the
declaration, a trait, and a prelude identity
([0060](0060-a-library-declaration-is-named-through-the-prelude.md)'s mechanism)
are all plausible. One example is not enough to choose.

**The syntax of a projecting member**, which is R3's question and unchanged by
this: `proj`, a place body with no keyword, or a marked return type. This ADR
fixes what a projection *means* when materialised, not how it is spelled.

**Whether a mutable view is possible**, which is where 0025 becomes observable
and therefore a separate decision.

**Whether a root is per-value or per-binding.** A set of places is the
conservative answer and it is what this specifies; whether flow-sensitivity buys
anything is unknown until something needs it.
