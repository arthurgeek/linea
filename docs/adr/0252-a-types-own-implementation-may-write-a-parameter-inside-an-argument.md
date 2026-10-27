# 252. A type's own implementation may write a parameter inside an argument

Status: Accepted — 2026-10-27. Supersedes the head clause of
[0182](0182-a-types-own-implementation-may-fix-its-type-arguments.md); builds
§15 of [0250](0250-tasks-are-structured-through-linear-sessions.md).

## Context

[0182](0182-a-types-own-implementation-may-fix-its-type-arguments.md) let a
type's own implementation fix some of its type arguments, and required every
declared parameter to stand alone as one whole argument:
`impl[P] Router[P, ()]` was admitted, `impl[T] Pair[Option[T], UInt8]` was
[T-Impl]. It rejected arbitrary patterns because a parameter written twice
needs the receiver match to unify the two positions, and nothing needed a
parameter inside another type.

[0250](0250-tasks-are-structured-through-linear-sessions.md) §15 needs one. A
session endpoint `Chan[P, H]` offers `send` only while its protocol's next
step is a send, and the postfix form `c.send(v)` is a member of the block
whose head says so:

```linea
impl[T: Discardable, N: Protocol, H] Chan[Send[T, N], H] {
    fn send(sink self: Self, sink value: T) -> Chan[N, H] { ... }
}
```

`T` and `N` sit inside the protocol argument. Under 0182 this is [T-Impl], and
the only spelling left is a free function, `send(c, v)`, beside `close` and
`enter`, which are already postfix: `impl[H] Chan[End, H]` fixes an argument
to a type naming no parameter, and `impl[P, H] Chan[P, H]` writes its
parameters bare.

The one-sided match 0182 relied on never needed the restriction. Selecting a
member for a receiver binds the block's parameters by `bindKey`, a structural
walk of the head against the receiver that descends through nominal
arguments, tuples, arrays, observations and callable signatures, and records
each parameter at the first position it meets. A parameter written at one
position, at any depth, is read from that position and from nowhere else.
What made a pattern expensive was a second position, not a deep one.

## Decision

**The head rule.** A type's own implementation `impl[P1, …, Pn] C[A1, …, Am]`
writes each declared parameter `Pi` **exactly once** across the head's
arguments `A1 … Am`, at any depth. A parameter may stand wherever a type
stands inside an argument:

- as a whole argument, `Chan[P, H]`;
- as an argument of a named type at any depth, `Chan[Send[T, N], H]`;
- as a tuple's component, `Slot[(A, B)]`;
- as an array's element, `Slot[[T; 2]]`;
- as an observation's referent, `Slot[borrow T]`;
- as a callable type's parameter or result, `Slot[fn(a: A) -> R]`.

It may not stand in an array's length: a length is a constant expression, and
a type parameter is not a value. Every other argument position holds a type
naming no declared parameter, as 0182 already allowed.

**What "once" counts.** Every position at which the parameter's name stands
as a type inside the head's arguments: each of the forms above, and the base
of an associated-type selection, `T.Dual`. A parameter's bounds, the block's
`where` clause and its members are not the head and are not counted. So
`impl[T] Pair[T, T]`, `impl[T] Pair[Option[T], T]` and
`impl[T: Protocol] Pair[T, T.Dual]` each write `T` twice.

**Diagnostics.** A parameter written a second time is [T-Impl], reported at
the second position: `` `T` is written more than once in this
implementation's head ``. A parameter the head never writes, or writes only as
the base of a selection, is the [T-Impl] every implementation parameter
already answers to, `` implementation parameter `U` cannot be recovered from
its key ``: a projection cannot be inverted to find its subject, so `T.Dual`
alone settles no `T`.

**Receiver matching.** A member of the block is offered to a receiver whose
type, through any observations of it, the head matches. The match walks the
head and the receiver together: a nominal type matches the same declaration
and then each argument in turn, a tuple, an array (of the same length) and an
observation match their own form and then their parts, a callable matches the
same invocation and the same convention at each parameter and then each
parameter's type and the result, and a declared parameter matches whatever
stands at its position and records it. Nothing is unified: each parameter has
one position, so the first record is the only one. Any other type matches only
itself. The member's own signature is then checked against the receiver with
the parameters the head recorded, as every call to an inherent member already
is.

**Cost.** One walk of the head per candidate member, linear in the size of
the head as written, which is bounded by the type-nesting height
([0054](0054-the-bound-is-on-height-and-covers-written-types.md));
the receiver's matching part is walked at most once alongside it. The
candidates are the members the receiver's declaration has under the called
name, read from the chain the resolver keeps per declaration, so nothing is
sized by the program.

**Why coherence still holds.** 0182's argument is unchanged by depth: a member
name is declared once per constructor across all of a type's own
implementations ([N-Duplicate]), so two inherent blocks never offer two
members for one call and no call chooses between heads. `impl[P, H] Chan[P, H]`
with `enter` beside `impl[T, N, H] Chan[Send[T, N], H]` with `send` is
admitted; a second `enter` in the latter is [N-Duplicate] whatever its head.
Trait implementations keep their own rule: a receiver argument of a trait
implementation is still a bare parameter
([0148](0148-parameter-heads-match-complete-trait-keys.md)).

**A receiver the head refuses.** A postfix call that reaches a member only
through a block whose head does not match the receiver is
[T-UnknownOperation]: `` `Chan[Recv[UInt64, End]]` has no operation `send` ``,
with the head as written, `` `send` is declared for `Chan[Send[T, N]]` ``,
labelled at the block. A member whose head matches but whose first parameter
takes something else stays the [T-Mismatch] at that parameter.

## Consequences

- `c.send(v)`, `c.recv()`, `c.choose_left()`, `c.choose_right()` and
  `c.offer()` can be members of `Chan`, each in the block for its protocol
  step; the method a value offers follows its protocol state. Stage 4 of 0250
  writes them in `std`; until then a program writes its own endpoint type.
- The rule is general: `impl[T] Shelf[Option[T]] { fn take … }` gives
  `take` to every shelf of optional items, and only to those.
- A call on the wrong state names the state the member needs rather than a
  mismatch at `self`.
- The callable form of the match compares each parameter's convention, so a
  slot holding `fn(inout a: UInt8) -> UInt8` is not one
  `impl[A, R] Slot[fn(a: A) -> R]` declares anything for.
- Settling a callee's type parameters from a callable argument no longer
  requires the two contracts to agree. `fn(a: A) -> R` states `carries(a)`,
  which a function value over scalars does not, so a function value settled
  nothing and `A` fell to a literal's default; whether the contracts agree is
  asked by the conversion once the parameters are settled.

## Alternatives considered

**Keep 0182 and write session operations as free functions.** `send(c, v)`
works today. It splits one value's operations between two call forms by an
accident of where the parameters sit, and a reader looking for what an
endpoint can do next finds `close` and `enter` on the type and the rest
elsewhere.

**Arbitrary patterns, a parameter written more than once.** `Pair[T, T]` needs
the match to check that two positions agree, which for first-order types is
an equality test, but it also makes two heads of one type able to overlap in
ways a name check does not see, and the diagnostics for a receiver that
matches one position and not the other have to say which. Nothing needs it.

**A parameter through a projection, `Shelf[T.Dual]`.** A projection is not
injective, so the receiver does not determine `T`; admitting it needs a
search over implementations. Refused as unrecoverable, as for a trait
implementation.

**Overlap checking between inherent heads instead of unique names.** Two
blocks could each declare `send` for heads that never meet, `Chan[Send[…]]`
and `Chan[Recv[…]]`, with a disjointness check like a trait's. It buys
nothing session operations need, since each step has its own operation name,
and it would make a member's meaning depend on which blocks exist.
