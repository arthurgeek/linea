# 290. A handler factory's error holds no end of a session

Status: Accepted — 2026-11-18. Supersedes the clause of
[0284](0284-serving-moves-a-factory-error-and-keeps-its-listener.md)
that bounds a factory's error `Owned + Release`.

## Context

0259 lets the factory each serving task of `http.serve` calls return
`Result[H, E]`, and ends serving with `Handler(E)` when one fails. `E` is sent
from the task that met it, and
[0284](0284-serving-moves-a-factory-error-and-keeps-its-listener.md) bounds it
`Owned + Release`: `Owned` because it is moved to the caller, and `Release`
because when two tasks fail the dispatcher keeps the first reason and releases
the second.

That release runs in the dispatcher, the task every serving task waits on for
its next connection, and before serving has ended. A `Release` is ordinary
code: an error holding an end of a session may send on it and wait for an
answer, from a serving task or from `main`, each of which may be waiting on the
dispatcher in turn. Then no task can move. The language promises that an
accepted program has no set of tasks waiting on each other forever, and the
bound let one through: `Owned` says nothing about what a value may wait on.

`Isolated` is the property that does: a type is `Isolated` when no value of
it holds an end of a session, so nothing reached through it can make its
holder wait on another task. An owning task bounds its state and its jobs
`Isolated` for the same reason
([0261](0261-an-owning-task-holds-nothing-that-waits.md)).

## Decision

**A handler factory's error is bounded `Owned + Isolated + Release`**, on `serve`, `serve_in`, `listen_and_serve` and every form that
reaches them, and on the dispatcher that receives it. A factory whose error
holds a session's end, a task's owner or a closure capturing one is [T-Bound]
at the call that passes the factory, which a corpus case holds.

## Consequences

- Every error a factory in the library, the examples and the guide returns is
  an enum of reasons or owned text, and each is `Isolated`.
- An application whose factory needs to report through a session sends on it
  inside the factory, before returning, rather than handing the end to the
  server.

## Alternatives considered

**Release a second failure's error after every serving task has been
joined.** The dispatcher would keep each reason until serving ended. That
holds an unbounded number of reasons for a policy of many tasks, and a reason
released after the joins may still wait on `main`, which is waiting for
`serve` to return.
