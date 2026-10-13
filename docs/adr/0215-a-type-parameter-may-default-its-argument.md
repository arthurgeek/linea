# 215. A type parameter may default its argument

Status: Accepted — 2026-10-07.
Supersedes [0206](0206-allocator-spelling-is-shortened-by-alias-never-by-default.md).
Extends [0098](0098-a-container-names-its-allocator-in-its-type.md) and
[0194](0194-an-alias-names-a-type-that-exists.md).

## Context

[0098](0098-a-container-names-its-allocator-in-its-type.md) made the allocator
a type parameter of every container that allocates.
[0206](0206-allocator-spelling-is-shortened-by-alias-never-by-default.md)
refused a default for it and chose aliases to shorten the written form. The
cost it recorded did not go away: 22 of 43 examples mentioned an allocator, a
program that used one allocator wrote `Vec[Str, mem.SystemAllocator]` in every
field, parameter and annotation, and the handler signature of an HTTP service
carried a type parameter for an allocator it never chose. A file-local alias
block repeated in every program, and the std alias module 0206 chose was still
unbuilt and had no agreed name.

The decision to allow a default was taken after weighing the alternatives
below. This record states the language rule, the guard that answers the
reviewer concern 0206 recorded, and what became of the alternatives.

## Decision

**A struct, an enum or an alias may give a trailing type parameter a default,
and a written type that omits the argument takes it.**

```linea
struct Vec[T, A: Allocator = SystemAllocator] { ... }

let names: Vec[Str] = Vec.open(mem.system())   // Vec[Str, mem.SystemAllocator]
```

The rules, defined in [T-ArgumentDefault] and [T-DefaultedAllocator] of the
semantics:

1. **Defaults trail.** A parameter without a default may not follow one with a
   default, so the arguments a written type must give are a prefix of the
   list. This is also the parameter-order rule for the library: the
   parameters a program chooses come first and the allocator last. `Router`,
   `Route` and `Handler` take the state first and the allocator last
   (`Router[S, P]`, `Route[S, P]`, `Handler[S, P]`), so `http.Router[App]` is
   the router over the system allocator.
2. **Only a type declaration declares one.** A function's type arguments are
   settled by its call, a trait's, an implementation's and a derive's by the
   head they key on; a default there would fill nothing. Trait parameters stay
   without defaults, which is why `Handler[S, P]` names both.
3. **A default names no parameter** of its own list, so it means the same type
   beside any argument that is written, and is read where the declaration is.
4. **An omitted argument is filled wherever a type is written**: annotations,
   fields, signatures, aliases, and the head of an inherent `impl`
   (`impl[T] Vec[T]` declares members of the system form). One routine settles
   a written type, so every position fills the same way. A path head such as
   `Vec.open(allocator)` does not write a type and keeps taking its arguments
   from the call ([0211](0211-a-generic-alias-heads-a-path-and-the-call-settles-its-parameters.md)).
5. **A trait implementation's head and a derive's head name every parameter.**
   The head key is the constructor applied to its own parameters, so an
   omitted argument would name no parameter and `impl[T] Trait for Vec[T]`
   would mean "the system form" under a key that stands for every `Vec`. It is
   [T-Bound], which now reads "takes 1 to 2 type arguments".
6. **Two spellings are one type.** `Vec[T]` and `Vec[T, SystemAllocator]` are
   one type and one implementation key: the written-type comparison coherence
   and derives read completes the shorter list with the defaults, and so does
   its hash, so `impl Trait[Vec[T]] for X` and the same with the argument
   written are [N-Duplicate].

### The guard

**Inside a declaration that declares an allocator parameter, a type written
without the argument of a defaulted allocator parameter is an error**
([T-DefaultedAllocator]). "Declares an allocator parameter" means any type
parameter bounded by `Allocator`, on the declaration or on the implementation
or trait it is a member of, written inline or in a `where` clause, naming
`Allocator` or a trait that requires it. The help says to write the parameter, or the
default out where the system allocator is meant.

This answers the first objection 0206 recorded. `fn f[A: Allocator](v: Vec[T,
A]) -> Vec[T]` would otherwise return a system vector from a function that
declares itself generic over where memory comes from, and a library would
harden into signatures that quietly exclude arena-backed values. A program
that declares no allocator parameter writes the short form freely, and a
library that does not write the allocator in a declaration generic over one
does not compile.

### `Answer` is dropped

`http.Answer[P]` was an alias for `Result[Response[P], Error[P]]`, added so a
handler signature could be written short. With the allocator defaulted the
explicit `fn health(inout _: (), request: http.Request) -> Result[http.Response,
http.Error]` is short, and it keeps the failure in the signature, so the alias
is deleted rather than kept as a second spelling.

## Consequences

- The parser keeps the default for the formatter, which prints it back;
  tree-sitter reads `= Type` after a parameter's bounds; hover on a binding
  shows the argument the default supplied, since the checker's type is the
  filled one.
- A diagnostic prints the expanded form (`Vec[Str, mem.SystemAllocator]`)
  after the code said `Vec[Str]`, and an arena-backed value mixed with a short
  form is a readable [T-Mismatch] naming both.
- `Vec`, `String`, `Map`, `mem.Handle`, `mem.Closure`, the two `Drain`s,
  `log.Logger`, `io.BufferedReader` and `io.BufferedWriter`, the `json` value
  and error types, and the `http` request, response, error, event, exchange,
  body-writer and router types default their allocator to
  `mem.SystemAllocator`. `Arena`, `SystemAllocator`, `RefusingAllocator`,
  `Buffer` and the types an allocator returns have none: they name a choice.
- [0191](0191-the-caller-chooses-every-allocator.md)'s survey rule is unchanged
  for non-test library code: a default is a declaration, and a function still
  receives its allocator as an argument. The default is a value-free type
  argument; no function gains a default allocator value, and construction names
  the allocator (`Vec.open(mem.system())`).
- A library handler generic over the allocator writes `P` in `Request[P]`,
  `Response[P]` and `Error[P]`; the guard says so when it does not.
- Cost: a written type with defaults reads each omitted default through the
  one routine that settles a type. Medians of three readings of the sweep
  dimensions that settle and compare written types, before and after, at 4n:
  nested alias implementations 89.6 and 89.8 ms, generic alias path heads
  108.6 and 107.4, coherence open arguments 48.4 and 47.3, implementations
  160.0 and 160.0, with slopes unchanged to the second decimal.

## Alternatives considered

**File-local aliases (0206's decision).** Every program repeats the same three
to five alias lines, each alias is a second name for a type the program does
not own, and the alias hides nothing. Kept as a feature for naming a domain
concept (`alias Rules = Vec[Rule]`), no longer needed for the allocator.

**A std alias module (`std.app`, `system` submodules).** The module 0206 chose
as Proposed. Rejected after the names were weighed: a module of aliases for
programs and not libraries is a grab-bag whose boundary nobody can state, it
needs its own convention to keep libraries from importing it, and it is still a
second spelling of every type it covers. The default puts the same short form
on the declaration.

**An erased allocator (Zig).** A container takes its allocator at each call and
the type does not name it. Rejected by
[0098](0098-a-container-names-its-allocator-in-its-type.md): the type is how a
`Vec` carries the proof that it releases to the allocator it came from.

**An implicit context (Odin).** A context value carries the current allocator.
Rejected: it is state a function reads without it appearing in the signature,
which is what 0191 refuses.

**A default without the guard.** The shape 0206 feared: `Vec[T]` in a library
signature means the system allocator by omission, and an arena-backed value
meets [T-Mismatch] far from the author. Rejected; the guard is the
difference between this record and Rust's `Vec<T, A = Global>`.

**Defaults on traits and implementations.** A trait's arguments are supplied by
each implementation and are part of the implementation key, so a default would
make `impl Handler[S] for X` and `impl Handler[S, SystemAllocator] for X` two
spellings of a key coherence compares by position. Not needed: the types that
carry an allocator are structs and enums, and `Handler` stays at two
arguments.

## Open

Whether a default may name an earlier parameter (`B = A`). The smallest rule is
that it may not, so a default means one type, and nothing asks for more.
