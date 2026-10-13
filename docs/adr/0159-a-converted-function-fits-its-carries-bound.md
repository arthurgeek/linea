# 159. A converted function fits its `carries` bound

Status: Accepted — 2026-09-24. Extends
[0136](0136-callback-binders-are-local-to-the-implementation.md), superseding
its requirement that contextual conversion keep result dependency contracts
equal.

## Context

[ADR 0132](0132-callable-results-separate-types-from-dependencies.md) makes a
result's `carries` clause an upper bound: a function may depend on fewer sources
than it promises. Generic callable bound satisfaction already applied that
reading. A function carrying `carries(left)` met a bound
`F: fn(left: Str, right: Str) -> Str where carries(left, right)`.

Contextual conversion did not. ADR 0136 kept "result and dependency contracts"
among the requirements that stay exact, so the same function was
[T-Mismatch] as a value of the structural type
`fn(left: Str, right: Str) -> Str where carries(left, right)`. One question,
whether this function can stand where this signature is promised, had two
answers. It depended on whether the promise was a bound or a value's type.

The HTTP router met this directly. Its handler table has one structural type,
and each handler a program registers depends on fewer of its parameters than
that type allows.

## Decision

**Contextual conversion fits a function's `carries` effects within the
contextual type's, by the relation bound satisfaction uses.** The comparison
reads `callableContractsSatisfy`, the one routine for both. A converted function
may carry fewer sources and narrower paths than the contextual type promises.

Everything else ADR 0136 keeps exact stays exact:

- Retention contracts must match exactly: `retains` constrains the caller, not
  only the result.
- The invocation convention must match exactly. A `read` function does not
  convert to an `inout fn` value, though it satisfies such a bound.
- Parameter conventions, types, defaults, stable-address requirements and
  nested callable types must match.

MIR function-address verification uses the same contextual-conversion predicate,
so it accepts exactly what the checker converted.

## Consequences

- A table of function values has one type that states the widest dependency any
  entry may have. Each entry declares only its own.
- Code pointers are unchanged. A dependency contract has no runtime
  representation, and a caller of the wider type already assumes every carried
  source, so no wrapper is emitted.
- A typed structural value still does not convert to another structural type.
  This decision is about converting a named function or a noncapturing lambda.

## Alternatives considered

**Keep exact contract equality (ADR 0136's rule).** It lost because it gave a
second answer to a question bound satisfaction already answered. Every handler
would have had to spell the table's exact clause, including sources it never
uses, which misstates its own dependencies to every direct caller.

**Relax retention as well.** Rejected: a narrower `retains` changes what the
callee may store into its arguments, and a caller relying on the wider promise
would be wrong about aliasing, not merely conservative.
