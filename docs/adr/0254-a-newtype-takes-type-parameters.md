# 254. A newtype takes type parameters

Status: Accepted — 2026-11-01. Extends
[0065](0065-a-phantom-type-parameter-is-declared.md) and
[0099](0099-a-phantom-parameter-carries-its-bound.md) to newtypes.

## Context

A newtype, `type Meters = UInt64`, is a distinct nominal type with its base's
representation. Until now it took no type parameters, so a value that is one
scalar but must be told apart by what it refers to had to be a struct:
`struct Id[phantom Of] { number: UInt64 }`. A struct is laid out in memory and
passed by address, so where the value crosses to C or to the runtime as a
plain integer, a struct cannot stand for it.

A typed raw address is such a value: the runtime hands a task's body an address as a
`UInt64`, and the function it calls must receive it as an address of the
body's type. It needs a newtype that names its element type.

## Decision

A newtype declares type parameters as a struct does:

```linea
@copyable
type Id[phantom Of] = UInt64

type Readings[T] = Option[T]
```

- **Instantiation.** `Id[Customer]` is a distinct type whose base is the
  declared base with the arguments substituted. It has that base's
  representation, so an `Id[Customer]` is held and passed as a `UInt64` is.
- **[T-Phantom].** A parameter the base does not name is declared `phantom`,
  as for a struct field or an enum variant. A phantom parameter carries its
  bound ([0099](0099-a-phantom-parameter-carries-its-bound.md)).
- **Construction.** `Id(42)` takes its type arguments from the type its context
  expects, as `.{ ... }` takes a struct's. A phantom parameter appears in no
  operand, so the operand cannot supply it, and a construction no context
  instantiates is refused by [T-Infer]. Patterns, `impl[T] Id[T]`, refinements
  and `opaque` apply as they do to a newtype without parameters; a refinement
  bounds every instantiation alike, since its base is an integer no parameter
  stands for.

## Consequences

- A scalar that names what it refers to costs nothing over the scalar, and
  crosses to C and the runtime as one.
- An instantiation read before its base is written, inside a generic body,
  writes its base first, as a structure's fields are written when first read.
- The formatter, the tree-sitter grammar and the guide accept the form.

## Alternatives considered

- **A struct with one field:** laid out in memory and passed by address, so it
  is not the integer a runtime callback receives.
- **Written arguments at the construction, `Id[Customer](42)`:** the callee of
  a call is an expression, where `Id[Customer]` reads as an index. Context
  already settles every construction a program needs, as it does for a
  struct's `.{ ... }`.
