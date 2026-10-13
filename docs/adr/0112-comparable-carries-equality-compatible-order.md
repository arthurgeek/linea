# 112. Comparable carries an equality-compatible order

Status: Accepted - 2026-09-04

Extends ADR 0082.

## Context

Structural lexicographic comparison must stop when a component pair is unequal
but incomparable. Advancing to a later component would be sound only if
`Comparable`'s inherited equality and order were unrelated, but then `<=` and
`>=` would not describe one partial order and substituting equal values could
change an ordering result.

IEEE NaN prevents requiring reflexive equality from every `Comparable` type.
It does not prevent requiring the remaining compatibility laws.

## Decision

For every `Comparable` type, inherited equality is symmetric and transitive,
is disjoint from `less`, and is substitutive for `less` on either side. Thus an
unequal pair for which neither direction is less is incomparable, and a
lexicographic comparison stops there. Equality need not be reflexive;
`Equivalent` remains the marker that adds reflexivity.

Structural `Comparable` compares enum case ordinals first, then same-case
components in declaration order. At each component it tests both less
directions and then equality. It advances only when the components are equal.

## Consequences

Structural partial order does not let a later component decide a pair an
earlier component made incomparable. `Float64` remains `Comparable` and not
`Ordered`: NaN satisfies the compatibility rules while remaining unequal to
itself and unordered.

## Alternatives considered

**Let later components break incomparability.** Rejected because the result
would depend on data after the first component that established the pair is not
related.

**Require reflexive equality from Comparable.** Rejected because it would
exclude IEEE floating-point comparison and collapse `Comparable` into
`Equivalent` for no operation that needs it.
