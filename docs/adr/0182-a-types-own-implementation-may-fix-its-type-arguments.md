# 182. A type's own implementation may fix its type arguments

Status: Accepted — 2026-09-26. Partially supersedes
[0081](0081-an-implementation-is-generic-over-its-head.md): its head rule now
governs trait implementations only.

## Context

[0081](0081-an-implementation-is-generic-over-its-head.md) made an
implementation generic over its head, and required the head to be the
constructor applied to the implementation's own parameters, each once and in
order. Its reason was coherence: a trait is implemented once per constructor,
every consumer takes the one implementation it finds, and a head that is a
pattern (`Pair[T, UInt8]`) would put two implementations in reach of one type
with neither more specific.

The rule was written for every implementation, and a type's own
implementation met it without sharing the reason. `http.Router[P, S]` lends
its routes a state of type `S`, and a program with nothing to share wants
`Router.new(allocator)` to make a `Router[P, ()]`:

```linea
impl[P: mem.Allocator] Router[P, ()] {
    pub fn new(allocator: P) -> Self { ... }
}
```

was [T-Impl], and a `new` declared in `impl[P, S] Router[P, S]` leaves `S`
settled by nothing where the router is made. The only other spelling was a
free function, a second constructor under another name.

The semantics also described a spelling the compiler does not accept: a bare
head, `impl Cell { fn zero() -> Self[UInt8] }`, was said to name the generic
declaration, while the checker refuses `Cell` without its arguments there as
everywhere ([T-Bound]). The open question in the index asked whether to refuse
it, on the premise that it was the only spelling that worked. That premise no
longer holds: `impl[T] Cell[T]` answers `Cell.take(c)` through the type's
namespace, and `impl Cell[UInt8]` declares a member of one instantiation.

## Decision

**A type's own implementation applies its constructor to types.** Each
declared parameter stands alone as exactly one argument, and every other
argument is a type naming no declared parameter. `impl[P] Router[P, ()]` and
`impl[A] Pair[A, ()]` are admitted; `impl[T] Pair[T, T]`,
`impl[T] Pair[Option[T], UInt8]` and a parameter the head leaves out are
[T-Impl].

Its members belong to the instantiations the head matches. A receiver settles
each parameter from the one position it stands in, by the structural match
every call to an inherent member already makes; a receiver the head does not
match is not one of its instantiations, and passing one is [T-Mismatch]
against the head.

**Why coherence does not apply.** A member name is declared once per
constructor across all of a type's own implementations ([N-Duplicate]), so two
of them never offer two members for one call, and no call has to choose
between patterns. What 0081 protects is the uniqueness of a trait's answer for
a type; an inherent member has one answer by its name.

**A bare head on a generic type is refused.** `impl Cell { … }` supplies none
of `Cell`'s arguments and is [T-Bound], as the compiler already reports. The
semantics paragraph describing it as naming the declaration is corrected, and
the open question is closed: a type's own implementation writes its
parameters, fixes some arguments, or fixes all of them.

## Consequences

- `http.Router.new(allocator)` returns a `Router[P, ()]`, declared in
  `impl[P] Router[P, ()]`, beside `Router.open` in the family's
  implementation.
- A parameter is found where a name stands in a type's position in the head:
  an argument, the base of a selection, or a callable's parameter or result.
  That is where a bare name resolves to the parameter it spells, so the member
  half of `mem.SystemAllocator` is a different type even when a parameter is
  called `SystemAllocator`. The check reads the head's written types once per
  parameter.
- Trait implementations are unchanged: their heads are still the constructor
  applied to bare parameters, in order.

## Alternatives considered

**A free function**, `http.new_router(allocator)`. A second way to construct
one type, found under a different name from the type's own.

**Admit arbitrary patterns** (`Pair[T, T]`, `Pair[Option[T], U]`). They need
the receiver match to unify a parameter written twice or inside another
type, which is more than a position to read; nothing needs them yet.

**Keep the bare head and give it meaning.** A name that is a type in one head
and a template in another is a second reading of one spelling. The generic and
fixed heads say the same things explicitly.
