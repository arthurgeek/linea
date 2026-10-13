# 160. A postfix call reaches the type's own operation first

Status: Accepted — 2026-09-24. Extended by
[0186](0186-a-type-reaches-the-operations-of-the-traits-it-implements.md) and
[0187](0187-a-bound-brings-its-traits-operations-into-reach.md).

## Context

A postfix call `x.op()` reaches an operation the receiver's type declares in an
inherent `impl`, or one a visible trait the type satisfies declares with `Self`
first. [N-Ambiguous] refuses a postfix call two visible traits answer, because
a rule that silently picked one would let an import or a new bound change what
an existing call runs.

The checker applied the same refusal where one answer was the type's own
operation and the other a trait's. Nothing in the semantics said so. It came
up when `std.net` gave `Listener`, which has its own `accept` and `close`, an
implementation of `net.Acceptor` declaring the same two operations so that
`http.serve` could take any acceptor: every `listener.close()` in the module
declaring the trait became an error, and the only spellings left were
`Listener.close(listener)` or removing the type's own operations.

A first cut gave precedence to any inherent declaration of the name. That
over-reached in three ways the written form `Door.close(door)` never does: a
private `close` in another module displaced a public trait's `close` and ran
([M-Vis] refuses the written form); an operation declared in
`impl Box[UInt8]` displaced the trait's for a `Box[Bool]` and the call was
then refused for its receiver; and `fn close(code: UInt8)` inside `impl Door`
displaced `Shut.close` and the call was refused for passing a door. Each is
an operation the call could not take standing in the way of one it could.

## Decision

**A postfix call whose name is both an operation of the receiver's type that
the call could take and an operation of a visible trait it satisfies runs the
type's own operation.** The trait's operation is reached written out,
`Trait.op(x)`. The type's own operation counts only where the call could take
it: it is accessible from the call's module under [M-Vis], its `impl` applies
to the receiver's instantiation, and its first parameter takes the receiver.
An operation the call could not take does not stand in a trait's way; lookup
proceeds as if the type declared none. Two traits answering a name the type
does not declare itself remain [N-Ambiguous]. A receiver known only through a
bound, `[T: Trait]`, has no operations of its own, so a postfix call on it
reaches the trait's.

**The implementation that is shadowed is told so.** Where a trait
implementation for a type supplies an operation under a name the type declares
itself, and a postfix call written in the implementation's own module could
take the type's own, [N-Shadowed] warns once, at that member: postfix calls on
the type reach the type's own, and the trait's is reached as `Trait.op(x)`,
spelled as the header spelled the trait. It is a warning and does not stop the
build. An implementation for every type, `impl[T] Trait for T`, names no type
to ask, so it draws no warning even where a type it covers declares the name.

The rule is one routine. `Reach` enumerates the operations a receiver answers
to, admitting the type's own only under the three conditions above, and
`NameReach.reaches` says which of them a postfix call runs. The checker reads
it to settle a call, the warning reads it from the implementation's module,
and completion reads it both for the operations in scope and for the ones a
`use` would bring, so an item that keeps its dot is one the dot reaches.

## Consequences

- The type's own operation is declared with the type and reached without an
  import, so importing a trait or adding a bound can never change what an
  existing postfix call runs. The hazard [N-Ambiguous] exists to prevent does
  not arise.
- The postfix form reaches exactly the operations the written form is not
  refused for. A private member stays private, an operation for one
  instantiation answers for that instantiation, and an operation not taking
  the receiver is reached only as `Door.close(3)`. The receiver is held to
  the first parameter as the call passes it, so `peek(self: borrow Door)` is
  reached from a borrowed door and `open(self: Door)` is not, while a
  parameter reading `Self` reads the door through the observation.
- A call that reaches nothing, where the type declares the name but the call
  could not take it, is refused for that reason rather than as an operation
  the type lacks: [M-Vis], [T-Arity] or [T-Mismatch] at the parameter, the
  report the written form makes.
- A trait implementation that shares a name with the type's own operation
  compiles, and its author is told at the declaration that the postfix form
  does not reach it.
- A reader of `x.close()` who knows the type declares a `close` the call could
  take knows what runs without looking for traits in scope.
- Enumerating the type's own operations reads a chain the resolver keeps per
  declaration, and each candidate costs one structural match, so a program of
  many trait implementations pays the members it declares and not the members
  times the program's type names.

## Alternatives considered

**An ambiguity error, as for two traits.** What the checker did. It protects
against nothing: the type's own operation is not brought in by an import or a
bound, so a program's meaning cannot shift under it. It made a type unable to
implement a trait whose operations it already offers under the same names
without every call site in the trait's module writing the call out, which is
the shape a listener, a file or any resource gains once a trait abstracts it.

**The trait's operation wins.** Then declaring a trait implementation, or
adding an import that makes a trait visible, would change what an existing
`x.close()` runs, which is exactly the hazard [N-Ambiguous] exists to prevent,
and the type's own operation would become reachable only written out.

**Precedence for any inherent declaration of the name.** What the first cut
did. It let the postfix form reach operations the written form refuses, and
so turned a call the trait answered into an error, or into a private body
running from a module that cannot name it. The written form's conditions are
the ones a call is held to, so the postfix form is held to the same.

**No warning.** The precedence alone is silent about a trait operation the
postfix form will never reach on that type. An author who wrote the
implementation expecting `x.close()` to run it would learn otherwise only from
behaviour. The warning sits at the one declaration that can be renamed or
reached written out, which is where the decision is made.

**Warning at each shadowed call instead.** That would cover a blanket
implementation too, at the cost of one report per call on a type whose author
has already decided, and of a warning the implementation's author never sees.
The declaration is where the name was chosen, so that is where it is reported.
