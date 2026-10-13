# 161. A postfix call reaches an operation, never a field

Status: Accepted — 2026-09-24. Extended by
[0181](0181-a-call-may-name-its-type-arguments.md).

## Context

The semantics said a field takes precedence over both kinds of operation: in
`door.width()`, lookup found a field `width` first and called it, and
[N-NotCallable] refused the call unless the field held a callable value. The
operation `width` was reached only written out, `Door.width(door)`. No
decision record carried the rule; it was one sentence of the semantics.

The rule surprised the first person to meet it. A module sealing `Ticket`
with `@opaque` could not offer a public operation `seat` beside its field
`seat`: every `ticket.seat()` outside the module was refused with
[M-Opaque], as if the caller had written `ticket.seat` and read the sealed
field. The same rule kept `net.Address` from offering an operation named
after any of its fields, and made a type's author choose operation names
around its representation, which the type's braces were meant to keep apart
from its behaviour.

## Decision

**A call written `x.name(args)` reaches an operation named `name` and never a
field.** Which operation is ADR 0160's rule, unchanged: the type's own one
the call could take, otherwise the one a visible trait declares, and
[N-Ambiguous] where two traits answer. A selection that is not called,
`x.name`, reads the field. A field holding a callable value is called through
the selection in parentheses, `(x.name)(args)`, which makes the selection a
value before the call. Parentheses around the receiver alone, `(x).name()`,
leave the postfix form intact.

A postfix call reaching no operation is [T-UnknownOperation]. Where the type
has a field of the name that the call's module can read, the report says so,
and where the field holds a callable value the help spells
`(x.name)(...)`. A trait out of scope that declares the name is reported
under the same rule with the `use` that brings it in, since it is the same
finding: no operation the call can reach.

`typecheck.isPostfixCallee` is the one predicate for "this call is the
postfix form". The checker reads it to settle the call and ownership reads it
to decline guessing argument positions for a postfix call that reached
nothing. Everything after the checker — ownership, instance discovery,
lowering, the language server — reads the settled call and the recorded
postfix spelling rather than asking again.

## Consequences

- An operation is reachable in the postfix form whatever fields its type
  holds, sealed or not. `ticket.seat()` reaches a public `seat` from any
  module.
- A field can no longer change what an existing call runs. Adding a field
  named like an operation leaves every `x.op()` in place, as adding a trait
  implementation already does under ADR 0160.
- Calling a callable field takes parentheses, `(handler.run)(3)`. The
  standard library's adaptors (`Map`, `FilterMap`, `Filter`) call their
  stored functions this way.
- Completion offers a type's operations beside its fields even where the
  names coincide, since each is reached by its own spelling.
- The formatter already keeps parentheses as written, so `(x.name)()` is
  never rewritten into the postfix form.

## Alternatives considered

**The field wins.** What the semantics said. It made an operation
unreachable in the postfix form as soon as a field shared its name, and made
a sealed field block a public operation with an error about reading the
field, which is not what the caller wrote.

**An ambiguity error where both exist.** It would refuse `ticket.seat()`
instead of calling the only thing a call can mean, and every type would need
operation names distinct from its field names to be usable with a dot. A
field and an operation are not two answers to one question: one is read and
the other is called.

**The operation wins only where the field holds no callable value.** Then
whether `x.f()` runs an operation or a stored function would depend on the
field's type, which a generic field `f: T` leaves open until instantiation,
and changing a field's type would silently change what calls run. The
parenthesised form keeps the two readings apart in the source.
