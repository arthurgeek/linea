# 211. A generic alias heads a path, and the call settles its parameters

Status: Accepted — 2026-10-06.
Supersedes the path clause of
[0194](0194-an-alias-names-a-type-that-exists.md). Extends
[0206](0206-allocator-spelling-is-shortened-by-alias-never-by-default.md).

## Context

[0194](0194-an-alias-names-a-type-that-exists.md) made an alias the same type
as its target wherever a type is written, and let a non-generic alias head a
path: `Bytes.open(allocator)`. For a generic alias it said "a path gives a
generic alias no arguments, so it is refused by [T-Bound]", and the compiler
refused every `SysVec.open(..)` that way.

[0206](0206-allocator-spelling-is-shortened-by-alias-never-by-default.md)
chose the alias as the only way a program shortens an allocator, and the
alias that does the shortening is generic: `alias SysVec[T] = Vec[T,
mem.SystemAllocator]` fixes the allocator and leaves the element open. It
could be written as a type and not constructed through, which defeats the
shortening, and a bare declaration (`Vec.open(..)`) already infers the
parameters the alias would leave open. The refusal was the clause 0194 wrote
about a position nobody had yet needed, and the code of that clause was a
single resolver diagnostic.

## Decision

**A generic alias at the head of a path takes its parameters from the call,
exactly as the bare name of the declaration it names does for the
declaration's parameters, and what the alias writes in its target is fixed.**

```linea
alias SysVec[T] = Vec[T, mem.SystemAllocator]

var names: SysVec[Str] = SysVec.open(mem.system())
```

- The resolver reaches the declaration the alias's target is headed by, as it
  does for a non-generic alias, and reports nothing for a generic one.
- The checker reads the alias's type once (`aliasedType`, the one place an
  alias becomes a type) with the alias's own parameters open. A call through
  the alias asks the implementation which arguments that type applies. The
  positions the alias writes without its parameters seed the call's inference;
  the others wait for the call, as the bare declaration's would.
- Once the call has settled, `settleAliasHeading` matches each position the
  alias writes with its parameters against what the call produced, and refuses
  the call where the substituted position is not the type produced
  ([T-Mismatch]), so a parameter appearing twice is one type at both and a
  position written as `Option[T]` is not satisfied by a `UInt8`. The settled
  arguments are then held to the alias's own bounds through the list a
  written alias application already records ([T-Bound]).
- A variant through a generic alias (`Maybe.Some(3)`) is settled by the type
  expected where it is written, or by its payload, as `Option.Some(3)` is. The
  arguments the alias writes closed seed the payload's inference, so
  `Failing.Ok(3)` over `alias Failing[T] = Result[T, Int64]` needs no
  annotation, and the same routine holds the result to what the alias writes.
- A parameter nothing settles is [T-Infer], reported at the call as an
  unsettled `Vec.open()` is. It names the alias's parameter where the
  unsettled position is exactly one.
- A path writes no arguments: `SysVec[UInt8].open(..)` stays [N-NotAValue], as
  `Vec[UInt8].open(..)` is. The alias is not more permissive than its target.
- A named literal's head takes written arguments as the declaration's does: a
  bare generic head is [T-Bound] for an alias as for a structure, and
  `Labelled[UInt8] { .. }` is accepted. A pattern's head carries no
  arguments, and a generic alias heading it is held to what it writes, as a
  non-generic alias is: `let Fixed { a, b } = pair` with
  `alias Fixed[T] = Pair[T, UInt8]` refuses a `Pair[UInt16, UInt16]`
  ([T-Mismatch]).
- An `impl` or `derive` head through an alias stays [N-TypeAlias]. The reason
  in 0194 stands: an implementation is written against the declaration, which
  keys coherence and `opaque`.
- No parameter gains a default and nothing converts: the alias is the same type
  as its expansion, and a diagnostic prints the expanded type.

Tooling reads the same answers. Hover on the alias in a path head prints the
type it names with the alias's own parameters, completion after the dot lists
the named declaration's members, and rename and definition reach the alias
declaration and every written use through the resolver's own binding.

## Consequences

- No new rule name: the failures are [T-Infer], [T-Bound], [T-Mismatch] and
  [N-NotAValue].
- The alias's parameters on a path are open in the type recorded for the head
  (`Vec[T, SystemAllocator]`), which only tooling reads; nothing below the
  checker meets an alias.
- A parameter the alias writes inside a larger type (`Pair[Option[T], UInt8]`)
  is not seeded into the call's inference, only checked after it, and a
  report about such a position names the declaration's parameter.
- A bound the declaration refuses is reported once, at the call; the alias's
  own bound check does not repeat it.
- The path head's cost is one open read of the alias, shared with every
  written use, and one match per position of the alias's target, sized by the
  alias.

## Alternatives considered

**Keep refusing, and require `Vec[T, SystemAllocator].open(..)` in a path.**
It leaves the alias usable only where a type is written, which is the position
0194's own alternatives list rejected and the reason 0206's module of aliases
could not be built.

**Allow written arguments on a path head, `SysVec[UInt8].open(..)`.** It would
be the only path head that takes written arguments, so `Vec[UInt8].open(..)`
and `SysVec[UInt8].open(..)` would disagree about one rule. The element is
settled by the annotation, the parameter type or the result the call is used
as.

**Default type arguments instead of alias heads.** Ruled out by
[0206](0206-allocator-spelling-is-shortened-by-alias-never-by-default.md).

**Seed only, with no check after the call.** A parameter that appears twice, or
inside another type, would be checked at one position and ignored at the
other, so an alias would permit a type its own written form refuses.
