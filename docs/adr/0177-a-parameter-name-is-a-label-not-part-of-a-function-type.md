# 177. A parameter's name is a label, not part of a function type

Status: Accepted — 2026-09-26. Supersedes the clause of
[0136](0136-callback-binders-are-local-to-the-implementation.md) that labels are
part of structural callable type identity, with the positional conversion that
existed to bridge it. Extends
[0105](0105-callable-values-have-static-call-targets.md) and
[0176](0176-a-function-name-is-a-value-its-uses-instantiate.md).

## Context

A structural `fn` type carried its parameters' names. `fn(cents: UInt64) ->
UInt64` and `fn(amount: UInt64) -> UInt64` were two types, and a value of one
could not be stored, passed or returned where the other was written. 0136
patched the most visible case: a function's name, or a lambda, converted
positionally where a written type flowed into it. A value that already had a
type did not, so once [0176](0176-a-function-name-is-a-value-its-uses-instantiate.md)
made a function's name a value without a written type, binding it first could
do less than naming it in place:

```linea
takes(add_one)            // converts: `value` meets `x` by position
let f = add_one
takes(f)                  // [T-Mismatch]: `fn(value)` is not `fn(x)`
```

The same held for two fields, two `Vec` elements, or two arms of an `if` that
held functions naming a parameter differently: each disagreement was a type
error about a spelling nothing at run time can observe. Labels have no
representation: a `fn` value is one code pointer whatever its parameters are
called.

Swift met the same problem and removed argument labels from function types in
Swift 3 ([SE-0111](https://github.com/apple/swift-evolution/blob/main/proposals/0111-remove-arg-label-type-significance.md)),
for the reasons above: labels made types that behave identically unequal, and
every place a value flowed needed a rule for relabelling it.

## Decision

**A structural callable type's identity is its invocation convention, and, in
order, each parameter's convention, type, stable-address requirement and
default, followed by its result and its dependency contracts.** Parameter names
are not part of it. `fn(cents: UInt64) -> UInt64` and `fn(amount: UInt64) ->
UInt64` are one type; the pool interns them as one, and a contract that names a
parameter names it by position.

**Labels govern named calls, and come from where the callee was declared.**

- A call to a declaration uses the declaration's own names.
- A call through a parameter, a field or an annotated local uses the names of
  the type written there. A parameter typed by a type parameter with one
  callable bound uses the bound's names; a kept closure, `mem.Closure[S, A]`,
  uses the names written in `S`.
- A call through a local with no written type uses the names of what it was
  bound to: a function's, a lambda's, or another local's. A capture takes its
  source's.
- A call through a value nothing declared names for -- a call's result, an
  element read out of a collection -- passes its arguments by position.

The checker finds those names in the syntax that wrote them, through one
routine (`calleeLabels`), and matches named arguments against them. Nothing
downstream of the checker reads a parameter name from a type.

**A type is spelled without its parameters' names.** A message writes
`fn(read UInt8) -> UInt8`, and a contract naming a parameter writes its
position, `where carries(#1)`. Where a message suggests a type to write, it
spells the declaration's own names. Symbols are mangled without names, so one
signature has one symbol.

**No conversion remains for labels.** Where one exact structural callable type
flows into a function's name or a lambda, 0136's positional comparison still
decides whether it fits, now without anything to relabel; it and generic bound
satisfaction compare what identity compares, except that a converted function
may promise fewer dependencies than the interface allows
([0159](0159-a-converted-function-fits-its-carries-bound.md)).

## Consequences

- `let f = add_one; takes(f)` is accepted wherever `takes(add_one)` is, and two
  functions naming a parameter differently can share a field, a `Vec` or an `if`.
- A named call reads the labels its callee's declaration wrote, so renaming a
  parameter in a written `fn` type changes the calls through that value and
  nothing else.
- Messages that showed two signatures differing only in names no longer occur.
  A message that printed a signature now prints it without names, which is
  shorter and cannot quote a spelling the reader did not write at that site.
- The MIR verifier's exact type comparisons of code pointers are unchanged: two
  signatures that differ only in names are one type there too.

## Alternatives considered

**Keep labels in identity and convert at each use.** A conversion wherever an
exact callable type is expected makes `takes(f)` compile, but a value's type
still differs by spelling wherever no conversion runs: a `Vec[fn(cents)]` is
not a `Vec[fn(amount)]`, and a joined `if` needs one label set. Every consumer
of a code pointer, down to the MIR verifier, would learn the conversion.

**Remove labels altogether, so calls through values are positional.** Swift 3's
exact rule. Linea's named arguments and defaults through a value are how a
stored callback's call site stays readable, and the labels are available where
the value was declared, so a call through it keeps them.

**Keep the first spelling a type was interned with, for messages.** A message
would then quote parameter names from another declaration than the one the
reader is looking at.
