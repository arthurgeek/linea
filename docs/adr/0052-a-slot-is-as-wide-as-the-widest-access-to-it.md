# 52. A slot is as wide as the widest access to it

Status: Accepted — 2026-07-29; scalar-word consequence superseded by [0102](0102-computation-and-storage-representations-are-separate.md), widest-access rule remains accepted

Clarifies [0031](0031-fields-are-packed-at-their-natural-alignment.md), whose
clause "a local is at least a word whatever it holds" reads as covering
aggregates and was written to answer a question about scalars. Required by
[0049](0049-generated-code-is-verified-before-it-is-emitted.md), which cannot
check a bound it has two definitions of.

## Context

0031 separates a part from a slot: "A local is at least a word whatever it
holds, because it is where a value is spilled rather than a field packed beside
others, and a scalar is written there at full width."

Read as written, *whatever it holds* covers an aggregate, and the backend does
not do that. `slotFor` gives a two-byte structure `alloc4 2`. Beside it sits
`slotSize`, which is `@max(size, word)` — what the sentence says, with no
callers. One rule, two implementations, disagreeing: for a two-byte structure
one answers 2 and the other 8. The dead one reads as the authority, because the
comment restating 0031's sentence sits above it.

Deleting a function with no callers would normally be a cleanup. It is not one
here, because it is not obvious which of the two is the bug, and the answer
decides more than the deletion. Slot sizing is about to move out of the backend
and beside the verifier that 0049 makes a precondition of emission, and that
verifier's entire content is `offset + width <= extent(slot)`. Moving the wrong
rule either accepts eight bytes written into a two-byte object or demands a
slot the emitter does not allocate. It has to be settled before the move, and
"it depends" would leave the next implementer where it found them.

## Decision

**0031's word floor describes a scalar local, not an aggregate one — and the
reason is inside 0031's own sentence rather than an exception to it. A slot is
at least as wide as the widest single access the backend makes to it.**

Two cases fall out, and they are the two the backend already emits:

- **A scalar local, or a local holding an address, is a word.** Every value is
  computed in QBE's `l`, and a named slot is written with `storel` and read
  with `loadl` unconditionally. One access covers the whole slot at eight
  bytes, so eight bytes is what it must have. That is 0031's clause and its
  reason, unchanged: without it a `u8` local is a one-byte allocation written
  by an eight-byte store.

- **An aggregate local is its type's own size, at its type's alignment.** No
  access covers it whole. Lowering never emits a store or a load against an
  aggregate local: it takes the local's address and reaches the bytes through
  field addresses at offsets from the layout table, and copies whole values
  with a blit sized from that same table. The widest access is a part or a
  blit, and both are accounted for by the type's size. The reason for the floor
  does not reach here, so neither does the floor.

`slotFor` is therefore correct and `slotSize` is the defect. It is deleted.

**0031 is not superseded and its text is not rewritten.** Nothing was ever
built against the aggregate reading — `slotSize` has never had a caller — so no
code depended on the broader claim, and the append-only test is whether a
specific clause shaped code. What 0031 got wrong is stating its conclusion more
widely than its own reason supports; the clause was written to answer the
scalar question and answers it correctly.

## Consequences

**The rule is now a property of accesses, which is what makes it checkable.**
"At least a word" is a number a verifier can only compare against. "At least as
wide as the widest access" is the same sentence as the bounds check, so slot
sizing and the verifier's notion of a slot's extent are one answer rather than
two that someone must keep equal.

**Slot sizing gets one home, and it is not the backend.** It moves to `src/mir/`
beside the verifier and the emitter calls it, which is what stops 0049's
verifier from becoming a second copy of the emitter's arithmetic. It also
respects the rule 0028 and 0031 share: the backend adds a number it was handed
and never computes one.

**A premise that was implicit becomes a check.** The emitter's unconditional
`storel` against a named slot is sound only because lowering never targets an
aggregate local with one. That was true by inspection and by nothing else. It
is now stateable — every access to a named slot lies within what the slot rule
allocated — and 0049 reports a violation rather than leaving it to a reader.

**A narrower directive is what buys anything, not a narrower size.**
`alloc8 2` occupies the eight bytes `alloc8 8` does, because QBE lays slots out
by the alignment it is given. The value in an aggregate slot's own size is
honesty about its extent, and the value in `alloc4` is that two such slots can
share a word. Nothing here saves stack for scalars, and nothing was meant to.

## Alternatives considered

**Apply the floor to aggregates: `slotSize` survives and `slotFor` is the
bug.** The reading 0031's text supports, and it costs almost nothing in stack —
a two-byte structure rounded to eight. Rejected on the reason rather than the
cost. The floor exists because one access covers a scalar slot whole; nothing
covers an aggregate slot whole, so applying it would leave a number with no
reason attached, and a number with no reason is what drifts.

The decisive argument is that over-allocating hides the bug class 0049 exists
to find. A slot deliberately larger than the object it holds is a slot in which
a wrong width or a wrong offset lands *inside* the allocation and is never
seen. A verifier over generously sized slots proves strictly less, and the
defects that motivated it — a zero-width part stored eight bytes wide, a copy
sized from the wrong end of an assignment — are exactly the ones a spare seven
bytes would have absorbed.

**Round every slot to its alignment and no further.** Equivalent for the
aggregate case and silently wrong for the scalar one, since a `u8` has
alignment one. It is the aggregate rule generalised to a place its reason does
not reach, which is the mistake this record is correcting in the other
direction.

**Keep both functions and let the verifier use `slotSize` as an upper bound.**
Two answers to one question with a documented direction between them. That is
drift with a comment, and the comment is what makes it survive review.

**Rewrite 0031's clause in place.** The clause is a design sketch in the sense
the conventions allow correcting — nothing was built against the aggregate
half. Rejected anyway: the scalar half *was* built against, the two halves are
one sentence, and editing a sentence that half the compiler depends on to say
something narrower is harder to review than a record that names it. A status
line pointing here costs less and loses nothing.
