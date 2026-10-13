# 100. A per-element table is keyed and sized by the domain it holds

Status: Accepted — 2026-08-21

Extends [0009](0009-stable-ids-across-passes.md), which made every cross-pass
reference a typed `enum(u32)` rather than a bare integer.

## Context

0009 typed the *references*. It did not type what they index.

A pass that records something per element holds it as `[]T` and reaches it by
writing `table[id.index()]`, which is a `u32` subscript whatever the identifier
was. This compiler declares twenty identifier types over `u32` — three of them
named `BlockId`, in `syntax`, `mir` and `ownership/cfg`, and two named
`ScopeId`. Nothing stopped a table of one being indexed by another, and nothing
would have said so: the two are the same width and the same shape, and the
mistake reads exactly like the correct line beside it.

The same erasure ran through signatures. `declOfType` answered `?u32` where it
meant `?DeclId`; `Instance`, `Template`, `Implementation` and `Head` each held a
declaration as a number; `SupplyIndex` held three distinct declaration domains
as three `u32` parameters, any two of which could be swapped silently — and a
swap answered `null`, which every caller read as "this implementation supplies
nothing" rather than as "you asked wrong".

A table has one line to correct. A signature spreads the number to every caller
that reads it, and each of those writes `.index()` to satisfy it and
`SomeId.at(...)` to get the type back.

## Decision

**A table holding one value per element of a domain is keyed by that domain's
identifier, and sized by whatever owns the count.**

`Table(Id, T)` in `src/support/table.zig`. Its key must be an enum with an
`index`; `get` and `set` take the identifier; `set` takes a mutable table, so a
pass that has produced its answer hands out `*const` and writes stop compiling.
`Reading` is what a borrow gets: no `set`, no `deinit`, so a pass cannot write
into another's answer or free memory it was lent. `pairs` walks the table
yielding the identifier beside each value, which is what lets an iterated table
be one at all.

**The count comes from what owns the domain.** `Ast.declTable` and
`Resolution.bindingTable` build a table of the right length, because a table
keyed by `DeclId` and sized by anything else answers for the wrong elements —
and sized *larger* it never trips the bounds check either. It simply says the
fill value for every element, and the pass reading it reports nothing.

**What this is not.** A raw index inside a storage boundary is correct and stays.
`Ast` reaches every one of its columns as `self.decls.items(.tag)[id.index()]`
behind an accessor naming the identifier; the domain is checked at a signature
and the subscript is an implementation detail one line deep. There are hundreds
of such sites and this changes none of them. What it answers is the table whose
domain nothing records at all.

A positional array is not a table: a run of arguments, a component per element,
a slot per binding of one body. The subscript there is a position, not an
identity, and this type is not for it.

## Consequences

**It cannot hide the memory.** Zig has no private field, so the backing slice is
reachable by anyone who writes `.entries`. What the type gives is that the
reaching path takes an identifier, so a wrong domain is a compile error on the
way anyone would actually write, and stepping around it takes a line that says
so and is greppable. That is the same guarantee `Ast` gives, where the columns
are reachable too: a boundary you must deliberately step around, rather than one
you cannot. An earlier draft of this rule claimed the stronger thing, and a
three-line program disproved it.

**The bounds check is guarded but not covered.** A table asked for an element
past its end panics naming both halves, rather than reading somebody else's
memory. No case stands behind it: a panic cannot be asserted from inside a Zig
test, and this project has no harness that runs one in a child process.

**A sentinel inside the domain is a lie the type will spread.**
`Implementation.ambient` was a number one below `DeclId.none`, which was honest
while the field was a number and became a lie when the field became a `DeclId` —
a value the type says names a declaration, standing for there being none, and
admitted anywhere a real one is. It is a `bool` beside the declaration now, which
is what `resolve.zig` already did for the same fact about a binding.

## Alternatives considered

**Leaving iterated tables out.** The first version of this rule said an iterated
table could not migrate, because `items()` would have to hand back the slice.
That was false, and it would have frozen the abstraction at two tables: an
iterator yielding the identifier beside each value withholds the slice *and*
removes the `@intCast` that `for (slice, 0..)` forces on a loop index.

**Enforcing the size in the type.** A `Table` could carry its domain's count as
a comptime witness, so a table sized by the wrong count would not compile. That
needs the count at comptime and it is a property of the program being compiled,
so the witness would have to be a runtime value and the check a runtime one —
which is what `Ast.declTable` and `Resolution.bindingTable` are, one level up and
without the machinery.

**A checked accessor per table, as `Ast` has.** Correct, and what a central
representation earns: thirty hand-written accessors are affordable there because
they are read constantly and change rarely. A scratch table a pass keeps to
answer one question never earns them, which is exactly why those tables were raw
slices. This makes the same discipline cost one line.
