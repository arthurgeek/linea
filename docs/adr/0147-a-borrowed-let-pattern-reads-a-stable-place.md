# 147. A borrowed let pattern reads a stable place

Status: Accepted — 2026-09-22. Extends the destructuring statement of
[0129](0129-struct-destructuring-may-infer-its-type.md).

## Context

Reading one part of a newtype or struct without consuming it required a
single-arm `match read`, even when the pattern was irrefutable. The discount
example's `Email.address` wrote `match read self { Email(raw) => copy(raw) }`
for what is a borrowed destructuring. A consuming `let Email(raw) = self` moves
`self`, which an accessor taking a read parameter cannot do.

## Decision

**`let read Pattern = place` binds read-only lent binders to parts of an
existing stable place, with exactly the semantics `match read` gives the same
irrefutable pattern.** The marker belongs to the pattern, not to the
initializer: `read` is not an expression operator, and `= read expr` is not
accepted. The patterns are the irrefutable newtype and whole-struct patterns a
consuming `let` accepts, including named and inferred heads, renamed fields and
empty structures. Nested patterns, refutable enum patterns and `var read` are
refused.

The initializer must be a stable readable place, such as a binding, a
projection, an indexed element, or an observation's referent. A temporary is
[T-Lend]; no lifetime is extended to make one stable. Binders refer to the
selected place: scalars still snapshot in value positions, other duplication
still needs `copy`, and a binder grants neither mutation nor consumption. The
owner's move, release and conflicting mutation follow the existing last-use
rules, and an ignored part settles nothing.

The syntax has its own statement tag beside the consuming destructure, as
`match_read` has beside `match_`. The checker passes the initializer to the
shared newtype and struct pattern checks, which already serve `match read`.
Ownership lends through the same pattern-holder walk, and MIR aliases the
checked field selections. The lowering of an equivalent `let read` and
`match read` is identical.

## Alternatives considered

- **A read flag on the consuming destructure tag.** Rejected because an
  exhaustive switch over statements would compile without handling the new
  meaning. A distinct tag makes every consumer decide.
- **`let pattern = read expression`.** Rejected because `read` would become an
  expression-level operator whose meaning depends on its position, and nothing
  else in the language reads a value that way.
- **Extending a temporary's lifetime to the binders' scope.** Rejected because
  it introduces an implicit owner no source line names, and its settlement
  would be invisible.

## Consequences

Irrefutable borrowed access no longer needs a one-arm match. The rule adds no
second pattern checker, place selector or lending path. Diagnostics come from
the shared checks: opacity [M-Opaque], coverage, duplicates, arity, [T-Lend]
for temporaries and [O-Borrow] for conflicting owner use.
