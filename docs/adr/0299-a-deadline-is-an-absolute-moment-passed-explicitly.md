# 299. A deadline is an absolute moment, passed explicitly to every wait

Status: Accepted — 2026-11-20. Supersedes the clause of
[0265](0265-waits-go-through-the-runtimes-poller-and-a-loop-runs-tasks-as-fibers.md)
§10 that states a connect's and an accept's bound as relative milliseconds
(`within_ms`, `accept_within(ms)`, zero meaning none).

## Context

Every bound on a wait in the standard library was a count of milliseconds from
the moment the call started: `net.connect(address, within_ms:)`,
`Listener.accept_within(ms)`, `Connection.set_timeouts(read_ms:, write_ms:)`,
and `Connection.set_deadline(started, within_ms:)`, which bounded the reads of
a session from an instant the caller supplied. Retrying had no shared shape:
`net.accept_pause` held one doubling schedule in milliseconds, and the HTTP
dispatcher and `net.serve` threaded a `pause_ms` counter through it.

A piece of work that makes several waits, a client that connects, sends a
request, reads the answer and retries on failure, could not give them one
budget. Each step took a time of its own, so a request meant to take two
seconds took two seconds to connect, two more for each read, and as long
again for each retry. Dividing a budget by hand means reading the clock
before every step and subtracting, which every caller writes differently, and
a retry loop had nothing to tell it that the next attempt could no longer
finish in time. `set_deadline` was the one absolute bound, and it covered
reads alone, so a peer that never read could still hold a writer.

The runtime already took absolute deadlines: every network entry point
receives a moment on the monotonic clock in nanoseconds, 0 for none, and the
simulated backend compares it with its virtual clock. Only the library spoke
in relative milliseconds.

## Decision

### 1. `time.Deadline` is a moment on the monotonic clock, or `never`

`time.Deadline` is an opaque, copyable value: the monotonic clock's reading at
the deadline, or `time.never`, which never passes. It is made with
`Deadline.after(duration)`, from now, and a moment past the clock's range is
`never`. It is read with `remaining()`, the time left (zero once passed, `None`
for `never`), and `expired()`. `earlier(other)` returns the nearer of two, so a
step with a limit of its own still stops when the whole piece of work must.
It is `Comparable`, `never` sorting last.

`never` is a value rather than a zero or an `Option`: a bound of zero no longer
means "no bound", and a caller writes the absence it means. The runtime's
convention of 0 for none stays at the boundary: `Deadline` converts to the
runtime's nanoseconds in one internal function, and neither clock, real or
virtual, ever reads 0.

`Duration` stays the type of a relative wait: `time.sleep`, a backoff's
pauses, a wait set's timer, `recv_until`.

### 2. A deadline is passed explicitly, never ambient

Every blocking network operation that can take a bound takes the deadline as
an argument or as state the caller sets on the value it owns:

- `net.connect(address, deadline:)`, defaulting to `time.never`;
- `Listener.accept_by(deadline)`, beside `accept()`, which has no bound, so
  the `Acceptor` trait and `http.serve` are unchanged;
- `Connection.set_deadline(deadline)`, which bounds every later read *and*
  write, and `Connection.set_read_deadline(deadline)`, which bounds reads
  alone.

A connection keeps its deadline as state because `io.Reader` and
`io.ByteWriter` are traits whose operations take no bound, and a buffered
reader or a JSON decoder reads through them; the caller who owns the
connection sets it once and every layer above inherits it without a parameter
of its own. `set_timeouts(read_ms:, write_ms:)` stays: it bounds each
operation's stall separately, which a deadline does not express (a stream
that sends for an hour, each write prompt). An operation ends at whichever of
its stall bound and its deadline comes first, and `set_timeouts` no longer
clears the deadline.

The default `time.never` on `connect` keeps 0265's reason: every fixed number
is wrong for some caller, and the comparable libraries wait until the kernel
answers.

### 3. An expired deadline is `TimedOut`

An operation that would wait past its deadline fails with an `io.IoError`
whose category is `TimedOut`, the category a per-operation timeout already
reported, so one match answers both. A deadline already passed fails before
anything is consumed: a read takes no waiting bytes, a connect starts no
handshake. `TimedOut` leaves the connection usable, as before.

### 4. HTTP: the server's read bound is the request's deadline

The dispatcher turns `Limits.read_timeout_ms` into a `Deadline` when it sees a
request's first bytes and sets it with `set_read_deadline`, so the head and
body share it and a response is written under `write_timeout_ms` alone. The
same deadline reaches the handler as `Request.deadline()`: a handler that
waits on another service for the request passes it on, or the earlier of it
and a deadline of its own, and the exchange has one budget. A request no
server reads, built by a test or by `serve_cgi`, has `never`. The limits keep
their millisecond fields: they configure relative bounds, and a `Deadline`
cannot be written in a constant.

### 5. Retries: `time.Backoff` gives no pause that would outlast the deadline

`time.Backoff.new(first:, longest:)` holds a doubling schedule.
`next_pause(deadline)` answers the next pause, or `None` when the deadline
would pass before the pause ends, since the next attempt could not start in
time; `reset()` starts the schedule again after a success. A retry loop is
then ordinary code:

```linea
let deadline = time.Deadline.after(time.Duration.from_seconds(2))
var backoff = time.Backoff.new(first: time.Duration.from_milliseconds(50), longest: time.Duration.from_seconds(1))
loop {
    match net.connect(address, deadline: deadline) {
        Ok(connection) => return .Ok(connection),
        Err(error) => match &backoff.next_pause(deadline) {
            Some(pause) => time.sleep(pause),
            None => return .Err(error),
        },
    }
}
```

`net.accept_backoff()` is the schedule serving uses between failed accepts,
5 ms doubling to one second, replacing `net.accept_pause`; serving has no
deadline, so it passes `never`. The task serving a listener for several
workers records the deadline before which the listener is not asked again
instead of an instant and a pause.

## Consequences

- One value bounds a whole piece of work: a client makes a deadline once and
  hands it to `connect`, `set_deadline` and its retry loop.
- A deadline now bounds writes. A server that bounded only reads with
  `set_deadline` uses `set_read_deadline`; a session-wide deadline that ends a
  stalled write is what a session bound means, and `bounded_echo` drops its
  per-operation timeouts for it.
- `within_ms`, `accept_within`, `set_deadline(started, within_ms)` and
  `accept_pause` are gone, and their callers in the library, the examples, the
  runtime's fiber-migration programs and the guide are migrated.
- The cost: a deadline made inside a simulation is on its virtual clock, as an
  `Instant` is, and used outside it means nothing; and there is no jitter in
  `Backoff`, so a fleet of clients retrying one server back off in step. Jitter
  needs a random source the library does not yet hold for every caller, and a
  deterministic schedule keeps tests exact.
- There is no HTTP client yet; when one lands it takes a `Deadline` per
  request on these terms.

## Alternatives considered

- **An ambient deadline**, carried by the task or the `Io` and read by every
  wait, as Go's `context.Context` is threaded by convention and some runtimes
  scope a cancel deadline to a block. It hides the bound from the call that
  waits, so a library function called inside a deadline's scope may fail as
  timed out with nothing in its signature saying so, and a task spawned inside
  one has to choose whether it inherits. An explicit value costs an argument
  and keeps both visible.
- **Relative budgets subtracted by hand**, a `Duration` each step takes and
  the caller reduces by what the last step used. It is what callers had, and
  it is what a deadline computes once: the subtraction moves into
  `remaining()`, read at the moment of the wait.
- **A deadline argument on every read and write.** `io.Reader` and
  `io.ByteWriter` are shared by files, pipes, buffers and simulations, and a
  bound on each call would reach every implementation and every layer above,
  for the one resource that needs it. A connection's own deadline reaches the
  same waits.
- **Replacing `set_timeouts` with the deadline.** A per-operation stall bound
  answers a different question, how long one write may make no progress, and
  a long-lived stream needs it without a total bound.
- **`Option[Deadline]` for no bound.** It makes every consumer match before it
  can compare, and `earlier` with an absent side needs a rule of its own;
  `never` sorting last gives both for free.
- **A retry combinator taking a closure**, `time.retry(deadline, backoff,
  attempt)`. Which failures to retry, what to report before sleeping, and what
  to hand back belong to the caller; `net.serve` reports a retry before it
  sleeps and the dispatcher sleeps on a wait-set timer. A schedule the loop
  asks composes with all of them.
