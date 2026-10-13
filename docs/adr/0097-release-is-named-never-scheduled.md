# 97. Release is named, never scheduled

Status: Superseded by
[0104](0104-release-is-optional-and-never-scheduled.md) - 2026-08-25.
Accepted 2026-08-20; extended
[0063](0063-disposal-is-scheduled-never-inserted.md).

## Context

A `Vec[T]` holding a Linear `T` must release each element when it is released,
and it cannot name `T`'s release without a trait to name it through. The
first-version bar (containers over a named allocator) reads that against
[0063](0063-disposal-is-scheduled-never-inserted.md) — disposal is scheduled
and never inserted — as a contradiction, and gates its container step on one of them giving
way:

> Rung 2 does not start until 0063 is either extended or superseded, with a
> record saying which mechanism owns "this value's release runs here" and how
> the other defers to it.

Neither has to give way. 0063 decides **who creates the disposal expression**,
not what an explicitly written one may do.

## Decision

**`Release` is an ordinary trait naming a consuming operation. Implementing it
changes nothing about ownership, scheduling, or `[O-Leak]`, and the compiler
learns nothing about it.**

```linea
pub trait Release {
    fn release(sink self: Self) -> ()
}
```

Three mechanisms, none reaching into another:

| | decides |
| --- | --- |
| the ownership checker | **whether** a value must be consumed |
| `Release` | **what** releasing it means |
| `defer` | **when** an explicitly written call runs |

That is the division the gate asked for.

### Why this is not implicit Drop

[0034](0034-ownership-is-positions-and-a-graph.md) rejects the destructor
because *"a destructor is code that runs where no one wrote any — which is
where the surprises are."* The test is authorship of the call site.

**The compiler never creates a release invocation. Every release invocation is
reached through an expression written in source, either directly by the
programmer or as ordinary behaviour of an explicitly written library
operation.**

The second clause carries the case this record is about. When `v.release()`
releases the elements `v` holds, the recursion was written by the library
author. An implicit drop's call site has no author: the compiler generates it
at a scope exit where no syntax exists.

The desugars are not a counterexample. `for x in xs` reaches
`Sequence.iterate` and `Iterator.next` without either appearing in the source,
but `for x in xs` **is** the site, and those calls are the meaning of syntax
the programmer wrote, exactly as `a + b` means an add. A disposal at a scope
exit is code at a point where nothing was written.

### What implementing it does not mean

Implementing `Release` does not make a value linear, does not oblige anyone to
consume it, and does not make it eligible for anything automatic. **The
implication runs from ownership to the obligation to release, never from
`Release` to ownership.**

A trait that made a value eligible for release at a scope exit would be the
implicit drop under another name, and 0034 and 0063 have each refused it once.

### Total, and built rather than granted

Every type participates in `Release`; where a type's universe is Free, its
implementation does nothing.

Totality is not a language guarantee and must not become one: a compiler
synthesising an implementation for every type would be knowing something about
this trait, which is the one thing it must not do. The library implements it
for what the library declares; a program implements it for its own types;
the first-version bar's derivation step derives
what is already total. A type with no implementation fails the bound where one
is required, as any unmet bound does.

Totality is what lets a container have one release implementation rather than
one per element universe, which would overlap and fail coherence.

## Consequences

**Rung 2's blocking open point is answered**, and nothing about 0063 changes.
`defer v.release()` schedules a written call by the rules 0063 already states.

**Every `Vec` is Linear**, because it owns a `Buffer`, whatever it holds
([0046](0046-the-universe-of-an-instantiation-is-computed.md),
[0051](0051-a-part-obliges-when-no-argument-can-remove-it.md)). The element's
universe changes what release *does*, never whether the container must be
released.

**Boilerplate until rung 3.** Most implementations are no-ops, and derivation
is already scheduled to retire them.

## Alternatives considered

**Superseding 0063 and admitting implicit release.** The ergonomic winner, and
what 0034 and 0063 have each already refused. Nothing has changed about why:
disposal a reader cannot see at the use site is disposal they stop reasoning
about, and implicit ordering becomes a rule every later feature must respect.
It is also unnecessary, which is what this record establishes.

**A container that releases elements through a compiler-known protocol.**
Whatever it were named, a protocol the compiler invokes is the destructor. The
trait here is invoked by written code and by nothing else.

**Leaving `Vec` unable to hold a Linear element.** The honest alternative if
the contradiction had been real. Rejected because rung 12's JSON document is a
tree of owned values in containers, so the answer must eventually be yes, and
the rungs between are shaped by it.

## Deliberately open

**Where `Release` lives.** `std.mem` holds `Buffer` and the allocator. The
prelude admits a name only where the syntax obliges a program to write it, and
nothing in the syntax names `Release` today.

**Whether release composes with `?`.** A release that can fail is a different
shape, and nothing yet needs one.
