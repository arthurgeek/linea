# 214. A route is a function whose parameters name its inputs

Status: Accepted — 2026-10-07.
Refines [0185](0185-a-handler-reads-its-inputs-through-extractors.md), which
declined signature extractors as an alternative, and extends
[0180](0180-state-is-lent-down-through-every-handler.md). Builds on
[0213](0213-a-trait-may-be-implemented-for-a-callable-type.md) and
[0215](0215-a-type-parameter-may-default-its-argument.md).
Its `where carries(request)` clause is superseded by
[0216](0216-a-carrier-type-supplies-its-signatures-default-contract.md).

## Context

0185 left a handler reading each input with `request.extract[T]()?`, one line
per input, and listed four costs that kept the signature form out. Three have
since gone: with the allocator defaulted (0215) a program writes non-generic handlers, so a named
function is a value of a plain callable type; a callable type may head a trait
implementation (0213), so one `Endpoint` per shape routes it; and a type that
reads itself from a request makes the parameter's type the one the body wants.
The fourth, that a handler holding a view-holding extractor writes
`where carries(request)`, is measured below.

## Decision

**`Router.route` takes a named function whose parameters are an optional
leading `inout state`, up to six extractors, and the request last.**

- **Shapes.** `http.Endpoint[S, P]`, state first and allocator last as `Handler` and `Router` are (a trait takes no defaults), is implemented for fourteen callable shapes:
  with or without a leading `inout state: S`, and with zero to six `read`
  extractor parameters before the `request`. A function without `inout state`
  is registered on a router of any state. The request is last and required
  because the answer is built in its arena, and its name is fixed by the head's
  `carries(request)`.
- **Order and refusal.** Extractors are read left to right. The first refusal is
  the answer, its status and message identical to `request.extract[T]()?`, and
  later extractors never run. `defer let` schedules each extractor's release, so
  on every exit what was read is released, last first. Every extractor
  implements `Release`; `Path`, `Query` and `Form` derive it from their value.
- **Read-only.** An extractor is lent `read`. A handler that must own what it
  extracts, or act on a refusal, keeps `request.extract[T]()` in its body.
- **A type says how it is read.** A domain type implements `http.Extract`, as
  `impl http.Extract[mem.SystemAllocator] for Order { .. request.extract[http.Json[Order]]() }`,
  and the parameter is `order: Order`. A scalar has no source by type alone, so
  `http.Path[UInt64]`, `http.Query[T]` and `http.Form[T]` keep their wrapper and
  the body reads `.value`.
- **The closure form is `route_raw`.** A lambda's type is its own and matches no
  callable head, and a generic handler is not a value. `route_raw` registers a
  closure or function taking `inout state` and the request, as `route` did.
- **`where carries(request)` stays written.** The clause is required when the
  answer may borrow from an extractor as well as the request, which is every
  handler holding a `Str` or an owned text; a handler with neither writes none.
  The contract is part of the callable type, so a handler's clause must be the
  head's.

Census of the clause, by grep over `examples/` and the guide's chapter 9 after
the rewrite: the lines `^fn name(.. request: http.Request) -> Result[http.Response, http.Error]` number
23, one of them `calendar`, which `route_raw` registers; 12 of the 23 carry
`where carries(request)`, always that clause, and none wrote another source.
A guide program repeating an example's handler counts once for each place it
is written. That is a majority, and the rule that would remove
it, "among several eligible sources a `Request` parameter wins", names an
http type in a language rule or needs a library-neutral phrasing nobody has
designed, and 0210's reasons stand (worse diagnostics where the guess is wrong,
a silent contract on a bodyless signature). It is not adopted here. The clause
says aloud that the answer lives as long as the request. The census is the
evidence a later record would cite to reopen it.

## Consequences

- Every handler in the repository that was registered with `route` and took
  `inout state` and the request moved to `route_raw` unless it gained
  extractors; the examples, the guide and the standard library tests moved
  together.
- A refused registration names the callable type and says why. A parameter that
  implements no `Extract` is reported with the unmet bound for that parameter;
  a function of another shape, such as a seventh extractor, a missing request
  or a `sink` state, is told the parameter conventions `Endpoint` answers for;
  a stateful function on a router of another state is told which argument the
  function and the bound disagree on; a closure is told it matches no callable
  type; and a generic function named as a value gets only the [T-Infer] that
  says what its parameter is.
- A library handler generic over the allocator cannot be registered by name;
  libraries take `P` and programs do not.
- Fourteen implementations are written by hand in `std/http/endpoint.lin`.

## Alternatives considered

**Irrefutable patterns in declaration parameters,
`fn create(http.Json { value: order }: http.Json[Order], ..)`.** Keeps the source
visible in the signature and removes `.value`, but every pass learns a
parameter form and 0177's label rule is amended. Domain types covered the
common case; revisit if `.value` still hurts.

**An attribute marking the source, `@json order: Order`.** Attributes apply to
type declarations, and the callable type would carry no marker for the
endpoint to read.

**Delegating member access through the wrapper, or a deref-like conversion.**
A field lookup would depend on a wrapper's declaration, and a conversion
selected by the receiving position is the implicit conversion 0207 refuses.

**One `Endpoint` with an associated tuple of extractors, or a handler taking a
tuple of extractors.** The associated type must be recovered from the handler,
which Linea never does (0081, 0148), and a declaration parameter cannot be a
pattern.

**A parameter-headed implementation carrying closures beside the callable
heads.** Overlaps every callable head (0148), so closures keep a second method
name.

**Extractors owned by the handler (`sink`).** A second convention doubles the
shapes per extractor.

**Sub-state injection (`State[T]` from `Project`).** Deferred: a handler takes
`inout app` and reads the field until several handlers take it only to copy one
handle out.
