# 253. Independent work runs through an explicit executor policy

Status: Proposed — 2026-10-27. Complements
[0250](0250-tasks-are-structured-through-linear-sessions.md). Once built, it
would extend [0095](0095-the-system-allocator-is-named-rather-than-received.md)
(the capability model) and [0154](0154-sockets-and-http-follow-go.md)
(`http.serve`).

## Context

[0250](0250-tasks-are-structured-through-linear-sessions.md) introduces
concurrency to Linea through `task.fork`, linear session endpoints `Chan[P]`,
and structured joins on `close`. This provides a rigorous calculus for stateful
dialogue between concurrently executing tasks.

However, a large class of parallel workloads requires no inter-task dialogue:
- Data-parallel maps over collections (`task.map`);
- Scatter-gather independent calculations (`task.gather`);
- Request dispatch across workers in an HTTP server (`http.serve`).

In these cases, each computation is an independent, value-producing job: it takes
owned or borrowed inputs, runs to completion without mid-flight back-and-forth
rendezvous, and yields an owned output.

Without an execution abstraction for independent work:
1. **Library code is forced to hardcode thread creation.** A library function
   measuring several documents must either spawn dedicated OS threads via
   `task.start` or execute serially, preventing callers from choosing their own
   concurrency strategy.
2. **Testing and debugging suffer.** Debugging concurrent code or testing in
   constrained single-core environments requires rewrites if concurrency is
   baked into function bodies.
3. **`http.serve` faces an API dichotomy.** Making `http.serve` strictly
   sequential forces high-throughput servers to write custom dispatchers;
   making it strictly concurrent complicates deterministic unit tests and
   single-threaded mocks.

Linea's memory management model already solves this problem for storage:
functions that allocate take an explicit allocator (`mem.system()`, `Arena`, or
fixed buffer). Callers choose the allocation strategy without altering library
logic. Execution strategy should follow the same principle.

## Decision

### 1. The `Executor` trait

Execution of independent computations is abstracted through a standard trait:

```linea
pub trait Executor {
    fn map[T, R, F: fn(T) -> R](self, items: Vec[T], f: F) -> Vec[R]
    fn gather[T1, T2, F1: fn() -> T1, F2: fn() -> T2](self, f1: F1, f2: F2) -> (T1, T2)
    fn gather3[T1, T2, T3, F1: fn() -> T1, F2: fn() -> T2, F3: fn() -> T3](
        self, f1: F1, f2: F2, f3: F3
    ) -> (T1, T2, T3)
}
```

`Executor` represents the capability to schedule independent computations. It
does not expose general task dispatch or session endpoint creation; session-connected
tasks are created exclusively via `task.fork`.

### 2. The `Policy` value and `ThreadPool` resource

Two standard implementors provide execution:

1. **`Policy` (Zero-ceremony copyable value):**
   ```linea
   pub enum Policy: Copyable {
       Sequential,
       Threads { max: UInt64 },
   }
   ```
   - `.Sequential` executes jobs synchronously inline on the caller's call stack.
     Zero OS worker threads are spawned. Execution is 100% deterministic.
   - `.Threads { max }` executes jobs across dedicated worker threads bounded by
     `max`. `max: 0` is refused as a configuration error. `max: 1` routes work
     through worker thread machinery with at most one active worker thread.

2. **`ThreadPool` (Managed linear resource):**
   ```linea
   struct ThreadPool: linear {
       pub fn open(workers: UInt64, max_queued: UInt64) -> Result[ThreadPool, PrepareError]
       pub fn close(sink self: Self)
   }
   ```
   `&ThreadPool` implements `Executor`. It maintains pre-spawned worker threads
   and a bounded submission queue, avoiding thread spawn overhead across
   repeated invocations in long-lived services.

### 3. Ownership semantics for `task.map`

`task.map` provides two distinct distribution contracts:

1. **Owned Distribution (`sink items: Vec[T]`):**
   Each input element moves exclusively into one job invocation (`T: Owned`). No
   cloning or copying occurs.
2. **Borrowed Distribution (`read items: Slice[T]`):**
   Each job receives a read observation of an element. Requires `T: Shareable`.
   The slice remains borrowed until all jobs join; the caller regains access upon
   return.

### 4. Error-path accounting (`task.map_results`)

To prevent linear resource loss when individual jobs fail:
- The base combinator `task.map` is infallible at the job level (`f: fn(T) -> R`).
- Fallible computations use `task.map_results`:
  ```linea
  task.map_results(exec, sink items, |sink item| -> Result[R, E]) -> Vec[Result[R, E]]
  ```
  Every input has an explicit slot in the returned vector. If one job fails,
  successful linear outputs produced by sibling arms and unprocessed inputs are
  neither dropped nor leaked; the caller receives all results and settles them.

Results are always collected in deterministic input order, matching sequential
execution.

### 5. Generic `http.serve`

`http.serve` is generic over `Executor`:

```linea
pub fn serve[E: Executor](
    exec: E = .Threads { max: 128 },
    listener: net.TcpListener,
    handler: fn(http.Request) -> http.Response,
) -> Result[(), http.ServeError]
```

- When passed `.Sequential`, handlers run inline on the caller thread. Unit tests
  and mocks run deterministically without spawning OS threads.
- When passed `.Threads { max }` or `&pool`, handlers execute concurrently bounded
  by `max`.
- **Capture safety:** Because `serve` is capable of concurrent execution, handlers
  must satisfy concurrent capture rules: read captures require `Shareable`;
  mutable `inout` captures across requests are refused by `[O-Cross]`. Handlers
  requiring shared mutable state communicate with an owning task via a mailbox.
- **Backpressure:** When `max` concurrent handlers are active, `serve` pauses calls
  to `listener.accept()`. New incoming connections buffer in the OS TCP listen
  backlog (`SOMAXCONN`).

### 6. The Four Systems Capabilities

Linea structures system interaction into four orthogonal resource capabilities:

| Capability | Governs | Representation | Ambient / Scope Rule |
| :--- | :--- | :--- | :--- |
| **`Allocator`** | Memory acquisition | `mem.system()`, `Arena` | Open naming for `mem.system()` (ADR 0095); `Arena` is linear & `@unshareable`. |
| **`Io`** | Kernel OS waiting | `net.TcpListener`, `File` | Strict capability carried by service handles. |
| **`Executor`** | CPU scheduling | `Policy`, `&ThreadPool` | Explicit parameter to parallel algorithms and servers. |
| **`Session`** | Inter-task protocol | `Chan[P]` | Strict linear endpoint created by `task.fork`. |

## Consequences

1. **One-token execution toggle:** Callers change `.Sequential` to `.Threads { max: 8 }`
   or `&pool` with a single argument, without modifying library code or job bodies.
2. **Determinism:** Tests run under `.Sequential` with identical input/output
   signatures, full stack traces, and zero thread concurrency hazards.
3. **Sound backpressure:** Servers naturally bound active handlers and delegate
   connection buffering to kernel socket queues without application-level OOM.

## Alternatives considered

- **Hardcoded concurrent-by-default server:** Rejected because it prevents
  deterministic single-threaded testing and hides concurrency configuration.
- **`dispatch` method on `Executor`:** Rejected because general task creation
  belongs to `task.fork` and linear sessions. Combining them creates ambiguity
  around handle types and protocol obligations.
- **Short-circuiting `task.map` returning `Result[Vec[R], E]`:** Rejected
  because failing early drops linear resources produced by sibling jobs.
