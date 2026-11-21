# 297. A handler test sends a request built in the arena `serve` would give it

Status: Accepted — 2026-11-19. Supersedes the test clause of
[0154](0154-sockets-and-http-follow-go.md), that `http.new_request` builds a
request for a test to hand to a handler, and the `http.new_request` example
under *A parameter that is not any allocator* in
[0220](0220-a-constructor-or-function-that-allocates-pairs-a-system-form-with-an-in-form.md),
and the sentence of [0185](0185-a-handler-reads-its-inputs-through-extractors.md)
that `Message.add_header` gives a test request its headers. Builds on [0263](0263-an-arena-grows-in-chunks-up-to-its-size-and-a-rewind-returns-them.md)
and the body clauses of
[0265](0265-waits-go-through-the-runtimes-poller-and-a-loop-runs-tasks-as-fibers.md) §6.

## Context

`serve` gives each request an arena of `limits.request_arena_bytes` carved
from its parent, reads the request head into it, hands the handler the
`Request` and an exclusive `RequestBody` that reads from the connection, and
rewinds the arena once the response is written. A handler test did each of
those steps by hand, five lines in every test:

```text
defer let arena = mem.Arena.open(mem.system(), size: 65536)
var sent = http.new_request(arena.handle(), "POST", "/echo", body: …).unwrap()
&sent.add_header("Authorization", "Bearer ada").unwrap()
defer var incoming = http.RequestBody.from_request(sent.request())
let response = &router.serve_http(&ctx, sent.request(), &incoming).unwrap()
```

Every test chose an arena size of its own (64 bytes to 128 KiB across the
library, the examples and the guide), none of them the size `serve` uses, and
needed `use mem.Lender` for `arena.handle()` and `use http.Handler` for
`serve_http`. `new_request` held a request to the standard limits whatever
the test's server used, `from_request` took the standard limits again
separately, and the two could be given different ones. And the request it
built held its body in the request's metadata, decoded as a form when it was
one, where `serve` hands a handler a request whose body is read only through
its `RequestBody`: `request.text()` or `request.form_params()` answered in a
test and were empty in a served request, so a handler that read them without
materializing its body passed its tests and failed in production.

## Decision

**`http.TestExchange` is the arena one exchange is served from.**
`TestExchange.open(limits:)` opens an arena of `limits.request_arena_bytes`
over the system allocator, as `serve` opens one for each serving task, with
`standard_limits` when none are given; `TestExchange.open_in(allocator,
limits:)` carves it from another allocator, as `serve_in` does from its
parent. It takes a 64 KiB first chunk and grows only as a request needs, so a
test holds what it uses, not 48 MiB. It is released with `defer`.

**`exchange.request(method, target, body:, content_type:)` builds a
`TestRequest` in that arena, as a client sends it and as `serve` reads it.**
The method and target are checked as a request line is, the headers are held
to the exchange's limits, a body is sent with its `Content-Length` and one
longer than `max_body_bytes` is refused with 413 before any handler runs, as
`serve` refuses it, and `content_type` adds the `Content-Type` header. The
request's metadata holds no body: the handler reads it through the `RequestBody` the `TestRequest`
holds, bounded by `max_body_bytes`, and materializes it to reach forms and
JSON, as it does in a served request. `&sent.add_header(name, value)` adds a
header under the same limits. `TestRequest` is linear because the body it
holds is, and it is released with `defer`, as `serve` releases the body once
the response is written.

**`&sent.send_to(&handler, &state)` calls the handler as `serve` does**, with
the request and its body, and answers its `Result[Response, Error]`. The
response may view the request, its body and the handler, and lives in the
exchange's arena, so the compiler holds a test to reading it while all of them
live. `sent.request()` is the view a handler reads, for code that takes a
`Request` directly.

The test above is three lines and names no allocator, no arena size and no
trait:

```text
defer let exchange = http.TestExchange.open()
defer var sent = exchange.request("POST", "/echo", body: …, content_type: "application/json").unwrap()
let response = &sent.send_to(&router, &ctx).unwrap()
```

`new_request`, `Message.add_header` and `RequestBody.from_request` are
removed, and `RequestBody.from_slice` is no longer public: a body is built
from held bytes inside the library alone, by the fixture and by `serve_cgi`.

## Consequences

- A handler test sees what a served handler sees: an unmaterialized body, the
  `Content-Length` a client sends, and refusals at the same limits (413 for a
  body past `max_body_bytes`, 431 past `max_headers`), so a test that passes
  under a service's limits describes that service.
- Four checks `serve` makes before a handler runs are not made: a request
  carries the `Host` a test adds and none otherwise, where `serve` refuses an
  HTTP/1.1 request without exactly one; a `Transfer-Encoding` header added by
  hand is kept, where `serve` answers 501; `max_line_bytes` is not applied to
  the request line or a header; and an arena smaller than the limits need is
  opened, where `serve` refuses it with `ArenaTooSmall`. The last is what lets a
  test reach an allocation failure, and the others keep a test of a handler
  from writing headers the handler never reads.
- A test that wants a smaller arena, to reach an allocation failure, says so
  through `limits: http.Limits { request_arena_bytes = n, ..http.Limits.default() }`;
  an exchange over another arena's handle takes its whole size from it at once,
  as any arena over an arena does, so it is opened at a size that parent holds.
- A test sends several requests to one exchange, or opens an exchange per
  request; either way each request's text stays in the arena until the
  exchange is released, where `serve` rewinds after each one.
- A function `fn(request: Request, inout body: RequestBody)` is a handler, and
  a test sends to it from a `var`; a generic one is registered on a router
  instead, since nothing in `send_to` names its allocator.

## Alternatives considered

**One value owning the arena and the request.** A test would write one
`defer` instead of two. The request's text and its body's handle borrow the
arena, and a value cannot own storage and hold an observation of that same
storage, so the request cannot sit inside the value that owns its arena; the
exchange and the request are two values because the language says so.

**Keep the body in the request's metadata, as `new_request` did.** Tests of
`Request.text` and `Request.form_params` read a built request without
materializing it. That is exactly the difference between a test and `serve`
that let a handler pass its tests and fail when served, so the body is read
through the `RequestBody` alone and those library tests materialize first.

**`send_to` answers an owned copy of the response.** Copying the status,
headers and body into the exchange's arena would let the request and its body
be released before the response is read. Every test reads the response it
already gets, through `Response` and `Error`, before releasing anything, and a
copy would hide from the test the borrow a handler's response really holds;
it would also need a second reading of a streamed body beside
`recorded_body`.

**A closure that receives the request and its body.** `with_test_request(…,
|request, inout body| …)` would scope the arena without a `defer`, but a test
body would no longer read like the code that serves, and every assertion would
move inside a callback that answers a `Result` of its own.
