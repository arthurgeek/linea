# 250. An alike-template instantiation is answered from its template

Status: Accepted — 2026-10-26. Partially supersedes
[0248](0248-an-instantiation-holding-a-parameter-is-written-when-read.md):
its rule that writing an instantiation writes every unwritten one among its
parts, so that a written type holds only written types, no longer holds for
an alike-template instantiation. Extends
[0241](0241-declared-answers-are-settled-when-first-needed.md), whose walk
over what types owns steps through one.

## Context

[0248](0248-an-instantiation-holding-a-parameter-is-written-when-read.md)
mints an instantiation holding a type parameter with its parts unwritten,
and writes them when something reads them. It kept one invariant from
writing at mint: a written type holds only written types. Writing an
instantiation wrote every unwritten one among its parts, the cycle and width
walks wrote every unwritten one a written type held, and the capability,
dependency and writer tables, meeting an unwritten part of a recorded type,
had the builder write it before they answered. Every walk over parts could
then read parts without asking whether they existed.

That invariant has a cost 0248 did not measure. Take `n` templates, each
holding the next at its own parameter:

```linea
struct G0[T: Tr] {
    v: G1[T],
}

struct G1[T: Tr] {
    v: G2[T],
}
```

`G0`'s part is `G1[T0]`, an instantiation at `G0`'s parameter. A capability
question about `G0` records it, and the table writes `G1[T0]`, whose part is
`G2[T0]`, which is written in turn, down to `Gn[T0]`. The same happens for
`G1` at `T1`, and for every template: about n²/2 instantiations, each written,
recorded and walked. The "nested templates" sweep dimension read n^2.12, and
`main` pays the same. With each part selecting the next, `v: Pad[G1[T]].Out`,
[0241](0241-declared-answers-are-settled-when-first-needed.md)'s walk over what
types own and `Builder.settleFactsOf` start the same cascade, and "templates
selecting the next" read n^2.63.

Almost none of those copies tells anything its template does not. `G1[T0]` is
`G1` with `T1` renamed `T0`, and `T0` promises exactly what `T1` does. Whether
it can be copied or discarded, whether it may carry a dependency, whether it
holds itself: each is a question about the shape of what it owns, and the
shape is the template's.

## Decision

**An alike-template instantiation is answered from its template while its
parts are unwritten.** Its parts are written when something reads them, as
0248 says, and writing another type's parts does not write it.

### Which instantiations are alike

An instantiation `D[A1, ..., An]` of a structure or an enum is alike its
template when:

- every argument `Ai` is a type parameter, and not a settled reference such
  as `T.Item`, which the pool also interns as a parameter;
- the arguments are pairwise distinct; and
- each `Ai` promises exactly what `D`'s parameter at position `i` promises:
  the same capability requirement, the same `Integer` and `Owned` promises,
  the same traits at the same arguments, compared by identity, and the same
  callable signatures.

`Desk[L]` with `fn pass[L: Ledger]` and `struct Desk[L: Ledger]` is alike.
`Crate[T]` with `fn ship[T: Discardable]` and `struct Crate[T]` is not: its
argument promises more, and its parts, once written, may answer differently.
`Pair[T, T]` is not: an implementation for `Pair[X, X]` applies to it and
not to its template. A bound whose arguments name its own parameter,
`T: Into[T]`, never compares equal, so such an instantiation is written as
before. Certified storage is never alike: its containment reads its element
argument, not its parts.

Promises are completed after instantiations are minted: a bound's traits and
callable signatures are read in a later sweep, and a `where` clause adds
`Owned`. So the decision is not taken once. `Builder.watchAlike` decides it
at mint and lists the instantiation under every parameter it compares;
`setBoundTraits`, `setCallableBounds` and `promiseOwned` decide each listed
instantiation again (`decideAlikeAgain`), and a decision that changes
rebuilds the capability and dependency tables. `Instance.alike` holds the
current decision, so the finished pool reads the same one.

### What is answered from the template, and where

`Typing.partsSource` is the one routine: it returns the template of an
alike-template instantiation whose parts are unwritten, and the type itself
otherwise. Every walk over what a type owns steps through it instead of
writing parts:

- the capability table records such an instantiation, seeded from its
  policy, with one owned edge, to its template; the dependency table, in its
  `raw_carriers` mode, records the same edge; the writer table records its
  arguments, which are parameters and so settle it, as 0248 already did;
- the cycle walk (`firstCycleIn`) walks it as its template, so a path names
  the declarations a reader edits: `A contains B contains A`;
- [0241](0241-declared-answers-are-settled-when-first-needed.md)'s walk over
  what types own lists its template as its one edge;
- the finished pool's walks over parts -- whether a type holds storage or a
  view, whether taking a value apart discharges what it owes, which part a
  dependency path or a contract's target selects, and which paths cover a
  type's dependencies -- read the template's parts.

None of these copies the template's answer into a table of its own; each
reads the template where the type would have been read. A question about an
alike-template instantiation that needs its actual parts -- a field read, a
pattern, a variant's payload -- writes them as before, and the tables then
record those parts in place of the template edge. The template's answer is
the one those parts give, so nothing recorded is invalidated.

### Scoped capabilities

A declaration's contextual constraints may cap a capability:
`fn tally[L: Ledger](sink desk: Desk[L], count: UInt8) -> UInt8 where
L.Entry: Discardable` caps `L.Entry` at discardable inside `tally`. The cap
is keyed by the subject it names, at `tally`'s own parameter. `Desk[L]`
answered from its template would reach `Desk`'s parameter instead, `L.Entry`
at the template's `L`, which `tally`'s clause does not name, and refuse to
drop a desk that may be dropped.

So **within a scope that caps any capability, every alike-template
instantiation a question reaches is written before the scoped answer is
prepared** (`Builder.prepareScopedCapability`), and the scoped answer is read
from its own parts. A scope that caps nothing answers every type as the
unscoped table does, so there the template's answer stands. A bound written
on the parameter itself, `[T: Discardable]`, is part of the parameter's
promise, and an instantiation at it is not alike in the first place.

### Hand-off

Before the checker hands the pool on, `fillMinted` writes every
instantiation the checker minted, alike or not, and follows the parts of
each only where they are not alike. So every type an expression, a binding,
a signature or a written type has is written, and an editor offering the
fields of a `Desk[L]` names each at `L`. What those writes mint is held only
as a part, and an alike-template instantiation among it stays unwritten.

Ownership, instance discovery and lowering may therefore meet an unwritten
alike-template instantiation as a part of a written type, and never as the
type of a value:

- ownership asks what it owes or may carry through the finished tables,
  which recorded it against its template, and walks its parts through
  `partsSource`; the finished pool's `readsFacts` admits such a type where
  `readsParts` admits no unwritten one;
- instance discovery substitutes concrete arguments into templates, and a
  ground instantiation is written as it is minted, so it never reads one;
- lowering lays one out empty, as 0248 already did for every unwritten
  instantiation, since no lowered value has a type holding a parameter; the
  layout oracle gives one no C form.

A read of an unwritten instantiation's parts in the finished pool is still a
compiler defect.

## Cost

Each instantiation is written at most once, and writing one writes only
those of its parts that are not alike their templates. Each fact table
records an alike-template instantiation as one edge, and the walk over what
types own pushes it once, with one edge. `n` templates each holding the next
cost `n` instantiations recorded through their templates and, at hand-off,
`n` written, each minting the one part it holds: linear. The sweep reads
n^0.24 for "nested templates" (1000 to 4000) and n^0.13 for "templates
selecting the next" (250 to 1000), where they read n^2.12 and n^2.63.

What makes the bound hold is that the alike decision is a local test, the
length of an instantiation's arguments, and that no walk follows an
alike-template part into its own parts. Deciding again costs one decision per
instantiation listed under a parameter whose promise changed, and each
parameter's promises change a fixed number of times. Within a scope that
caps a capability, the instantiations written are those the scope's
questions reach, which preparing the scoped answer visits anyway, and the
scope remembers what it prepared.

## Consequences

A written type may hold an unwritten instantiation, so a walk over parts
must not assume a part has parts. Every such walk named above goes through
`partsSource`; a new one must too, and the finished pool's `readsParts`
stops one that does not.

The tables now know which instantiations are alike, and a promise added late
rebuilds them once per changed decision. Such a change is rare: it needs a
parameter to gain a promise after an instantiation at it was recorded.

## Alternatives considered

**Keep the invariant and make each write cheaper.** The cost is the number of
instantiations, not the price of each: n²/2 of them are minted, recorded and
walked.

**Answer every instantiation holding a parameter from its template.**
0248 rejected this for substitution on every read, and it is wrong where the
arguments promise differently: `Crate[T]` at a discardable `T` may be
dropped, and `Crate` at its own unbounded `T` may not. Restricting it to
arguments that promise what the template's parameters promise makes the
answer a renaming, which needs no substitution.

**Let an alike-template instantiation share its template's run of parts.**
Raw walks would read the template's parts without any routine. But the fact
tables record a snapshot of a type's parts, and a template's parts are
settled after its instantiations are minted
([0241](0241-declared-answers-are-settled-when-first-needed.md)), so a
shared run's recorded edges would go stale; and a write to the shared run,
breaking a cycle or writing the instantiation's own parts, would write the
template.

**Decide alikeness once, at mint.** Bounds' traits, callable signatures and
`Owned` promises are completed after instantiations are minted, so the
decision would be read stale.

**In a capping scope, rename the scope's caps onto the template's
parameters.** A cap's subject is any type at the scope's parameters,
`L.Entry` or `Vec[L]`, so renaming it is the substitution every scoped reader
would carry. Writing the instantiations a capping scope reaches costs what the
scope asks about.

**Leave alike-template instantiations unwritten at hand-off.** Ownership and
lowering only ask what they own, but an editor names the type of each field
of a value, which needs the parts at the value's own arguments, and the
finished pool cannot write. Writing what the checker minted, without
following alike-template parts, is linear.
