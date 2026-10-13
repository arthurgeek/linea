# 216. A carrier type supplies its signatures' default contract

Status: Accepted — 2026-10-07.
Supersedes the `where carries(request)` clause of
[0214](0214-a-route-takes-a-function-whose-parameters-name-its-inputs.md).

## Context

A signature that writes no contract clause is read by inference: one eligible
parameter is the source, no eligible parameter means an independent result, and
several mean [T-BorrowContract], with the candidates named
([0210](0210-receiver-wins-contract-inference-is-not-adopted.md) declined to
choose among them, because a guess loses on a bodyless signature and reads
worse where it is wrong).

[0214](0214-a-route-takes-a-function-whose-parameters-name-its-inputs.md) left
`where carries(request)` written on every handler that also takes an extractor
holding text, and counted it: 12 of the 23 handlers in the examples and the
guide wrote exactly that clause. It declined the rule that would remove it,
"among several eligible sources a `Request` parameter wins", for two reasons:
the language rule would name an http type, and 0210's reasons stand.

Both reasons are about a rule that picks *a particular type by name* or *a
parameter by position*. Neither applies to a rule keyed on a property the type
declares itself: the language names no library type, and the signature's
meaning is decided by its parameter types alone, not by its body.

## Decision

**A struct or an enum may mark itself a carrier, and where a signature that
writes no clause has several eligible sources, the one carrier among them
settles the choice: the contract is `where carries(that parameter)`.** The
carrier settles a choice among several dependency sources. It never overrides
a single inferred source, and never a lent place.

- **Spelling.** `@carrier struct Request[P: Allocator = mem.SystemAllocator] { .. }`.
  `carrier` is a closed attribute beside `opaque`, `linear`, `copyable` and
  `derive(..)`, written once, alone or in an `@(..)` group, and reserved like
  them. It declares what values of the type are: built from the type, they live
  as long as it does. It restates no ownership policy, so it combines with
  `linear` and `copyable`.
- **Where it applies.** A struct or an enum. On a function, an alias, a
  `type` that renames another, an implementation or any other declaration it is
  [S-Entry], as every attribute off a type declaration is; on a `type` it is
  [S-Entry] with a message that says a carrier is a struct or an enum, since the
  newtype's representation is another type's and the mark would be a claim about
  that other type. An alias is refused because it names a type that exists
  ([0194](0194-an-alias-names-a-type-that-exists.md)); a parameter written with
  the alias is checked against the declaration the alias reaches.
- **Which parameters count.** A parameter whose type, after alias expansion, is
  the carrier declaration or any instantiation of it (`Request[P]` for every `P`),
  with any convention: `read`, `inout` and `sink` all supply `carries`, which is
  an upper bound on the result's dependencies and permits all three
  ([T-BorrowContract]). Extractors, state and the other parameters do not.
- **Ordinary inference runs first.** One eligible source is that source,
  carrier or not; no eligible source is an independent result. Only an
  ambiguity reaches the carrier, and it settles it only if the carrier is
  among the eligible sources and no parameter other than the carrier lends a
  place the result observes: a result typed as a borrow of a parameter's type
  names its own provenance. A result that observes the carrier's own place
  settles to `borrows` of the carrier rather than `carries`. Otherwise the
  signature stays ambiguous and [T-BorrowContract] reports it.
- **When it applies.** Only when the signature writes **no** `where carries(..)`,
  `borrows(..)` or `retains(..)` clause, including an empty `carries()`; an
  explicit clause wins and is how a function states the exception. And only when
  a contract can apply: the result may carry dependencies, as for any
  inferred contract (`-> UInt8` stays independent).
- **A property of the signature.** The default is computed where a signature's
  contract is, so a bodyless declaration, a trait method, a function value and a
  callable head all read it. A handler that writes no clause is the same type as
  the one that writes `where carries(request)`, and meets the fourteen
  `http.Endpoint` heads.
- **Two carriers choose nothing.** With two or more carrier parameters there is
  no default and the existing rules apply. If that leaves the source ambiguous,
  [T-BorrowContract] says so in terms of carriers, naming each, and offers
  `where carries(..)` for each.
- **Provenance is not re-inferred.** The default is the signature's contract
  and the body is checked against it. A body that returns something from
  another parameter is [O-Escapes], exactly as with `where carries(request)`
  written; the report says the contract is the carrier default, names the
  parameter the value came from and the clause that would say so.
- **Heads stay as written.** The `Endpoint` implementations keep their
  `where carries(request)`: a callable head spells the shape it matches, and the
  clause there is the same contract the default would give.

The type supplies the common default; the function supplies the exceptional
provenance.

## Consequences

- `http.Request` is `@carrier`, and `where carries(request)` leaves every
  handler, guide program and example whose only clause was that one with the
  request as its only carrier. The clause stays where it names anything else.
- A signature's contract now depends on its parameter types' declarations, not
  only on their shapes: a type gaining `@carrier` changes the contract of every
  clause-less function taking it. The cost is one declaration lookup per
  parameter of a signature that writes no clause, bounded by the signature.
- A carrier whose values carry no dependencies has a default that is dropped
  from the callable's key like any dependency-free `carries`.
- `carrier` becomes a reserved word.
- The ambiguity diagnostic has a second wording, for signatures with several
  carriers.

## Alternatives considered

**Inferring the contract from the body.** Rejected by 0210's evidence and again
here: a bodyless signature has nothing to infer from, and a signature would mean
different things as its body changes.

**Naming `Request` in the language rule** ("a `Request` wins among eligible
sources"). The rejected form in 0214: it puts an http type in the language
rules. A declared mark moves the choice into the library.

**A trait, `impl Carrier for Request`.** A property of the type's meaning with
no methods and no implementation to look up; it would make every signature's
contract depend on implementation resolution, which runs after the signatures
are read.

**`@(carrier)` on `type` and alias.** A newtype's values are another type's
values and an alias is that type; marking either asserts something about a type
declared elsewhere.

**A default that applies with one carrier even where the clause is partly
written.** A written clause is the programmer saying where the result comes from;
adding a second source silently would make the clause an under-statement.

**Choosing the first of several carriers.** Position carries no meaning, and a
silent choice is 0210's receiver-wins again.
