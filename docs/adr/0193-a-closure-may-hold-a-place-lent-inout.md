# 193. A closure may hold a place lent `inout`

Status: Accepted — 2026-09-28. Supersedes the clause of
[0131](0131-closure-invocation-and-capture-ownership-are-independent.md)
"Stored inout captures remain forbidden"; extends
[0123](0123-observations-carry-owner-dependencies-through-callable-contracts.md),
[0124](0124-copyability-and-settlement-are-independent-capabilities.md),
[0130](0130-explicit-captures-use-inline-environments.md) and
[0173](0173-a-capturing-closure-is-erased-into-allocator-owned-storage.md).

## Context

A stateful callback inside a lazy pipeline kept its state in a `sink` capture.
Reading that state afterwards meant taking the pipeline apart:
`into_parts()` on each adapter, in the order the adapters were nested, and
then `into_captures()` on the callback. Each step depended on how the
standard library represents its adapters, so reordering `map` and `filter`
broke the recovery path.

State that stays outside the pipeline avoids that recovery, but only if the
pipeline may hold an exclusive lend of it. The language already stored read
observations in closures (0130) and tracked their owners through `carries`
(0123), and it already lent places exclusively for the length of one call
(`&x`, `for inout`). It had no stored exclusive observation.

## Decision

A capture may be written `[inout name]` or `[inout alias = place]`. The
source must be a place that may change, as `&` requires. The environment field
stores an observation of that place, as a read capture's does; the capture
binding in the body names the place itself, as an `inout` parameter does.
The body may read and write it and must leave it initialized. Only a closure
called `inout` or `sink` may hold such a capture: a closure called for reading
may be reached through several observations at once, and each of them could
write through the lend ([O-Capture]).

Ownership records the observation as an exclusive lend. A dependency fact
carries the capture source that lent it, which is the mode bit and the site
diagnostics name. `carries` copies facts unchanged, so the lend travels
through every adapter, result and `mem.Closure` whose contract carries the
callback, and no standard-library signature changes. `borrows` creates a new
read fact at the argument's place; it never creates an exclusive one.

Lending a place `inout` ends every earlier observation of it, as a write
does. While a value carrying the lend is live, any read, write, move, `&`,
new observation or second lend of an overlapping place is [O-Borrow]. The
check invalidates the lend at that access and reports when a value carrying
it is used afterwards, so the lend ends at the last use of whatever holds it.
Disjoint fields remain independent, with the same overlap relation as
[N-Aliased] and [O-Lent].

An exclusive lend never leaves the function that lends the place. A result, a
retained `inout` destination or any other boundary carrying one is
[O-Escapes], whatever the contract says. No contract clause may name an
`inout` capture, and a closure result never depends on one.

Only a closure, a function value or a value of a type parameter can write
through a lend, and a closure's result never observes a place it has lent. So
a lend reaching a value whose type can hold none of these — a vector of
borrowed numbers, an optional borrowed item, a recovered environment of
observations — becomes a read observation there: the place may be read beside
that value, and is still refused a write, a move or a new lend until the
value's last use. Whatever still holds the writer keeps the exclusive lend.
Typing answers which types can hold a writer, in one containment table beside
the dependency one; it follows fields, observed referents and every type
argument, phantom ones included, so a container that erases what it stores
still counts. Ownership applies it wherever a set of facts lands in a value of
a known type: an expression's result and a binding's write.

An environment holding an `inout` capture is affine: it may be dropped, since
dropping a lend settles nothing, and it is never Copyable, since a copy would
duplicate exclusive access. A Linear place may be lent; its owner settles it
after the lend ends. `into_captures()` consumes the closure and returns the
field as a read observation of the place.

MIR stores the source's address in the field, exactly as for a read capture,
and a write in the body is a store through it.

## Consequences

A counting predicate reads as

```linea
var inspected = UInt64(0)
let accepted = iter.filter(arrivals, inout [limit, inout inspected] |parcel| {
    inspected += 1
    *parcel <= limit
})
```

and `inspected` is readable once the pipeline's last use has passed. No
recovery operation is needed for state, and `into_parts()` remains only for
settling a callback that owns a resource.

A value whose contract carries a whole adapter, such as an item from a
filter's `next()` (`carries(.Some: self)`) or the values `collect` gathers
(`carries(.Ok.values: allocator, iterator)`), carries its callback's lend; the
demotion above makes that a read observation wherever the value cannot hold a
writer, so a vector of borrowed items leaves the counter readable. An item
type that is itself a closure keeps the lend.

A closure cannot store into a place lent to it a value that may observe
another place. Its `retains` clause cannot name an `inout` capture, because
the retained dependency would have to reach the lent place in the enclosing
function through the stored observation, which contracts do not follow. In
generic code this refuses `place = copy(value)` for a `T` whose values may be
observations.

The cost stays per function. The fact gains one field. The owner index files
each live set under its owner and under the first step of the observed path,
elements sharing one bucket, and the lends form a second index of the same
shape. A read of a field inspects only the lends of that field and of the
whole owner; a read of the whole owner inspects its lends; nothing is
inspected where the function holds no lend. So one read costs the live lends
overlapping its path times their facts, and n lends of n fields of one record
read n times cost linear time. There is no program-wide table.

A lend cannot yet be returned. A function that builds a counting adapter over
its own `inout` parameter and hands it back would need a caller-visible
clause saying that the result holds the lend; none exists, and such a program
is [O-Escapes].

A result that a generic operation says carries its callback holds the
callback's lend, even where the operation drops the callback before
returning. `fold`'s result carries `combine`, because `fold_inout` retains the
callback into its accumulator under `retains(accumulator: item, combine)`;
`find_map`, and `Option` and `Result` `map` and `and_then`, likewise carry their
callback into what they return. So `let kept = xs.fold(first,
inout [inout n] |sink acc, sink _x| { n += 1; acc })` keeps `n` lent until
`kept`'s last use when the accumulator's type is a type parameter, which could
hold the callback, so reading `n` before then is [O-Borrow]. A concrete
accumulator type that can hold no writer demotes the lend to a read, so there
`n` is readable while `kept` lives.

`Map`'s `merge`, `update`, `upsert` and `upsert_inout` say they retain their
callbacks into the map (`retains(self: …, transform)`), although none keeps
one. On a map whose value type can hold no writer the lend demotes to a read,
as above. Where the value type is a type parameter and the map is an `inout`
parameter, the retained lend would leave the function with the map, so
`fn bump[V: Discardable](inout m: Map[UInt64, V, A]) { &m.update(1,
inout [inout n] |sink v| { n += 1; v }) }` is refused with [O-Escapes], and the
next read of `n` with [O-Borrow]. Such a function gives the closure its own
state with a `sink` capture instead.

Narrowing these contracts
needs a way to say that a callback's result depends on its arguments and not
on the callback, and is left open.

## Alternatives considered

**Keep state in the terminal operation (the `_inout` terminals).** A callback
borrowed by `fold_inout` or `find_inout` stays with its caller, so its owned
captures are readable afterwards. It needs no language change, but it works
only where the stateful callback is the terminal. A counting `filter` whose
accepted items flow on into `map` and `collect` still had to be taken apart,
and a program wanting both a count and a collection had to be rewritten as a
loop.

**Read-only accessors for adapter parts and closure captures.** Methods such
as `source()` and `predicate()` on each adapter, and a borrowing `captures()`
on closures, would replace consumption with observation. They were rejected
because the path still spells the nesting, `collected.iterator.source()
.predicate().captures().inspected`, so it exposes the same representation
under nicer names and breaks the same way when the adapters are reordered.

**Allow writing through an `inout` capture under read invocation.** A closure
called for reading may be reached through several observations of it at
once, including one passed to its own body. If the body observed the lent
place and then called itself through that observation, the inner call could
write through the lend, and a reallocation would leave the outer frame's
observation dangling. Requiring `inout` or `sink` invocation makes
a writing call exclusive, which [N-Aliased] then checks at every call.
