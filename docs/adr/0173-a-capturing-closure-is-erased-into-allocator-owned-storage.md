# 173. A capturing closure is erased into allocator-owned storage

Status: Accepted — 2026-09-26. Extends
[0098](0098-a-container-names-its-allocator-in-its-type.md),
[0105](0105-callable-values-have-static-call-targets.md),
[0130](0130-explicit-captures-use-inline-environments.md),
[0131](0131-closure-invocation-and-capture-ownership-are-independent.md),
[0132](0132-callable-results-separate-types-from-dependencies.md) and
[0158](0158-a-function-value-implements-release.md). Used by
[0154](0154-sockets-and-http-follow-go.md) for streamed bodies and router
handlers.
Extended by [0176](0176-a-function-name-is-a-value-its-uses-instantiate.md)
and [0180](0180-state-is-lent-down-through-every-handler.md).

## Context

A capturing closure has a type of its own, and its environment lives inline in
its value ([ADR 0130](0130-explicit-captures-use-inline-environments.md)). That
keeps calls direct and allocation-free, but two closures with different
captures have different types, so neither can be stored where a single type is
written: a struct field, a `mem.Vec` element, a response body. A structural
`fn` type is a code pointer and holds no environment, so converting a
capturing closure to one is [O-Capture].

The HTTP library met this twice. `http.stream` took a
`fn(inout body: BodyWriter[P])`, and a streamed body that needed state its
handler computed got it through `stream_with(request, state: UInt64, ...)`, a
stopgap for exactly one number. `Router.route` took a function value, so a
handler could not own application state. `Response[P, F]`, generic over the
body's closure type, is not an answer: the `Handler` trait fixes
`Response[P]`, and a router's table needs one handler type.

The user rule is that a caller always chooses the allocator, and
[ADR 0098](0098-a-container-names-its-allocator-in-its-type.md) makes a
container that owns memory name its allocator in its type.

## Decision

**`mem.Closure[S, A]` is a standard-library type holding a callable called as
`S` whose environment lives in bytes from allocator `A`.** `S` is a `fn` or
`inout fn` type; anything else, `sink fn` included, is [T-Bound].
`mem.Closure.open(allocator, callback)` moves the callback into bytes from the
allocator its caller names and answers `Result[Closure[S, A], Oom]`; a callback
with no size allocates nothing. There is no contextual conversion into
`Closure`, because nothing in a conversion names an allocator.

**Any callback callable as `S` converts:** a capturing or noncapturing lambda,
a function, a member of an implementation, an enum constructor, a function
value, a generic parameter with a fitting callable bound. `open` is written
`open[F: Release](allocator: A, sink callback: F)`, and the checker gives `F`
the closure's `S` as its callable bound, a requirement no written bound can
spell because `S` is a parameter of the implementation. Call inference reads
that bound once `S` is settled: by the closure type the call's context
expects, and only where the context leaves it open, by the callback's own
signature with its capture contracts left out. A lambda without context must
then write its parameter types. `S` must be a `fn` or `inout fn` type where
`open` is called; a type parameter is [T-Bound], because the callback's type
is erased there and nothing could check it against `S` afterwards.

**Ownership is the existing model.** Captures keep their conventions.
`open`'s contract `carries(.Ok: callback, allocator)` gives the closure the
callback's external dependencies and the allocator's, so a read capture keeps
pinning its owner. A call through the closure is checked as a call through a
callable bound whose signature is `S`: its result may carry what the closure
carries, through the callee contract root
([ADR 0132](0132-callable-results-separate-types-from-dependencies.md)), and
never borrows the closure's storage. `F: Release` is required, because once
its type is erased releasing it is the only operation left.

**Settlement follows the allocator, as it does for `Buffer[A]` and
`Vec[T, A]`.** `Closure` is declared affine, and its buffer's obligation makes
it linear where `A`'s buffers must be released, as over `mem.system()`. Over
an arena's handle the closure may be dropped with the arena. The obligations
the callback's captures carry are invisible in the erased type, so a callback
that must be released is refused ([T-Bound]) unless the closure is provably
linear: its type is linear and `A` names no type parameter an instantiation
could settle to an arena's handle. A callback erased through a generic
allocator must therefore be `Discardable`.

**Invocation is `fn` or `inout fn`.** A read closure is called `closure(args)`
and lends its environment; an `inout` one is called `&closure(args)` and may
change what it owns. A read callback satisfies an `inout` `S`. A consuming
`sink fn` closure is not provided: it would need a call that disposes the
storage without releasing what the body already consumed, and nothing that
uses closures needs a body that moves its captures out; an `inout` body can
exchange a capture out when it must.

**One representation.** A closure's fields are the code address it is entered
through, the code address that releases the stored callable, the stored
callable's address and length, and the optional buffer that owns those bytes.
The entry's type is `mem.ClosureEntry[S]`, which the compiler makes, for a
callable `S`, the signature `S` with two `UInt64` parameters appended: the
address and length. Every value on this path is honestly typed, so the MIR
verifier checks the entry's call like any indirect call.

Lowering generates two bodies per stored callable type, discovered where `open`
is instantiated: the **entry**, which takes `S`'s arguments and the address and
length, checks through a storage address at offset 0 that the length holds the
stored callable (the address is aligned because the buffer's allocation is),
and calls the stored callable — a capturing closure's body directly with its
environment's address, a function value through its loaded address — and the
**release**, which reads the stored callable out the same way and calls the
release the closure-release supplier already plans for it. A call through a
`Closure` reads its entry, address and length and makes one indirect call. No
pass, representation or MIR instruction is added.

## Consequences

- `http.stream` takes any `Discardable` callable fitting its body signature
  and erases it into the request's arena; `stream_with` is removed. A
  streamed body captures what its handler computed, but nothing that must be
  released: state of that kind is built in `request.allocator()`, where
  per-request state belongs. `Response[P]` stays affine, so a handler that
  fails after building one simply returns the error, and
  `var r = http.text(...)?; &r.set_header(...)?` needs no release.
  `Router.route` erases a `Discardable` route into the router's allocator. A
  route is called for reading, so its captures are fixed configuration; a
  count that changes lives in the state `http.with_state` lends it
  ([0180](0180-state-is-lent-down-through-every-handler.md)).
- A vector or a struct field can hold closures with different captures.
- A call through a closure is an indirect call to a generated entry, which
  calls the stored body directly; the backend can inline the second call. A
  function value stored in a closure costs eight bytes of storage, because its
  type does not name the function it holds. A function name that becomes a
  value of a type of its own, with no size, would be called directly from the
  entry and allocate nothing, as a noncapturing lambda does now.
- A closure is about sixty bytes: two code addresses, an address and length,
  and the buffer, which carries its allocator and obligation.
- A call's result may carry the closure's allocator's dependencies as well as
  its captures', because the closure's dependencies are one set.
- Generic higher-order code (`iter`, `Option.map`, `Vec.from_fn`) is unchanged
  and stays direct.

## Alternatives considered

**`Response[P, S]` monomorphised over the body's closure type.** The `Handler`
trait fixes `Response[P]`, a router's table needs one handler type, and every
handler would carry a response type of its own.

**Boxed trait objects in general (`dyn Trait`).** A larger feature than the
problem needs. The entry and release pair is a two-entry table, so a later
trait object can take this shape without changing it.

**Keep `stream_with(UInt64)`.** It carries one number and nothing a handler
owns; each further kind of state would need another variant.

**Contextual conversion into `Closure`, or every closure erased.** The
allocator cannot be supplied by context, and a hidden allocator breaks the
rule that the caller chooses it. Erasing every closure would allocate for the
calls generic code makes directly today.

**`Closure` always linear.** Sound, and it lets a closure in an arena own
what must be released. But a streamed body lives in the request's arena, so
every `Response` became linear: the ordinary handler that builds a response
and then adds a header with `?` leaked on that `?`, and every test reading a
response had to release it. Letting settlement follow the allocator keeps
the shape `Vec[T, A]` already has and costs only the refusal of a callback
that must be released in an arena, which the diagnostic names.

**Enter a capturing closure's body directly**, with an environment pointer
appended to `S`'s parameters, and forward only for function values. Two entry
shapes, and the body's environment type would differ from the one the call
passes, so the verifier would have to accept an address taken at a signature
the function does not have. One generated entry per stored callable keeps every
type honest.

**A vtable pointer instead of two code addresses.** It saves eight bytes and
needs static data with relocations in MIR, a representation this does not
otherwise need.

**Code addresses kept as `UInt64` bits.** It drops the verifier's code-pointer
provenance, which the typed entry keeps for no cost.

**A spelled bound, `F: S`.** Admitting a type parameter as a callable bound is
a language rule of its own; the one declaration that needs it is certified
instead, as `mem.Storage` and `mem.Slice` are.
