# Networking

This chapter puts the earlier ones to work on a network. `std.net` gives you
TCP: listening, accepting and connecting. `std.http` builds an HTTP/1.1 server
on top of it: handlers that return responses, a router that picks the handler,
extractors that read a request's inputs, state that every handler shares,
logging, bodies streamed as they are written, and the same handlers run as CGI
programs.

Three ideas from earlier chapters carry most of the weight here. Sockets are
**linear** ([Copying, settling and
sealing](04-copying-settling-and-sealing.md#linear-values-you-must-not-forget)):
a listener or connection you forget to close is a compile error. Every HTTP
request lives in **an arena** ([Memory](07-memory.md#one-arena-per-http-request)),
so a handler never releases anything. And **closures** ([Calling
things](02-calling-things.md#closures-functions-that-capture)) carry what a
handler computed into a streamed body or a route.

Several earlier mechanisms combine in this chapter's code: `?`, `let ... else`,
`defer` and closing a linear value. You do not need to follow every line yet;
each section below takes them one at a time, and the programs read the same
once you have seen them used.

## TCP with `std.net`

A server listens on an address and accepts connections; a client connects to
one. Both ends of a connection are an `io.Reader` and a `Writer`, so the
reading and writing tools of `std.io` work on them.

### Both ends in one program

This program plays both sides on one machine, so you can run it without a
second terminal:

```linea
import std.io
import std.mem
import std.net

use mem.Owner
use net.Accepted
use net.Acceptor

// Read everything the other side sends until it stops writing, and print it.
fn print_all(label: Str, inout connection: net.Connection) -> Result[(), io.IoError] {
    let arena = mem.Arena.open(mem.system(), size: 4096)
    defer arena.release()
    let received = io.read_all_in(arena.handle(), &connection, max_bytes: 1024) else |failure| {
        // The failure owns any bytes read before it, so it is released.
        failure.release()
        return io.println("{label}: the read failed")
    }
    // `Str.from_bytes` reads the bytes as text, or fails when they are not UTF-8.
    let message = Str.from_bytes(received.as_slice()) else |_| {
        return io.println("{label}: that was not text")
    }
    io.println("{label} received: {message}")
}

// The client says ping, the server answers pong. `shutdown_write` tells the
// other side that nothing more is coming, which ends its `read_all`.
fn exchange(inout client: net.Connection, inout server: net.Connection) -> Result[(), io.IoError] {
    &client.write_str("ping")?
    &client.shutdown_write()?
    print_all("server", &server)?
    &server.write_str("pong")?
    &server.shutdown_write()?
    print_all("client", &client)
}

fn main() -> UInt8 {
    // Port 0 asks the operating system for any free port.
    var listener = net.listen(net.loopback(0)) else |error| {
        io.eprintln("cannot listen: {error}")
        return 1
    }
    let address = listener.local_address() else |error| {
        io.eprintln("no address: {error}")
        let _closed = listener.close()
        return 1
    }
    // The operating system queues a connection until the listener accepts it,
    // so one program can play both sides.
    var client = net.connect(address) else |error| {
        io.eprintln("cannot connect to {address}: {error}")
        let _closed = listener.close()
        return 1
    }
    let accepted = &listener.accept() else |error| {
        io.eprintln("cannot accept: {error}")
        let _client = client.close()
        let _closed = listener.close()
        return 1
    }
    let Accepted { connection, address: _ } = accepted
    var server = connection
    let exchanged = exchange(&client, &server)
    // Every connection and the listener are closed whatever happened above.
    let server_closed = server.close()
    let client_closed = client.close()
    let listener_closed = listener.close()
    match exchanged {
        Ok(_) => if server_closed.is_ok() && client_closed.is_ok() && listener_closed.is_ok() { 0 } else { 1 },
        Err(error) => {
            io.eprintln("the exchange failed: {error}")
            1
        },
    }
}
```

```
server received: ping
client received: pong
```

### What the program does

- `net.listen(net.loopback(0))` listens on 127.0.0.1. Port 0 asks the
  operating system for any free port, and `local_address()` says which one it
  chose. `net.any(port)` listens on every interface instead, and
  `net.Address.parse("10.0.0.5:80")` reads an address from text.
- `net.connect(address)` connects. The operating system holds the new
  connection in a queue until the listener accepts it, which is why one
  program can connect first and accept second.
- `&listener.accept()` takes the next connection from the queue and returns an
  `Accepted`: the `connection` and the `address` it came from. `accept`
  belongs to the `net.Acceptor` trait, hence `use net.Acceptor`; `close` is the
  listener's own and needs no `use`.
- `write_str` sends text; `shutdown_write` tells the other side nothing more
  is coming, which is what lets `io.read_all` on the far end finish.
- Every early `return` closes what is open so far, and the end of `main`
  closes both connections and the listener. Leave any of those out and the
  program does not compile.

### Closing each resource in its own `let`

`main` closes each resource in its own `let`, and checks the results
afterwards. The shorter-looking `server.close().is_ok() && client.close().is_ok()`
is refused, and the reason is worth seeing. Put this line in place of the three
`close` lets, and `Ok(_) => if closed { 0 } else { 1 }` in the `match`:

```linea
    let closed = server.close().is_ok() && client.close().is_ok() && listener.close().is_ok()
```

<!-- guide: unchecked the error an edit of the program above produces -->
```
error[O-Merge]: the paths here disagree about `client`
  --> loopback_shortcircuit.lin:64:18
   |
64 |     let closed = server.close().is_ok() && client.close().is_ok() && listener.close().is_ok()
   |                  ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ consume it on the other path too, or on neither
error[O-Merge]: the paths here disagree about `listener`
  --> loopback_shortcircuit.lin:64:18
   |
64 |     let closed = server.close().is_ok() && client.close().is_ok() && listener.close().is_ok()
   |                  ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ consume it on the other path too, or on neither
```

`&&` stops at the first `false`, so if closing the server connection failed,
the client and the listener would never be closed. The compiler follows that
path too.

### A socket must be closed

`net.Listener` and `net.Connection` are linear ([Copying, settling and
sealing](04-copying-settling-and-sealing.md#linear-values-you-must-not-forget)),
which is why the program above closes every one on every path. Open a listener
and forget to close it:

```linea
import std.io
import std.net

fn main() -> UInt8 {
    let address = net.loopback(0)
    let listener = net.listen(address) else |error| {
        io.eprintln("cannot listen on {address}: {error}")
        return 1
    }
    match listener.local_address() {
        Ok(bound) => io.eprintln("listening on port {bound.port}"),
        Err(error) => io.eprintln("no address: {error}"),
    }
    0
}
```

```
error[O-Leak]: `listener` (a linear `net.Listener`) is still owned when this path leaves
  --> listener_forgot.lin:6:9
   |
6  |     let listener = net.listen(address) else |error| {
   |         ^^^^^^^^ never settled on the path that reaches the end of this block
15 | }
   | - the block ends here
   |
   = help: settle it first with `listener.release()` or `listener.close()`
```

A listener has two endings. `close()` closes it and reports a failure as a
`Result` for you to handle. `release()` closes it too, but has nowhere to
report a failure, so it drops one; it is what a `defer` usually calls. Here
`close` is the right choice, in place of the final `0`:

```linea
    match listener.close() {
        Ok(_) => 0,
        Err(error) => {
            io.eprintln("cannot close the listener: {error}")
            1
        },
    }
```

The help does not offer to take the listener apart, the way `redeem` took a
`Ticket` apart in [Copying, settling and
sealing](04-copying-settling-and-sealing.md#linear-values-you-must-not-forget).
That works for your own types, but not for a listener: its type is `@opaque` in
the `net` module, so no pattern outside `net` can open it.
Try it anyway, with `use net.Listener` at the top of the file and
`let Listener {} = listener` in place of the `close`:

<!-- guide: unchecked the error an edit of the program above produces -->
```
error[M-Opaque]: `Listener` is opaque outside `net`
  --> listener_apart.lin:19:9
   |
19 |     let Listener {} = listener
   |         ^^^^^^^^^^^ only its own module can take one apart
```

In Go you would write `defer listener.Close()` and hope nobody forgets. In
Linea, forgetting is a compile error.

### Serving each connection with `net.serve`

The accept loop above is the same for every TCP server: accept, hand the
connection to something, repeat. `net.serve` is that loop. You write the
function that deals with one connection, and `serve` calls it for each one:

```linea
import std.io
import std.mem
import std.net

use mem.Owner

// Print everything the server sent, then close the connection.
fn print_greeting(label: Str, sink client: net.Connection) {
    var visitor = client
    let arena = mem.Arena.open(mem.system(), size: 4096)
    defer arena.release()
    match io.read_all_in(arena.handle(), &visitor, max_bytes: 64) {
        Ok(bytes) => match Str.from_bytes(bytes.as_slice()) {
            Ok(text) => {
                let _printed = io.print("{label}: {text}")
            },
            Err(_) => io.eprintln("{label}: that was not text"),
        },
        Err(failure) => {
            failure.release()
            io.eprintln("{label}: the read failed")
        },
    }
    let _closed = visitor.close()
}

// The handler owns the connection: it greets the visitor and closes it.
fn welcome(sink connection: net.Connection, peer: net.Address) {
    var visitor = connection
    if &visitor.write_str("welcome\n").is_err() {
        io.eprintln("cannot greet {peer}")
    }
    let _closed = visitor.close()
}

fn main() -> UInt8 {
    var listener = net.listen(net.loopback(0)) else |error| {
        io.eprintln("cannot listen: {error}")
        return 1
    }
    let address = listener.local_address() else |error| {
        io.eprintln("no address: {error}")
        let _closed = listener.close()
        return 1
    }
    // The kernel queues a connection until the listener accepts it, so both
    // clients can connect before `serve` runs.
    let first = net.connect(address) else |error| {
        io.eprintln("cannot connect: {error}")
        let _closed = listener.close()
        return 1
    }
    let second = net.connect(address) else |error| {
        io.eprintln("cannot connect: {error}")
        let _closed = first.close()
        let _closed_too = listener.close()
        return 1
    }
    // `serve` takes the listener, hands each connection to `welcome`, and
    // closes the listener when it returns after two.
    var handler = welcome
    let ended = net.serve(listener, &handler, connections: .Some(2))
    print_greeting("first", first)
    print_greeting("second", second)
    match ended {
        Ok(_) => 0,
        Err(error) => {
            io.eprintln("{error}")
            1
        },
    }
}
```

```
first: welcome
second: welcome
```

- `net.serve(listener, &handler, connections: .Some(2))` takes the listener,
  accepts connections, and passes each to the handler along with the address
  of the peer that opened it. With `connections: .Some(2)` it returns after
  two. Leave the argument out and it serves for ever, which is what a real
  server wants. The listener is closed on every way out of `serve`, so
  `main` has nothing left to close.
- The handler takes the connection with `sink`, so it owns it. `net.Connection`
  is linear, which means the handler must close or release it, and the
  compiler holds it to that. Take the `close` out of `welcome`:

<!-- guide: unchecked the error an edit of the program above produces -->
```
error[O-Leak]: `visitor` (a linear `net.Connection`) is still owned when this path leaves
  --> welcome_forgot.lin:29:9
   |
29 |     var visitor = connection
   |         ^^^^^^^ never settled on the path that reaches the end of this block
33 | }
   | - the block ends here
   |
   = help: settle it first with `visitor.release()`, `visitor.close()` or `visitor.reset()`
```

- The handler returns `()`. It reports its own failures, as `welcome` does with
  `io.eprintln`, and a connection that failed never stops the server.
- `serve` handles one connection at a time. The handler finishes with a
  connection before the next is accepted, so a slow client holds up the
  clients queued behind it. A server that must not wait needs a different
  design, and one that waits bounds each connection: `set_timeouts` limits
  every read and write, and `set_deadline` limits all the reads together, so a
  client that sends a byte at a time cannot hold the server either.
- When accepting fails because the peer reset the connection or the process ran
  out of descriptors, `serve` waits and tries again, starting at 5
  milliseconds and doubling up to a second, without telling anyone. Any other
  failure ends `serve` with `Accept`, and a listener that fails to close ends
  it with `Close`; both print as a sentence, such as `accepting a connection
  failed: Accept failed (ConnectionReset) after 0 bytes`.
- Both clients connect before `serve` runs. That is legitimate: the operating
  system queues a connection, and what the client sent, until the listener
  accepts it. It is also how a test drives `serve` without threads:

```linea
import std.net
import std.testing

// Closes whatever connection it is handed.
fn hang_up(sink connection: net.Connection, _peer: net.Address) {
    let _closed = connection.close()
}

test fn serve_stops_after_the_connections_it_was_given() {
    let listener = net.listen(net.loopback(0)).unwrap()
    let address = listener.local_address().unwrap()
    // Both clients connect first; the kernel holds them until `serve` accepts.
    let first = net.connect(address).unwrap()
    let second = net.connect(address).unwrap()
    var handler = hang_up
    let ended = net.serve(listener, &handler, connections: .Some(2))
    let _first_closed = first.close()
    let _second_closed = second.close()
    testing.assert(ended.is_ok(), "serve did not stop cleanly after two connections")?
}
```

```
ok    serve_stops_after_the_connections_it_was_given

1 passed, 0 failed
```

State that lasts across connections lives in a closure. The handler is lent
`inout`, so a closure that owns a counter, `inout [sink greeted = UInt64(0)]`,
changes it on every call, and `into_captures()` hands the counter back when
`serve` is done ([Calling things](02-calling-things.md#a-closure-that-changes-what-it-owns)
shows the same closure on its own). Only the handler in `main` changes:

```linea
    var handler = inout [sink greeted = UInt64(0)] |sink connection: net.Connection, peer: net.Address| {
        greeted += 1
        welcome(connection, peer)
    }
    let ended = net.serve(listener, &handler, connections: .Some(2))
    let { greeted } = handler.into_captures()
    let _printed = io.println("greeted {greeted} visitors")
```

<!-- guide: unchecked the output of an edited or partial program -->
```
greeted 2 visitors
first: welcome
second: welcome
```

The [visitor counter](../../examples/visitor_counter.lin) is that program with
a name read from each visitor, and it counts them the same way.

### An echo server

Everything so far fits together as a small `nc`: the
[TCP echo example](../../examples/tcp_echo.lin) is a server that sends back
what a client sends, and the client that talks to it. `serve` listens, accepts
one client at a time, echoes it and closes its connection. Each step that can
fail has one `let ... else` that reports the failure and leaves, and each
resource is closed in exactly one place: the listener in `serve`, and the
connection in `accept_clients`, after `echo` has borrowed it.

<!-- guide: unchecked the program is a server and a client started from the command line -->
```linea
// Echo text over TCP. `tcp_echo serve PORT` waits for a client, sends back
// everything the client sends, closes that connection, and waits for the next
// client. Add a number, as in `tcp_echo serve PORT 3`, to stop after that many
// clients. `tcp_echo send PORT MESSAGE...` connects, sends each message as a
// line, and prints what comes back.
import std.env
import std.io
import std.mem
import std.net

use mem.Owner
use net.Accepted
use net.Acceptor

fn main() -> UInt8 {
    let args = env.args()
    let mode = args.at(1) else {
        return usage()
    }
    let port = port_argument(args) else {
        return usage()
    }
    if mode == "serve" {
        let clients = clients_argument(args) else {
            return usage()
        }
        return serve(port, clients)
    }
    if mode == "send" && args.count() > 3 {
        return send(port, args)
    }
    usage()
}

// Print this when the arguments are not a mode and a port.
let usage_text =
    \\usage: tcp_echo serve PORT [CLIENTS]
    \\       tcp_echo send PORT MESSAGE...

fn usage() -> UInt8 {
    io.eprintln(usage_text)
    64
}

// Read the port from the third argument. `?` returns `.None` early when the
// argument is missing, and `else |_|` does the same when it is not a number.
fn port_argument(args: env.Args) -> Option[UInt16] {
    let text = args.at(2)?
    let port = text.parse[UInt16]() else |_| {
        return .None
    }
    .Some(port)
}

// Read how many clients to serve from the fourth argument. Without one, the
// server never stops.
fn clients_argument(args: env.Args) -> Option[UInt64] {
    if args.count() == 3 {
        return .Some(UInt64.max)
    }
    let text = args.at(3)?
    let clients = text.parse[UInt64]() else |_| {
        return .None
    }
    .Some(clients)
}

fn serve(port: UInt16, clients: UInt64) -> UInt8 {
    // Each fallible step has one `let ... else`: report the failure and leave.
    // The listener is linear, so every way out of `serve` closes it.
    var listener = net.listen(net.loopback(port)) else |error| {
        io.eprintln("cannot listen on port {port}: {error}")
        return 1
    }
    let address = listener.local_address() else |error| {
        io.eprintln("cannot read the listening address: {error}")
        let _closed = listener.close()
        return 1
    }
    io.eprintln("listening on {address}")
    let accepted = accept_clients(&listener, clients)
    // The listener is closed here, once, whether or not accepting worked.
    let closed = listener.close()
    if closed.is_err() {
        io.eprintln("cannot close the listener")
        return 1
    }
    if accepted {
        0
    } else {
        1
    }
}

// Echo clients one at a time until `clients` have been served, and answer
// whether accepting never failed.
fn accept_clients(inout listener: net.Listener, clients: UInt64) -> Bool {
    var served: UInt64 = 0
    while served < clients {
        let accepted = &listener.accept() else |error| {
            io.eprintln("cannot accept a client: {error}")
            return false
        }
        // `Accepted` holds the connection and the address of the client.
        let Accepted { connection, address } = accepted
        var open = connection
        echo(&open, address)
        // The connection is closed here, once, whether or not the echo worked.
        let _closed = open.close()
        served += 1
    }
    true
}

// Send everything the client sent back to it. A client shuts down its side
// when it has sent everything, which is what ends `read_all`.
fn echo(inout connection: net.Connection, client: net.Address) {
    defer let arena = mem.Arena.open(mem.system(), size: 8192)
    let received = io.read_all_in(arena.handle(), &connection, max_bytes: 4096) else |failure| {
        io.eprintln("cannot read from {client}: {failure}")
        // The failure owns any bytes read before it, so it is released.
        failure.release()
        return
    }
    let _written = io.write_all(&connection, received.as_slice()) else |error| {
        io.eprintln("cannot echo to {client}: {error}")
        return
    }
    io.eprintln("echoed {received.length()} bytes to {client}")
}

fn send(port: UInt16, args: env.Args) -> UInt8 {
    var connection = net.connect(net.loopback(port)) else |error| {
        io.eprintln("cannot connect to port {port}: {error}")
        return 1
    }
    let echoed = exchange(&connection, args)
    // The connection is closed here, once, whether or not the exchange worked.
    let closed = connection.close()
    if closed.is_err() {
        io.eprintln("cannot close the connection")
        return 1
    }
    if echoed {
        0
    } else {
        1
    }
}

// Send the messages from the fourth argument on, one per line, and print what
// the server sends back. Report the first step that fails and answer whether
// every step worked.
fn exchange(inout connection: net.Connection, args: env.Args) -> Bool {
    defer var text = String.new()
    for index in 3..args.count() {
        let message = args.at(index) else {
            io.eprintln("a message must be valid UTF-8")
            return false
        }
        let _line = io.line(message, &text) else |_| {
            io.eprintln("a message is too long to send")
            return false
        }
    }
    let _written = io.write_all(&connection, text.view().as_bytes()) else |error| {
        io.eprintln("cannot send: {error}")
        return false
    }
    // Shutting down writes tells the server nothing more is coming.
    let _shut = &connection.shutdown_write() else |error| {
        io.eprintln("cannot finish sending: {error}")
        return false
    }
    defer let arena = mem.Arena.open(mem.system(), size: 8192)
    let received = io.read_all_in(arena.handle(), &connection, max_bytes: 4096) else |failure| {
        io.eprintln("cannot read the echo: {failure}")
        failure.release()
        return false
    }
    let echoed = Str.from_bytes(received.as_slice()) else |_| {
        io.eprintln("the echo was not text")
        return false
    }
    io.print(echoed).is_ok()
}
```

Start the server in one terminal. Port 0 asks for any free port, and the
second number stops it after that many clients:

```
$ linea run tcp_echo.lin -- serve 0 1
listening on 127.0.0.1:64541
```

Send it two messages from another terminal, using the port it printed:

<!-- guide: unchecked a session with a server on a port the operating system chose -->
```
$ linea run tcp_echo.lin -- send 64541 hello "two words"
hello
two words
```

The server reports the echo and, having served its one client, stops:

<!-- guide: unchecked the log of the server in the other terminal -->
```
echoed 16 bytes to 127.0.0.1:64543
```

With the server gone, the same command reports the refusal and exits with
status 1:

<!-- guide: unchecked a session after the server has stopped -->
```
$ linea run tcp_echo.lin -- send 64541 hi
cannot connect to port 64541: Connect failed (ConnectionRefused) after 0 bytes; errno 61
```

### Bounding what a client can do

That server trusts its clients. It answers one at a time, so a client that
connects and says nothing, or sends a byte at a time, holds every client queued
behind it. The [bounded echo](../../examples/bounded_echo.lin) is the same
server and client with three limits added, and `net.serve` in place of the
accept loop:

- `set_timeouts` bounds each read and each write on a connection.
- `set_deadline` bounds all the reads of a session together, so a byte at a
  time cannot stretch it.
- A cap on the text a connection may send, past which nothing is echoed.

It also logs what happens, and reads lines through an `io.BufferedReader`
instead of reading until the client stops. The limits are a few lines at the top
of its connection handler:

```linea
    var bounded = connection
    let _ = &bounded.set_timeouts(read_ms: bounds.session_ms, write_ms: bounds.session_ms) else |error| {
        logger.error("cannot bound a connection", log.field("peer", peer).and("error", error))
        let _closed = bounded.close()
        return
    }
    &bounded.set_deadline(time.Instant.now(), within_ms: bounds.session_ms)
```

Run it the same way. It takes its port with a `--port` flag, and its log goes
to standard error with a timestamp:

<!-- guide: unchecked a session with a server on a port the operating system chose -->
```
$ linea run bounded_echo.lin -- serve --port 0 --connections 1
2026-10-06T16:46:16Z INFO listening address=127.0.0.1:64531
2026-10-06T16:46:22Z INFO echoed peer=127.0.0.1:64532 lines=2
```

<!-- guide: unchecked a session with a server on a port the operating system chose -->
```
$ linea run bounded_echo.lin -- send --port 64531 hello "two words"
hello
two words
```

## An HTTP server

`std.http` answers HTTP/1.1 requests. You write **handlers** — functions that
take a request and return a response — and register them on a **router** with
a pattern. `http.listen_and_serve` opens a listener, accepts connections and
answers one request on each.

### The smallest service

Most services start from this: a few functions that each answer one kind of
request, a table that says which request goes to which function, and a `main`
that starts the server. Save it as `hello_http.lin`
([the example](../../examples/hello_http.lin) also carries its tests):

<!-- guide: unchecked the server runs until it is stopped and the output is a curl session -->
```linea
// A small HTTP service with two routes.
// GET /health answers `ok`. POST /echo reads a JSON message such as
// `{"text":"hello"}` and answers it as `{"echo":"hello"}`. The service listens
// on 127.0.0.1 at the port its first argument names.
import std.env
import std.http
import std.io
import std.json
import std.mem
import std.net

// `Message` is the JSON object POST /echo expects. `json.Decode[A]` builds one
// from a document and refuses an object that lacks `text`, gives it the wrong
// kind of value, or has a field `Message` does not. `mem.Handle` is the memory
// that holds the text, and `Release` is what lets a `Message` free it.
@derive(Release, json.Decode[mem.Handle])
struct Message {
    text: String[mem.Handle],
}

// `Reply` is what POST /echo answers, and `json.Encode` writes it as the
// JSON object `{"echo":"hello"}`.
@derive(json.Encode)
struct Reply {
    echo: Str,
}

// A handler is a function from a request to an answer. `http.Request` and
// `http.Response` take their memory from the system allocator, so a handler
// needs no type parameter for it.
fn health(request: http.Request) -> Result[http.Response, http.Error] {
    // The handler takes the request because every answer is built in the
    // memory the request came with: `http.text` puts the body there.
    http.text(request, "ok")
}

// A handler asks for what it reads by naming it as a parameter. `Message`
// implements `http.Extract`, so the router reads the JSON body into one before
// calling `echo`, and answers the request with the refusal when it cannot: 400
// for a body that is not JSON, and 422 naming the field for one that is not a
// `Message`. The router releases the message when `echo` returns.
impl http.Extract[mem.SystemAllocator] for Message {
    fn extract(request: http.Request) -> Result[Message, http.Error] {
        request.extract[http.Json[Message]]()
    }
}

// `http.Request` is a carrier, so the answer may borrow from the request, as it
// does from the message's text held in the request's memory.
fn echo(message: Message, request: http.Request) -> Result[http.Response, http.Error] {
    // `http.json` encodes the reply and answers with it.
    http.json(request, Reply { echo = message.text.view() })
}

// A route pairs a method and a path with a handler. `?` stops at a pattern
// the router refuses.
fn routes(inout router: http.Router[()]) -> Result[(), http.RouteError] {
    &router.route("GET /health", health)?
    &router.route("POST /echo", echo)
}

fn main() -> UInt8 {
    match port_argument() {
        Some(port) => serve(port),
        None => {
            io.eprintln("usage: hello_http PORT")
            64
        },
    }
}

// Read the first command-line argument as a port number. `?` returns `None`
// when there is no argument, and `parse` fails on text that is not a port.
fn port_argument() -> Option[UInt16] {
    let text = env.args().at(1)?
    match text.parse[UInt16]() {
        Ok(port) => .Some(port),
        Err(_) => .None,
    }
}

fn serve(port: UInt16) -> UInt8 {
    var router = http.Router.new()
    let _ = routes(&router) else |error| {
        io.eprintln("cannot register a route: {error}")
        router.release()
        return 2
    }
    io.eprintln("listening on http://127.0.0.1:{port}")
    // `listen_and_serve` opens the listener, answers requests until it fails,
    // and releases the router. One `else` handles a failure to listen and a
    // failure while serving.
    let _ = http.listen_and_serve(net.loopback(port), router) else |error| {
        io.eprintln("{error}")
        return 1
    }
    0
}
```

Each handler is a function from a request to a `Result` of a response or an
error. A handler names what it reads as parameters: `echo` asks for a
`Message`, and because `Message` implements `http.Extract` the router reads the
JSON body into one before calling it. When the body cannot be decoded the
router answers the request itself, 400 or 422, and `echo` never runs. `health`
reads nothing, so it takes only the request. `routes` registers the two
handlers, and
`main` hands the router to `listen_and_serve`, which serves until it fails. The
program needs a port, so run it with `linea run hello_http.lin -- 8080` and ask
it things from another terminal:

```
$ curl -i http://127.0.0.1:8080/health
HTTP/1.1 200 OK
Connection: close
Content-Type: text/plain; charset=utf-8

ok
$ curl -i -X POST -H "Content-Type: application/json" -d '{"text":"hello"}' http://127.0.0.1:8080/echo
HTTP/1.1 200 OK
Connection: close
Content-Type: application/json

{"echo":"hello"}
$ curl -i -X POST -H "Content-Type: application/json" -d '{}' http://127.0.0.1:8080/echo
HTTP/1.1 422 Unprocessable Content
Connection: close
Content-Type: text/plain; charset=utf-8

missing field at $["text"]
```

The server prints `listening on http://127.0.0.1:8080` to standard error and
runs until you stop it with Ctrl-C. The rest of this section builds on this
shape: other routes, shared state and logging.

### A first server

<!-- guide: unchecked the server runs until it is stopped and the output is a curl session -->
```linea
import std.http
import std.io
import std.json
import std.mem
import std.net

// A handler takes what it reads and the request, and returns the answer.
// `http.Path[Str]` reads the route's one path value, `{city}`, and `.value` is
// the text. The answer may borrow from the request, as the city does, because
// `http.Request` is a carrier.
fn forecast(city: http.Path[Str], request: http.Request) -> Result[http.Response, http.Error] {
    http.text(request, "Sunny in {city.value}.\n")
}

// A literal segment wins over `{city}`, so this answers `/forecast/today`.
fn today(request: http.Request) -> Result[http.Response, http.Error] {
    http.text(request, "Today is sunny everywhere.\n")
}

// `derive(json.Encode)` writes a `Reading` as a JSON object.
@derive(json.Encode)
struct Reading {
    station: Str,
    celsius: Int64,
}

fn reading(station: http.Path[Str], request: http.Request) -> Result[http.Response, http.Error] {
    if station.value.length() > 12 {
        return .Err(http.error(request, .BadRequest, "a station name has at most 12 letters"))
    }
    http.json(request, Reading { station = copy(station.value), celsius = 21 })
}

// `{rest...}` matches the rest of the path, slashes included.
fn archive(rest: http.Path[Str], request: http.Request) -> Result[http.Response, http.Error] {
    http.text(request, "archived under {rest.value}\n")
}

fn routes(inout router: http.Router[()]) -> Result[(), http.RouteError] {
    &router.route(r"GET /forecast/{city}", forecast)?
    &router.route("GET /forecast/today", today)?
    &router.route(r"GET /stations/{station}", reading)?
    &router.route(r"GET /archive/{rest...}", archive)
}

fn main() -> UInt8 {
    var router = http.Router.new()
    if routes(&router).is_err() {
        router.release()
        io.eprintln("a route pattern was refused")
        return 2
    }
    // The program chooses the address and the handler.
    // `listen_and_serve` opens the listener and serves until it fails, then
    // closes the listener and releases the router, whichever way it stopped.
    // One `else` handles a failure to listen and a failure to serve.
    let _ = http.listen_and_serve(net.loopback(8080), router) else |error| {
        io.eprintln("{error}")
        return 1
    }
    0
}
```

`listen_and_serve` takes the router, so the program no longer closes or
releases anything after the call. Its error says what stopped it: `Listen`
when the address could not be opened (a port another program holds, for
example), and `Serve` carries the `ServeError` that ended serving: `Accept`,
`Close`, `ArenaTooSmall` or `Memory`. `http.serve` is the same loop for a
program that opens the listener itself. A service whose routes share state
passes it as `state: app`, and `listen_and_serve` returns it when serving ends
([Shared state](#shared-state)); a service that shares nothing, like this one,
leaves it out. Each request is served from memory that comes from the system
allocator unless the call names another with `parent:`
([Limits](#limits)).

### Asking the first server questions

Run it with `linea run weather.lin` and ask it things from another terminal:

```
$ curl -i http://127.0.0.1:8080/forecast/lisbon
HTTP/1.1 200 OK
Connection: close
Content-Type: text/plain; charset=utf-8

Sunny in lisbon.
$ curl http://127.0.0.1:8080/forecast/today
Today is sunny everywhere.
$ curl http://127.0.0.1:8080/stations/harbour
{"station":"harbour","celsius":21}
$ curl -i http://127.0.0.1:8080/stations/a-very-long-station-name
HTTP/1.1 400 Bad Request
Connection: close
Content-Type: text/plain; charset=utf-8

a station name has at most 12 letters
$ curl http://127.0.0.1:8080/archive/2026/09/25
archived under 2026/09/25
$ curl -i -X POST http://127.0.0.1:8080/forecast/lisbon
HTTP/1.1 405 Method Not Allowed
Connection: close
Allow: GET, HEAD
Content-Type: text/plain; charset=utf-8

method not allowed
$ curl -i http://127.0.0.1:8080/radar
HTTP/1.1 404 Not Found
Connection: close
Content-Type: text/plain; charset=utf-8

not found
```

### Handlers return responses

A handler's parameters name what it needs, and the router builds each one
from the request before it calls the handler:

```linea
fn forecast(city: http.Path[Str], request: http.Request) -> Result[http.Response, http.Error]
```

The parameters take one of these shapes, and `route` accepts any of them:

- an optional first `inout state`, the application's state the next server
  shares; a handler that does not use the state leaves it out, and a router
  of any state takes it, as `today` and `health` show;
- up to six **extractors**, the values the handler reads, such as `city`
  ([Extractors](#extractors) lists them);
- the `request`, always last, because the answer is built in its memory.

The handler returns either a response or an error. The extractors are read in
the order they are written, and the first one that refuses answers the request
with its error, so the handler never runs and the extractors already read are
released, last first. A handler is lent each extractor, so it reads one but
does not keep it: a handler that must own what it reads, or must act on a
refusal, takes the request and calls `request.extract[T]()` itself, and is
registered with `route_raw`, which takes a function of the state and the
request.

A handler whose answer may borrow from an extractor as well as from the
request, such as one that holds a `Str` or an owned `String`, still writes no
`where` clause: `http.Request` is a carrier (chapter 6), so the compiler reads
the answer as living as long as the request. A handler whose answer comes from
an extractor instead writes the clause that says so.

`http.Request`, `http.Response` and `http.Error` take
their memory from the system allocator unless a type argument says otherwise,
so a handler names no allocator. Everything a handler builds lives in the
request's arena, so it releases nothing
([Memory](07-memory.md#one-arena-per-http-request) walks through why).

The response helpers each build one kind of answer:

| Helper | Answers with |
| --- | --- |
| `http.text(request, value)` | any `Display` value as `text/plain`, interpolations included |
| `http.json(request, value)` | any `json.Encode` value as `application/json`; `@derive(json.Encode)` writes the encoder |
| `http.bytes(request, bytes)` | bytes already built in the request's arena |
| `http.status(request, .NoContent)` | a status with an empty body |
| `http.stream(request, write)` | a body `write` produces after the head is sent |
| `http.error(request, .BadRequest, message)` | an error: the status, with the message as a plain-text body |

A response can take extra headers with `&response.set_header(name, value)?`
before it is returned, and cookies with `&response.set_cookie(name, value)?`
([Cookies](#cookies)). A page of HTML is `http.text` with a
`text/html; charset=utf-8` content type, and it escapes the text a visitor
supplied with [`html.escaped`](08-text.md#escaping-text-for-html).

Errors travel with `?` like any other `Result`. The library's own failures —
a body that is not JSON, an arena that is full, a push that ran out of room —
convert into the `http.Error` whose status answers them (400, 422 or 500), so
a handler writes `?` and lets a bad input answer itself.

### Every request lives in an arena

[Memory](07-memory.md#one-arena-per-http-request) listed the four steps
`serve` takes for each request: carve an arena, read the request into it, run
the handler, and rewind the arena. A router can be driven through the same
steps by hand, without a network, which is also how [Testing](10-testing.md#testing-a-server)
tests a handler:

```linea
import std.http
import std.io
import std.mem

use http.Handler
use mem.Owner

// Everything this handler builds comes from `request.allocator()`, the
// request's arena, so it releases nothing.
fn receipt(item: http.Path[Str], request: http.Request) -> Result[http.Response, http.Error] {
    var body = String.new_in(request.allocator())
    &body.append("Receipt\n")?
    Display.fmt("item: {item.value}\n", &body)?
    &body.append("paid: yes\n")?
    // `into_bytes` hands the body's bytes to the response.
    .Ok(http.bytes(request, body.into_bytes()))
}

fn main() -> Result[UInt8, io.IoError] {
    defer var router = http.Router.new()
    if &router.route(r"GET /receipt/{item}", receipt).is_err() {
        return .Ok(2)
    }
    // `serve` does this for every request: carve an arena, read the request
    // into it, run the handler, write the response, and rewind the arena.
    defer var arena = mem.Arena.open(mem.system(), size: 65536)
    // The router's state is `()`, so the loop passes its one value, `()`.
    var nothing = ()
    let paths = ["/receipt/tea", "/receipt/scones"]
    for path in paths {
        &arena.rewind()
        let sent = http.new_request(arena.handle(), "GET", path, body: "") else |_| {
            return .Ok(1)
        }
        let response = &router.serve_http(&nothing, sent.request()) else |_| {
            return .Ok(1)
        }
        // The body is bytes; `Str.from_bytes` reads them as text.
        let body = Str.from_bytes(response.body().unwrap()).unwrap()
        // `io.print` writes the text without adding a line break.
        io.print(body)?
    }
    .Ok(0)
}
```

```
Receipt
item: tea
paid: yes
Receipt
item: scones
paid: yes
```

`receipt` never names an allocator of its own: `request.allocator()` is the
arena, so the body, and the response `http.bytes` wraps around it, live there.
`body.into_bytes()` hands the finished `String`'s bytes to the response.
`Display.fmt("item: {item}\n", &body)?` writes an interpolated line into the
string ([Text](08-text.md#an-interpolation-is-a-value-not-a-str) explains why
an interpolation is written this way rather than passed to `append`).

The loop in `main` plays `serve`. `http.new_request` builds a request in the
arena, and `&router.serve_http(state, request)` runs the router on it, as
`serve` does for each connection; `serve_http` belongs to the `http.Handler`
trait, hence `use http.Handler`. This router has no state, so the loop passes
`()`, the unit type's one value, from a `var`, because the state is lent
`inout`.
`response.body()` answers the body's bytes, `Str.from_bytes` reads them as
text, and `io.print` writes that text without adding a line break.

The rewind protects every request the way it protected `first` in
[Memory](07-memory.md#rewinding-one-arena-used-again-and-again). Build a
request before the loop and read its path after the loop:

<!-- guide: unchecked the error an edit of the program above produces -->
```
error[O-Borrow]: this operation invalidates a place that a later observation still needs
  --> request_kept.lin:37:9
   |
37 |         &arena.rewind()
   |         ^^^^^^^^^^^^^^^ keep this place available until the last use of its observation
49 |     io.println(first.request().path())?
   |                ----- the observation is still used here
```

Inside `serve`, the same check means a handler cannot keep a request's text or
a response past the request it belongs to: the program would not compile.

### Router patterns

A pattern is a method and a path. Write it as a raw literal
([Text](08-text.md#raw-literals-text-exactly-as-written)) so the braces are the
router's, not an interpolation:

| Segment | Matches |
| --- | --- |
| `forecast` | exactly that segment |
| `{city}` | any one segment, percent-decoded |
| `{rest...}` | the rest of the path, slashes included |

A pattern without `{rest...}` matches its own path and nothing beneath it:
`GET /` answers the root alone, and `GET /static/` answers `/static/` but not
`/static/site.css`. To answer every path beneath one, end the pattern with
`{rest...}`: `GET /static/{file...}` answers `/static/site.css` and
`/static/css/print.css`, and `/static/` too, with an empty `file`.

When several patterns match, the most specific wins: at the first segment
where two patterns differ, a literal beats `{name}`, which beats `{name...}`.
That is why `/forecast/today` reached `today` although `{city}` matches it
too, and the order you register routes in does not matter. A path that matches
only under another method is answered 405 with an `Allow` header, and a path
nothing matches is answered 404, both without a handler of yours.
`&router.route(…)` refuses a malformed pattern with an `http.RouteError`, so
`routes` passes it up with `?`.

## Reading inputs, sharing state and logging

A real service reads more than the path, keeps something between requests, and
says what it did.

### A server that reads, remembers and logs

This server takes readings from weather stations; save it as `stations.lin`:

<!-- guide: unchecked the server runs until it is stopped and the output is a curl session -->
```linea
import std.http
import std.io
import std.json
import std.log
import std.mem
import std.net

// `App` is the state every route shares. `http.with_state` owns it and lends
// it to the route that answers each request as `inout app`.
@derive(Release)
struct App {
    logger: log.Logger[io.Descriptor],
    readings: UInt64,
}

// `Reading` is the JSON a station posts, such as `{"celsius":21,"sky":"clear"}`.
// `json.Decode[mem.Handle]` reads one from a JSON document, allocating the text
// of `sky` in `mem.Handle`, and `Release` frees that text.
@derive(Release, json.Decode[mem.Handle])
struct Reading {
    celsius: Int64,
    sky: String[mem.Handle],
}

// A `Reading` reads itself from the request's JSON body, so a handler can ask
// for one.
impl http.Extract[mem.SystemAllocator] for Reading {
    fn extract(request: http.Request) -> Result[Reading, http.Error] {
        request.extract[http.Json[Reading]]()
    }
}

// `Recorded` is the answer, such as `{"station":"harbour","sky":"clear","count":1}`.
@derive(json.Encode)
struct Recorded {
    station: Str,
    sky: Str,
    count: UInt64,
}

// `Station` names the station that sent a request, read from its
// `Authorization: Bearer <name>` header.
@derive(Release)
struct Station {
    name: Str,
}

// Any type becomes an extractor by implementing `http.Extract` for every
// allocator `P`. `extract` answers the value, or the error that answers the
// request instead. The name borrows the request's header, so it lives as long
// as the request, which is a carrier.
impl[P: Allocator] http.Extract[P] for Station {
    fn extract(request: http.Request[P]) -> Result[Station, http.Error[P]] {
        let header = request.header("Authorization").unwrap_or("")
        if header.slice(0, 7).unwrap_or("") != "Bearer " || header.length() == 7 {
            return .Err(http.error(request, .Unauthorized, "name the station with `Authorization: Bearer <name>`"))
        }
        let name = header.slice(7, header.length()).unwrap()
        .Ok(.{ name })
    }
}

// POST /readings records one reading. After the state, each parameter is an
// extractor: the station, then the reading. The router reads them in this
// order and answers the request with the first refusal.
fn record(inout app: App, station: Station, reading: Reading, request: http.Request) -> Result[http.Response, http.Error] {
    app.readings += 1
    app.logger.info("reading", log.field("station", station.name).and("celsius", reading.celsius))
    http.json(request, Recorded { station = copy(station.name), sky = reading.sky.view(), count = app.readings })
}

// `derive(http.Params)` reads a struct from a query's `name=value` pairs.
// An `Option` field may be left out of the query.
@derive(http.Params, Release)
struct Outlook {
    days: Option[UInt64],
}

// GET /outlook?days=3 streams one line per day. The closure captures the
// checked `count` with `sink`, so it keeps the number after `outlook` returns.
fn outlook(query: http.Query[Outlook], request: http.Request) -> Result[http.Response, http.Error] {
    let count = copy(query.value.days).unwrap_or(3)
    if count > 7 {
        return .Err(http.error(request, .BadRequest, "the outlook covers at most 7 days"))
    }
    http.stream(request, [sink count] |inout body| write_outlook(count, &body))
}

fn write_outlook(days: UInt64, inout body: http.BodyWriter) -> Result[(), http.Error] {
    for day in 1..=days {
        Display.fmt("day {day}: sunny\n", &body)?
    }
    .Ok(())
}

// GET /stats reads the count `record` keeps in the state.
fn stats(inout app: App, request: http.Request) -> Result[http.Response, http.Error] {
    http.text(request, "{app.readings} readings\n")
}

// `retains(router: greeting)` says the router keeps what `greeting` points at.
fn routes(inout router: http.Router[App], greeting: Str) -> Result[(), http.RouteError] where retains(router: greeting) {
    &router.route("POST /readings", record)?
    &router.route("GET /outlook", outlook)?
    &router.route("GET /stats", stats)?
    // A route can be a closure, registered with `route_raw`. This one captures
    // a copy of `greeting`.
    &router.route_raw("GET /", [sink greeting = copy(greeting)] |inout _, request| http.text(request, greeting))
}

fn main() -> UInt8 {
    let logger = log.to_stderr(minimum: .Info)
    // The annotation names the state the routes take.
    var router: http.Router[App] = http.Router.new()
    if routes(&router, "Weather stations report here.\n").is_err() {
        router.release()
        return 2
    }
    // `http.logged` logs the address the server listens on and one line per
    // request. `http.with_request_ids` around it numbers each request, so the
    // number is in the response and in the logged line. `state: app` hands the
    // state to the server, which lends it down through both to the route that
    // answers and gives it back when serving ends.
    let app = App { logger = copy(logger), readings = 0 }
    let server = http.with_request_ids(http.logged(copy(logger), router))
    let finished = http.listen_and_serve(net.loopback(8080), server, state: app) else |error| {
        logger.error("serving stopped", log.field("error", error))
        return 1
    }
    logger.info("stopped", log.field("readings", finished.readings))
    finished.release()
    0
}
```

### Trying the station server

Run it with `linea run stations.lin`. Each `curl` command below is followed by
what the server answers:

```
$ curl http://127.0.0.1:8080/
Weather stations report here.
$ curl -X POST -H 'Authorization: Bearer harbour' -H 'Content-Type: application/json' -d '{"celsius":21,"sky":"clear"}' http://127.0.0.1:8080/readings
{"station":"harbour","sky":"clear","count":1}
$ curl -i -X POST -H 'Content-Type: application/json' -d '{"celsius":21,"sky":"clear"}' http://127.0.0.1:8080/readings
HTTP/1.1 401 Unauthorized
Connection: close
X-Request-Id: 3
Content-Type: text/plain; charset=utf-8

name the station with `Authorization: Bearer <name>`
$ curl -i -X POST -H 'Authorization: Bearer harbour' -H 'Content-Type: application/json' -d '{"celsius":21}' http://127.0.0.1:8080/readings
HTTP/1.1 422 Unprocessable Content
Connection: close
X-Request-Id: 4
Content-Type: text/plain; charset=utf-8

missing field at $["sky"]
$ curl http://127.0.0.1:8080/stats
1 readings
$ curl 'http://127.0.0.1:8080/outlook?days=2'
day 1: sunny
day 2: sunny
$ curl -i 'http://127.0.0.1:8080/outlook?days=many'
HTTP/1.1 400 Bad Request
Connection: close
X-Request-Id: 7
Content-Type: text/plain; charset=utf-8

cannot read query value "days" from "many": invalid decimal syntax at byte 0
```

While it runs, standard error shows what happened:

<!-- guide: unchecked the output of an edited or partial program -->
```text
2026-09-27T13:04:43Z INFO listening address=127.0.0.1:8080
2026-09-27T13:04:43Z INFO request method=GET path=/ request_id=1 status=200 bytes=30 duration=91µs
2026-09-27T13:04:43Z INFO reading station=harbour celsius=21
2026-09-27T13:04:43Z INFO request method=POST path=/readings request_id=2 status=200 bytes=45 duration=144µs
2026-09-27T13:04:43Z WARN request method=POST path=/readings request_id=3 status=401 bytes=53 duration=28µs error="the handler refused the request: name the station with `Authorization: Bearer <name>`"
2026-09-27T13:04:43Z WARN request method=POST path=/readings request_id=4 status=422 bytes=26 duration=37µs error="the handler refused the request: missing field at $[\"sky\"]"
2026-09-27T13:04:43Z INFO request method=GET path=/stats request_id=5 status=200 bytes=11 duration=25µs
2026-09-27T13:04:43Z INFO request method=GET path=/outlook request_id=6 status=200 bytes=26 duration=27µs
2026-09-27T13:04:43Z WARN request method=GET path=/outlook request_id=7 status=400 bytes=77 duration=28µs error="the handler refused the request: cannot read query value \"days\" from \"many\": invalid decimal syntax at byte 0"
```

The rest of this section takes it apart.

### Extractors

An **extractor** is a type the router can read out of a request. A handler asks
for one by naming it as a parameter, one per input, and the router answers the
request with the refusal when an input cannot be read. If you know axum, these
are its extractors, named in the handler's signature as axum names them.

| Extractor | Reads | Refuses with |
| --- | --- | --- |
| `http.Path[T]` | the route's path values: one into a `Str` or a number, several into a struct | 400 when a value does not parse |
| `http.Query[T]` | the query, `?days=2`, into a struct that derives `http.Params` | 400 when a value does not parse, or a name appears twice |
| `http.Json[T]` | a JSON body into a `T` that derives `json.Decode[A]`, decoded into the request's arena | 415 when it is not sent as JSON, 400 when it is not JSON, 422 when it is not a `T` |
| `http.Form[T]` | a form body, `name=Ada&age=30`, into a struct that derives `http.Params` | 415 when it is not sent as a form, 400 when a value does not parse |
| a type of your own | whatever its `http.Extract` implementation reads | whatever its implementation answers |

`http.Path`, `http.Query`, `http.Json` and `http.Form` wrap the value they
read, so a handler writes `query.value.days`. A type that implements
`http.Extract` itself is read straight into the parameter: `Reading` reads its
JSON body, so `record` takes `reading: Reading` and uses `reading.sky`. The
implementation is the one line `request.extract[http.Json[Reading]]()`, which
reads the wrapper and hands over what it holds. Each extractor must implement
`Release`, which the router calls after the handler returns; in the request's
arena that costs nothing, but the type does not know where it lives.

`derive(http.Params)` fills a struct field by field from values of the same
names: a field that implements `text.Parse`, such as a number, is parsed, a
`Str` is taken as sent, and an `Option` of either is `.None` when the request
leaves it out. `Outlook { days: Option[UInt64] }` is that. The [JSON echo
server](../../examples/http-json-echo/main.lin) reads a form with `http.Form`.

`Station` is an extractor of the program's own. Any type becomes one by
implementing `http.Extract` for every allocator `P`. `impl[P: Allocator]` is a
generic implementation: its brackets declare a type parameter for the whole
`impl`, as a generic function's do, so one block implements
`http.Extract[P]` for every `P` at once. `extract` looks at the
request and answers the value, or the `http.Error` that answers the request
instead. `Station` reads its name out of the `Authorization` header, and the
name points into the request, so it lives as long as the request does. A real service would check a token there; this one
trusts the name.

A handler that wants to read an input itself, to log a refusal before
answering it, say, calls `request.extract[T]()` in its body and registers with
`route_raw`. `request.extract[http.Path[UInt64]]()` returns the number itself,
where a parameter holds the `Path`, and `?` answers the request with the
refusal. The [calendar
export](../../examples/calendar-export/main.lin) does this.

### Cookies

A browser sends the cookies it holds in a `Cookie` header, `theme=dark;
visits=3`, and a server sets one with a `Set-Cookie` header on a response.
`request.cookie(name)` returns the value of the cookie with that name, or
`None`; `request.cookies()` walks every `name=value` pair in the order they
arrived. Both borrow the request and allocate nothing. Names are case-sensitive,
whitespace around a pair is ignored, a pair that is not `name=value` is skipped
without hiding the others, and the value is exactly what the browser sent: no
decoding, and the quotes dropped if it sent any.

`&response.set_cookie(name, value, ...)?` adds a `Set-Cookie` header. Its
attributes are named arguments, each left out unless given: `path` and `domain`,
`max_age` in seconds, `expires` as a `time.Timestamp`, `secure`, `http_only`
and `same_site` (`.Strict`, `.Lax` or `.Unrestricted`, which sends
`SameSite=None`). `clear_cookie(name, path:, domain:, secure:)` asks the
browser to delete one, as the second program below shows.

```linea
import std.http
import std.io
import std.mem

use mem.Owner

fn main() -> Result[UInt8, io.IoError] {
    defer let arena = mem.Arena.open(mem.system(), size: 8192)
    var sent = http.new_request(arena.handle(), "GET", "/", "").unwrap()
    &sent.add_header("Cookie", "theme=dark; visits=3").unwrap()
    let request = sent.request()

    // `cookie` finds one cookie by name; `cookies` walks them all.
    io.println("theme: {request.cookie("theme"):?}")?
    io.println("lang: {request.cookie("lang"):?}")?
    for pair in request.cookies() {
        io.println("{pair.name} = {pair.value}")?
    }

    var response = http.text(request, "ok").unwrap()
    &response.set_cookie("visits", "4", path: "/", max_age: .Some(3600), http_only: true, same_site: .Some(.Lax)).unwrap()
    io.println(response.header("Set-Cookie").unwrap())?

    // A value that holds `;` would end the cookie early, so it is refused.
    match &response.set_cookie("note", "a;b") {
        Ok(_) => io.println("accepted")?,
        Err(error) => io.println("refused: {error}")?,
    }
    .Ok(0)
}
```

```
theme: Some("dark")
lang: None
theme = dark
visits = 3
visits=4; Path=/; Max-Age=3600; SameSite=Lax; HttpOnly
refused: the cookie value holds a byte a cookie cannot carry
```

`set_cookie` refuses a cookie that would be sent malformed rather than send it,
with a `CookieError`: a name that is not an HTTP token, a value holding a space,
`"`, `,`, `;`, `\`, a control byte or anything outside ASCII (encode such text,
for example in hexadecimal), a path that does not start with `/` or holds a
space, `;`, a control byte or anything outside ASCII (percent-encode it), and a
domain that is not letters, digits, hyphens and dots. It also refuses what
browsers would silently discard: `SameSite=None` without `secure`, an `expires`
before 1601, a name starting with `__Secure-` without `secure`, and a name
starting with `__Host-` without `secure`, with a `domain`, or with a `path`
other than `/`. Because a handler's own mistake is not the client's, `?`
answers 500 for it. Set `http_only` on a cookie scripts do not need to read,
and `secure` on any cookie that matters over HTTPS.

A browser deletes a cookie only when the clearing header names the same `path`
and `domain` the cookie was set with, and it deletes a `__Secure-` or `__Host-`
cookie only through a `secure` header. A `__Host-` name is the safest choice
for a session: no other subdomain can set a cookie of that name for yours. A
handler that signs a visitor out clears both of its cookies:

```linea
import std.http
import std.io
import std.mem

use mem.Owner

fn main() -> Result[UInt8, io.IoError] {
    defer let arena = mem.Arena.open(mem.system(), size: 8192)
    let sent = http.new_request(arena.handle(), "POST", "/logout", "").unwrap()
    let request = sent.request()

    // The theme cookie was set with `path: "/app", domain: "example.com"`.
    var forget_theme = http.text(request, "signed out").unwrap()
    &forget_theme.clear_cookie("theme", path: "/app", domain: "example.com").unwrap()
    io.println(forget_theme.header("Set-Cookie").unwrap())?

    // A `__Host-` cookie is cleared only by a secure header with the path /.
    var end_session = http.text(request, "signed out").unwrap()
    match &end_session.clear_cookie("__Host-session", path: "/") {
        Ok(_) => io.println("accepted")?,
        Err(error) => io.println("refused: {error}")?,
    }
    &end_session.clear_cookie("__Host-session", path: "/", secure: true).unwrap()
    io.println(end_session.header("Set-Cookie").unwrap())?
    .Ok(0)
}
```

```
theme=; Path=/app; Domain=example.com; Max-Age=0; Expires=Thu, 01 Jan 1970 00:00:00 GMT
refused: a cookie named __Secure- must be secure, and one named __Host- must also have the path / and no domain
__Host-session=; Path=/; Max-Age=0; Expires=Thu, 01 Jan 1970 00:00:00 GMT; Secure
```

The [welcome-back server](../../examples/welcome_back.lin) counts a browser's
visits in a cookie and shows the visitor's name with
[`html.escaped`](08-text.md#escaping-text-for-html).

### Handlers over another allocator

Every request lives in an arena of its own, carved from a parent allocator
`P`. `http.Request`, `http.Response` and `http.Error` default `P` to
`mem.SystemAllocator`, so the handlers above serve requests whose arenas come
from the system. A handler for a server whose parent is another allocator, or
a handler that must serve any parent, writes `P` as a type parameter and
passes it to each of the three, as a library would. Such a handler takes the
state and the request and is registered with `route_raw`, because `route` takes a
function whose types are settled and a generic function is not a value until
its `P` is. A decoded type that holds text names its allocator in the same way,
as `Note[mem.Handle[P]]` for a generic handler and `Note[mem.Handle]` for the
system one. The handlers of this program have no type parameter, so `route`
registers them by name:

```linea
import std.http
import std.io
import std.json
import std.mem

use http.Handler
use mem.Owner

@derive(Release, json.Decode[mem.Handle])
struct Note {
    text: String[mem.Handle],
}

impl http.Extract[mem.SystemAllocator] for Note {
    fn extract(request: http.Request) -> Result[Note, http.Error] {
        request.extract[http.Json[Note]]()
    }
}

fn health(request: http.Request) -> Result[http.Response, http.Error] {
    http.text(request, "ok")
}

fn echo(note: Note, request: http.Request) -> Result[http.Response, http.Error] {
    http.text(request, note.text.view())
}

fn main() -> Result[UInt8, io.IoError] {
    var router = http.Router.new()
    defer router.release()
    if &router.route("GET /health", health).is_err() {
        return .Ok(2)
    }
    if &router.route("POST /echo", echo).is_err() {
        return .Ok(2)
    }
    var arena = mem.Arena.open(mem.system(), size: 65536)
    defer arena.release()
    var nothing = ()
    let sent = http.new_request(arena.handle(), "POST", "/echo", body: r#"{"text": "hello"}"#, content_type: "application/json") else |_| {
        return .Ok(1)
    }
    let response = &router.serve_http(&nothing, sent.request()) else |_| {
        return .Ok(1)
    }
    io.println(Str.from_bytes(response.body().unwrap()).unwrap())?
    .Ok(0)
}
```

```
hello
```

`health` and `echo` have no type parameter, and `Note` reads itself, so the router
reads the body into one before it calls `echo`. The same handler written for any parent is
`fn health[P: Allocator](inout _: (), request: http.Request[P]) -> Result[http.Response[P], http.Error[P]]`:
inside a declaration with its own allocator parameter, a type that leaves the
allocator to its default is refused with `[T-DefaultedAllocator]`, so a generic
handler writes `P` in all three
([Memory](07-memory.md#the-allocator-is-part-of-the-type)).

### Shared state

`App` is the **state**: the logger and the count of readings. The call
`http.listen_and_serve(address, server, state: app)` owns it and lends it, as
`inout app`, to the route that answers each request, one request at a time.
So `record` can add to `app.readings` and `stats` can read it, with no global
variable and no lock: `serve` answers one request at a time. The annotation
`http.Router[App]` on the router names the state its routes take, and
`Router.new()` makes it. A route that does not use the state leaves it out,
like `outlook`, and the router lends it only to the routes that ask. Leave the
annotation out and `Router.new()` makes a `Router[()]`, whose routes take no
state: registering `record` on it is a mismatch, and its help says that
`Router.new()` left `S` to its default `()`.

The state is released with the server on a failure, so it may hold something
that must be settled, such as a vector from `mem.system()` or a database
connection. When serving ends normally `listen_and_serve` returns the state,
as the last lines of `main` do to log a final count, and the program releases
it. A call that passes no `state:` serves a state of `()`, and returns `()`.
A program that serves with `http.serve` keeps the server, so after serving
stops `server.state()` reads the state back. This is axum's `State`, lent
rather than cloned.

A route can be a closure instead of a named function, registered with
`route_raw`, which takes a function of the state and the request: `GET /` is
`[sink greeting = copy(greeting)] |inout _, request| http.text(request, greeting)`.
The router keeps the closure for as long as it lives and calls it for reading,
so its captures are fixed configuration, such as this greeting; they may hold
nothing that must be released. A count that changes belongs in the state.
Because the router keeps a copy of the `greeting` view, `routes` says so with
`where retains(router: greeting)` ([Borrowing](06-borrowing.md#retains--i-am-putting-it-inside-something-of-yours)).

### Streaming

`outlook` answers with a **streamed** body. `http.stream(request, write)`
sends the head straight away, then calls `write` with an `http.BodyWriter`,
which is a `Writer`, and sends what it writes as it writes it. Use it for a
body larger than the request's arena, such as a generated report, or for one
that arrives over time. `write` is a closure here, `[sink count] |inout body|
write_outlook(count, &body)`: the handler checks `count` first, refusing more
than seven days with a 400 before anything is sent, and the closure carries the
checked number into the body. If `write` fails partway, the server resets the
connection, so the client cannot mistake half a body for a whole one. The
closure lives in the request's arena with the rest of the response, so it too
may capture nothing that must be released.

#### A body that arrives over time

What `write` produces is buffered and sent 4 KiB at a time. A body that paces
itself — a line now, the next a second later — calls `body.flush()` to send
each line before it waits. The [countdown server](../../examples/countdown-server/main.lin)
counts down to a launch this way. Its handler checks the count and streams:

```linea
fn countdown(inout app: App, path: http.Path[UInt64], request: http.Request) -> Result[http.Response, http.Error] {
    // `http.Path[UInt64]` reads the route's only path value, `{seconds}`, as a
    // number, and the router answers 400 when it is not one.
    let seconds = path.value
    if seconds < 1 || seconds > longest_countdown {
        return .Err(http.error(request, .BadRequest, "{seconds} is not a count from 1 to {longest_countdown}"))
    }
    app.logger.info("starting a countdown", log.field("seconds", seconds))
    http.stream(request, [sink seconds] |inout body| count_down(seconds, &body))
}
```

and the body writes one line a second:

```linea
fn count_down(seconds: UInt64, inout body: http.BodyWriter) -> Result[(), http.Error] {
    let tick = time.Duration.from_seconds(1)
    var left = seconds
    while left > 0 {
        "T-{left}\n".fmt(&body)?
        let _sent = &body.flush()?
        time.sleep(tick)
        left -= 1
    }
    &body.write_str("liftoff\n")?
    .Ok(())
}
```

`"T-{left}\n".fmt(&body)` is `Display.fmt("T-{left}\n", &body)` written as a
dot call. `time.sleep` blocks for at least the duration it is given, and
`flush` comes from the `io.ByteWriter` trait, so the example has
`use io.ByteWriter`. Run it
with `linea run examples/countdown-server -- --port 8080`, and ask for a
countdown with `curl -N`, which prints each line as it arrives instead of
waiting for the whole body:

<!-- guide: unchecked a shell session, not the output of one program -->
```
$ curl -N http://127.0.0.1:8080/countdown/3
T-3
T-2
T-1
liftoff
```

The lines appear a second apart. The server's log shows the request took as
long as the countdown did:

<!-- guide: unchecked the output of an edited or partial program -->
```text
2026-09-27T13:05:02Z INFO listening address=127.0.0.1:8080
2026-09-27T13:05:03Z INFO starting a countdown seconds=3
2026-09-27T13:05:06Z INFO request method=GET path=/countdown/3 status=200 bytes=20 duration=3.027366s
2026-09-27T13:05:06Z WARN request method=GET path=/countdown/11 status=400 bytes=31 duration=32µs error="the handler refused the request: 11 is not a count from 1 to 10"
```

### Logging

`log.to_stderr(minimum: .Info)` makes a logger that writes lines
at `Info` and above to standard error. `logger.info(message, fields)` writes
one line; `log.field("station", name).and("celsius", celsius)` builds its
fields, each looking at its value. A line with no fields passes `()`, the one
value of the unit type from [Linea in an
hour](01-linea-in-an-hour.md#read-inout-and-sink): `logger.info("stopping", ())`.
A logger to standard error owns nothing, so `copy(logger)` gives the state and
the middleware loggers of their own, and `main` keeps one for its own lines.

`http.logged(logger, handler)` is **middleware**: a handler that holds another
handler and passes each request on. It logs one line per request once the
answer has been sent, with its status, size and duration: `Info` for 2xx and
3xx, `Warn` for 4xx, `Error` for 5xx. The `reading` line comes from `record`
itself, through `app.logger`, while it answers.

`http.with_request_ids(handler)` is middleware too. It numbers the requests it
passes on, 1, 2, 3 and so on, so a client can quote the number when reporting a
problem. Each request the handler receives carries the number as an
`X-Request-Id` header, read with `request.header("X-Request-Id")`. Any header
of that name the client sent is removed, so the handler never sees a number a
client chose. The handler's answer, a response or a refusal, carries the same
header, replacing one the handler set itself. An answer the server writes
without the handler, such as a 413 or a 503, has no number.

Wrap it around `logged`, as `stations.lin` does, and each logged line gains
`request_id=3`. The number is printed from a field only `with_request_ids`
sets, never from a header, so plain `http.logged` never logs a client's value.
Wrapped inside `logged`, the handler and the answer still carry the number,
but the line has no `request_id` field. You do not need `http.Observer` for
any of this.

`serve` writes no log of its own. It reports each finished exchange, failures
included, to its handler through the `http.Observer` trait, which every handler
ignores unless it implements it; `http.logged` is what turns those reports into
lines. `listen_and_serve` also reports the address it bound, so `logged` writes
`INFO listening address=127.0.0.1:8080` before the first request.

#### Writing middleware of your own

A middleware of your own implements `http.Handler` to pass requests and the
state on, and `http.Observer` to pass the reports on; without the second, the
handler it holds, and anything logging inside it, would never see an event.
This one counts the responses it has passed on, works over any state `S`, and
keeps its count in a field of its own:

```linea
use http.Handler
use http.Observer

struct Counted[H] {
    next: H,
    served: UInt64,
}

impl[P: Allocator, S, H: http.Handler[S, P]] http.Handler[S, P] for Counted[H] {
    fn serve_http(inout self: Self, inout state: S, request: http.Request[P]) -> Result[http.Response[P], http.Error[P]] {
        self.served += 1
        var response = &self.next.serve_http(&state, request)?
        var count = String.new_in(request.allocator())
        self.served.fmt(&count)?
        &response.set_header("X-Served", count.view())?
        .Ok(response)
    }
}

impl[H: Observer] Observer for Counted[H] {
    fn observe[P: Allocator](inout self: Self, event: http.Event[P]) {
        &self.next.observe(event)
    }
}
```

A middleware that works with the application's own state implements
`http.Handler[App, P]` instead, and reads or changes `state` before passing it
on. The [JSON echo server](../../examples/http-json-echo/main.lin) wraps its
router in `http.logged` and then in `http.with_request_ids`. A middleware placed
inside `http.logged` is timed with the handler it holds.

## Limits

`http.listen_and_serve(address, server, state: app)` uses the standard
limits. Pass `limits:` to change them. `http.Limits.default()` gives the
standard ones, so struct update changes only what you write. In
`stations.lin`, this serves one connection and returns:

```linea
    let limits = http.Limits { connections = .Some(1), ..http.Limits.default() }
    let finished = http.listen_and_serve(net.loopback(8080), server, state: app, limits: limits) else |error| {
```

Each request is served from an arena carved from the system allocator. Pass
`parent:` to carve it from another one, such as `parent: arena.handle()`; a
call inside code that is generic over an allocator writes `parent:` too, since
a default there would silently exclude every other allocator.

| Field | Default | What it bounds |
| --- | --- | --- |
| `max_line_bytes` | 8 KiB | the request line and each header line |
| `max_headers` | 100 | how many headers a request may send |
| `max_query_pairs` | 100 | how many `name=value` pairs a query may hold; more is answered 414 |
| `max_form_pairs` | 100 | how many pairs a form body may hold; more is answered 413 |
| `max_body_bytes` | 1 MiB | the body |
| `request_arena_bytes` | 48 MiB | the arena each request is served from; it holds the request, what decoding its JSON body reserves, and the response |
| `read_timeout_ms` | 5000 | how long the whole request, head and body together, may take from the moment the connection is accepted, in milliseconds; a slower one is answered 408 |
| `write_timeout_ms` | 5000 | how long one write may wait, in milliseconds |
| `connections` | `.None` | how many connections to serve before `serve` returns; `.None` serves until the program ends |

`connections = .Some(n)` is how tests and examples run a server for a fixed
number of requests. `serve` refuses to start, with `ArenaTooSmall`, when the
arena could not hold the largest request the other limits allow.

## What `listen_and_serve` and `serve` promise

`listen_and_serve` opens the listener, tells the handler the address it bound
(`http.logged` logs it), runs `serve`, and releases the handler it took, and
the state too on a failure. So
these hold for `serve`, and for `listen_and_serve` with the handler released too:

- It owns the listener it is given and closes it on every exit.
- It answers one request per connection, one connection at a time.
- A failed connection — a client that disconnects, a malformed request, a
  timeout — is answered or dropped, and never stops the server.
- It returns only when accepting fails in a way retrying cannot fix, when the
  listener cannot be closed, when `limits.connections` is reached, or when
  the arena is too small for the limits you set.

## Running a handler as a CGI program

`listen_and_serve` makes your program the server. CGI turns that around: a web
server you already run starts your program once for each request, and the
program answers that one request and exits. CGI is serverless, minus the
vendor (and surprise bills): a supervisor invokes your code per request, hands
it a bag of environment variables, and collects the result. The variables
describe the request, a body arrives on standard input, and the response goes
to standard output.

`http.serve_cgi` runs any handler that way: the same routers, extractors,
middleware and limits as `listen_and_serve`, with the request read from the
environment and standard input instead of a connection.

```linea
import std.http
import std.io
import std.log

// `Visitor` is the name a query or a form gives, such as `name=Ada`.
@derive(http.Params, Release)
struct Visitor {
    name: Str,
}

// GET /hello?name=Ada greets the name in the query.
fn hello(visitor: http.Query[Visitor], request: http.Request) -> Result[http.Response, http.Error] {
    http.text(request, "Hello, {visitor.value.name}!\n")
}

// POST /hello greets the name a form sends on standard input.
fn sign(visitor: http.Form[Visitor], request: http.Request) -> Result[http.Response, http.Error] {
    http.text(request, "Welcome, {visitor.value.name}.\n")
}

fn routes(inout router: http.Router[()]) -> Result[(), http.RouteError] {
    &router.route("GET /hello", hello)?
    &router.route("POST /hello", sign)
}

fn main() -> UInt8 {
    var router = http.Router.new()
    if routes(&router).is_err() {
        router.release()
        io.eprintln("a route pattern was refused")
        return 2
    }
    // `http.logged` writes one line for the request to standard error.
    let logger = log.to_stderr(minimum: .Info)
    // `serve_cgi` reads the request this process was started for from its
    // environment and standard input, answers it on standard output, and
    // returns.
    let _ = http.serve_cgi(http.logged(logger, router)) else |error| {
        io.eprintln("{error}")
        return 1
    }
    0
}
```

```sh
linea run greet.lin
```

```
REQUEST_METHOD is not set, so no web server started this program to answer a request
```

Run from a shell with nothing set, there is no request to answer, so
`serve_cgi` returns `NotCgi` and writes nothing to standard output. A web
server always sets `REQUEST_METHOD`, and so can you:

<!-- guide: unchecked the program reads its request from environment variables the gate does not set -->
```
$ REQUEST_METHOD=GET PATH_INFO=/hello QUERY_STRING=name=Ada linea run greet.lin
Status: 200 OK
Content-Type: text/plain; charset=utf-8

Hello, Ada!
2026-10-12T22:47:51Z INFO request method=GET path=/hello status=200 bytes=12 duration=7µs
```

The answer starts with a `Status` header instead of an HTTP status line,
because the web server writes the status line and frames the connection
itself. The last line is `http.logged`'s, on standard error, which a web
server keeps in its error log.

That is the other half of what CGI buys you: the web server calls your
handler directly, so you debug it as an ordinary program by piping it a
request and watching standard error. Standard error is also where a handler's
own output belongs: standard output is the response, so a line a handler
writes there with `io.println` lands before the `Status` header, and the web
server refuses the whole answer. A form's body goes to standard input, and `CONTENT_LENGTH` says
how much of it to read:

<!-- guide: unchecked the program reads its request from environment variables and standard input the gate does not set -->
```
$ printf 'name=Grace' | REQUEST_METHOD=POST PATH_INFO=/hello \
    CONTENT_TYPE=application/x-www-form-urlencoded CONTENT_LENGTH=10 linea run greet.lin
Status: 200 OK
Content-Type: text/plain; charset=utf-8

Welcome, Grace.
2026-10-12T22:48:15Z INFO request method=POST path=/hello status=200 bytes=16 duration=7µs
$ REQUEST_METHOD=GET PATH_INFO=/hello linea run greet.lin
Status: 400 Bad Request
Content-Type: text/plain; charset=utf-8

missing query value "name"
2026-10-12T22:48:48Z WARN request method=GET path=/hello status=400 bytes=27 duration=9µs error="the handler refused the request: missing query value \"name\""
$ REQUEST_METHOD=POST PATH_INFO=/hello CONTENT_LENGTH=2000000 linea run greet.lin < /dev/null
Status: 413 Content Too Large
Content-Type: text/plain; charset=utf-8

2026-10-12T22:49:22Z WARN request status=413 bytes=0 error="reading the request failed: the request was refused with 413 Content Too Large"
```

These are the variables `serve_cgi` reads:

| Variable | What it becomes |
| --- | --- |
| `REQUEST_METHOD` | the method; without it there is no request |
| `PATH_INFO` | the path after the program's own address, `/` when empty |
| `QUERY_STRING` | the query, as the client encoded it |
| `CONTENT_TYPE`, `CONTENT_LENGTH` | the `Content-Type` and `Content-Length` headers; the body is that many bytes of standard input, and without a length there is no body |
| `HTTP_*` | every other header: `HTTP_USER_AGENT` is `User-Agent` |

`SERVER_PROTOCOL`, such as `HTTP/2.0`, is how the browser spoke to the web
server, which your program never speaks, so it is not read. Nor are
`HTTP_TRANSFER_ENCODING` and `HTTP_CONTENT_LENGTH`: the web server has already
taken apart however the browser framed the body, and `CONTENT_LENGTH` alone
says how long it is. When a variable appears twice, the first is read.

The request is held to the same `http.Limits` as one read from a connection,
and refused with the same statuses: 413 for a body past `max_body_bytes`, as
above, 431 for too many headers, 400 for a malformed method or length, and 400
for a method, query or header that is not UTF-8. A path that is not UTF-8 is
encoded byte by byte, as a browser would send it. The
timeouts do not apply, since the web server decides how long a program may
run. `serve_cgi(handler, state: app, limits: limits)` takes the same
`state:` and `limits:` as `listen_and_serve`, and `serve_cgi_in(allocator,
handler)` carves the request's arena from another allocator. Any other variable, such as one your server sets for the program's
configuration, is yours to read with `env.variable`, which returns
`Option[Str]`: `env.variable("PARTY_DATE").unwrap_or("soon")`. The text it
returns views the environment the process started with, so it allocates
nothing and lives until the process exits.

### Behind a web server

Any web server that speaks CGI can run the program. Build it once with `linea
build greet.lin -o greet` and point the server at the executable: Apache's
`mod_cgi`, lighttpd's `mod_cgi`, OpenBSD's `httpd` with `slowcgi`, or nginx
through a CGI wrapper such as `fcgiwrap`. A request for
`/cgi-bin/greet/hello?name=Ada` then runs `greet` with `PATH_INFO=/hello` and
`QUERY_STRING=name=Ada`, and the router sees `/hello`. The server also sets
`SCRIPT_NAME=/cgi-bin/greet`, the program's own address, so
`env.variable("SCRIPT_NAME")` is how a page builds a link or a form that leads
back to the program, as the party RSVP example below does.

Two rules come from CGI rather than HTTP. A response cannot set a `Status`
header, which the response's own status writes; `set_header` refuses it as it
refuses `Content-Length`. And a 200 response whose `Location` is a path on the
same server, such as `/thanks`, is a local redirect: the web server answers
the browser with that path's response instead and drops yours. To send the
browser elsewhere, answer a redirect status such as 303 with the `Location`.

### CGI or `listen_and_serve`

Both run the same handler; what differs is who owns the process.

- `listen_and_serve` is one long-lived process that answers one connection
  at a time. State in `state:` lives between requests, and nothing is paid to
  start each one; a slow request holds up the ones queued behind it.
- CGI starts a process per request, so the web server runs as many at once as
  it lets programs run: concurrency comes from processes, and the operating
  system keeps each one's memory apart. Every request starts fresh, so state
  that must outlive it goes in a file or a database, and each request pays for
  starting a process.

The [party RSVP](../../examples/party_rsvp.lin) example is a complete CGI
program: an HTML form, a reply checked and confirmed as JSON, and a date read
with `env.variable`.

## What you have seen

- A TCP listener and connection are linear and `@opaque`: `close` them on every
  path, and `&&` does not count as every path.
- A handler's parameters name what it reads: an optional `inout` state, up to
  six extractors, and the request last. The router reads each extractor,
  answers the first refusal with its status, and releases what it read.
- `http.Path`, `http.Query`, `http.Json` and `http.Form` are extractors, and a
  type of your own that implements `http.Extract` is read straight into its
  parameter. `request.extract[T]()` reads one in a handler's body, which
  `route_raw` registers.
- Every request lives in an arena that `serve` rewinds; `http.new_request`
  and `&router.serve_http(state, request)` drive the same steps by hand.
- `state: app` hands the state to `listen_and_serve`, which lends it to each
  route and returns it when serving ends; `http.Router.new()` and a call
  without `state:` serve none.
- `http.logged` logs every request, and handlers log through a logger kept in
  the state. `http.with_request_ids` numbers each request and answer, and
  around `logged` puts the number in the line.
- A closure can be a route, registered with `route_raw`, or a streamed body that carries what its handler
  computed; `body.flush()` sends what has been written.
- `http.listen_and_serve(address, handler, state:, parent:, limits:)` opens the
  listener, serves, and closes and releases everything on every path; only the
  address and the handler are required, and `http.serve` is the loop for a
  program that opens the listener itself.
- `http.Limits`, passed as `limits:`, bounds what a request may send and how
  many connections are answered.
- `http.serve_cgi(handler)` answers the one request a web server started the
  program for, read from the environment and standard input, on standard
  output; `env.variable(name)` reads any other variable the server sets.

Handlers are ordinary functions, so they are tested by calling them:
[Testing](10-testing.md#testing-a-server) shows how. The [JSON echo
server](../../examples/http-json-echo/main.lin) puts everything here together,
and the [calendar export](../../examples/calendar-export/main.lin) streams a
year of dates as CSV.

Next: [Testing](10-testing.md) — tests, helpers, allocation failures and
servers.
