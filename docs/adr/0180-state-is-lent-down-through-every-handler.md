# 180. The application's state is lent down through every handler

Status: Accepted — 2026-09-26. Extends
[0154](0154-sockets-and-http-follow-go.md),
[0173](0173-a-capturing-closure-is-erased-into-allocator-owned-storage.md) and
[0174](0174-logging-is-a-leveled-structured-logger-and-http-logs-through-middleware.md).
Extended by [0214](0214-a-route-takes-a-function-whose-parameters-name-its-inputs.md):
a handler that does not use the state leaves it out.

## Context

A web application shares state between its routes: a count, a cache, a
database connection, the logger every handler writes to. Its middleware needs
the same state: a request counter bumps it, an authentication layer looks a
token up in it.

A route is a `mem.Closure` kept in the router's allocator
([0173](0173-a-capturing-closure-is-erased-into-allocator-owned-storage.md)).
Each route owns its own captures, so captures cannot be shared between routes;
the router may keep them in an arena, so a capture holds nothing that must be
released, and a connection cannot be captured at all. A type implementing
`http.Handler` could hold state in `self`, but then it gets no routing, and a
middleware wrapping a router knows only that it holds some handler.

axum's `State` is the shape readers know: handlers and middleware are given
the application's state, and the application gives it once.

## Decision

**Every handler takes the state.** `http.Handler[P, S]` is

```linea
pub trait Handler[P: mem.Allocator, S] {
    fn serve_http(inout self: Self, inout state: S, request: Request[P]) -> Result[Response[P], Error[P]] where borrows(self), carries(request)
}
```

and a route has the same shape: any closure or function callable as
`fn(inout state: S, request: Request[P]) -> Result[Response[P], Error[P]] where carries(request)`.
Every layer -- a route, a `Router[P, S]`, a middleware -- takes `inout state`
and a middleware passes `&state` on with the request. A middleware that does
not use the state is generic over it, `impl[P, S, H: Handler[P, S]] Handler[P, S] for RequestIds[H]`;
one that does implements `Handler[P, App]` and reads or changes `state` before
passing it on.

**`http.with_state(state, handler)` owns the state at the top of the stack.**
It returns an `http.Stated[S, H]`, which implements `Handler[P, ()]` by
lending its own state to the handler it holds, passes events on through
`Observer`, and releases the state with itself, so a linear resource such as a
connection lives there. `stated.state()` reads the state back, such as a
count to log once serving stops. `serve` keeps its signature, requires
`H: Handler[P, ()] + Observer`, and lends `()`, so a program with nothing to
share serves a `Router[P, ()]` directly.

`inout` is sound without a lock because `serve` answers one request at a time:
while a handler runs it holds the only access to the state, and `self` and
the state are distinct places. The result may not view the state, which the
next request changes, and the signature grants no retention, so a route that
stores a view of its request in the state -- which outlives the request's
arena -- is [O-Escapes].

**A router is made for one state type.** `Router.new(allocator)` makes a
`Router[P, ()]`, declared in `impl[P] Router[P, ()]`
([0182](0182-a-types-own-implementation-may-fix-its-type-arguments.md)).
`Router.open(allocator)` makes a `Router[P, S]` whose `S` the context names,
as `mem.Vec.open` takes its element type: a stateful program writes
`var router: http.Router[mem.SystemAllocator, App] = http.Router.open(allocator)`,
because a local's type is not inferred from its later uses.

**A route's closure is called for reading.** The route type is a `fn`, not
an `inout fn`, so a closure that changes its captures is refused, with
messages that name the convention and say where a changing value belongs.
This divides the work between the two places a route finds a value:

- **The state holds whatever is shared or changes**: counters, caches,
  connections, the program's logger. It is given once, to `with_state`.
- **A capture holds fixed configuration for one route**: a limit, a message,
  a path prefix. It is kept in the router's allocator and captures nothing
  that must be released.

A value that changes between requests has one home.

**The examples keep the logger in the state.** Every route logs through it,
so it is shared: `http-json-echo` holds `App { logger, echoed }`, and the
streaming examples, whose only shared value is the logger, hold
`App { logger }`, which names the router `Router[P, App]` rather than spelling
the logger's type.

**Extractors compose with the state.** A handler is
`(inout app: App, request: Request[P])`. The state is not part of the
request, so it stays a parameter, and what is read from the request -- a
decoded body, a typed path value -- is read inside the handler, as
`request.extract[T]()` will be. Neither changes the other's signature.

## Consequences

- A stateless handler takes `inout _: ()`, one parameter more than a handler
  that takes only the request; a trait implementation names it `_state`,
  because it adopts the trait's parameter names.
- A route that only reads the state still takes it `inout`, because the
  parameter's convention is part of the route's type. A function taking the
  state by `read` is registered through a lambda,
  `|inout app, request| search(app, request)`.
- `Observer.observe` is not given the state. A middleware records what it
  wants per request in `serve_http`, before or after the handler it holds,
  with the state and the response in hand; only facts known after the answer
  is written -- bytes sent, a failed write, a retried accept -- reach
  `observe`. Giving it the state would cost more than it gives:
  `Observer[S]` loses `default impl[T] Observer for T`, because a default
  implementation applies only to a trait with no type parameters, so every
  handler would have to implement `Observer`; and a method generic over the
  state, `observe[P, S](inout self, inout state: S, …)`, cannot reach the
  fields of any particular state.
- A test calls a handler with a state it built, `&router.serve_http(&app, request)`,
  and reads what the handler changed from `app` afterwards.
- A state type that holds views -- a `Str` read from configuration, say --
  gives a route two eligible result sources, so such a route writes
  `where carries(request)`.
- **Concurrent serving needs a sharing rule, which this record does not
  supply.** `inout` is sound only while one request is answered at a time. A
  server answering requests in parallel must either give each worker its own
  state or share it behind a type that makes concurrent access safe; which,
  and how `with_state` expresses it, is decided when `serve` becomes
  concurrent.

## Alternatives considered

**Keep state in `inout` route closures.** State could not be shared between
routes, released, or seen by middleware, and a changing value would have two
homes.

**A router that owns the state** (`Router.with_state(allocator, state)`),
with middleware reading it through a trait that returns a `borrow`.
Middleware could only read it: a mutable place cannot be returned, so a
middleware that counts requests in the shared state could not be written, and
every middleware had to implement a forwarding trait beside `Handler`. Lending
the state down gives every layer the same access with the parameter it
already has.

**A mutable place reached through a projection**, `server[http.state]`, with
an `Index` implementation per middleware forwarding to the handler it holds.
It works, but a bracket on a key type is an odd way to reach application
state, and every middleware still needs a forwarding implementation.

**Reach the state through the request**, `request.state()`. A `Request` is a
copyable view of what the server read for the exchange; a mutable place
reached through a copy would let two copies change it at once.

**Shared ownership with a lock**, as axum pairs `State` with
`Arc<Mutex<_>>`. It answers concurrent access, which `serve` does not have,
and costs a lock on every request that sequential serving never contends.
