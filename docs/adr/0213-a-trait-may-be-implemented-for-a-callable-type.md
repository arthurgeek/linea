# 213. A trait may be implemented for a callable type, keyed by its shape

Status: Accepted — 2026-10-07.
Extends [0081](0081-an-implementation-is-generic-over-its-head.md),
[0093](0093-two-implementations-that-could-answer-once-are-refused.md) and
[0148](0148-parameter-heads-match-complete-trait-keys.md).

## Context

A library that wants to accept "a function with whatever parameters it can
supply" had no way to say so. A callable bound infers a callback's result but
not its parameters, a bound on a type parameter cannot dispatch on the shape of
the function it is given, and a trait could be implemented only for a type that
some module declares. A callable type declares nothing, so `impl Trait for fn(..)`
was a parse error, and the one workaround, a trait with a method per arity, makes
the caller name the arity.

The constraint is the coherence rule. [0081](0081-an-implementation-is-generic-over-its-head.md)
keys an implementation on its head's constructor, [0148](0148-parameter-heads-match-complete-trait-keys.md)
matches complete trait keys, and [0093](0093-two-implementations-that-could-answer-once-are-refused.md)
refuses two implementations whose keys unify. A callable type has no constructor
declaration to key on, and one chain for every callable would make each
implementation compare against every other.

## Decision

**A structural callable type may head an implementation of a trait, written
after `for`, and coherence keys it by its shape.**

```linea
impl[S] Handle[S] for fn(inout state: S, input: UInt64) -> UInt64 { .. }
impl[S] Handle[S] for fn(input: UInt64) -> UInt64 { .. }
```

- **Shape.** The invocation and each parameter's convention, in order, packed
  into an exact 128-bit key, so two shapes never share one. A callable head
  names at most 60 parameters ([T-Impl] otherwise).
  Implementations of one trait at different shapes sit on different chains and
  never meet. The resolver reads the shape off the written type and the checker
  off the interned one through one routine, `node.CallableShape`.
- **Duplicates.** Two implementations of one trait at one shape and one
  argument list are [N-Duplicate], whatever types their signatures write, as two
  tuple heads of one arity are. `impl Tr for fn(x: UInt64) -> UInt64` beside
  `impl Tr for fn(x: UInt8) -> UInt8` is therefore refused, and so is a generic
  `impl[T] Tr for fn(x: T) -> T` beside a concrete one: a trait implemented for
  a callable type takes one implementation per shape, and a library that needs
  to treat parameter types differently writes a type parameter in that one
  implementation and a bound on it. Where the trait arguments differ, the ordinary
  overlap rule of 0093 decides by unifying the complete keys, so
  `impl[T] Handle[T] for fn(x: UInt64) -> UInt64` beside
  `impl Handle[Bool] for fn(x: UInt64) -> UInt64` is [T-Impl].
- **Ownership.** A callable type has no declaring module, so only the trait's
  own module may write the implementation ([M-Impl]), as for a parameter or
  borrow head. There is no inherent `impl` for a callable type.
- **Matching.** A function value implements the trait where its signature
  matches the written head exactly, contract included, binding the head's
  parameters. A function taking `read` where the head writes `inout`, or whose
  result promises another contract, does not match, and is refused at the use
  as an unmet bound naming the callable type.
- **Closures.** A closure's type is its own and matches no callable head;
  passing one is [T-Bound]. A library that accepts both keeps its callable
  bound for closures and a trait for named functions, as `http.Router` does
  with `route_raw` and `route`.
- **Parameters.** The implementation's type parameters are recovered from the
  head and the trait arguments like any other head's.
- **Tooling.** The grammar, the formatter, the outline and the dumps print the
  head as written. No new syntax node: the head is the existing callable type.

## Consequences

- A library writes one implementation per shape it supports by hand; nothing
  derives over a function's parameters, and variadic generics are not
  proposed. The cap is the library's, not the language's.
- Two same-shape implementations with disjoint parameter types cannot coexist;
  the one implementation takes a type parameter for the difference.
- The chain for a trait with a callable head is as long as its shapes, so a
  library with fourteen shapes does fourteen one-member chains, not one chain
  of fourteen. `zig build sweep -Drelease -Dsweep-filter=impl` and
  `-Dsweep-filter=coherence` read the same before and after.
- A handler that cannot be registered because its shape is not implemented is
  refused at the registration with a bound naming the whole callable type,
  which prints parameters by position.

## Alternatives considered

**Overlap by parameter types, so `fn(UInt64)` and `fn(UInt8)` coexist.** The
resolver's duplicate check is syntactic and runs before types are settled; it
compares a head's constructor and trait arguments, which is all a tuple or a
parameter head has. Telling two callable heads apart by their parameter types
would give the head's own types a second role beside the trait arguments, and
make every implementation's chain a unification against each other member
instead of a one-member lookup. The type parameter and bound above say the same
thing without it; reopen if a library cannot.

**One chain for all callables, overlap by unification alone.** What the spike
built. It compares every pair of a trait's implementations, N(N-1)/2 unifications,
for shapes that can never agree on their conventions.

**A trait per arity, chosen by the caller.** Moves the dispatch into every
call site, and a function cannot be generic over its own arity.

**A parameter-headed implementation bounded by a callable type.** Refused by
coherence: a callable bound is not structure, so it overlaps every callable
head beside it ([T-Impl]).

**Variadic generics or a derive over a function's parameters.** Packs,
expansion and a static fold for a handful of hand-written arities; a derive
attaches to a `struct`, `enum` or newtype and reflects over its components.
