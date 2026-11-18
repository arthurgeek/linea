# 285. A serving task announces the bound address once every task has its handler

Status: Accepted — 2026-11-18. Supersedes
[0259](0259-a-handler-factory-may-fail-and-serving-begins-once-every-task-has-one.md)
§4, that `listen_and_serve` makes one handler on the calling thread to
announce the bound address before any serving task starts, and the
consequence that it "makes one handler more than it has serving tasks".

## Context

`listen_and_serve` tells a handler `Event.Listening(address)` before it
accepts anything, which is how a program that asked for port 0 learns its
port and how `http.logged` writes its `listening` line. Under
`.Threads(n)` it called the factory once more than it had serving tasks: one
handler on the calling thread, told `Listening` and released at once, and
then one per task. 0259 accepted the extra handler and left a lifecycle
observer for later.

That order announced readiness before the serving tasks had started. With a
factory that fails on its second call and `.Threads(2)`, the announcing
handler succeeded, the first serving task's failed, and serving ended with
`Handler(E)` after `listening` had been logged. For the guest book the extra
handler was a SQLite connection opened and closed before serving.

The dispatcher already hands a serving worker work that only asks its
handler to observe something: an accept failure it is about to retry, which
the worker answers `Observed`.

## Decision

**`Listening` is one more kind of work a serving worker observes.**
`DispatchWork` gains `Listening(address)`. Once every serving task has
reported that its buffer and handler are ready, the dispatcher hands
`Listening` to one free worker and waits for `Observed` before it registers
its signals or the listener, so the announcement precedes every accepted
connection. A startup failure ends serving before that point, so nothing is
announced.

**The factory is called once per serving task and for nothing else.**
`.Sequential` already announced on its one handler and is unchanged. No
lifecycle observer is added: the handlers stay what is told what happened.

## Consequences

- With `.Threads(n)` the factory is called `n` times, and a factory that
  always fails is called once, by the first task, which stops the others
  from starting. Two tests in `std/http/serve.lin` hold both, and one holds
  that a factory failing on its second call leaves nothing announced.
- `Listening` reaches the handler of one serving task, on that task, rather
  than a throwaway handler on the calling thread. A handler that counts its
  events sees it once across all tasks.
- The guest book opens one SQLite connection per serving task and no other.

## Alternatives considered

**A lifecycle observer apart from the handlers.** It would be a second
public way to be told what happened while serving, for one event the
existing work channel already carries.

**Announce once the first worker is ready.** It is still before a later
task's factory may fail, so it announces a server that never serves.
