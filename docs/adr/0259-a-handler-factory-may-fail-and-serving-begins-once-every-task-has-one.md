# 259. A handler factory may fail, and serving begins once every task has its handler

Status: Accepted — 2026-11-07; extends
[0253](0253-independent-work-runs-through-an-explicit-executor-policy.md)
(a handler per serving task).

## Context

[0253](0253-independent-work-runs-through-an-explicit-executor-policy.md)
gives each serving task of `http.serve` a handler of its own, built by a
factory `M: fn() -> H` that the task calls once before it serves anything.
A handler can therefore own what its task alone uses, and needs no lock for
it. State every task shares lives in an owning task (`task.own`,
`listen_and_serve_with`), which runs one call at a time.

The guest book kept its one SQLite connection in such an owning task, so
every read and every signature ran one at a time behind it while the server
answered up to 128 connections at once. SQLite itself serves that workload
better: in write-ahead-log mode any number of connections read at once, each
seeing the last committed state, and one writes at a time while the others
keep reading. What it needs is a connection per thread. The natural owner of
a connection is therefore the serving task, and the place to open it is the
handler factory.

Opening a connection can fail: the file cannot be created, the process is
out of descriptors, the SQLite build is not thread-safe. The factory's type
had no failure case, so a factory that opened a database could only panic,
or open lazily on the first request and answer 500 to every request after,
while the server kept accepting connections it could not serve.

A second gap followed from the first. Each task called its factory when it
started, and then asked the listener's owning task for a connection. A task
that could not begin (the parent refused its 503 buffer) returned at once
while the others went on serving, so with no connection limit serving never
ended and the failure was never reported. Worse, a task already waiting in
`accept` holds the owning task, so a message from a failed task telling the
others to stop would wait behind that `accept` until some client connected.

## Decision

**A handler factory returns a handler or a `Result` holding one, and serving
accepts nothing until every serving task has made its handler.**

1. **`http.MadeHandler[P]` names what a factory may return.** It is
   implemented for every `H: Handler[(), P]`, answering `.Ok(self)` with
   `Error = Never`, and for every `Result[H, E]` with such an `H`, answering
   itself. `serve`, `serve_in`, `listen_and_serve`, `listen_and_serve_in`,
   `listen_and_serve_with` and `listen_and_serve_with_in` take
   `M: fn() -> R` (or `fn(client: task.Client[S]) -> R`) with
   `R: MadeHandler[P]`, and bound `R.Handler` and `R.Error` in their `where`
   clauses. A factory that cannot fail is written as before:
   `listen_and_serve(address, routes)` with `fn routes() -> Router[()]`. One
   that can returns `Result[H, E]`:

   ```linea
   let serving = [sink logger, path] || {
       Ctx.open(path).map(
           [sink logger = copy(logger)] |sink ctx: Ctx| {
               var router: http.Router[Ctx] = http.Router.new()
               routes(&router).unwrap()
               http.logged(copy(logger), http.with_state(ctx, router))
           },
       )
   }
   ```

   The two implementations are disjoint by the rule that a bare parameter
   bounded by a trait does not overlap a constructor no implementation of the
   trait answers for: nothing implements `Handler` for `Result`. A program
   cannot add one, since both belong to the library ([M-Impl]), nor a second
   `MadeHandler` for a handler of its own ([T-Impl]); two corpus cases in
   `tests/http/` hold both refusals.

2. **The failure reaches the error.** `ServeError[E = Never]` gains
   `Handler(E)`, and `ListenAndServeError[E = Never]` carries
   `Serve(ServeError[E])`. The default, a type parameter's default of
   [0215](0215-a-type-parameter-may-default-its-argument.md), keeps
   `http.ServeError` written alone meaning the failures of an infallible
   factory, which is every annotation written before. Both are `Display`
   when `E` is, and copyable only when `E` is: a `ServeError[String]` is
   moved, and copying it is [O-Copy], which a corpus case holds. `E` must be `Owned`, `Shareable` (it is sent from the task that met it)
   and `Release` (when two tasks fail, the second reason is released).

3. **Serving begins once every task has its handler.** The listener's owning
   task is told how many serving tasks to expect, and answers `Wait` to every
   request for a connection until each has reported that it is ready or that
   it failed. A share of tasks that `task.prepare` could not start is
   reported as never coming. One failure stops the owning task handing out
   connections, so nothing is accepted, every task releases the handler it
   made, the listener is closed, and serving ends with `Handler(E)` (or
   `Memory`, for a refused 503 buffer). Since no task is waiting in `accept`
   while another is still getting ready, the stop is never queued behind a
   blocked `accept`.

   The barrier holds one invariant: **every expected serving task
   contributes exactly one startup outcome, on every path that does not end
   the process.** A task that takes its 503 buffer and makes its handler
   reports ready; one whose buffer `parent` refuses, or whose factory
   answers `.Err`, reports failed, after releasing what it took; a share of
   tasks `task.prepare` could not start is reported by the task that tried
   to start it, before that task runs its own share. A trap ends the process,
   so it leaves no barrier waiting. Tests inject each recoverable failure:
   a refused discard buffer, a factory that fails on one task, and tasks
   that cannot be made (a stack no system gives), and check that serving
   ends instead of waiting.

4. **`listen_and_serve` asks the factory first on the calling thread.** It
   already made one handler to announce the bound address as
   `Event.Listening`; that handler is now made before any serving task
   starts, so a factory that always fails is asked once and the program
   learns why before a task is started. On `.Sequential`, and where the
   listener's owning task cannot be made, the one handler is made on the
   calling thread and a failure closes the listener.

The default policy of `serve` and `listen_and_serve` stays `.Threads(128)`.
A program whose handlers hold a resource per task keeps that count and makes
room for it: the guest book holds two file descriptors per SQLite connection,
so it raises its own open-file limit with `process.raise_open_file_limit`
before serving, since 128 connections pass the 256 descriptors a macOS shell
allows by default.

## Consequences

- The guest book starts in the order a server with per-task resources
  needs: it prepares what every task shares (it raises the open-file limit,
  then initializes the database once: the table and the switch to the
  write-ahead log, which needs the file to itself), then each serving task
  opens its own connection, and only then is a connection accepted. Reads
  run in parallel and only signatures wait on one another. A database file
  that cannot be opened stops the program at initialization; a connection a
  task cannot open ends serving with `guest-book: a serving task's handler
  could not be made: ...` before a connection is accepted.
- The 389 files the guest book checks for before serving are an estimate:
  three per task (the database, its log, a client's socket) and five more.
  SQLite may open other files, a temporary one for a large sort, so the
  check does not replace handling a failure to open one while serving,
  which the guest book answers with a 500. The barrier is what guarantees
  serving starts only with every task's connection open. The limit is the
  whole process's, so only a program raises it, never a library.
- Every infallible factory in the library, the examples and the guide is
  unchanged. Annotations of `http.ServeError` and `http.ListenAndServeError`
  keep their meaning through the default.
- A server with many tasks starts serving only once the slowest factory has
  returned. Each waiting task asks again after a millisecond. That polling
  is the barrier's only cost while it waits; the park primitive of ADR 0261
  is where a readiness barrier that wakes the waiting tasks once replaces
  it.
- `listen_and_serve` makes one handler more than it has serving tasks, to
  tell it `Event.Listening`, and releases it at once. For the guest book that
  is one SQLite connection opened and closed before serving, and a factory
  may succeed for the announcement and then fail on a serving task. Telling
  a listener-level observer of the server's lifecycle, apart from the
  handlers, would remove the extra handler; it is left for later.
- A factory that takes long, or blocks, delays the first accepted connection
  for every task. A factory is meant to build a handler and open what it
  needs, not to wait on clients.
- `ServeError` and `ListenAndServeError` are generic, so a program matching
  on them names `Handler` among the cases, and a variant constructed where
  nothing settles `E` (`fmt.render_owned(ServeError.NoWorkers)`) is
  [T-Infer]: an enum constructor does not take its type's default, only an
  inherent implementation's members do
  ([0217](0217-a-call-leaves-an-undetermined-parameter-to-its-types-default.md)).
  Writing the type (`let error: ServeError = .NoWorkers`) settles it.
- `MadeHandler` declares its allocator parameter `phantom`, and states the
  bounds on `Handler` and `Error` at each serving function rather than on the
  associated types. An associated type's bound cannot name its trait's
  parameters: those bounds are settled once per declaration, where the
  trait's parameters do not resolve.

## Alternatives considered

- **Every factory returns `Result[H, E]`.** One shape, no trait. Every
  infallible factory, the common case and the first networking example a
  reader meets, would write `Result[Router[()], Never]` and wrap its tail in
  `.Ok`; a `||` closure would need its result type written for `E` to be
  settled. That is ceremony on the common path to serve the rarer one.
- **A second family of serving functions for fallible factories**
  (`serve_opening`, `listen_and_serve_opening`, and their `_in` and `_with`
  forms). The names double, a reader has to learn which family a factory
  belongs to, and the two would be one implementation under two names, the
  split [0219](0219-a-function-type-parameter-and-its-parameter-may-default.md)
  removed from `listen_and_serve`.
- **Open lazily, inside the handler, on the first request.** No API change,
  but the failure arrives as a 500 on every request while the server keeps
  accepting, and the program cannot report why it should not be serving.
- **Keep the database in an owning task, as before.** Correct, and still the
  right shape for state every task shares; but SQLite's readers then run one
  at a time although SQLite would run them together.
- **Stop the other tasks on failure without a gate.** A failed task could
  tell the owning task to stop handing out connections. Another task already
  waiting in `accept` holds the owning task until a client connects, so with
  no client the stop never runs and serving does not end. Waiting for every
  task to be ready before the first `accept` removes the race instead of
  narrowing it.
- **Count ready tasks only, without an expected count.** Without knowing how
  many tasks will run, the owning task cannot tell the last ready task from
  the first; `on_tasks` knows how many shares it could not start, so the
  expected count is exact.
