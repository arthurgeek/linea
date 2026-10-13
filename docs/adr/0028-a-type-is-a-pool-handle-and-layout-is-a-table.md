# 28. A type is a pool handle, and layout is a table the module carries

Status: Accepted — 2026-07-26; the `[T-Payload]` clause superseded by [0030](0030-a-variant-carries-several-values.md); extended by [0102](0102-computation-and-storage-representations-are-separate.md)

## Context

Until a program could declare a type, `TypeId` was a closed enumeration of nine
values and every pass switched over it exhaustively. An enum declaration ends
that: the set of types is now a property of the program being compiled, and it
grows while the checker runs.

Payloads then end something else. A fieldless enum is a tag, and a tag fits a
machine word, so every value the compiler had ever handled was one word wide.
A variant that carries a value is not, and the backend has to know how wide a
slot to allocate and where inside it the payload begins.

That second question is the dangerous one. The backend cannot see names, the
syntax tree or the type pool — deliberately, because a backend that could ask
what a type *means* could answer differently from the checker, and a
disagreement between the two is a program that compiles and is wrong. But it
must now know something about types that it never needed before.

## Decision

**`TypeId` is a handle into a pool that grows during checking, with the
builtins at reserved indices.** A declared type lands past them, so a switch
written over the builtins still covers them and only its `else` sees a declared
one. The handle means the same thing in every pass that holds it, because the
pool is immutable once the checker returns it.

**Layout is computed from the pool by one function, and reaches the backend as
a table indexed by `TypeId`.** The module carries `layouts`, filled once by
lowering from the finished typing. The backend reads sizes and offsets from it
and has no other access to types at all.

The arrangement itself is deliberately dull. A tag occupies a full word rather
than the bits it needs; a payload begins immediately after it; a value is an
aggregate exactly when it does not fit a word. `Layout.isAggregate` is the
whole of what the rest of the compiler asks.

**One function answers, and both callers go through it.** The checker asks
mid-build — it needs to know whether a payload is itself an aggregate in order
to reject it — and lowering asks afterwards to fill the table. Two
implementations that could drift are the bug this prevents, so `Builder` and
`Typing` both call `layoutIn`.

## Consequences

The backend gained a fact about types and no ability to reason about them. It
can be wrong about a number in a table, which a test catches; it cannot be
wrong about the language, because there is no question about Linea it is in a
position to ask. That was the property worth protecting and it survived.

A value too wide for a register is held by address, and the two accessors that
read and write a slot are where that lives. Everything above them — a `let`, a
conditional's arms, the slot a loop breaks to, the join a `match` writes into —
was already going through them and needed no case of its own. The cost is that
a "value" in MIR now means one of two things depending on its type, and the
only thing keeping that straight is that nothing bypasses the two accessors.

Returning one is not a table lookup but a calling convention. An aggregate
returned by address hands the caller storage that ends with the call, and
`f(make(3), make(40))` read one buffer twice. QBE's aggregate return is what
copies it out, which means the emitted signature depends on the return type and
the `Mir` had to start carrying one.

A payload must fit a machine word, which [T-Payload] rejects. **Superseded by
[0030](0030-a-variant-carries-several-values.md):** the rule did not do this.
It waved through a payload that is its own type, which is the case that most
needed catching, and what replaces it checks the condition that actually stops
a layout rather than the shapes the algorithm could not describe. That is a real
restriction and it is stated in the semantics rather than left implicit,
because the layout as decided here would size a nested aggregate as a word and
read it as one — a wrong answer rather than a missing feature. Lifting it means
a general size-and-alignment algorithm, and `payloadOffset` already takes the
variant index so that a variant carrying several fields can place them
differently.

## Alternatives considered

**Pack the tag and payload into one word.** A `u8` payload and a small tag fit
in 64 bits with room to spare, and nothing about values, calls or returns would
have changed — no aggregates, no copies, no calling convention. It was rejected
because it does not extend: a variant carrying a `u64` cannot pack, so the
representation would have to be replaced rather than widened, and every pass
that had learned the packed form would have to unlearn it. It also makes the
layout unspeakable — there is no offset to name, so the layout table would not
exist and the backend would carry the shift-and-mask knowledge instead.

**Give the backend the type pool.** Then layout is computed where it is needed
and no table travels. Rejected because it is exactly the coupling the pass
boundary exists to prevent: with the pool in hand the backend can ask what a
type is, and a second implementation of any question the checker already
answers is a disagreement waiting to be found by a user.

**Compute layout once and store it in the pool.** A `Type` would carry its own
size. Rejected because the pool is built incrementally — an enum is entered
before its payloads are known, so a layout stored at entry would be wrong and a
layout stored later would need a second pass over the pool. Computing on demand
from the pool as it stands is correct at every moment, and the table is filled
from it when there is nothing left to change.

**Make every enum an aggregate, for uniformity.** One representation, no
predicate, no two meanings of "value". Rejected because it makes a fieldless
enum — which is a tag, and fits a register — travel through memory for nothing,
and would have rewritten the emitted code for every program in the corpus that
uses one. The predicate is one function and the uniformity was not worth what
it cost.
