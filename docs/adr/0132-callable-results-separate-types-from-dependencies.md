# 132. Callable results separate types from dependencies

Status: Accepted — 2026-09-11. Supersedes the source-clause spelling in
[0123](0123-observations-carry-owner-dependencies-through-callable-contracts.md)
and extends [0131](0131-closure-invocation-and-capture-ownership-are-independent.md)
with generic captured-result promises.

Extended by [0173](0173-a-capturing-closure-is-erased-into-allocator-owned-storage.md).

## Context

A borrowed result needs both a value type and a relationship to its source.
Adjacent type and contract tokens obscure their distinct jobs. Generic callbacks
also need to return references to captured external owners without exposing the
representation of their environments or borrowing the callback object itself.

## Decision

Callable source contracts follow `where`. Contracts and generic type predicates
share one comma-separated clause. A lambda introduces a result annotation with
`->`; its result type can be omitted when a contract follows:

```linea
[document] || -> borrow Document where borrows(document) { borrow document }
[document] || -> where borrows(document) { borrow document }
```

The verbs `borrows`, `carries`, and `retains` retain their meanings. Deliberate
scalar observations remain valid; ordinary scalar results use value snapshots.
There is no compatibility syntax for bare source clauses.

A generic callable requirement permits external dependencies already carried by
the callable, unless explicit `where carries()` promises independence. Typing
records this as a normalized callee source. Ownership propagates its value
facts, never its storage. Concrete closure bodies keep capture identities for
validation. Result sources are upper bounds; retention requirements stay exact.
Structural code-pointer type identity remains exact.

## Consequences

Generic wrappers and combinators preserve captured result dependencies through
ordinary contracts. A callback can end before its returned observation while
the external owner remains protected. Neither syntax nor generic compatibility
permits closure-owned storage to escape or introduces allocation or cleanup.

## Alternatives considered

**Rename `borrows` to `borrowing`.** Rejected because an access convention and a
result dependency are different facts; the three contract verbs form one family.

**Reject all scalar observations.** Rejected because a reference to scalar
storage differs from a scalar snapshot, including in generic collection access.

**Require an environment source annotation on every generic callback bound.**
Rejected because ordinary result-producing adapters must forward captured
external dependencies. Explicit independence remains available where required.
