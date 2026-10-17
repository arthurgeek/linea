# 124. Copyability and settlement are independent capabilities

Status: Accepted — 2026-09-09

Extended by [0125](0125-scalar-value-positions-take-snapshots.md) and [0221](0221-owned-admits-a-type-that-can-carry-no-borrow.md).

Supersedes the declaration/universe classification decisions in
[0046](0046-the-universe-of-an-instantiation-is-computed.md) and
[0051](0051-a-part-obliges-when-no-argument-can-remove-it.md), and the two-universe
default of [0034](0034-ownership-is-positions-and-a-graph.md). Preserves the
owner-observation boundary and certified logical containment of
[0123](0123-observations-carry-owner-dependencies-through-callable-contracts.md).
Extends [0103](0103-linear-constrains-consumption-release-grants-one-way.md).

## Context

An arena reservation need not be individually freed, but a mutable container
over that reservation must not be duplicated. Treating every discardable value
as copyable cannot express that distinction. Conversely, permitting arena
storage to disappear must not erase the obligations of files or transactions
held in its elements.

## Decision

User-defined structs, enums, and nominal newtypes are affine by default: they
cannot be copied, but their representation may be discarded when no owned part
requires settlement. A `linear` declaration imposes mandatory consumption even
when its fields do not. Owned linear parts propagate that obligation through
all wrappers, including concrete wrappers without an explicit modifier.

`copyable` is a conditional declaration policy. It permits copying only when
every owned part permits copying. A generic copyable Option remains usable
with affine or linear elements; the actual parts determine the instantiated
capabilities. A concrete copyable declaration containing a known noncopyable
part is rejected. `linear` and `copyable` are mutually exclusive.

The canonical answers are:

```text
mayCopy = copyable declaration policy AND all owned parts mayCopy
mustConsume = linear declaration policy OR any owned part mustConsume
mayDiscard = NOT mustConsume
```

Built-in scalar, observation, and noncapturing callable types retain their
copyability policy. Arrays compose their actual elements; a zero-length array
owns no elements. Observing a T does not own it. Certified Storage contributes
its logical T ownership while certified Slice does not.

`Copyable` replaces the `Free` bound, without a compatibility alias.
`Discardable` is a separate built-in bound admitting affine and copyable
values. These are checked capabilities, not user-implementable traits.
Unbounded parameters remain noncopyable and potentially require settlement.
Declaration policy and effective capabilities are distinct facts; later passes
consume settled answers instead of reclassifying types.

Ordinary aggregate moves invalidate the source in all categories. Branch
merges, partial moves, observation invalidation, and fallible-result
acknowledgement remain independent of whether a value may be discarded.
`Release` remains an optional ordinary trait, not the definition of an
obligation. Discard invokes no code. An explicit release may have effects even
when its receiver is discardable.

An allocator supplies an associated `Obligation` type stored in Buffer's private
representation. System allocation supplies a private zero-sized linear token;
an arena reservation supplies unit. Trusted acquire/dispose operations
construct and consume these values. This makes allocation responsibility
structural without deriving it from a copyable allocator handle or introducing
another region identity. Buffer, Storage, Vec, String, and Arena compose their
owned parts. Protocol types such as BufferedWriter remain explicitly linear.

Discarding a parent-backed child arena does not reclaim capacity or rewind the
parent. The backing system owner still requires explicit release. Optional
Vec.release retains its element Release bound and its element-release behavior.

## Consequences

The compiler must distinguish copying checks from abandonment checks at every
former Free consumer. Generic iteration can require Discardable without
requiring Copyable. The previous admissibility machinery whose purpose was
requiring a redundant linear wrapper declaration is removed, not renamed.

Source and library callers migrate with the default change. Copyable opt-ins
describe intended APIs rather than mechanically preserving every former Free
declaration. No automatic element finalization or runtime registry is added.

## Alternatives considered

**Make arena vectors Free.** Permits duplication of mutable storage owners.

**Separate arena-only container APIs.** Duplicates interfaces and prevents a
single generic container from expressing both storage and element obligations.

**Classify by Release implementation.** A discardable value may implement it,
and a mandatory protocol may omit it; neither direction gives the right answer.

**Require linear on every concrete wrapper.** Retains annotation ceremony and
an additional classification question when owned parts already prove the debt.
