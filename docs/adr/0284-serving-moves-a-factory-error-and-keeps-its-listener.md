# 284. Serving moves a factory's error and keeps its listener on the calling task

Status: Accepted — 2026-11-18. Supersedes the clause of
[0259](0259-a-handler-factory-may-fail-and-serving-begins-once-every-task-has-one.md)
§2 that a factory's error `E` "must be `Owned`, `Shareable` (it is sent from
the task that met it) and `Release`". Its bound on a factory's error,
`Owned + Release`, is superseded by
[0290](0290-a-handler-factory-error-holds-no-end-of-a-session.md), which adds
`Isolated`.

## Context

`http.serve`, `serve_in` and the private functions they forward through bound
their listener `L: net.Acceptor + io.Close + io.Pollable + Owned + Shareable +
Isolated`, and every serving function bounds the factory's error
`R.Error: Owned + Shareable + Release`.

The listener bounds date from when a listener moved into an owning task that
handed connections to the serving tasks. Since
[0265](0265-waits-go-through-the-runtimes-poller-and-a-loop-runs-tasks-as-fibers.md)
§6 the dispatcher on the calling task keeps the listener, registers it in its
wait set and accepts from it; 0265 states the bound as
`L: net.Acceptor + io.Pollable`. No serving task captures the listener, so
`Owned`, `Shareable` and `Isolated` asked a question nothing needed answered,
and refused a listener wrapper that observes a label of its caller.

The error's `Shareable` was justified by "it is sent from the task that met
it". Sending moves a value: a session's `send` and `recv` require `T: Owned`
alone, and the dispatcher takes the first failure into one slot and releases
later ones. No task reads an error another task still holds, so `Shareable`,
which lets two tasks read one value at once, guarded nothing, and refused an
error that keeps a handle to a C object the failing task opened.

## Decision

**The listener is bounded by what the dispatcher does with it**:
`L: net.Acceptor + io.Close + io.Pollable` with
`L.CloseError: Into[io.IoError]`.

**A factory's error is `Owned + Release`.** `Owned` stays because the error
leaves the task that made it, so it may not observe that task's memory; a
corpus case holds that an error holding a `Str` is refused. `Release` stays
because the second of two failures is released.

The parent allocator `P: Allocator + Shareable` and the factory
`M: Shareable + Copyable` keep their bounds: every serving task reads the
parent and runs a copy of the factory. `.Threads(128)` stays the default
policy.

## Consequences

- A listener holding a borrow of its caller is served, on any number of
  tasks; a corpus case serves one on two.
- A factory error holding a C handle, which is not `Shareable`
  ([0260](0260-a-handle-to-a-c-object-is-not-shareable-unless-its-wrapper-vouches.md)),
  is returned from `serve` and released by its caller; a corpus case serves
  with one on two tasks.
- Raw-storage types such as `mem.Arena` are still refused as an error,
  because they are not `Owned`.

## Alternatives considered

**Keep the bounds as a margin for a later design that moves the listener
again.** A later design that moves it adds the bound with the move. A bound
that no code needs is checked against every caller now and refuses programs
that are correct.
