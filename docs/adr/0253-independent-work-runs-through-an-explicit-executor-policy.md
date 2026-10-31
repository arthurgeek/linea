# 253. Independent work runs through an explicit policy, and shared state through an owning task

Status: Proposed — 2026-10-27, rewritten 2026-10-31 to record what is built.
Complements [0250](0250-tasks-are-structured-through-linear-sessions.md) and
extends [0154](0154-sockets-and-http-follow-go.md) (`http.serve`).

## Context

[0250](0250-tasks-are-structured-through-linear-sessions.md) introduces tasks:
`task.prepare` and `task.start` run a body on a thread of its own, and the
creator's handle is a linear session endpoint `Chan[P, H]` whose `H` carries
every dependency the body captured until `close` joins the thread. That gives
dialogue between tasks a calculus, and it is the reason an accepted program
has no data race: a body's reads and lends last exactly as long as the body
runs.

Many parallel workloads need no dialogue:

- a data-parallel map over a collection;
- a few independent computations whose results are gathered;
- answering many HTTP requests at once.

Each is a set of independent, value-producing jobs. Two needs follow. A caller
must choose how much concurrency a library uses without the library being
rewritten, as a caller chooses an allocator. And jobs that must share mutable
state, a server's count of requests or its database, need a way to do it that
keeps the promise of no data races, no locks and no use of freed memory.

The first implementation of this record answered the second need with an
unjoined worker pool (`task.dispatch_worker`, `drain_workers`), a worker
handle that carried nothing (`Slot.start_worker` answering `WorkerTask`), a
process-wide handler lock, latches and a connection queue handing descriptors
between workers, and a many-to-one `session.Mailbox`. Review found each one
broke a promise in a program the compiler accepted: a body started with
`start_worker` kept running after its lends ended, so two tasks wrote one
place at once; a latch handle outlived the latch it freed; the handler lock
was held across user code and deadlocked when re-entered; a task holding its
own mailbox's sender waited on itself. Every one of those was a compiler bug,
not a library bug: the compiler trusted an annotation it could not check. This
record states the decisions that make them unwritable.

## Decision

### 1. `task.Policy` names how much concurrency a computation uses

```linea
pub enum Policy {
    Sequential,
    Threads(UInt64),
}
```

`.Sequential` runs every job in turn on the caller's thread and starts no
task. `.Threads(max)` runs jobs on tasks of their own: `task.map` and
`task.all` divide their items among at most `max` tasks, and `task.join`,
`join3` and `join4` start a task for each job whenever `max` is more than 1.
`.Threads(1)` runs the jobs in turn on the caller. A `max` of 0 is a
configuration error: the combinators stop the program, and serving reports
`ServeError.NoWorkers`.

### 2. Independent work goes through combinators over joined tasks

`task.join(policy, f1, f2)`, `join3` and `join4` answer a tuple of their jobs'
results; `task.all(policy, jobs)` answers a `Vec` of results in job order;
`task.map(policy, items, f)` applies `f` to every item and keeps their order;
`task.map_results` does the same for a fallible `f` and answers every result,
so one failing job drops none of the others' outputs. A job is `Owned`: it
holds no view of a value the caller keeps, so the jobs and the caller never
touch one value at once. `map`'s function is also `Shareable` and `Copyable`,
since every task calls a copy. Every combinator starts its tasks through
`task.start` and joins them before it returns.

### 3. Only the joined start may start a thread ([T-ThreadStart])

A runtime function that runs Linea code on a thread of its own may be named,
as a callee or as a value, only inside `task.Slot.start`, whose handle carries
the body's dependencies until `close` joins the thread. The runtime symbol
table marks those functions, and the rule reads the symbol a declaration
names, so a module granted `extern` is held to it as the standard library is.
No library can offer an unjoined or detached task: a worker pool, a fire-and-
forget dispatch or a handle that carries nothing cannot be written.

### 4. Shared mutable state lives in an owning task

`task.own(state)` starts a task that holds `state` and answers its linear
`Owner[S]`, or `Unowned[S]` holding the state when the task cannot be made.
`owner.client()` answers a copyable `Client[S]` that borrows the owner.
`client.call(job)` runs `job`, a function of `inout state: S`, on the owning
task, one call at a time, and answers what the job answers. `owner.close()`
joins the task and answers the state; releasing an `Owner` closes it and
releases the state.

The promises hold through rules the compiler already enforces:

- Only the owning task's thread touches the state. A call is a rendezvous on
  a runtime call queue under one mutex, so everything a caller did before the
  call happens before the job runs, and the job happens before the call
  returns.
- A client borrows its owner, so [O-Borrow] refuses `close` while a client is
  still used: every task holding one is joined first, and no client outlives
  the queue it reaches.
- A job must be `Owned`. A client is a borrow, so a job that holds one is
  refused, and a job cannot call the task that runs it.
- The owning task is started through `Slot.start`, so [T-ThreadStart] accepts
  it.

The job is erased into a `mem.Closure` whose wrapper writes the job's answer
into bytes the caller holds while it waits, so every request has one type
whatever its answer.

A client's `Shareable` answer follows the state's: `Shareable` follows every
type argument, phantom ones included, so that a container that erases what it
stores is still counted, and a client names its state's type. A client crosses
into a task only where the state is `Shareable`, although the state never
leaves the owning task. The answer is sound and stricter than it need be.

### 5. Concurrent HTTP serving builds a handler per serving task

`http.serve(listener, make_handler, limits, policy = .Threads(128))` serves on
as many tasks as `policy` allows. Each serving task builds its own handler
with `make_handler`, so no handler is reached by two tasks and a router needs
no lock. The listener lives in an owning task that each serving task asks for
its next connection, so a task takes a connection only when it is free and a
slow client holds up no other. The serving tasks are started as a balanced
tree, half of each share on a new task, so starting `n` of them takes a depth
of the logarithm of `n`, and every one is joined before `serve` returns.

`http.listen_and_serve_with(address, make_handler, state)` keeps `state` in an
owning task, gives `make_handler` a client of it for each serving task, and
returns the state once every task has been joined. `http.listen_and_serve`
serves a service that shares nothing. The `_in` forms carve each task's arenas
from a parent every task reads, so the parent must be `Shareable`.
`http.serve_sequentially` and `listen_and_serve_sequentially` lend one handler
to every request, one connection at a time, for a program that reads its
handler back or serves one that cannot be shared, such as one carving every
request from one arena.

## Consequences

1. A caller changes `.Sequential` to `.Threads(8)` with one argument, without
   changing library code or job bodies.
2. Tests run under `.Sequential`, or through `serve_sequentially`, with one
   handler they read back.
3. A server's shared state is written as data in an owning task, and its
   routes reach it through `call`; a route that needs request data in a call
   copies it into owned values first.
4. A request-numbering middleware numbers the requests its own handler sees,
   so two serving tasks' requests may share a number.

## Alternatives considered

- **An `Executor` trait implemented by `Policy` and a `ThreadPool`:** rejected
  because the combinators need only the policy's bound, and a pool of threads
  kept between calls is a worker pool, which section 3 rules out.
- **An unjoined worker pool, a connection queue between workers and a global
  handler lock:** built first and removed. An unjoined task cannot carry its
  body's dependencies, so the compiler could not keep a creator from writing
  what a worker read; the lock was held across user code, deadlocked when
  re-entered and serialised every server; descriptors crossed between workers
  as integers, minting a second owner of a connection.
- **A many-to-one `session.Mailbox`:** removed. Senders were cloned and moved
  freely, so a task could hold a sender of the mailbox it waited on, or wait on
  a task that waited on it. No user code receives from an owning task, so
  neither wait can be written.
- **One handler shared by `read` between serving tasks:** rejected because a
  router keeps per-request buffers, and a shared handler would have to keep
  them elsewhere; every shared value would need to be `Shareable`.
- **A task per connection, joining the oldest when the bound is reached:**
  rejected because a slow client held up every connection behind it. The
  owning task over the listener lets any free task take the next connection.
- **A short-circuiting `task.map_results` answering `Result[Vec[R], E]`:**
  rejected because failing early drops outputs other jobs produced.
