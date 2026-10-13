# 107. A trailing where predicate constrains any open type expression

Status: Accepted - 2026-08-28

## Context

A bound in a generic parameter list constrains only that parameter. Generic
code can nevertheless depend on a type derived from one: an iterator operation
may need `I.Item: Free` while requiring `I: Iterator`, and replacing that
relationship with another independent parameter would lose the fact that the
implementation for `I` chooses `Item`.

Adding a projected-bound special case would give bound discharge, universe
checking, callable promises and diagnostics a second model. It would also leave
no general spelling for the next open type expression that needs a constraint.

## Decision

**A generic function, struct, enum, trait or implementation may carry a trailing
`where` clause.** A bodyless function or projection signature carries it at the
end. A clause is admitted wherever the declaration or an enclosing scope
provides an open type parameter.

Each comma-delimited predicate has a subject and one or more existing
requirements:

```linea
where I.Item: Free + Display, I: Iterator
```

The subject is any type expression that depends on an open parameter, including
an associated projection. A trait's implicit `Self` is open on the same terms;
an implementation's `Self` is open only where its head depends on an open
parameter. A concrete assertion such as `where UInt8: Free` is refused because
it constrains no generic declaration. Requirements retain the existing bound
grammar: named traits with arguments, exact structural callable types,
universes and `+` composition.

**A generic-list bound and a trailing predicate are one constraint model.** The
former is shorthand whose subject is its parameter. Both normalise into
per-declaration records containing a subject type expression and requirements.
Bound discharge, transitive promises, callable compatibility, universe checking
and diagnostics consume those records.

The complete constraint set is collected before projected subjects are
resolved, so predicate order has no meaning. A projection must be declared by a
bound in that set; no declaring bound is the existing unresolved-associated-name
diagnostic, and several possible declaring bounds are the existing ambiguity
diagnostic.

At an instantiation, substitution makes every subject concrete and the existing
bound checker asks whether it satisfies each requirement. An open declaration
passing a parameter or projection into another generic declaration must carry a
constraint that promises everything the callee requires.

An implementation's predicates decide which members of its generic family it
answers for. They do not distinguish overlapping implementations, rank
candidates or introduce specialisation. Coherence still decides whether at most
one implementation can answer; constraints decide whether that implementation
applies to the concrete member.

## Consequences

`I.Item: Free` can be stated without introducing an unrelated element parameter,
and the same syntax applies to `Self.Error` and future open type expressions.

The AST retains the written clause for formatting and tools. Resolution records
references on both sides. Type checking owns normalised constraint records;
instantiation substitutes them as part of the declaration it already
instantiates, and no later pass rechecks a bound.

Existing duplicate-bound, ambiguity and unsatisfied-bound behaviour applies.
`[T-Where]` is limited to declaration shape: a subject that depends on no open
parameter, or a clause with no open parameter in its declaration or enclosing
scope.

For one declaration, collection, subject resolution and checking are linear in
the number of subject nodes and requirements, apart from each requirement's
existing implementation lookup. Storage is per declaration and no predicate
causes a program-wide declaration scan.

## Alternatives considered

**Add a second parameter for every projected type.** Rejected because a caller
could choose a type other than the associated type its implementation settled,
turning one implementation-owned answer into two unrelated inputs.

**Permit only projected subjects.** Rejected because projection is the first use
and not the semantic boundary. The relevant property is dependence on an open
parameter, which also covers a parameter itself and nested open type
expressions.

**Treat `where UInt8: Free` as a compile-time assertion.** Rejected because it
constrains no generic declaration and gives declaration-bound syntax a second
purpose. A false assertion and an inapplicable generic constraint are different
questions.

**Use predicates to choose among overlapping implementations.** Rejected
because adding or removing an implementation elsewhere could change which body
a call reaches. Coherence remains independent of whether a particular bound is
satisfied.
