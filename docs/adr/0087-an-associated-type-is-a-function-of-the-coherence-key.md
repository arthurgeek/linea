# 87. An associated type is a function of the coherence key

Status: Accepted — 2026-08-15

Extended by [0142](0142-construction-derives-expand-to-ordinary-source.md)
with associated selections from recursive written type bases.

## Context

A trait sometimes has to name a type its implementations choose. `Index` is the
case that forces it: `v[i]` yields an element, the element's type is the
container's to decide, and every signature the trait writes — the projection's
result, and every method a container gains later — is written in terms of it.

The generics design left one line of credit here: parameters alone, until a
case parameters cannot express. This is that case, and what makes it one is
that the element is not something a call site could supply. `Index[I]` takes
its index type from the caller — `Index[UInt64]`, `Index[Range[UInt64]]` and
`Index[FromEnd]` are three keys one container answers — while the element is
fixed the moment the container is. Write both as parameters and the two are
indistinguishable in the syntax and no longer distinguishable in the checker.

Coherence keys an implementation on `(trait, arguments, head)`, which the
compiler holds unique. That is what makes a written `Index[UInt64]` on `Grid`
the one row a bracket can reach. It is also what turns an extra parameter into
an ambiguity: `Index[UInt64, UInt8]` and `Index[UInt64, Bool]` for one `Grid`
are two distinct keys, so coherence admits both, and `g[0]` names neither
argument beyond the first. The mechanism that rules that out elsewhere is a
functional dependency — a declaration that one parameter determines another —
and this language does not have one and would be adding it here for a single
use.

The compiler already reads a trait member whose answer is a type: a trait's
braces hold `type Item`, an implementation's hold `type Item = UInt8`, and
`Self.Item` names what the implementation settled. What was missing is the
decision this record makes, and one spelling: inside the trait's own braces the
name stood for nothing, so the trait that declares the type could not write a
signature in terms of it without reaching back through `Self`.

## Decision

**A trait names a type its implementations choose by declaring it, not by
taking another parameter.** `type Elem` inside a trait declares a member whose
answer is a type; an implementation binds it, `type Elem = T`; and no call site
chooses it.

**It is a member with a type shape, not a category with rules of its own.** The
implementation that leaves it unbound leaves the hole a missing operation
leaves, and is refused by the impl-completeness rule; one that binds it twice is
refused as a duplicate name; and every other member of the implementation is
checked against the trait's signature under the binding, by the substitution
that already checks a member against a generic trait's parameters. So a member
declared `-> Elem` and supplied `-> UInt16` where `type Elem = UInt8` is
refused by the same signature-agreement rule that refuses a wrong `fn` result,
naming the type the implementation itself bound.

**Inside the trait's own braces the bare name is in scope**, and names that
declaration the way `Self` names the type an implementation is for. `-> Elem`
and `-> Self.Elem` are one signature written two ways, read the same way and
answered by the same implementation. Outside those braces the name is a member
and is reached through a head, which is what it already was.

**Uniqueness is inherited rather than enforced.** The binding is a function of
the key coherence already holds unique, so there is no second uniqueness rule
to write and nothing that could disagree with the first: `Index[UInt64]` for
`Grid` is one row, and one row settles `Elem` once.

## Consequences

**A trait may state a relationship between types, not just operations over
one.** `proj at(inout self: Self, i: I) -> Elem` says the container yields
elements of a type it chooses, and a generic body bounded on `Index` writes
`C.Elem` for it — the settled reference, resolved through the implementation
the bound's discharge names.

**A signature in the trait says what it means without `Self`.** That is the
whole of the spelling this record adds, and it is why the bare name is in scope
only inside those braces: everywhere else the name has a head, and a head is
what says which implementation answers.

**The element's type is not a knob a caller can turn.** A container answers one
element type per key, which is the property `v[i]` needs to have one meaning at
a site that writes no type at all.

## Alternatives considered

**An output parameter — `Index[I, E]` with `E` written on the head.** It
reintroduces exactly the ambiguity that constructor-headed coherence removed:
two implementations differing only in `E` are two legal keys, and a bracket
naming no `E` reaches whichever the lookup finds first. Ruling it out needs a
functional dependency, which is a language feature added for one trait, and
without one the failure is silent rather than diagnosed.

**Restate the element as a bound parameter at every caller** —
`fn head[C: Index[UInt64], E](read c: C) -> E`. Every signature that touches a
container then carries a parameter with exactly one valid answer, the caller
re-derives that answer at each of N sites, and nothing in the signature says
the two are related. The relationship is a fact about the implementation, so it
belongs beside the implementation.

**Let a trait's braces see nothing, and write `Self.Elem` throughout.** It
works and reads worse in the one place where there is no choice about which
implementation is meant: a trait declaring a type and unable to name it plainly
in the signature next to it is a head written to satisfy the checker rather
than the reader. Nothing else changes with the bare name in scope, because it
resolves to the same declaration through the same record.
