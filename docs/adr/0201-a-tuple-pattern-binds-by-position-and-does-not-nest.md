# 201. A tuple pattern binds by position wherever a struct pattern binds by name, and does not nest

Status: Accepted — 2026-10-04. The nesting clause and the lending-walk place
are superseded by [0224](0224-a-pattern-nests-wherever-a-binder-stands.md).

Extends [0129](0129-struct-destructuring-may-infer-its-type.md) and
[0147](0147-a-borrowed-let-pattern-reads-a-stable-place.md).

## Context

[S-Destructure] and [S-Match] admit whole-value patterns that bind names and
compare nothing, and refuse nesting and partial moves. A `for` binds one name.
A tuple is only useful if it can be taken apart where it arrives.

## Decision

**`(a, b)` is a pattern in `let`, `let read`, `match`, `match read`, every
`for` form and a lambda parameter.** It binds each
component by position to a name or `_`, must match the arity ([T-Arity]), and
consumes or lends the whole value. In a `match` over a tuple it is one
irrefutable arm: one tuple pattern or `_` covers the scrutinee
([T-Cover]), and an arm after either is [T-Unreachable].

A component bound to `_` is settled by nothing, so a linear one is [O-Leak],
reported by its component name.

A tuple pattern is not admitted inside a variant payload or another pattern.
A lambda parameter takes one, as `|(a, b)| a + b` ([S-Params]), and the
binders are locals of the lambda. A declaration parameter does not take one,
because its name is a label
([0177](0177-a-parameter-name-is-a-label-not-part-of-a-function-type.md)).

The checker records each binder's component in `Typing.field_names`, the
table struct patterns use, keyed by the binder token, so ownership and MIR
read one selection for both. `bindPatternFields` takes the two apart by
position or by name with one routine, told apart by whether the pattern names
fields. A pattern names no type, so no expectation flows from it into the
initialiser.

## Consequences

- In a lending walk, every binder of a tuple pattern takes the walk's
  conservative element place ([O-Lent]). A binder record holds one place step,
  not a path, so a component of an element cannot be named, and a program
  that writes one component through another binder is refused though it is
  safe. This is a limit of the one-step binder record, not a rule of tuples.
- `Some((a, b))` is written in two steps, a binding of the payload and a
  destructure of it.
- A layout is the declaration's: parts sit in positional order
  ([L-Layout]).

## Alternatives considered

**Nested patterns now.** A tuple inside a payload or a tuple needs a
pattern-walking routine in each of the checker, ownership, MIR, the resolver,
the formatter and the editor, and a binder record that names a path rather
than a step. That is a general pattern feature, and it gets its own design.

**Patterns on declaration parameters.** A call names its arguments by the
parameter's name ([0177](0177-a-parameter-name-is-a-label-not-part-of-a-function-type.md)),
so a pattern would leave a call nothing to name.

**A per-component place for lending walks.** It would lift the conservative
element place, but it makes the binder record a path and changes every
consumer of `binder_places`; the limit is recorded so a later design can lift
it for tuples and structs together.
