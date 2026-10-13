# 122. A traversal may read its receiver

Status: Accepted — 2026-09-08

## Context

A receiverless traversal can enumerate fixed positions, but a vector's current
length is a property of its value. The iteration policy belongs in Linea; a
compiler special case for Vec's length would make the library's representation
part of lowering.

## Decision

A traversal may declare one explicit read receiver:

```linea
trav positions(read self: Self) = UInt64(0)..copy(self.len)
```

The receiver uses the ordinary parameter representation and lexical binding
rules. Its written type is `Self`, settled to the implementation's type. It
cannot be `sink` or `inout`, has no default, and is the only parameter; these
constraints are [T-Lend]. As with ordinary parameters, omitting the `read`
keyword means `read`. Its name follows the ordinary unused-name rule. A
receiverless traversal remains the form for an expression
independent of the walked value.

The initializer is checked as an ownership body using the existing CFG builder.
Reading the receiver grants no ability to move a Linear part. Its resulting
iterator obeys the existing traversal restrictions.

A lending walk evaluates its head once. Lowering supplies that evaluated value
as the receiver when evaluating the traversal expression, then uses the same
head for projected places. It neither reconstructs the head nor duplicates the
source traversal policy. Resolver binding, typing, ownership and lowering each
consume the same explicit parameter rather than inventing a synthetic self.

## Consequences

Dynamic lengths and other read-only traversal policies are expressible by
library source. The formatter and editor grammar retain the receiver syntax.
No consuming iteration protocol, general reference type, or new ownership
control-flow construct is introduced. Receiver binding is indexed through
`Resolution.parametersOf`; lowering splices the walked value through that
record under the selected implementation's type substitution.

## Alternatives considered

Implicit self would require an invented binding with no source parameter for
existing parameter consumers to read. A Vec-specific compiler traversal would
encode a library field and growth invariant in lowering. A function returning
references would change the language's lifetime model. The explicit receiver
uses the smallest existing representation that states the needed dependency.
