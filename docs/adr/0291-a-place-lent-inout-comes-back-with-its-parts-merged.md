# 291. A place lent `inout` comes back with its parts merged

Status: Accepted — 2026-11-18. Extends
[0123](0123-observations-carry-owner-dependencies-through-callable-contracts.md):
a retention between parts of one `inout` parameter no longer needs a clause,
and a caller no longer trusts a callee to keep each part's dependencies where
they were.

## Context

The ownership checker tracks dependencies per part of a place: after
`s.b = owned.view()`, `s.b` depends on `owned` and `s.a` does not, so
releasing `owned` while only `s.a` is still used is accepted. Across a call
that lends `s` `inout`, the caller kept that per-part picture unless the
callee's contract said otherwise, and the callee was checked at its exit
against its own clauses. The callee's check let a dependency stay "where the
caller put it" whenever it was still rooted at the parameter and the path it
came from covered the path it sat at.

That exemption could not tell a dependency left in place from one moved. A
function lending its parameter on to `swap(inout s) where retains(s: s)`,
which writes `s.a = copy(s.b)`, needed no clause of its own, because the
retention it received was whole-to-whole; a function writing
`s = swapped(s)` through a contract that carries `s` needed none either. Its
caller then released the owner of `b` and read `a`: accepted, and the program
read freed storage. Such programs are in `tests/borrows/inout_lend`; each
aborts with "storage was used after it was freed" under `--check-storage` on
the compiler before this decision. The hole is reachable from any wrapper,
any generic function lending its parameter to a trait operation, and any
iterator advanced through a function that is lent it.

## Decision

**Every `inout` lend merges the lent place's parts at the caller.** After a
call lends a place `inout`, every part of that place may hold what any part
of it held before the call. The rule has no exception: it applies to a whole
local, a field, a field of a field, an element, a walk binder, a closure's
`inout` capture, a method receiver (through the receiver's observations to the
place they reach), a lent walk's call of `next`, and each place a callable
holds lent `inout` when it is invoked, whether it is called `inout` or
by `sink`. A callable lent or given to a call carries the places it holds lent
`inout`, and those places are merged too, because the callee may invoke it.
A write through a binding that is a lend of another place, such as a
`for inout` binder, is a write into that place.

The merge joins: the parts keep what they held and gain what the others
held, so no dependency is dropped at a join, an assignment, a return or a
later lend. The call's own result is read from the lent place as it stood
before the call: the callee's exit check holds everything it returns to the
sources its contract names, by where each dependency came from rather than
where it sits at the return, so a part it moved into a named source does not
pass. Every later reading of the lent place sees the merge.

**A callee may move what its `inout` parameter held between the parameter's
parts.** Its exit check no longer asks where inside the parameter a
dependency the caller gave it sits; a `retains` clause between parts of one
parameter states nothing the caller does not already assume. A dependency
that comes from another parameter, a capture, or a value the callee made
still needs its clause.

**A contract naming one part of a parameter holds only until the body lends
the parameter.** `carries(.Err.Input.reason: self.reader)` cannot be kept by a
reader whose read lends `self` to its own helpers first, since after that lend
the reader part may hold what the buffers or the allocator held. Such
contracts name the whole parameter, and a value that must stay independent of
one part of a record is kept out of the record that is lent: a JSON object
decoder is given the document on each call instead of holding a view of it.

## Consequences

The eight programs in `tests/borrows/inout_lend` are refused by [O-Borrow] where
the moved owner is released and then used, and the accepted counterpart runs
clean. The soundness matrix gains a part-move family: each place shape lent
`inout` to each kind of mover (a declaring callee, a wrapper, a rebuild
through a contract, a generic trait operation, a method), written live and
ended.

The cost is precision. A program that lends a record `inout`, then releases
the owner of one field while still using another, is refused even when the
callee touched neither. Such programs keep the field apart from the lent
place, or lend only the field the call needs. In the library,
`io.BufferedReader`'s reads, `io.prompt` and `io.BufferedWriter.finish` now
carry their whole receiver, a failed `Map.upsert` carries the whole map, and
`json.ObjectDecoder` no longer holds the object: `open` checks it, and
`field`, `required`, `optional` and `finish` are each given it.

## Alternatives considered

**The callee declares every movement (A).** Treat a dependency as in place
only while it has not passed through a contract, and make every function that
lends its parameter to a retaining callee declare `retains(p: p)` itself. It
keeps per-part precision at callers, but the clause climbs every wrapper: a
vector that reallocates must declare it, so must `String.append`, and so must
any program function that appends to a `String` it is lent. The language would
ask every author to state a fact about the callee's insides that the caller
can assume for free. It also leaves the proof that every path a dependency can
take through a callee is covered by a declared clause to a check that has
already been wrong once.

**Merge only outside opaque types.** Callers cannot name an opaque type's
fields, so a merge inside one changes nothing they can observe, and the
library's own types would keep their per-field contracts. Rejected for now:
the module that declares the type does name its fields, and a rule with an
exception for one kind of type is a second rule to keep sound.

**Future work.** Either refinement may come back with its proof. A must show
that the callee-side check accounts for every movement — direct writes,
retentions received from callees, rebuilds through contracts, aliases and
callables invoked inside — so that a caller trusting the per-part picture
never trusts a stale one; the soundness matrix's part-move family is the
minimum such a change must keep refused. The opaque refinement must show that
no code outside the declaring module can separate the parts, through
destructuring, field access, or a contract naming a part, and that the
declaring module's own callers still merge.
