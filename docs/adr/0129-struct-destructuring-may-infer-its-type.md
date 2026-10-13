# 129. Struct destructuring may infer its type

Status: Accepted — 2026-09-10.

## Context

A whole-value destructuring binding repeats a struct name even when its
initializer already determines the complete type. Requiring that name also
forces callers to name an otherwise inferable generic instantiation's head.

## Decision

A struct destructuring binding may omit its type head:
`let { field, other: binding } = value`. The initializer determines the struct
type independently. A named head remains available to supply an expected type
to the initializer. Both spellings use the same struct-pattern representation;
an omitted head has no callee expression.

The existing checker resolves fields and records their types for both forms.
Every field must occur exactly once. Opaque visibility and whole-value
consumption are unchanged. Field aliases, shorthand and discards follow the
existing rules. Empty structs admit an empty field list. Neither nested
patterns nor partial moves are introduced.

## Consequences

Callers can consume an inferred struct without repeating its type name.
An untyped struct literal cannot acquire its type from a headless pattern.
Resolver and formatter handle an absent head; ownership and lowering continue
to consume the same checked pattern and field information.

## Alternatives considered

Inferring the struct declaration from field names would make representation
shape a type-selection mechanism and introduce ambiguity between unrelated
structs. Requiring a named head adds no information when the initializer
already establishes the type. A separate inferred-pattern node would duplicate
one field and consumption contract across two representations.
