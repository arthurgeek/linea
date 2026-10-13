# 123. Observations carry owner dependencies through callable contracts

Status: Accepted — 2026-09-08
Extended by [0137](0137-arrays-expose-checked-borrowed-slices.md).
Mandatory backing-buffer shape superseded by [0133](0133-empty-typed-storage-needs-no-allocation.md).
Source-clause spelling superseded by [0132](0132-callable-results-separate-types-from-dependencies.md).

The projection syntax is superseded by [0126](0126-observations-project-referent-places-transparently.md); owned capability composition is refined by [0124](0124-copyability-and-settlement-are-independent-capabilities.md).
A caller's stable address for an argument that is not a place is refined by [0175](0175-a-borrowed-temporary-lives-until-the-end-of-its-statement.md): the argument is a temporary of its statement.

Supersedes 0069. Refines [0046](0046-the-universe-of-an-instantiation-is-computed.md):
an instantiated aggregate derives ownership from its substituted parts; an
argument occurring only behind `borrow` contributes no ownership obligation.
The compiler records no phantom ownership bit mask, and phantom positions are
not restricted by the machine word width.
Supersedes the reference-free and interchangeable-address ABI
clauses of [0025](0025-mutation-through-a-parameter-is-marked.md), and the
owner-erased signatures and region propagation clauses of
[0121](0121-typed-storage-is-private-and-checked.md). Extends
[0034](0034-ownership-is-positions-and-a-graph.md),
[0048](0048-one-question-has-one-answer.md), and
[0076](0076-a-raw-access-is-a-declaration-lowering-replaces.md).
Extended by [0128](0128-qualified-enum-constructors-are-contextual-callables.md).

## Context

Dynamic text needs views into owned bytes, including views returned from
operations that compute a new descriptor. A pointer to a locally computed
`Str` descriptor cannot provide that lifetime. Views also occur in records,
enum payloads and dynamically allocated collections, where copying or moving a
descriptor must preserve the owners its backing storage observes.

Invocation-created region identities introduce a separate ownership model.
An unknown callback may consume an input owner or return that same owner;
source upper bounds cannot express a promise that it preserves an invocation's
pool identity. Giving `carries` that additional meaning would require callback
effect polymorphism for ordinary generic map operations. Owner observations
express the required allocator lifetimes directly.

## Decision

`borrow T` is a sized, read-only place observation. `borrow place` observes
existing storage; `.value` projects the observed place without introducing a
second owner. `copy(b)` duplicates the observation. `copy(b.value)` duplicates
an admissible observed value and retains any dependencies contained in that
value. It does not retain an unnecessary dependency on the copied descriptor.
Borrow disposal discards only the observation and requires no disposal trait
on the referent.

`Str` is a sized UTF-8 descriptor containing a certified `Slice[UInt8]`.
`Slice[T]` describes a checked, initialized, aligned extent, including empty
extents. It is not an ordinary observation of the first element. Private span
operations preserve the backing owners while constructing new descriptors.

Callable contracts distinguish observing source storage (`borrows`) from
forwarding dependencies contained in a value (`carries`). `retains` declares
which sources an inout destination may retain, with `borrow source` explicitly
allowing its place to escape. `carries()` suppresses source inference and
promises an independent result. Otherwise a sole eligible source can be
inferred; multiple eligible sources require a declaration.

A result target such as `carries(.Ok.view: source)` restricts an effect to that
contained component. Paths traverse fixed fields and named enum variants with
one payload. Typing resolves names into field identities and ordinals or
variant/payload ordinals. Ownership consumes that answer. Contracts are checked
upper bounds, including for sink sources; they impose no pool-preservation
promise. Trait and callable compatibility account for normalized effects.

An escaping observation of parameter storage uses the caller's stable address,
including for scalar parameters and observations retained without a borrowed
return value. Carries-only descriptor parameters may be temporaries. Typing
records the ABI decision; lowering does not infer it from a body.

Ownership's existing CFG computes observation roots, field paths, stored
contents and last uses. A live observation prevents overlapping mutation,
replacement, moves, disposal and relocation of its owner. Fixed record fields
can be disjoint; observing a collection element protects the whole container.
Dependency sets may include several owners. Removing an element may retain the
conservative union of its collection's represented owners. A value cannot own
storage and contain an observation of that same owned storage.

Private compiler-certified `Storage[T,A]` represents logical out-of-line T
containment over `Buffer[A]`. Taking a slot requires inout storage and forwards
contained dependencies; putting a slot retains the value's dependencies. The
certificate survives raw buffer locals during growth. No pass recognizes Vec
method names as special ownership operations.

Allocator lifetimes use these same roots. An arena handle contains a borrow of
its arena, and an allocated buffer retains its concrete allocator value. A
nested arena owns its backing buffer. An arena cannot move or be released while
live handles or allocations observe it. Buffer disposal dispatches through its
retained allocator; allocation-instance validation is a separate runtime
contract. Invocation-region result markers, identities, pool-transfer facts,
and the old type-checker provenance propagation are removed.

A trait forwards structurally through an observation only if its entire surface
uses Self solely as whole read-parameter types. Returning, consuming, mutating
or nesting Self prevents forwarding of that trait. Typing records the selected
underlying implementation and receiver; lowering emits the real ABI adaptation.
An explicit implementation for borrow T may instead define behavior of the
observation itself, such as disposal.

## Consequences

Generic APIs can consume inputs into independent results or forward borrowed
values under the same source upper bound. Owned copied text can outlive its
source because its result carries its chosen allocator's dependencies alone.
An independent failure arm does not inherit a success arm's owners.

The producing pass owns each answer: syntax retains written clauses; typing
normalizes types, selectors, source contracts, observation eligibility and
address conventions; ownership determines dynamic lifetime facts; MIR carries
pointer values and checked storage addresses; emission renders those records.
There is no second region propagation pass. Containment metadata is sized by
the type domain, and dependency/liveness worklists by each function's CFG and
recorded paths.

Writable stored borrows, disjoint dynamic container ranges and self-referential
owner/view aggregates remain excluded. This decision does not add implicit
copying, implicit disposal, hidden allocation, or undefined behavior.
