# 217. A call leaves an undetermined parameter to its type's default

Status: Accepted — 2026-10-07; extends
[0215](0215-a-type-parameter-may-default-its-argument.md).

## Context

[0215](0215-a-type-parameter-may-default-its-argument.md) lets a written type
omit a defaulted argument, and keeps a path head such as `Router.new_in(...)`
out of that: the head writes no type, so its arguments come from the call.
That left a gap for a type whose first parameter has a sensible default and no
argument ever mentions it. `http.Router[S, P]` is the case. Its routes take a
state `S`, and a program with nothing to share wants `S = ()`:

```linea
var router = http.Router.new()
```

Nothing in that line says what `S` is, so the call was [T-Infer]. The library
answered with two constructors: `Router.new(allocator)` on `impl Router[(), P]`
for the stateless router and `Router.open(allocator)` on `impl Router[S, P]`
for the stateful one. Two names for one idea, chosen by whether the state type
was written, and the split could not be spelled with the single `new` and
`new_in` pair every other owning type uses.

## Decision

**A parameter of an implementation that nothing in a call determines takes the
default of the type parameter it stands alone for in the implementation's
head.**

```linea
struct Router[S = (), P: Allocator = SystemAllocator] { ... }

impl[S] Router[S] {
    pub fn new() -> Self { ... }
}

var stateless = http.Router.new()                    // Router[()]
var stateful: http.Router[App] = http.Router.new()   // the annotation settles S
```

The default is read after every argument, the expected type and the callbacks
have had their chance, so it never overrides a determined parameter. It fills
only a parameter the implementation's head writes as itself in a position whose
type parameter has a default. A parameter with no default, or one the head
writes inside a larger type, stays [T-Infer].

The fallback is the one routine that reads a default
(`defaultAt`), so a default means the same type in a written type and in a call.
The fallback is subject to the guard of
[0215](0215-a-type-parameter-may-default-its-argument.md): inside a declaration
generic over an allocator, a call whose allocator parameter only the default
would fix is [T-DefaultedAllocator], exactly as a written type that omits the
allocator is, and the allocator must be passed or written.

The fallback applies to the members of an inherent implementation. A member of
a trait implementation settles its parameters through the trait, so
`Box.make()` through `impl[T: Default] Make for Box[T]` stays [T-Infer] even
where `Box` defaults `T`.

A mismatch against a type that holds an argument a call took from its default
carries a note naming that call and the default, since nothing at the mismatch
says the argument was not written.
The note is given only where the default is the difference; a value moved into
another binding, or a mismatch that also has another source, gets no note,
because a missing note costs less than a wrong one.

## Consequences

- `Router` has one pair of constructors, `new()` and `new_in(allocator)`, and
  the state type is `()` unless the context names another.
- A program that wants an error where it forgot to name a state loses it for
  types that default that parameter. Only `Router` defaults a non-allocator
  parameter, and a stateless router is the intended reading of a bare
  constructor.
- The rule reads only the implementation's own head and the type's declared
  defaults, so it adds no work to a call that determines every parameter.

## Alternatives considered

**A third constructor name for the stateful router** (`Router.with_state()` or
keeping `open`). Rejected: `open` is reserved for constructors that can fail or
acquire a resource, and a name that exists only to compensate for a missing
default is the vocabulary the library was trying to remove.

**Stateless-only `impl Router[()]`.** Rejected: the stateful router would then
have no constructor of the same name, and `Router[App]` could not be written
without one.

**Requiring `var router: http.Router = http.Router.new()`.** Rejected: an
annotation that restates what the constructor already means is the ceremony
0215 removed for allocators.
