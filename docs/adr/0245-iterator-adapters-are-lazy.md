# 245. Iterator adapters are lazy, reversal needs a double-ended source, and only a terminal allocates

Status: Accepted — 2026-11-10. Extends
[0192](0192-iterator-operations-belong-to-every-sequence.md) and
[0203](0203-zip-and-skip-require-discardable-items-and-zip-is-left-biased.md).
`rev` depends on a bound reaching its supertraits' associated types, which
[0243](0243-a-bound-reaches-its-supertraits-associated-types.md) decides.

## Context

`std.iter` offered seven lazy adapters and nine terminals. The library is
gaining about forty operations: folds (`sum`, `min`, `reduce`, …), shaping
(`chain`, `take_while`, `flat_map`, …), reversal (`rev`, `fold_right`),
look-ahead (`peekable`, `dedup`, `intersperse`), generators (`unfold`,
`successors`, `repeat`, `cycle`), slice views (`windows`, `chunks`,
`chunk_by`), and groupings that need memory proportional to the input
(`partition`, `unzip`, `frequencies`, `group_by`, `distinct`).

Each of these could be written several ways, and the choices interact with
four constraints already in force:

- `Iterator.next` answers `Option` and has no error channel, while ADR 0017
  says a failure is a value or a trap, never hidden, and ADR 0220/0225 give
  every allocating operation a system form and an `_in` form that states its
  allocator.
- `next` takes `inout self` and its result `carries(.Some: self)`, so an item
  may observe what the iterator observes but never the iterator (ADR 0123).
  Nor may `next` store into `self` a value that carries `self`: the trait's
  signature permits no `retains(self: self)`.
- An operation that disposes of a value says so in its bounds (ADR 0203), and
  a `for` refuses an iterator it would abandon holding obligations
  ([O-LinearWalk]).
- A slice yields `borrow T`, and a view does not convert to the value it views
  (ADR 0207).

This record decides the shape every operation takes. The first group lands
with it: `copied`, `sum`, `product`, `min`, `max`, `reduce`, `position`,
`rev`, `peekable`, `scan` and `Slice.windows`.

## Decision

The rules below bind every operation of the list above. The first group is in
the library; an operation named here that is not in that group is held to
these rules when it lands, and until then the library does not offer it.

**Every adapter is lazy.** Building an adapter calls no `next` and no
callback. Each `next` pulls only what one output needs, and an adapter whose
source has answered `None` answers `None`, as every `Iterator` promises;
`Peekable` records that its source ended and does not ask it again. The one
eager step allowed is in `iter.successors`, which will compute an item's
successor when it hands the item out, because the item is moved to the caller
and its successor is computed from it; the function will say so.

**An operation is an adapter or a terminal, and only a terminal allocates.**
An operation whose memory grows with its input (`partition`, `unzip`,
`frequencies`, `group_by`, `distinct`, and `collect` as today) is a terminal
returning `Result`, with an `_in` form, whose failure hands back what it
gathered and the iterator. An adapter holds at most one item inline
(`peekable` now; `dedup`, `intersperse` and `take_while` when they land) and
never a buffer. A
new terminal takes its callback `sink` and has no `_inout` form: whether
`inout` should accept a temporary, so that one form serves a callback the
caller keeps and one written in the call, is being decided separately, and
the operations here do not add to the forms that decision would retire.

**Reversal needs a double-ended source.** `DoubleEnded: Iterator` adds
`next_back`, which yields the last item neither end has yielded, so the two
ends meet without yielding an item twice. `Sequence.rev` requires
`Self.Iter: DoubleEnded`. Slices, ranges, `Slice.windows`, `Rev`, and `Map`,
`Filter`, `FilterMap` and `Copied` over double-ended sources implement it, and
`Chain` will when it lands. There is no `rev` that collects a single-ended
source. `DoubleEnded` is not in the prelude: a program implementing it or
calling `next_back` names `iter.DoubleEnded`, while `rev` needs no import.

**Groups without allocation are slice views.** `windows` is an operation of
`mem.Slice[T]` whose items are sub-views of the storage the slice observes,
so each carries what the slice carries and the storage cannot move while one
is in use ([O-Borrow]). `chunks`, `chunk_by` and `span` will be operations of
`mem.Slice[T]` of the same kind. A general iterator
offers no grouping adapter that yields borrowed groups, because its items
cannot borrow it. `windows(0)` traps: a window of no elements says nothing
about its neighbours, and an `Option` would burden every caller for a size
that is a constant in practice.

**An adapter that holds an item is linear when the item is.** A `for` over one
is then [O-LinearWalk], and the program walks it lent and recovers the held
item through `into_parts`, which every such adapter offers. No adapter drops a
held item silently, and none requires `Discardable` only to be able to hold
one. `peekable` holds its item in a field typed `Option[I.Item]`; its `peek`
lends that item, so `next` cannot run while the view is in use ([O-Borrow]).
`Peekable` has no `Release` implementation: releasing `Peekable[I]` would
instantiate the release of `I.Item`, which [T-PolyRec] refuses, so
`into_parts` is how one that holds obligations is settled.

**An adapter's state carries nothing a callback made.** The value a callback
returns may carry the callback itself, so an adapter that stored such a value
in its own field would retain itself, which `next` may not. `scan` therefore
keeps a state its callback updates in place, `scan(initial, |inout state,
sink item| …)`, and yields what the callback returns; the state is never
replaced by a returned value. What the callback returns may carry the item
and what the state carries, so a state that is itself a walk over a slice may
hand out that slice's views, but it may not view the state.

**Sums are typed by `Additive` and `Multiplicative`** in `std.num`,
implemented for every integer type and both float types. `Additive` offers
`zero()` and `add`, `Multiplicative` `one()` and `multiply`; both operations
consume their operands. An empty sum is `zero()`, an empty product `one()`,
and integer overflow traps as `+` does.

**A view's value is reached through `copied`.** `Additive.add` returns `Self`,
so it cannot be forwarded through `borrow T` the way `Comparable.less` is.
Rather than give each numeric trait a second shape for views, `copied` turns
items implementing `iter.Observation` (every `borrow T` with a Copyable `T`)
into the values they view: `prices.as_slice().copied().sum()`. `min` and
`max` need no `copied`, since `Ordered` forwards through a view; a slice's
`min` answers a view of its least element.

**`min` keeps the first of equal items and `max` the last**, the ones a
stable sort would put first and last, so the two agree with `sort`.

## Consequences

- A guide reader can tell from the operation table whether a call does work
  now, and the laziness section proves it with call counts.
- `xs.rev()` over an iterator that cannot go backwards is refused with
  `[T-Bound]` naming `DoubleEnded`; the program collects first, where the
  allocation is visible.
- `xs.as_slice().sum()` is refused with `[T-Bound]` naming `Additive`; the
  program writes `copied()`.
- `chunk_by` over a general iterator is not offered. Grouping a stream means
  collecting it or grouping into a map, both fallible and both visible.
- Linear items work through `peekable` at the cost of a lent walk and an
  explicit recovery, and `take_while`, `dedup` and `intersperse` will work
  the same way.
- `scan` reads `|inout total, sink x| { total += x; total }` rather than
  `|total, x| total + x`.
- Ten operations join `Sequence` with this record and about thirty more will
  follow, so a module that declares a trait with one of their names and
  implements it for a sequence makes the dot call `[N-Ambiguous]` (ADR 0192's
  consequence, now wider).
- `min` and `max` are also the names of an integer type's bounds
  (`UInt8.max`). Those still resolve first. Written on a type that has no
  such bound, `Bool.min` or `Count.max` on a newtype, the name is now looked
  for in `Sequence` as any operation's name is, and the [N-Undefined] report
  says the type implements no trait that declares it.

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

**A `scan` whose callback returns the next accumulator**, `|total, x| total +
x`, yielding a copy of each. The adapter would store a value the callback
returned, which may carry the callback the adapter holds, so `next` would
retain `self` in `self`. A self-observing value dangles once moved if the
callback owns its captures inline, so the ownership checker is right to refuse
it.

**`Additive` implemented for `borrow T`.** `add` must return a `Self`, and a
view of a sum computed inside `add` has no storage to view.

**A `Peekable[I, T]` with the item type as its own parameter**, as
`Collected` does to stay within [T-PolyRec]. Its `Iterator` implementation
would need `T` equal to `I.Item`, which an implementation head cannot state
without a type-equality predicate, and its head may not repeat `I`.
