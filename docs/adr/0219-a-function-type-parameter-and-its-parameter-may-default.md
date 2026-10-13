# 219. A function type parameter and its parameter may default

Status: Accepted — 2026-10-08; extends
[0077](0077-arguments-match-by-name-and-evaluate-by-declaration.md),
[0215](0215-a-type-parameter-may-default-its-argument.md) and
[0217](0217-a-call-leaves-an-undetermined-parameter-to-its-types-default.md).

## Context

`http.listen_and_serve` came in two names. `listen_and_serve(address, handler,
parent, limits)` served a handler whose routes share nothing, and
`listen_and_serve_with_state(address, state, handler, parent, limits)` served
one that shares a state and returned it. They were one implementation: the
first called the second with `()`. A reader meets the second name only after
the first stops being enough, and the library had no way to say what a
reader wants, which is one call where `state` is an argument that may be left
out.

The language could not say that for three reasons, each a rule that holds for
a good reason elsewhere:

- [0215](0215-a-type-parameter-may-default-its-argument.md) gives a default to
  a struct, an enum or an alias only. A function's type arguments are settled
  by its call, and [0217](0217-a-call-leaves-an-undetermined-parameter-to-its-types-default.md)
  extended that to the members of an inherent implementation, never to a
  function's own parameters.
- [T-Default] refuses a default on a parameter whose type is a type parameter,
  because the constant has no type until a call settles one.
- [S-Default], from [0077](0077-arguments-match-by-name-and-evaluate-by-declaration.md),
  admits a default on `read` parameters only, on the argument that
  an unevaluated default cannot provide the obligation a `sink` or `inout`
  parameter hands over. A state is moved into the call, so it is `sink`.

## Decision

**A function's type parameter may write a default, a parameter typed by that
type parameter may default to a constant of the default type, and a `sink`
parameter may carry a default.**

```linea
pub fn listen_and_serve[
    H: Handler[S, P] + Observer + Release,
    S: Release = (),
    P: Allocator = mem.SystemAllocator,
](address: net.Address, sink handler: H, sink state: S = (), parent: P = .System, limits: Limits = standard_limits) -> Result[S, ListenAndServeError]
```

1. **A function's type parameter may write `= Type`**, with the trailing rule
   and the no-forward-reference rule of 0215. A trait's, an implementation's
   and a derive's parameters still may not.
2. **A parameter typed by exactly such a type parameter may default.** The
   default is a constant checked against the type parameter's default, by the
   rules [T-Default] already gives every default (constant, discardable,
   copyable parts).
3. **A call that nothing else settles takes the default.** After every
   argument, the expected type and the callbacks have had their chance, a
   type parameter of the callee that is still open takes its default. This is
   the fallback of 0217 applied to the callee's own parameters, and it is
   subject to the same guard: inside a declaration generic over an allocator,
   a defaulted allocator is [T-DefaultedAllocator], so the allocator is
   passed or written.
   A type parameter an unsuffixed literal alone would settle takes the default
   too, as `W { v = 5 }` is a `W[UInt8]` over `struct W[T = UInt8]`, so
   `two(5)` over `fn two[T = UInt8](sink a: T)` is a `UInt8`. A default that
   does not meet its parameter's bounds is [T-Bound] at the call that took it,
   and says the type came from the default. A trait method's signature writes
   the defaults; an implementation's member restating or adding one is
   [T-Impl], as for a parameter default.
4. **A default argument is a constant of the default type.** A call that
   settles the type parameter as another type and omits the argument is a
   [T-Mismatch]: `listen_and_serve(a, router)` over a `Router[App]` has no
   state to invent.
5. **A `sink` parameter may carry a default.** A default is a constant that
   owes nothing ([T-Default] refuses a type with an obligation), so a `sink`
   parameter takes it as it takes any argument. An `inout` parameter still may
   not: it needs the place the caller changes.

MIR lowering reads an omitted argument from the call's own signature, whose types
the checker has already settled, so the omitted argument has the type the
call settled for it, `()` in the example.

## Consequences

- `http.listen_and_serve(address, handler)` serves a stateless handler,
  `http.listen_and_serve(address, handler, state: app)` a stateful one, and
  `parent:` replaces the allocator. `listen_and_serve_with_state` is removed,
  with its callers migrated.
- The system allocator is the default of a library entry point only where the
  caller is not itself generic over an allocator, which the guard enforces.
- The default parameters are named at the call, which `[S-Args]` already
  requires after the first named argument.

## Alternatives considered

**Keep two names, `listen_and_serve` and `listen_and_serve_with_state`.**
Rejected: a name that exists only to compensate for a missing default is the
vocabulary 0217 removed from `Router`, and the stateful form is the one a
service grows into.

**Carry the state in the handler (`listen_and_serve(address,
http.with_state(app, router))`) and return the handler's output through an
associated type.** Rejected: it works without a language change, but the call
then needs a trait whose stateless case is a default implementation and
whose stateful case a second, and the state stops being a named argument the
call reads at a glance.

**Infer the type parameter from the default's own type**, with no `= Type` on
the type parameter. Rejected: the declaration would read `state: S = ()` with
nothing saying `S` is `()` when the argument is omitted; 0215's syntax says it
where a reader looks.

**Admit a `sink` default for a type parameter only.** Rejected: the reason a
default is refused on `sink` (an obligation a constant cannot carry) is
already refused by [T-Default] for every convention, so restricting by
parameter type adds a rule that excludes nothing the first does not.
