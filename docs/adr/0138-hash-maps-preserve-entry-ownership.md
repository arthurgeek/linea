# Hash maps preserve complete entry ownership

## Status

Accepted. Extends [0082](0082-a-comparison-is-a-trait-call.md),
[0103](0103-linear-constrains-consumption-release-grants-one-way.md) and
[0113](0113-structural-derivation-is-library-defined-source.md).

Extended by [0139](0139-default-implementations-follow-ordinary-selection.md)
with default same-type Key queries for Hash types.

## Context

Keyed collections are needed by file processing, JSON objects and HTTP headers.
Keys and values can own resources or contain observations. Replacement and
allocation failure must not silently dispose of either field. Existing Vec
storage and ownership contracts provide the required memory operations.

## Decision

`std.hash.Hash` extends `cmp.Equivalent`. Equivalent values have equal hashes,
and key equality/hash behavior stays stable while a key is stored. Scalar/text
instances and library-defined structural derivation implement the contract.
Derived Hash requires derived equality; custom equality requires an explicit
compatible hash. Digests are noncryptographic and not a persistent format.

`std.collections.Map[K,V,A]` owns initialized Vec buckets using linear probing,
cached hashes and tombstones. Empty construction is allocation-free. Growth
allocates the destination before transferring entries. Replacement and tombstone
reuse do not allocate. An insertion returns the replaced complete entry; refusal
returns both incoming fields. Removal transfers ownership; lookup and iteration
borrow stored values. A value-transform update preserves its key.

Query operations require `hash.Key: Hash`, which declares `Query: Hash` and
`matches`. A matching query and stored key have equal hashes; a query matches
at most one stored-key equality class. Equivalent stored keys match the same queries. String keys use Str queries; scalar keys
use their own type. Custom keys choose their query representation explicitly.
Insertion only requires Hash. One probe loop accepts the appropriate comparison.

Release is conditional on both fields. A consuming drain and finish_empty
support non-Release protocols. Iteration order is unspecified. No allocating
projection, implicit cleanup, new compiler trait or raw storage primitive is added.

## Consequences

Expected operations are constant time for well-distributed hashes; probing is
bounded by capacity even under collisions. Rehashing may take quadratic time
for colliding keys, and deterministic hashing does not claim collision-attack
resistance. Network APIs must choose their own input limits or stronger policy.

Borrowed entries prevent conflicting mutation or release. Allocators remain
explicit, and callers choose how to settle replaced or rejected resources.

## Alternatives

A Vec of pairs duplicates linear searches in every client. Chained allocation
adds a separate allocation policy per entry. Heavy bracket projections would
add language machinery solely for insertion syntax. Implicit replacement
release would exclude protocol values without Release and conceal disposal.
