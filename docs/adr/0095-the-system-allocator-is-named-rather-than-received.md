# 95. The system allocator is named rather than received

Status: Accepted — 2026-08-20; supersedes
[0064](0064-heap-memory-is-a-linear-value-from-an-explicit-allocator.md)

## Context

[0064](0064-heap-memory-is-a-linear-value-from-an-explicit-allocator.md) said
an allocator is reached by being passed, and that there is **no global one, no
implicit one, and no way for a library type to acquire memory without its
caller supplying the means**. The library did not do that: `Buffer.alloc(size)`
called `linea_alloc` and reached the process heap on its own authority.

Closing that gap requires deciding what "reached by being passed" is worth,
because three different properties hide under it and only one of them is a
memory-safety property.

**Explicit allocation** — the call says which allocator it uses.

**Explicit propagation** — an allocator appears in the parameters of every
function that allocates, so a signature says whether allocation happens
beneath it.

**Capability restriction** — code cannot obtain an allocator at all unless
something hands it one.

0064's wording claims the third. Nothing in it argues for the third over the
first, because when it was written there was no allocator value to reason
about.

## Decision

**`mem.system()` is publicly reachable and answers a `Free` handle naming the
process's stateless allocation facility. Allocation is explicit at the
operation and is not capability-restricted.**

```linea
Buffer.alloc(mem.system(), size)
```

Any code may name the system allocator without receiving one. That is weaker
than 0064's sentence, and this record is what narrows it: **no implicit one**
stands, **no global one** does not.

### Why the narrowing is sound

Restricting who may name a **stateless** facility buys auditability, not memory
safety. The facility owns nothing that an allocation depends on: the storage
belongs to the `Buffer`, which is `linear`, and the handle is not its owner.

The three failures 0064 set out to refuse are unaffected, and are refused by
the rules it named, because none of them ever involved a handle:

| Failure | Refused by | What the handle contributes |
| --- | --- | --- |
| leak | `[O-Leak]` | nothing — a `Buffer` still owed at a scope end |
| double free | `[O-Move]` | nothing — freeing consumes; a second read is `moved` |
| use after free | `[O-Move]` | nothing — the same rule, the same place |

What a handle *could* refuse is a fourth failure — releasing storage through
the wrong allocator — and there is one allocator, so there is nothing to get
wrong yet.

### What is given up

A signature no longer says whether allocation happens beneath it. `fn parse(s:
Str) -> Ast` may allocate; nothing in its type objects. That is the property
this record trades away, and naming it here is the point: a later reader should
not have to rediscover that it was traded rather than overlooked.

### The parameter is the carrier, and the match is the dispatch

The parameter exists because 0064 requires the caller to supply the means. It
is the value through which the means is supplied -- not a label on the call and
not a note to a reader, which is what "explicit allocation" would amount to if
the argument were decorative.

`alloc` reads it:

```linea
match read a {
    System => ...,
}
```

One arm, because there is one facility. That is where the choice of facility is
answered, so a second facility is an arm rather than a change to the signature
or to any caller. Lent rather than taken, so a caller holding a handle may
allocate from it more than once.

What is deferred is not the parameter but its *polymorphism*: a trait over
facilities, an allocation carrying which facility released it, and `free`
dispatching on that. Those are rung 2's, and gated below.

`free` takes no handle. With one stateless facility a handle there could not
tell correct use from incorrect, so it would be a parameter that cannot be
wrong; what should decide its shape is what rung 2 makes the primitive.

### Not the allocator abstraction

`SystemAllocator` is the first concrete allocation facility, not the protocol
over facilities. A trait naming allocation and release participates in the
release semantics [0063](0063-disposal-is-scheduled-never-inserted.md) has
deliberately left open — it holds that the compiler never inserts a release
expression, while a container releasing what it holds is the compiler inserting
one — and the first-version bar (containers over a named allocator) therefore gates
that step on 0063 being extended or
superseded. Writing the trait here would settle that question by implication
while claiming to be about memory.

## Alternatives considered

**A handle threaded from `main`.** This is what 0064's sentence describes and
what Austral ships for capabilities generally: a linear root passed to the
entry point, with capabilities underivable ex nihilo. It was rejected on two
grounds. `main` is fixed at `main() -> UInt8` by
[0019](0019-entry-point-is-main-returning-u8.md), so it is a language change
rather than a library one; and every program would carry a parameter that
establishes no invariant, because the facility owns nothing an allocation
depends on. Austral is also evidence rather than a counterexample: it exempts
memory allocation from its own capability model, and capability-gated
allocation appears only in its future work.

**A second allocation facility now, to make the parameter dispatch.** Two
allocators would make the handle load-bearing and let a `Buffer` carry the
provenance its release needs. It is the right eventual shape and the wrong
thing to build here: it is rung 2's, and rung 2 is gated as above.

**Leaving 0064 as written and calling this compliance.** Rejected because it is
not true. The sentence says there is no global one, and `mem.system()` is
reachable from anywhere.

## The three properties, by rung

| | explicit | capability-restricted | polymorphic |
| --- | --- | --- | --- |
| 0064 as written | yes | yes | unstated |
| this rung | yes | no | no |
| rung 2 | yes | no | yes, gated on 0063 |

The middle column is what this record narrows, and the reason is that a
stateless facility owns nothing an allocation depends on. The right column is
what 0063 gates, and it is a different question with a different answer.

## What would reopen this

An allocator that represents authority worth restricting — one that owns
storage, or reaches something a caller should not reach on its own account.
At that point "who may name it" stops being an auditability question, and this
record is the one to supersede.
