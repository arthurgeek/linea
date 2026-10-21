# 245. Iterator adapters are lazy, reversal needs a double-ended source, and only a terminal allocates

Status: Proposed — 2026-10-18. Would extend
[0192](0192-iterator-operations-belong-to-every-sequence.md) and
[0203](0203-zip-and-skip-require-discardable-items-and-zip-is-left-biased.md).
`rev` and `fold_right` depend on a bound reaching its supertraits'
associated types, which is proposed separately.

## Context

`std.iter` offers seven lazy adapters and nine terminals. The library is about
to gain about forty operations: folds (`sum`, `min`, `reduce`, …), shaping
(`chain`, `take_while`, `flat_map`, …), reversal (`rev`, `fold_right`),
look-ahead (`peekable`, `dedup`, `intersperse`), generators (`unfold`,
`successors`, `repeat`, `cycle`), slice views (`windows`, `chunks`,
`chunk_by`), and groupings that need memory proportional to the input
(`partition`, `unzip`, `frequencies`, `group_by`, `distinct`).

Each of these could be written several ways, and the choices interact with
three constraints already in force:

- `Iterator.next` answers `Option` and has no error channel, while ADR 0017
  says a failure is a value or a trap, never hidden, and ADR 0220/0225 give
  every allocating operation a system form and an `_in` form that states its
  allocator.
- `next` takes `inout self` and its result `carries(.Some: self)`, so an item
  may observe what the iterator observes but never the iterator (ADR 0123).
- An operation that disposes of a value says so in its bounds (ADR 0203), and
  a `for` refuses an iterator it would abandon holding obligations
  ([O-LinearWalk]).

## Decision

**Every adapter is lazy and fused.** Building an adapter calls no `next` and no
callback. Each `next` pulls only what one output needs. Once an adapter answers
`None` it answers `None` again without calling its source or callback. The
only eager step in the library is `iter.successors`, which computes an item's
successor when it hands the item out, because the item is moved to the caller
and its successor is computed from it; the function says so.

**An operation is an adapter or a terminal, and only a terminal allocates.**
An operation whose memory grows with its input (`partition`, `unzip`,
`frequencies`, `group_by`, `distinct`, and `collect` as today) is a terminal
returning `Result`, with an `_in` form, whose failure hands back what it
gathered and the iterator. An adapter holds at most one item inline
(`peekable`, `dedup`, `intersperse`, `take_while`) and never a buffer.

**Reversal needs a double-ended source.** `DoubleEnded: Iterator` adds
`next_back`. `rev()` and `fold_right` are provided by `Sequence` under
`where Self.Iter: DoubleEnded`. Slices, ranges, the slice views, `Rev`, and
`Map`, `Filter`, `FilterMap` and `Chain` over double-ended sources implement it.
There is no `rev` that collects a single-ended source.

**Groups without allocation are slice views.** `windows`, `chunks`, `chunk_by`
and `span` are operations of `mem.Slice[T]` whose items are sub-views of the
storage the slice observes. A general iterator offers no grouping adapter that
yields borrowed groups, because its items cannot borrow it.

**An adapter that holds an item is linear when the item is.** A `for` over one
is then [O-LinearWalk], and the program walks it lent and recovers the held
item through `into_parts`, which every such adapter offers. No adapter drops a
held item silently, and none requires `Discardable` only to be able to hold
one.

**Sums are typed by `Additive` and `Multiplicative`** in `std.num`,
implemented for every integer type and each float type. An empty sum is
`zero()`, an empty product `one()`, and integer overflow traps as `+` does.

## Consequences

- A guide reader can tell from the operation table whether a call does work
  now, and the laziness section proves it with call counts.
- `xs.rev()` over an iterator that cannot go backwards is refused with
  `[T-Bound]` naming `DoubleEnded`; the program collects first, where the
  allocation is visible.
- `chunk_by` over a general iterator is not offered. Grouping a stream means
  collecting it or grouping into a map, both fallible and both visible.
- Linear items work through `peekable`, `take_while`, `dedup` and
  `intersperse` at the cost of a lent walk and an explicit recovery.
- About forty operations join `Sequence`, so a module that declares a trait
  with one of their names and implements it for a sequence makes the dot call
  `[N-Ambiguous]` (ADR 0192's consequence, now wider).

## Alternatives considered

**Lazy adapters that allocate** (a lazy `distinct` keeping a seen set, a `rev`
buffering its source). `next` would have to trap on a refused allocation, or
yield `Result` items so every consumer unwraps; the first hides a failure
ADR 0017 requires be visible, the second makes the common case pay for the
rare one.

**Lending iterators**, whose items borrow the iterator, so a general
`chunk_by` could yield a group that reads the iterator's buffer. That needs a
`next` whose result observes `self`, which would change what every
`Iterator` signature means and what every adapter may hold; ADR 0123 left
writable stored observations out.

**Adapters that require `Discardable` items wherever they hold one.** Simpler
signatures, but `peekable` and `take_while` would then refuse linear items they
never need to drop.
