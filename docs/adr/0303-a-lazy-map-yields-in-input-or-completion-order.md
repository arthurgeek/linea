# 303. A lazy map yields in input order or, when asked, in completion order

Status: Accepted — 2026-11-21. Extends
[0276](0276-independent-jobs-run-through-one-bounded-window.md) §1 and §2 with
a second order for `task.lazy_map` and `task.lazy_map_in`.

## Context

ADR 0276 gives `task.lazy_map` one bounded window of workers and yields its
results in input order: when the item at the head of the order is still being
mapped, the caller waits for whichever worker answers first, keeps that
result in its place, and yields the head once it arrives. A result that is
ready early waits for every slower item before it.

That is the right default for a pipeline whose output follows its input, and
the wrong one for work whose results are independent and are reported as
they come in. The link checker (`examples/link-checker`) reported links in
the order the file lists them, so one slow link held back every report after
it and the output looked sequential although the checks ran in parallel. The
library had no way to ask for results as they finish: `lazy_map`, `map` and
`all` all yield in input order by design, and the only alternative was a
hand-written `task.WaitSet` over started tasks, which rebuilds the window,
its bound and its settlement.

## Decision

### 1. The order is a named parameter of `lazy_map` and `lazy_map_in`

```text
pub enum Order { Input, Completion }

pub fn lazy_map(sink policy: Policy, sink items: S, sink f: F, order: Order = .Input) -> LazyMap[...]
pub fn lazy_map_in(allocator: A, sink policy: Policy, sink items: S, sink f: F, order: Order = .Input) -> LazyMap[...]
```

`task.lazy_map(.Threads(8), urls, check, order: .Completion)` yields each
result as soon as its job finishes, the first to finish first. `.Input` stays
the default, so every existing call keeps its meaning.

The choice is a parameter rather than a sibling function because everything
else about the two is one thing: the same scheduler, the same window and
bound, the same linear `LazyMap` type and the same three ways of settling it.
A sibling (`lazy_map_unordered`, with its own `_in` form) would double the
signatures and their documentation for one difference, and the name at the
call site, `order: .Completion`, says what changes. The default is honest and
stable: input order is what a reader of `for x in &mapped` expects unless
told otherwise.

### 2. Completion order is a queue of finished chunks in the same places

In input order the map keeps a ring of places, one for each chunk handed out
and not yet yielded, the `n`th chunk handed out at `n % places`, marked
running until its results come back. In completion order the same ring is a
queue: the chunk that finishes `n`th, counted by a new `finished` field,
takes place `n % places` when its results come back, nothing is marked
running, and the caller yields from the place after the last it took. An
empty place there means no chunk has finished since, so the caller waits for
whichever busy worker answers first, through the same wait set. A chunk a
worker could not be started for is mapped on the caller and joins the queue
as it finishes.

The ring never overflows: a chunk is handed out only while fewer than
`places` chunks are handed out and not yet taken, and a finished chunk is one
of them. A lazy map hands out one item per chunk (its source's length is
unknown), so each result is yielded as soon as its own job finishes.

Without a wait set, where the system refused one, input order waits for the
worker mapping the head's chunk; completion order waits for the worker
holding the earliest chunk handed out, so the map still makes progress and
yields every result.

### 3. Every guarantee of input order holds

- At most `max` jobs run, and an item is pulled only when a job may start for
  it, with at most `2 * max` pulled items not yet yielded.
- The map stays linear. `release()`, `stop()` and `finish()` behave as 0276
  §2 says: every job already started is joined and its result released or
  yielded, so none is lost, and a walk left by `break` and then settled
  waits only for the window. After `stop()` a walk yields the started jobs'
  results in completion order.
- A refused allocation moves work to the caller and never changes which
  results are yielded.
- Under `.Sequential` and `.Threads(1)` every job runs on the caller, one
  after another, when it is asked for, so completion order is input order
  there and nothing is allocated.

`task.map` and `task.all` keep input order and take no order: they collect
every result into a `Vec`, where an order other than the items' would only
lose the position.

### 4. A result carries no input index

A result in completion order is `R`, as in input order, not `(UInt64, R)`.
The window knows the position: a lazy map hands out one item per chunk, so a
chunk's number is its item's. But yielding it would change the iterator's
item type with a run-time choice, which only a sibling function and a second
`LazyMap` type could express, and most callers already have the position in
what `f` answers. A caller that needs to know which input finished has `f`
return it; the link checker's `Checked` already names its URL, and the
guide's example returns the page it fetched.

## Consequences

1. `examples/link-checker` passes `order: .Completion` and prints that each
   link is reported as its check finishes; its test asks that every link is
   reported once, in any order, since real sockets finish in no fixed order.
2. A corpus program,
   `tests/tasks/a_lazy_map_in_completion_order_yields_results_as_jobs_finish_on_a_simulated_clock.lin`,
   forces a finishing order on a simulation's virtual clock, so the order
   and the virtual time it asserts are the same on every run. The tests in
   `std/task/task.lin` cannot open a simulation: every program loads
   `task`, which imports only `std.io.core`, and the simulation lives in
   `std.io`. They hold one slow job tenfold apart from the rest, as the
   window's other tests do.
3. The guide's chapter on tasks teaches `order: .Completion` with a program
   that really waits, its finishes 100 ms apart, and a test of the same
   function run in a simulation that pins the order and each finishing
   millisecond; `std/README.md` names `task.Order`.
4. A `LazyMap` carries one more field for the order and one counter, and the
   yield, collect and release paths each check the order where they read a
   place.

## Alternatives considered

- **A sibling function, `lazy_map_unordered` and `lazy_map_unordered_in`:**
  two more public signatures with identical bounds, settlement and
  documentation for one difference the parameter states at the call site.
- **Yielding `(index, result)` in completion order:** the item type would
  depend on a run-time value, so it needs a separate type and function, for
  a position a caller that wants it can return from `f`.
- **A completion order for `task.map` and `task.all`:** both collect every
  result before answering, so the order of the collected `Vec` would only
  hide each result's position.
- **A hand-written `task.WaitSet` over started tasks in the link checker:**
  it would rebuild the window's bound, its pulling on demand and its
  settlement in an example, for a question the library's window already
  answers when it waits for the first worker to answer.
