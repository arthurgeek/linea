# 203. `zip` and `skip` require the items they dispose of to be Discardable, and `zip` is left-biased

Status: Accepted — 2026-10-04

Extends [0192](0192-iterator-operations-belong-to-every-sequence.md).

## Context

Control flow does not imply disposal; an operation that disposes of a value
says so in its bounds, as `filter` does for the items it rejects. `zip` stops
when either iterator is exhausted, holding an item from the other; `skip`
disposes of its first n items. An item may be linear. A `[T-Bound]` report names
a type and a trait at a site and nothing else.

## Decision

**`zip` draws from the first iterator before the second and disposes of the
first's item when the second ends first**, so it requires only the first
sequence's items to be Discardable. `Sequence.zip` carries
`where Self.Iter.Item: Discardable` on the operation itself, so the refusal
lands at the call, and `Zip`'s `Iterator` implementation carries the same
bound. `xs.zip(ys)` can be refused while `ys.zip(xs)` is accepted.

`Skip[I]` requires `I.Item: Discardable`; `enumerate` and `take` impose no
bound, because `take` stops asking and disposes of nothing.

An unsatisfied `Discardable` requirement written on a library operation's own
clause is reported with a help that names the operation and says it may
dispose of the value. For `Sequence.zip` the report itself carries the
explanation: `zip` draws an item from the first sequence before asking the
second, and if the second sequence ends first it disposes of that first item,
so the first sequence's items must be Discardable; the fix is to zip in the
other order or to walk both sequences by hand. The checker reads that sentence
from one per-operation table keyed by the providing trait and the operation's
name, so no other operation gains it. The guide states the left bias beside
the operation too, and the corpus pins the message and the bias.

`Parts[I, F]` becomes the pair `(I, F)`: `into_parts` returns it with
`carries(._0: self.iterator)` and `carries(._1: self.transform)`, because
the two components are read by position at every use.

## Consequences

- A `zip` over a linear first sequence is refused at the `zip` with the item
  type named; the program zips in the other order or walks both by hand.
- The help is general to `Discardable` clauses on operations, so `skip` and
  `filter` gain it too; only `zip` also states its reason.
- `Zip`'s `Release` settles the second source and then the first, the order a
  tuple's derived `Release` settles its components, so a test observes one
  order for both.
- Discarding an item never runs its `Release`, so the first sequence's third
  item in a `zip` over a shorter second sequence is abandoned unreleased.

## Alternatives considered

**Return the unmatched item through a recovery operation.** It is an API for
one item of one adapter.

**Hold it in the adapter.** The item would be abandoned at the walk's end,
which [O-LinearWalk] refuses.

**A symmetric `zip` requiring both items Discardable.** It refuses
`ys.zip(xs)` for an item that call never disposes of.

**A bound that carries its reason.** The reason is recorded as data the
checker reads when it builds the help, in a table beside the help keyed by the
trait that provides the operation and the operation's name. A reason written
in source needs an attribute or a clause form the language does not have, so
the table is the smallest mechanism that keeps one place deciding the help.

**The general help alone, with the left bias taught only in the guide and the
doc comment.** A program that is refused at `zip` reads the error, not the
guide, and the general help ("may dispose of a `Job`") does not say why `zip`
disposes of anything, nor that zipping the other way would be accepted.
