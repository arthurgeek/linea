# 164. A trait implementation adopts its trait's contract

Status: Accepted — 2026-09-24. Extends
[0132](0132-callable-results-separate-types-from-dependencies.md) and
[0159](0159-a-converted-function-fits-its-carries-bound.md).

## Context

A function written without a `where` clause infers its result contract: the one
parameter that can reach the result is its source, and two such parameters are
[T-BorrowContract]. A member of `impl Trait for T` inferred the same way, even
though its trait signature already states the contract every call is checked
against.

That inference reads the implementing type. A handler whose state holds text
has a `self` that may carry dependencies, so a member of

```linea
trait Handler[P: mem.Allocator] {
    fn handle(self: Self, request: Request[P]) -> Result[Response[P], HttpError] where carries(.Ok: request)
}
```

found two sources and was refused, followed by an [O-Escapes] for a body
checked against the empty contract that stood in for the missing one. With a
stateless handler, inference found one source and inferred `carries(request)`,
which exceeds the trait's `.Ok` target and was refused as wider than the
signature. In both cases the application had to restate a clause the library
had already written, and the restatement said nothing the trait did not.

## Decision

**A member of a trait implementation that writes no clause adopts the contract
its trait signature declares.** The contract is the signature's as it was
normalised, written or inferred, with each source and destination rooted at
the member's parameter in the same position and spelled with the member's name
for it. The body is checked against that contract, and a result it does not
cover is [O-Escapes] with a label naming the trait signature.

- **A written clause keeps its meaning.** A member that writes one is checked
  against it, and it must still fit within the signature's promise
  ([T-BorrowContract]). It may promise less. Calls read the trait signature
  either way.
- **Every implementation of a trait adopts.** Ordinary and `default`
  implementations pair their members with signatures in one table, and a
  template's source members are paired from the resolver's plan; all three read
  the same routine. A template member and the members derived from it therefore
  answer alike.
- **Generic traits need no substitution.** A contract names parameter positions,
  fields and variant ordinals, never types, so the trait's parameters are read
  as the implementation's by position like the rest of the signature.
- **An undecided signature is reported once.** If the signature's own inference
  is ambiguous, or a clause it wrote is refused, that [T-BorrowContract] is the
  only error: the member adopts no contract and its body is not checked against
  one. The same holds for a function or closure whose own inference is
  ambiguous or whose clause is refused, and for a member that does not match
  its signature ([T-Impl]), whose adopted contract is written over other
  parameters or another result. Before this, each was also checked against an
  empty or partial contract and reported [O-Escapes] as well.
- **Inherent methods and free functions infer as before.** They have no
  signature to adopt from.

Adoption costs one lookup of the trait signature per implementation member,
and a copy of each contract that signature declares. A signature is built once:
the member that reaches it first builds it, and the walk over declarations does
not build it again.

One diagnostic spelling changes with this. A callable type written with
`where carries()`, whose sources would otherwise be inferred, is displayed with
that clause, so `fn(text: Str) -> Str where carries()` no longer reads as the
type `fn(text: Str) -> Str`, which infers `carries(text)`.

## Consequences

- A library trait is the one place a handler's contract is written. An
  application implements it with no clause, whatever its handler's state holds.
- A member adopting a contract wider than its body needs is checked against the
  wider promise. Nothing observable changes: calls already read the trait
  signature, and a contract is an upper bound.
- Standard-library implementations that restated their trait's clause drop it.

## Alternatives considered

**Infer per member (the previous rule).** It lost because the inference reads
the implementing type, which the trait cannot see. The same trait was
implementable by a stateless type and not by a stateful one, and a stateless
implementation inferred a whole-result contract that exceeded a trait promising
one variant. Either way the trait's clause was not enough.

**Require the member to restate the clause.** Rejected: the restatement carries
no information, since the member may not exceed the signature and calls read
the signature anyway. Every implementation would repeat the library's clause,
and a clause spelled slightly differently would become a new refusal.

**Adopt only when inference is ambiguous.** Rejected because it keeps two
answers to one question. A member with one eligible source would still infer,
and that inference is exactly what exceeded `carries(.Ok: request)` for a
stateless handler. Whether a member adopted would depend on the fields of the
implementing type rather than on what the member wrote.
