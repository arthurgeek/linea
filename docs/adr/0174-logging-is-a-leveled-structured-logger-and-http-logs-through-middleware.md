# 174. Logging is a leveled, structured logger, and HTTP logs through middleware

Status: Accepted — 2026-09-25. Builds on
[0154](0154-sockets-and-http-follow-go.md) and
[0171](0171-the-standard-library-is-an-ordinary-library.md).
Extended by [0180](0180-state-is-lent-down-through-every-handler.md).

## Context

A server needs to say what it did. Before this record `std.http.serve` wrote
its failures to standard error as ad-hoc sentences (`http: reading a request
failed: …`), the HTTP examples printed `listening on …` to standard output,
and nothing recorded the requests that were answered. The library had no clock
either, so nothing could say when a line was written or how long a request
took.

Three things were wanted together: a logger an application uses directly, the
clocks it and any timing need, and request logging that no handler writes by
hand.

## Decision

### `std.time`

**`time.now()` reads the wall clock as a `time.Timestamp`**: whole seconds
since the Unix epoch and the nanoseconds past them, in the years 0000 to 9999,
the years RFC 3339 can write. Display writes RFC 3339 in UTC to the second,
`2026-09-25T09:31:02Z`. **`time.Instant.now()` reads the monotonic clock**, and
`since` and `elapsed` return a `time.Duration`, which displays in the largest
unit below it (`750ns`, `12.5µs`, `3.25ms`, `90.125s`).

**`time.sleep(duration)` blocks the calling thread for at least the
duration, measured on the monotonic clock.** It fixes a deadline when it is
called and sleeps until the clock reaches it; a signal or an early wake-up
sleeps again for what the clock says remains, so a pause is never cut short
and interruptions do not accumulate rounding. `Duration.from_milliseconds`
makes the durations a program usually writes.

Both clocks and the sleep come from two runtime functions,
`linea_clock_read(clock, &seconds, &nanoseconds)` and
`linea_clock_sleep(nanoseconds)`, declared in the runtime signature table
([T-ExternRuntime]) and tested in C. A fault test replaces `clock_gettime` and
`nanosleep`: a failed read is reported as its errno and writes nothing, and a
simulated clock shows an interrupted or early sleep going back to sleep for
exactly what remains. `serve`'s pause before retrying a failed accept is a
`time.sleep`, and the millisecond sleep the I/O runtime carried for it is gone.
A clock the system cannot read is a fault of the machine rather than of the
program, so `now` and `sleep` panic instead of returning a `Result` every
caller would have to handle, as Rust's `SystemTime::now` does.

### `std.log`

**`log.Logger[S, A]` writes to a `log.Sink` the caller chooses**, with a
minimum `log.Level`: `Debug`, `Info`, `Warn` or `Error`, which compare in
that order. A line is the time, the level, the message and the fields:
`2026-09-25T09:31:02Z INFO listening port=8080`.

**Logging reads the logger and never changes it.** `log.Sink.write_line`
takes its receiver read-only: a descriptor or a file writes through its
descriptor, which writing does not change. So `logger.info(...)` needs no
`&`, and `Logger` is `@copyable`: it copies wherever its sink and allocator
do. `log.to_stderr(allocator, minimum)` makes a logger over standard error,
which it does not own, so a program keeps one and hands `copy(logger)` to
`http.logged`; nothing is lent and taken back, and nothing needs releasing.
A logger that owns a file is affine: it moves, and `release` closes the file.

**Fields are built by `log.field(key, value)` and `.and(key, value)`**, and
`{}` is no fields. A field borrows its value, so a program logs a value it
keeps using, however many times, without copying it. A literal or a computed
value is a temporary that lives until the end of the logging statement
([ADR 0175](0175-a-borrowed-temporary-lives-until-the-end-of-its-statement.md)),
so `log.field("count", 3)` is written inline. The value is
any `Display` type, written through Display and quoted when it is empty or
holds a space, `=`, `"` or a control character, with escapes inside the
quotes. The message is quoted only when it holds `=`, `"` or a control
character, so spaces in it read naturally. Building fields formats nothing.

**A line below the minimum level costs one comparison**: no clock read, no
formatting, no allocation, and a test holds that last part with a counting
allocator.

**Each line is built in a buffer from the caller's allocator** and handed to
the sink in one write, so standard error receives whole lines and one system
call per line rather than one per piece. The buffer is released after the
write; the logger holds none, which is what lets it copy.

**A line that cannot be written is reported by `log` and dropped by the level
methods.** `log(level, message, fields)` returns `log.LogError`, `Memory` or
`Sink`, where a caller must notice a lost line. `debug`, `info`, `warn` and
`error` return `()` and drop such a line whole, never part of it, because a
program whose log output has failed has nowhere better to report it, and a
call site that must handle an error on every line is a call site nobody
writes.

**The text format visits fields through `log.Visitor`**, so a second format
is a second visitor over the same `log.Fields`, and a type of the program's
own can implement `Fields` to log itself.

### `http.Observer`, `http.logged` and middleware

**`serve` reports what happened through `http.Observer`**, a trait of its
own with one method, `observe[P](inout self, event: http.Event[P])`. `serve`
requires `H: Handler[P, ()] + Observer` and calls `observe` once each exchange has
ended, with what happened (`http.Exchange`: the request when it was read, the
status, the body bytes the answer wrote, and an `http.Failure` when the answer
was not the handler's response written whole), and before it retries a
failed accept. `serve` writes nothing of its own: its former stderr sentences
are these events.

**Every type observes by ignoring the events**, through
`default impl[T] Observer for T`, so a plain handler is one method,
`serve_http`, as before. The default sits on a separate trait because a
default implementation applies only to a trait with no type parameters, and
`Handler[P, S]` has two.

**A middleware is a handler holding another handler.** It implements
`Handler` to pass `serve_http` and the state on and wrap or change what
comes back, and
`Observer` to pass each event on. `http.logged(logger, handler)` is one: it
reads the monotonic clock before the handler runs and again in `observe`,
after the response has been written or streamed and the connection closed,
and logs one line per exchange at `Info` for 2xx and 3xx, `Warn` for 4xx, and
`Error` for 5xx or an answer that failed, with an `error` field saying why.
`Logged` is opaque: the logger and the start time are its own. The HTTP
examples wrap their routers in it, and the JSON echo example adds a second
middleware that numbers responses with an `X-Request-Id` header.

Because a response or error may view what the handler owns, and `observe` may
change it, `serve` writes the answer and settles its connection before
`observe` runs, and copies a message the event quotes into the request's arena
first.

### A streamed body can pace itself

A streamed body is written through a buffer, so lines written a second apart
would reach the client together. `BodyWriter` is an `io.ByteWriter`, and its
`flush` sends what is buffered at once; a flush that fails converts through
`?` into a 500 `http.Error`, as a failed write does. The
[countdown server](../../examples/countdown-server/main.lin) writes a line,
flushes, sleeps a second, and writes the next, and its transcript holds the
first byte arriving at least a second before the last, which fails when
the flush is taken out.

### Found on the way

Two compiler defects stood between this design and a middleware written the
obvious way, and both were fixed with cases of their own:

- **A call through a bound takes the trait's arguments from the bound.**
  A call through an `H: Handler[P, S]` bound read `P` only from its arguments, so a variant written without its enum had no type to take. Where
  the parameter carries exactly one bound on the trait, the bound's arguments
  are now the call's. A call whose argument the bound does not promise is
  refused in the generic body rather than at an instantiation.
- **A postfix call reaches an implementation whose trait arguments its
  arguments settle.** `impl[P, T, H: Handler[P, T]] Handler[P, T] for Logged[H, S, A]`
  covers `Logged` at every `P`; `Handler.serve_http(&logged, &state, request)`
  found it, and `&logged.serve_http(&state, request)` did not.

## Alternatives considered

**A facade in the style of Rust's `log` crate**: global macros writing to a
logger installed once per process. Linea has no global mutable state to install
a logger into, and a library that logs through a hidden global is a library
whose output the caller did not choose. Passing the logger is the explicit
form, and `http.logged` shows it costs one argument.

**`printf` only**: keep `io.eprintln` with interpolated sentences. It is what
the code did, and it gave no levels to filter by, no time, and no structure a
tool could read back; every sentence was a format of its own, and `serve`'s
were written to a stream its caller never chose.

**JSON now.** A JSON line format is the obvious second format and the fields
are designed for it: a visitor that writes `"key":value`. It was left out
because nothing in the repository reads logs by machine yet, and the text
format is what a person reads in a terminal. Adding it adds a visitor and a
choice at `Logger.open`, not a change to any call site.

**An anonymous struct literal for fields**, `.{ port = 8080 }`, read by
reflection. Linea has neither anonymous structs nor reflection, and a derive
would have to run at every call site. `field(…).and(…)` is a chain of ordinary
generic values the compiler already checks.

**A fixed buffer on the stack** instead of an allocator. Linea has no
array-repeat literal to make one of a useful size, and a fixed buffer either
cuts a long line or writes it in pieces; the caller's allocator keeps each line
whole and makes the one allocation the caller chose.

**Returning the write error from every log call.** Rejected above: `log`
reports it for the call site that must know, and the level methods do not
make a hundred call sites each discard a `Result`.

**Counting failed lines in the logger**, read back with `failures()`. The
count is state that every line changes, so logging would lend the logger
mutably and it could not be copied: a program would lend its logger to
`http.logged` and take it back to log after serving. A failure is reported
where it happens instead.

**A logger that keeps its line buffer between lines.** It saves one
allocation per line and makes the logger own memory, which again rules out
copying it. A line costs one allocation from the caller's allocator, which the
caller can make an arena.

**Fields that take their values**, `field(key, sink value)`. A value the
program keeps using had to be copied at every line: an echo server logging its
peer's address wrote `copy(peer)` five times. Borrowing takes nothing, and a
value that is not a place lives until the end of the logging statement.

**`serve` keeping its own stderr lines beside the events.** Two formats and a
writer the caller did not choose. With events, an unlogged server is silent,
which is what a handler that ignores `observe` asks for.

**Keeping `linea_sleep_ms` beside the new sleep.** It restarted `nanosleep`
with the time the interrupted call reported remaining, which is not measured on
the clock `Instant` reads and rounds at every interruption. Two sleeps would be
two answers to one question, so `serve` uses `time.sleep` and the old one is
removed.

**Timing in `serve`** rather than in the middleware. Every server would read
the clock whether it logged or not, and the duration would include reading the
request. `http.logged` times from the handler to the end of the response,
which is the time the application is answerable for; a request refused before
the handler ran is logged without one.

**`observe` as a required method of `Handler`.** Every handler, a router and
each application's state included, would carry an empty generic method for
events it ignores. It would not even prevent the mistake it guards against: a
middleware author writing the empty body hides events just as the default
does. With a separate `Observer` and a default, only middleware authors write
`observe`, and the pattern they follow says to pass it on.

## Consequences

- A handler implements `serve_http` alone. A middleware also implements
  `Observer` and passes each event on; one that does not takes the default,
  and what it holds, including any logger inside it, sees no events.
- A field built from a literal or a computed value is used in the statement
  that builds it; a field kept for a later statement borrows a binding.
- `serve` no longer writes to standard error. A server that wants its failures
  and requests recorded wraps its handler in `http.logged`.
- Once capturing closures land, a middleware can be written inline around a
  handler without a named type; the pattern stays the same, and the guide's
  chapter on HTTP should show both forms.
- A logger holds no mutable state, so copies of it can log from separate
  threads once there are threads; whether a sink's writes interleave is the
  sink's question, and a line is always one write.
