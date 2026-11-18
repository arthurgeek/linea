# 289. A literal settles the one implementation its value fits

Status: Accepted — 2026-11-18. Supersedes the clause of
[0186](0186-a-type-reaches-the-operations-of-the-traits-it-implements.md)
that a literal argument several implementations answer takes its default type.

## Context

0186 fills a trait parameter a literal argument waits on from `Self`'s one
implementation of the trait, so `Money.from(1250)` converts from the integer
type `Money` implements `From` for. Where several implementations answer, it
let the literal take its default type, and recorded the cost: adding a second
implementation can change which body a literal argument runs, with no
diagnostic.

A type parameter bounded on one trait at several argument lists later gained a
rule of its own. Its generic body is checked where it is written, so the call
has to say which bound it means there: a literal fitting exactly one of the
lists, as [T-Literal] decides whether a type can hold its value, takes that
list's type; one fitting several is [N-Ambiguous]; one fitting none takes its
default type. So `s.scale(1)` under `S: Scale[UInt8] + Scale[Bool]` is a call
at `Scale[UInt8]`, while the same call on a concrete type implementing both
took `Int64` and was refused `K does not implement Scale[Int64]`. One call
answered two ways by whether `Self` is known through a bound or through its
implementations.

## Decision

**A literal argument several implementations answer settles the one its value
fits, for a concrete `Self` as for a bounded parameter.** The lists are the
ones `Self` implements the trait at: a parameter's bounds, a concrete type's
implementations. A literal fitting one of them takes its type; fitting several,
the call is [N-Ambiguous]; fitting none, or where an implementation leaves its
trait arguments open, the literal takes its default type and the call is held
to that list. One routine answers both, so the two cannot drift again.

## Consequences

- `Gauge {}.scale(1)` beside `Scale[UInt8]` and `Scale[Bool]` runs the `UInt8`
  body, and `Ruler {}.scale(300)` beside `Scale[UInt8]` and `Scale[UInt16]`
  the `UInt16` one, where both were refused.
- Adding an implementation no longer changes silently which body a literal
  runs: with only `impl Scale[UInt8]`, `m.scaled(2)` runs the `UInt8` body,
  and adding `impl Scale[Int64]` makes the call [N-Ambiguous] rather than a
  call at `Int64`. A program that relied on the default type with several
  implementations its literal fits is refused and names its type, as
  `m.scaled(Int64(2))`.
- A single implementation is unchanged: the literal takes its type whether it
  fits or not, and a value it cannot hold is [T-Literal].

## Alternatives considered

**Keep the default type for a concrete `Self`, and bring a bounded parameter
to it.** That would refuse `s.scale(300)` under `S: Scale[UInt8] +
Scale[UInt16]`, where only one bound can be meant, and keep the silent switch
0186 recorded.
