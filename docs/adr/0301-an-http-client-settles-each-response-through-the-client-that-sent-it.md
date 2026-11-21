# 301. An HTTP client settles each response through the client that sent it

Status: Accepted — 2026-11-20. Extends
[0154](0154-sockets-and-http-follow-go.md), whose server this client shares
its parser with, and [0300](0300-tls-runs-over-rustls-linked-into-the-runtime.md),
whose TLS stream it reaches `https` origins over; its requests are bounded by
the deadline of [0299](0299-a-deadline-is-an-absolute-moment-passed-explicitly.md).

## Context

`std.http` could serve HTTP and could not ask for it. A program that called
another service wrote a request by hand over `net.connect`, parsed the status
line itself, and either ignored chunked bodies or decoded them in a loop of its
own, the same work every such program repeated with different mistakes.
`net` connected only to an IPv4 address, so a program could not name a host.

Four properties decide the shape of a client in this language rather than in
another:

- A response's body arrives on the connection after its head, so a streamed
  body holds the connection. A connection is a linear `net.Connection`, and
  whatever holds one is linear too.
- Reusing a connection means giving it back once the body has been read to
  its end, and only then: a connection with unread bytes on it cannot carry
  the next response.
- A bound on outstanding requests is a count the client keeps, and a count is
  right only when every response that ends passes through it.
- The server already reads a message head: line endings, header grammar,
  `Content-Length` agreement, line and header limits. A client that read
  response heads with a second parser would answer the same question twice
  ([one question, one answer](../architecture.md)).

## Decision

### 1. `http.Client` owns a pool and counts its responses

`Client.new(limits)` and `Client.new_in(allocator, limits)` make a client with
no connections; nothing is allocated or opened before the first request.
`Client.with_tls(config, limits)` and `with_tls_in(allocator, config, limits)`
make one that reaches `https` origins with the `tls.ClientConfig` it is given
(§9). The
allocator holds the pool, each response's head and read-ahead buffer, and
bodies read whole. A `Client` is linear: `close()` closes every idle
connection and reports the first close that fails, and `Release` does the
same, best effort.

`ClientLimits` states every bound, with these defaults: 8 KiB lines and 100
headers in a response head (the server's request defaults); 10 s to connect,
30 s for each read and each write; 16 idle connections, at most 4
to one origin, each reused only within 4 s of its return, shorter than the
5 s common servers hold an idle connection; 16 outstanding
responses; 10 redirects; 64 KiB drained to keep a connection; and 16 KiB of
read-ahead per response.

The pool is keyed by origin: scheme, host under ASCII case folding, and port.
It holds at most `max_idle_connections`, so taking a connection walks at most
that many entries, closing every one found idle past `idle_timeout_ms`.
Giving one back past `max_idle_per_host` or `max_idle_connections` closes the
oldest to make room.

A `Client` is used by one task. A program fetching on several tasks gives each
task a client, and the bound on work in flight is the policy it fetches under
(`task.lazy_map(.Threads(n), …)`), as the link checker does.

### 2. A response is linear and is settled only by its client

`client.send(request)` answers a `ClientResponse` once its head is read: its
status, its headers, the URL that answered after redirects, and the body still
on the connection. The response is an `io.Reader` that decodes the body as it
arrives, so it composes with `io.BufferedReader` and everything built on
readers. It is linear, and it has no `Release`: the only ways to end one are
the client's own.

- `client.read_text(response, max_bytes)` and `client.read_bytes(…)` read the
  rest of the body, at most `max_bytes`, and settle it;
- `client.finish(response)` reads what remains when it is at most
  `drain_bytes`, then settles it;
- `client.discard(response)` settles it without reading, closing the
  connection.

Each settles the same way: the client stops counting the response and puts its
connection back in the pool when the body was read to its end, nothing past it
was read ahead, the response was HTTP/1.1 without `Connection: close`, and no
read failed; otherwise it closes the connection. Nothing read ahead means
nothing in the response's reader (`io.BufferedReader.buffered_bytes`, added
here) and nothing in a TLS stream under it, which can hold ciphertext the
session has not taken and plaintext it decrypted and no read has asked for
(`tls.Stream.holds_input`); either would be read as the next response.

A response settles only through the client that sent it, and the type cannot
say which client that is. A response borrowing its client would say it, and
would also forbid a second request while one response is held, since a
request takes its client `inout`, which leaves `max_outstanding` nothing to
bound. So each client draws a random 128-bit identity (`uuid.Uuid.v4`) when
it is made, and each response records its sender's. A response settled
through another client has its connection closed, never pooled, so a
connection verified under one client's TLS configuration, or presenting its
client certificate, never serves another client; and the settling client's
count does not change. The sender's count cannot come down then: the settling
client holds nothing that reaches its sender, so the response stays counted
there, and a sender whose responses are settled elsewhere reaches
`Saturated` once `max_outstanding` of them are. Within each client's own
responses `client.outstanding()` is exact, and `send` refuses a request with
`Saturated` when `max_outstanding` responses are unsettled, before it
connects.

### 3. The server's readers read the response's head

The head reader in `parse.lin` is split in two: `read_header_fields` reads
`name: value` lines up to the empty line with the line and header limits it is
given, and answers a `HeaderTally`; `read_headers` is the request's use of it,
which adds the request-only rules about `Host`. A response's head is read by
`read_status_line`, new beside `read_request_line` and reusing its line and
version checks, then `read_header_fields`. The request reader's refusals are
the client's in its own words: an over-long head is `HeadTooLarge`, any other
refusal `MalformedResponse`, a connection that ended before a byte `Closed`,
and a failed read `Io` with the bytes it got.

The body is framed as RFC 9112 §6.3 says: no body for a response to `HEAD` or
a status without one; chunks when the last transfer coding is `chunked`, whose
size lines, extensions and trailers are read with the same line reader under
the same limits; until the server closes for any other coding or for a
response with neither a coding nor a length; and `Content-Length` otherwise.
A response framed both ways is malformed, as the server refuses such a
request. Interim `1xx` heads are skipped, at most eight; `101` is malformed,
since the client never asks to switch protocols.

### 4. Requests are built whole or streamed

A `ClientRequest[A]` owns its method, URL, headers and body. The URL is any
`Display` value, so an interpolation names one, and must parse as `http.Url`
reads one. Headers are checked as they are added, by the token and field-value
rules the server applies to requests it reads, and `Host`, `Content-Length`,
`Transfer-Encoding` and `Connection` are refused because the client writes
them. `with_header`, `with_body` and `with_json` take the request and answer it
with one more part, releasing it when they fail, so a chain ends in one `?`.
A body set this way is held whole; it is framed by its
length, and `POST`, `PUT` and `PATCH` send `Content-Length: 0` without one.

`client.send_from(request, &reader, length:)` streams the body from any
`io.Reader`: by `Content-Length` when a length is given, in chunks when not. A
streamed body cannot be read twice, so `send_from` follows no redirect and
never sends a request again.

### 5. Redirects follow the method rules, bounded

`send` follows `301`, `302`, `303`, `307` and `308` with a `Location`, resolved
against the URL that answered by `http.resolve_url_in`. `303` turns every
method but `HEAD` into `GET` without a body, and `301` and `302` turn `POST`
into `GET` the same way, as browsers and RFC 9110 §15.4 allow; `307` and
`308` keep the method and the body. A redirect to another origin drops
`Authorization`, `Cookie` and `Proxy-Authorization`. Each intermediate
response is finished, so its connection goes back to the pool and the next
hop to the same origin reuses it. Each hop is one call deeper, so the depth is `max_redirects`. The redirect past `max_redirects` fails
with `TooManyRedirects`; a limit of zero answers the first redirect as it is.

### 6. A stale pooled connection is replaced once

A server closes connections it holds idle on a clock of its own. A request
written on one fails before any byte of a response arrives: an end of input,
a reset or a broken pipe with nothing read. When a pooled connection fails
that way and the method is idempotent (RFC 9110 §9.2.2), the request is sent
once more on a new connection. A failure on a new connection, or after any
byte arrived, is the answer.

### 7. Names resolve through the system, IPv4 only

`net.resolve(host, port)` answers the first IPv4 address the system's
resolver gives, through a new runtime entry, `linea_net_resolve`, declared in
`mem` beside the other byte-address calls and listed among them. A dotted
address answers itself and `localhost` is read from the hosts file, so tests
need no network. The lookup blocks the calling thread, as a blocking foreign
call does, and no timeout bounds it: `connect_timeout_ms` starts once the
address is known, so a resolver that does not answer holds the request for as
long as the system's resolver retries; inside a simulation only a dotted address resolves. A failure is an
`io.IoError` of the new operation `Resolve`, `NotFound` when the name has no
IPv4 address. `net.Address` holds IPv4 only, so the client refuses a bracketed
IPv6 host with `UnsupportedAddress` before any lookup, rather than as a name
that did not resolve.

### 8. Errors are categories

`ClientError` says which step failed: `Url`, `Tls` (an `https` handshake
failed, carrying the `tls.TlsError`), `Resolve`, `UnsupportedAddress`,
`Connect`, `Io`, `Closed`, `MalformedResponse`, `HeadTooLarge`,
`BodyTooLarge`, `TooManyRedirects`, `Saturated`, `InvalidRequest`, `Body` (the
streamed body's reader failed) and `Allocation`. It is copyable and
`Equatable`, and `is_timeout()` tells a wait that ran out of time, a
handshake's included, from any other failure. A non-`2xx` status is an answer, not an error: the program
reads `status()`.

### 9. One link type for the server and the client, over TCP or TLS

`link.lin` holds the only code that touches a connection, and one type,
`Link`, for both ends of HTTP: a plain `net.Connection`, or a
`tls.Stream[net.Connection]` over one. The server's link and the client's
answer the same question (which byte stream an HTTP/1.1 exchange runs over,
and how a read, a write, a close and a bound reach it), so they are one type:
the server opens one per accepted connection and the client one per origin
it connects to, and `read_some`, `send`, `writer`, `close`, `Release`,
`set_timeouts` and `set_deadline` are the same code for both.
`connect_origin` resolves the host, connects by the earlier of the connect
timeout and the request's deadline, and sets the read and write timeouts and
the deadline on the connection; `secure_link` runs the TLS handshake over it,
naming the URL's host as the server name the certificate must state, by the
same deadline.

An `https` origin is reached with the client's `tls.ClientConfig`, which the
client owns and closes with itself. `with_tls` gives it one, such as a
configuration trusting a private authority's roots; otherwise the client
builds one with `verify: .System` at its first `https` request and keeps it.
A `tls:` parameter with a default on `Client.new` was the first choice, and
it cannot be written: a `tls.ClientConfig` is linear, and a default of a type
that must be settled is refused ([T-Default]), as it is for `http.serve`'s
`tls:`. A required parameter would make every client name TLS whether or
not it reaches an `https` origin, and a lazily built default makes
`Client.new()` reach the public internet's servers with the operating
system's roots, as a browser does. Keeping one configuration per client
keeps its session cache, so a second connection to a server resumes. A
configuration that cannot be built fails that request with
`Tls(.Tls(refusal))`.

The pool keys `https` apart from `http` (§1), so a pooled TLS stream serves
only its own origin. A redirect between schemes is a redirect to another
origin, so it drops credentials (§5).

### 10. One deadline bounds a whole request

`send`, `send_from` and `get` take `deadline: time.Deadline = time.never`. The
deadline is one budget for the request: connecting, the TLS handshake, every
redirect `send` follows, writing the request and reading the response's head
and body, which fail as `TimedOut` once it passes. Resolving the host name is
outside it: `net.resolve` blocks the thread in the system's resolver, which
keeps timeouts of its own and cannot be interrupted, so a deadline that passes
while it works is seen by the connect after it. A deadline already passed
sends nothing and fails with `Connect(TimedOut)` before the host is resolved. A pooled link is given the
deadline with `Link.set_deadline`, a new one with the connection it is opened
on. The per-operation timeouts of `ClientLimits` still bound each wait, and
a wait ends at whichever comes first, so `time.never` leaves a request
bounded by the timeouts alone. A limit on an exchange's length in
milliseconds was the first shape, and it lost: it starts again at each
exchange, so a request that follows redirects or a program that retries
cannot share one budget across them, which a deadline the caller made once
can.

## Consequences

- A program calls an HTTP service with a client, a request and one settling
  call, and the compiler holds it to settling every response it opened.
- A response read to its end leaves its connection for the next request to
  that origin; the tests prove reuse against a server that accepts one
  connection.
- The server's head reader changed shape. A request refused before is
  refused now and none newly, but a duplicate or invalid `Host` is refused
  once the whole head is read, so a later refusal of the same head (an
  over-long line, too many headers, a full arena) now answers first.
- `https://` URLs work with the operating system's roots by default, so the
  GitHub example reaches `https://api.github.com`; the tests run against local
  servers over HTTP and over TLS with the test root.
- A client is not shared between tasks, so connections are not reused across
  tasks.

## Alternatives considered

- **A response with `Release` that closes its connection.** It would let
  `defer` and `?` end a response, but a response released that way never
  passes through its client, so the outstanding count would drift and the
  bound would mean nothing. Settling through the client is the price of an
  exact count.
- **A response that borrows its client.** A borrow makes the count exact with
  `Release`, and it allows one response at a time per client, which is no bound
  at all.
- **A pool in an owning task (`task.own`), shared by every task.** Reuse
  across tasks needs it. Each checkout and return would be a call to another
  task, and a response would hold a client of that task; nothing in the
  examples needs reuse across tasks yet, and the owning-task shape can be
  added beside this client without changing its API.
- **A client generic over its stream.** `io.Reader` and `io.ByteWriter` both
  declare `Error`, so a bound on both cannot name either ([N-Ambiguous]); a
  generic client would need a trait of its own that every stream implements.
  A closed set of streams in one file is simpler and is all `http` and
  `https` need.
- **A client link apart from the server's.** It would be a second type
  answering which stream an exchange runs over, with its own reads, writes
  and closes over the same two streams; every change to one would have to be
  made to the other.
- **Treating a non-`2xx` status as an error.** It hides the body of a `404`
  or a `422`, which APIs fill with the reason.
