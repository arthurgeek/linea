# 31. Fields are packed at their natural alignment, in declaration order

Status: Accepted — 2026-07-26; the slot clause clarified by
[0052](0052-a-slot-is-as-wide-as-the-widest-access-to-it.md) and its scalar-word
consequence superseded by
[0102](0102-computation-and-storage-representations-are-separate.md).

Extends [0028](0028-a-type-is-a-pool-handle-and-layout-is-a-table.md), which
put layout in a table the module carries and gave an enum a fixed arrangement.
That record's tag decision stands; this replaces the arrangement with an
algorithm.

## Context

0028 described an enum's layout with three constants: a word for the tag, a
word for the payload, sixteen bytes in all. A variant carrying two values has
no description in those terms, and neither does a structure, so the constants
had to become a rule before either could exist.

The rule itself was not the interesting decision. How wide a part is, was.

## Decision

**A part occupies its own width, at the next offset its alignment allows.** A
type's alignment is the greatest of its parts', its size rounds up to that, and
parts stay in the order they were declared.

**A part is not a slot.** A local is at least a word whatever it holds, because
it is where a value is spilled rather than a field packed beside others, and a
scalar is written there at full width. Without that distinction a `u8` local
became a one-byte allocation written by an eight-byte store.

**Offsets never reach the backend.** The module's table carries size and
alignment — what is needed to allocate and to copy. An offset is baked into a
`field_addr` by lowering, which can see the type pool. So the backend adds a
number it was handed and never computes one, which is the property 0028 exists
to protect.

**The tag still occupies a full word.** C has no tagged unions, so nothing
about compatibility ever concerned enums, and a payload beginning already
aligned is worth the seven bytes.

## Consequences

**`isAggregate` stopped meaning "wider than a word".** A two-byte structure
fits a register and still lives in memory, because a part is reached through an
address and a register has not got one. It is now a property of having parts.
A fieldless enum answers no and stays a tag in a register, which is what kept
every program using one lowering exactly as it did.

**Alignment is asserted rather than chosen.** `alloc8` names an alignment, and
a word is the widest any type demands — the widest builtin is eight bytes and a
composite inherits its parts'. A narrower `alloc4` would save nothing a slot
must give back, so there is an assertion where the decision is instead of a
branch no test can reach. The day a type wants sixteen, it fails there.

**Reading and writing a field are the same walk.** A path is lowered the way it
is read, and only the last step differs, so `o.inner.y` on the left of an
assignment and on the right compute one address by one piece of code.

**Layout is checked by programs, not by a table.** A structure of mixed widths
is written field by field and read back; an offset overlapping its neighbour
shows as a value that changed when something else was written. And reordering a
structure's fields cannot change an answer, which is a rewrite in the corpus —
it caught a deliberate injection on four generated programs that nobody wrote.

## Alternatives considered

**A word per part.** Every value in the backend is computed in QBE's `l` and
every load was `loadl`, so an eight-byte field would have asked nothing new of
it — no widths, no alignment, no padding. Rejected on what it would cost later
rather than what it costs now. Nothing observes layout today: there is no FFI,
no `extern`, and the only C boundary takes scalars, so the argument was never C
compatibility. It is that changing the width of a load is cheap before
structures, arrays and ownership are built on it and expensive afterwards, and
that it would churn every recorded `.ssa` a second time.

Two things already in place made the cheap version cheap. The backend reads a
type's width and signedness from the handle alone, in five places, so choosing
`loadub` asked nothing new. And a value reaching a narrow part has already
passed a range check against that type's bounds, so a store that truncates
cannot lose what the checker did not permit.

**Sorting parts by width.** Would pack `{ u8, u64, u8 }` into sixteen bytes
rather than twenty-four. Rejected for now: layout that depends on an ordering
the compiler chooses is layout a programmer cannot predict, and the reason
bites before any FFI does — a deterministic arrangement is what makes a value
inspectable in a debugger, a memory dump readable, and a layout bug
reproducible rather than dependent on the order someone happened to declare
things in. It is a decision the layout table can carry later without any other
pass noticing.

**Per-variant arrangements chosen independently.** Each variant could place its
values wherever suited it. Rejected because every variant already shares one
tag and one allocation, and letting them disagree about where values begin buys
nothing a shared rule does not already give.
