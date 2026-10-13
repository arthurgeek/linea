# 154. Sockets and HTTP follow Go's shape where ownership allows

Status: Accepted — 2026-09-24. Builds on
[0103](0103-linear-constrains-consumption-release-grants-one-way.md),
[0104](0104-release-is-optional-and-never-scheduled.md),
[0153](0153-an-inherent-impl-function-is-a-function-value.md),
[0157](0157-a-newtype-built-from-a-constant-is-a-constant-expression.md),
[0158](0158-a-function-value-implements-release.md),
[0160](0160-a-postfix-call-reaches-the-types-own-operation-first.md) and
[0162](0162-question-mark-converts-an-error-through-from.md).
Extended by [0180](0180-state-is-lent-down-through-every-handler.md).
Its subtree clause, that a path ending in `/` matches every path beneath it,
is superseded by [0220](0220-a-route-pattern-matches-its-own-path.md).

## Context

The bar set for the first public version asks for a program that listens on a socket and answers `curl`, and the claim
the bar settles is demonstrated on one program, `examples/http-json-echo/`. The
library it needs did not exist: no socket type, no request parser, no router.

Go's `net` and `net/http` are the model most readers already know: a listener
that accepts connections, a `Handler` interface, a router registered with
`"METHOD /path"` patterns, a response writer that streams, and a `Serve` loop.
Linea's ownership model changes what several of those pieces can be. A socket is
a resource owed a close, so it is linear; a value stored in a table cannot
borrow; a capturing lambda is not a function value; every value built from a
system allocation is owed a release; and every cost a pass or a library
routine pays must be bounded by what it is handed, not by everything
registered.

A handler that writes into a Go-shaped response writer paid for the last two
of those on every line: each value it built from `mem.system()` needed a
`release` or a `defer`, and a handler could not simply return what it
computed. Vapor, Hummingbird and axum return the response as a value instead.
A feasibility spike of 38 programs established what Linea needs for that shape
to compile with no clause in a handler: a request that is a copyable view of
data the server owns for the exchange, a response built in an arena the server
releases after writing it, and a signature whose result may carry the
request. This
record keeps the decisions and what they cost.

## Decision

**A listening socket and a connected socket are two types**, `net.Listener`
and `net.Connection`, both `@(opaque, linear)`. Accepting on a connection or
reading from a listener is a compile error, not a runtime failure. Each follows
`fs.File`: `close` consumes the handle and reports failure, `Release` makes one
best-effort close, and a path that does neither is [O-Leak].

**Accepting goes through a trait, `net.Acceptor`**, with `accept(inout self)`
and `close(sink self)`, as Go's `http.Serve` takes a `net.Listener` interface.
`Listener` implements it and has no inherent `close`, so a program writes
`use net.Acceptor` and then `listener.close()`. `http.serve` is generic over an
acceptor, so a test stands a scripted listener in for a socket to reach the
accept and close failures a real socket seldom produces.

**A TCP server that is not HTTP runs `net.serve`**, which accepts from any
acceptor and hands each connection and its peer address to a handler, one at a
time. The handler takes the connection `sink`, so the linear obligation to
close it stays with the code that reads it, and returns nothing: a handler
reports its own failures, and one failed connection never stops serving.
`serve` retries a reset or exhausted accept after a growing pause, the
schedule `http.serve` shares, stops with `ServeError.Accept` on any other
accept failure, and takes `connections: Option[UInt64]` as `http.Limits` does.
A handler that returns a Continue or Stop value was rejected: the count bounds
a test or example, and a server that must stop on a request exits its process.
Serving is sequential, because the language has no threads.

**One request is served per connection.** The response always sends
`Connection: close` and ends where the connection closes, so no length or
chunked framing is needed.

**The body is read before the handler runs**, bounded by `Limits`, and the
handler receives it as a borrowed slice. Go hands a handler an unread stream;
here that stream would be a resource inside a borrowed request, and a handler
that neither read nor closed it would leave the connection in an unknown state.

**A handler returns its response.** A handler is
`fn(request: Request[P]) -> Result[Response[P], Error[P]]`, generic over `P`,
the allocator each exchange's arena is carved from. `Request` is a copyable
view of what the server read for the exchange, the path values its router
matched and the exchange's arena; each accessor's result carries the request.
`http.text`, `http.json`, `http.status` and `http.stream` build a response from
the request, so a handler's inferred signature says its result carries the
request, and it writes no clause.

**Each request is served from an arena carved from the caller's allocator.**
`serve` takes a parent allocator and opens one `mem.Arena` of
`limits.request_arena_bytes` (5 MiB by default) over it for the serve loop,
which answers one connection at a time. Each request is read into it, the
handler builds its response in it through `request.allocator()`, the response
is written, and the arena is rewound. `Arena.rewind` zeroes the bytes the
exchange used, which keeps the rest of the slab zero, so a reservation is
handed out zeroed without clearing anything as it is bumped, and an exchange
pays for what it used rather than for the arena's size. An arena's buffers
carry no obligation, so a handler drops what it built and releases nothing.
A response kept past the arena is refused with [O-Borrow], and a handler that
stores a view of its request in its own state, which outlives the exchange,
is refused with [O-Escapes]. A parent that refuses the arena is answered 503
and the arena is opened again for the next connection; a request larger than
the arena, or a handler that fills it, is answered 500. The 503 discards the
unread request into a 4 KiB buffer `serve` takes from the parent once, before
accepting, and holds for the whole run, so the answer allocates nothing and
the client reads the 503 the observer reports rather than a reset. `serve`
refuses to start, with `ServeError.ArenaTooSmall`, when the arena cannot hold
every request the limits admit, and with `ServeError.Memory` when the parent
refuses that buffer. The floor adds up what reading such a request
reserves, each term an upper bound: the three 4 KiB buffers and the cursor,
the body at its exact length, the reader's line record (less than twice the
line limit), the head's text (four times one line limit per line, since it
grows by doubling and the arena keeps what it outgrew) and the table of header
ranges. A test serves a request at every limit in the smallest arena `serve`
accepts. The defaults need about 4.2 MiB, so the default arena is 5 MiB. A
smaller arena would answer 500 to requests the limits accept.

**A handler's error is a status and an optional message.** `Error[P]` holds a
status and a message rendered into the request's arena by
`http.error(request, status, message)`; `Error.new(status)` answers with the
reason phrase. It names `P` because a rendered message is owned by the arena:
`text.String[mem.Handle[P]]`. A view of that text keeping only the arena
handle would drop the parameter, and the language has no way to make one (see
*Path values stored in the arena* below); spelling the parameter away would
also hide it. `?` converts the library's own errors into the status that answers
them: a body that is not UTF-8, not JSON or not the expected shape is 400,
running out of memory, a refused header, a refused `Vec.push` or a failed
write is 500, and a `RequestError` answers its own status.

**A response's body is held or streamed.** A held body lives in the arena;
`http.bytes` answers with bytes already built there, without a copy. A
streamed body is written by any closure or function callable as
`inout fn(inout body: BodyWriter[P]) -> Result[(), Error[P]]` after the head is
sent, through the connection's 4 KiB buffer, so a body larger than the arena
goes out as it is produced. `http.stream` keeps it in the request's arena as a
`mem.Closure`
([ADR 0173](0173-a-capturing-closure-is-erased-into-allocator-owned-storage.md)),
so it captures what its handler computed, such as a checked year, and it reads
the request it answers through `body.request()`. The arena is dropped whole,
so the closure captures nothing that must be released, and a response stays
affine. The status and
headers are settled before it runs, so its error, or a failed write, resets
the connection, and the client reads an error rather than a short body that
looks whole; one line is logged. A `HEAD` request is answered with the head
alone, and a streamed body's closure is not run for it.

**A handler is lent the application's state.** `http.Handler[P, S]`'s
`serve_http(inout self, inout state: S, request) -> Result[Response[P], Error[P]] where borrows(self), carries(request)`
takes `inout self` and `inout state`, which is sound because the server is
sequential; `http.with_state` owns the state and lends it down, as
[0180](0180-state-is-lent-down-through-every-handler.md)
records. The result may borrow `self`, and not the state, because a `Router` keeps the names and decoded values
of the path values it matched in storage of its own, reused across requests,
and the request it hands its handler views them; `serve` writes the response
before `self` answers again. A type whose state holds no view implements the
trait without a clause. What happened to each exchange reaches the handler
through a separate trait, `http.Observer`, which every type implements by
ignoring it; [0174](0174-logging-is-a-leveled-structured-logger-and-http-logs-through-middleware.md)
records it and the middleware that logs through it.

**The server frames every response.** It sends `Connection: close` and no
length, and `text/plain; charset=utf-8` when the headers name no content type.
A header that could inject a line or reframe the response is refused with an
`http.HeaderError`, which `?` answers with 500.

**The most specific route answers, decided segment by segment from the left.**
A pattern is `[METHOD ]PATH`; a segment is a literal, `{name}`, or `{name...}`
(the remainder), and a path ending in `/` is a subtree. At the first segment
where two patterns differ, a literal comes before `{name}`, before `{name...}`,
before a subtree; at one shape, the request's own method comes before `GET` for
`HEAD`, before a pattern naming no method. The router holds the patterns in a
segment trie and searches it depth first in that order, backing out of a
branch that dead-ends or whose patterns name only other methods, so
`/items/{id}/edit` answers `/items/new/edit` beside `/items/new`. A path some
pattern matches only under other methods is answered 405 with `Allow` naming
them; no match is 404. Two patterns of the same shape and method are refused as
`Duplicate`, whatever their parameter names.

**`serve` stops after `limits.connections` connections** when that is
`.Some(n)`, and otherwise runs until the process ends, as Go's `Serve` does.
Tests and transcripts use the limit; the acceptance program exposes it as
`--requests`. A failure inside one connection is reported to the handler
through `http.Observer`, and serving continues; `serve` writes nothing to standard error of
its own (0174); a transient accept failure is retried after a pause that
doubles from 5 ms to one second; any other accept failure, or a failed close of
the listener, ends `serve` with `ServeError`.

**Every error the two modules report implements `Display`**, rendering its
reason, as the library's other errors do: `NetError`, `ServeError`,
`RouteError`, `RequestError`, `HeaderError` and `Error`. A program reports
`serve`'s failure with `io.eprintln("{error}")`.

**The exchange belongs to `serve`.** Reading a request and writing a response
are not public; `http.new_request` builds a request for a test to hand to a
handler, as Go's `httptest.NewRequest` does, and a test reads the response the
handler returns.

## Consequences

The acceptance program is under 200 lines, its handlers are plain functions
that return their answers and release nothing, and its tests call them
directly. The variant that returns early without closing its listener is
refused with [O-Leak]
(`tests/ownership/a_listener_left_open_on_one_path_is_refused.lin`).
`examples/calendar-export/` streams a year of dates as CSV.

Serving acquires the arena and a 4 KiB buffer for a 503's discarded input
from the parent allocator once each and disposes them once, whatever the
handlers do; a refused arena adds a second acquisition of the arena. Inside an
exchange every allocation is a bump of the arena's cursor, and rewinding
zeroes only the bytes the exchange used. The slab is zeroed once when
acquired, as every buffer is, and that is a real cost: `calloc` of 4 MiB
clears it eagerly on macOS, and on glibc once freed heap is reused. Measured
over 10,000 `GET /health` requests, an arena per exchange cost about 42 µs of
CPU per request at 4 MiB; one arena rewound per exchange costs about 5 µs. A
router stores the path values of each request in buffers it keeps and clears,
so a pattern with values allocates only while those buffers grow.

A handler cannot stream a large upload: the body is bounded by
`max_body_bytes` (1 MiB by default) and held in memory before the handler runs.
A client sending a body past the limit is answered 413 without the body being
read, and the server then discards up to 64 KiB of what is still arriving so
closing the socket does not reset the connection before the client reads the
answer.

One request per connection costs a TCP handshake per request. Keep-alive is out
of scope; it adds no type when it arrives, because the server already frames
every response.

Routing cost is bounded by the patterns sharing the request's prefix, not by
all registered patterns, and registration adds at most one node per pattern
segment. The price of that bound is that two overlapping patterns neither of
which Go would call more specific (`/a/{x}` and `/{y}/b`) are both accepted,
and the left-to-right order decides between them: `/a/b` is answered by
`/a/{x}`.

Handlers are written generic over the allocator. A handler registered with `route` may
be a closure, called for reading, whose captures are fixed configuration for
its route; what changes between requests lives in the state `http.with_state`
lends. A handler type whose own fields hold views has two sources for its
result, so its implementation writes the trait's clause until an
implementation adopts its trait's contract. A streamed body gets its
state from the request it answers and from what its closure captured. A
generic body type, `Response[P, F]`, was not an option: the `Handler` trait
fixes the response as `Response[P]`.

`Response.recorded_body()` runs a streamed body into the request's arena so a
test reads it. The `BodyWriter` holds its output as an enum, a connection's
buffer or recorded bytes, and a write takes the output out and puts it back.
There is no `match inout` to write through the payload in place, and putting
a value back over a place just set to the payload-free `Taken` is refused with
[O-Leak] (ownership does not track which variant the place holds), so the put
goes through a checked exchange that panics if the place was not `Taken`: a
runtime check where the language could prove the place empty.

`calendar-export` pads its dates with zeros by hand; format specifications
such as `{day:02}` are another task's, and the example adopts them then.

## Alternatives considered

**One socket type.** Smaller, and closer to the file descriptor underneath. It
turns `accept` on a connected socket and `read` on a listener into runtime
failures, which is the trade the rest of the language refuses.

**Keep-alive.** Serving several requests per connection needs response framing
by `Content-Length` or chunked encoding, a rule for reading the next request
after a handler that did not read its body, and idle timeouts. That bar
asks for a request parsed and a response written; none of that serves it.

**Go-shaped handlers**, `fn(inout response: ResponseWriter, request) ->
Result[(), HandlerError]`, writing into a response writer that streams.
Streaming every body is Go's default, and it made a handler's error only a
status, so no clause was needed. It cost a release or a `defer` for every value
a handler built from a system allocator, a response that could not be returned
or tested as a value, and header changes that could fail after the head was
sent. Returning the response keeps streaming as one kind of body.

**An owning request**, holding its text and body itself. A handler returning a
view of it needs `borrows(request)`, which no inferred signature says, so every
handler would carry a clause; a request copied into the handler's result
doubles the text. A view of data the server owns needs neither.

**An arena per exchange.** Opening a `mem.Arena` over the parent for every
connection and releasing it after the response acquires and zeroes the whole
slab each time, about 42 µs of a 4 MiB `calloc` per request, whatever the
request used. The server answers one connection at a time, so one arena
rewound after each exchange serves the same purpose for what each exchange
uses.

**Zeroing each reservation as it is handed out.** The arena could take an
unzeroed slab and clear each reservation as it bumps the cursor, which also
costs what an exchange uses. Rewinding clears the used prefix in one pass at a
point where nothing can observe the arena, and leaves the allocation path and
the zeroed-slab contract of every allocator unchanged.

**A response that owns its arena.** A response holding both the arena and
values built in it is a value observing its own storage, which is refused; the
server holding the arena for the exchange is the shape that compiles.

**Path values stored in the arena.** The router can decode path values into
the arena through `request.allocator()`, and does, but the text it decodes is
owned by a `text.String[mem.Handle[P]]` local to the call. The request it hands
its handler needs a `Str` view of that text, and a view borrows its owner, so
it dies with the local when the call returns. An arena's storage outlives
every buffer carved from it, but the language has no operation that gives up
an arena-backed owner and keeps a view carrying only the arena handle: a
`freeze(sink owned: text.String[mem.Handle[P]]) -> Str where carries(owned)`
is refused with [O-Escapes]. The router's own buffers outlive the call, so the
trait's result borrows `self` instead. That operation would let path values
and `Error`'s message live in the arena and drop both `borrows(self)` and
`Error`'s type parameter.

**A streamed body given the request as a parameter.** A
`fn(request, inout body)` has two sources for its result, the request and the
writer, which holds the arena, so every such function would need a clause. The
writer carries the request instead.

**`read_request` and `write_response` public**, so a program owns its loop, as
Go's `http.ReadRequest` and `Response.Write` allow. The exchange is an arena,
a request read into it and a buffered writer a streamed body runs through,
which a program would have to assemble in the same order `serve` does;
no program owns its loop, and one that must builds it on `std.net`.

**State held by the router**, passed to every handler as a third parameter.
Every handler would take a state type whether it used one or not, and two
applications' state types could not share a router. A type implementing
`Handler` holds exactly the state it needs and composes by delegation.

**Function values only in the router's table.** A table of
`fn(request) -> ...` values could not hold a handler with state. `route` keeps
each handler as a `mem.Closure` in the router's allocator instead, so a
closure and a function register alike and the router releases them with its
table.

**Go's conflict rule for routes.** Go accepts two overlapping patterns only
when one matches a strict subset of the other's requests, and refuses them
otherwise. Detecting that compares each new pattern with every registered one,
a cost in the number of routes at registration, and it makes the outcome of
registering a pattern depend on every pattern already present. Left-to-right
specificity is a total order a segment trie answers directly. Where Go's rule
accepts two patterns and prefers one, the pattern matching the smaller set of
requests is at least as specific at every segment and at the method, so this
order prefers it too; the two differ only on pairs Go refuses.
