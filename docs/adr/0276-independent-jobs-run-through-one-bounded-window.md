# 276. Independent jobs run through one bounded window, and a lazy map yields from it

Status: Accepted — 2026-11-16. Supersedes the clause of
[0253](0253-independent-work-runs-through-an-explicit-executor-policy.md) §1
that `task.map` and `task.all` divide their items among at most `max` tasks.
Extends 0253 §2 with `task.lazy_map` and the `_in` forms of every
combinator.

## Context

ADR 0253 gives independent work an explicit `task.Policy` and five
combinators. Two of them shared no scheduler and neither kept its workers
busy:

- `task.map(policy, items, f)` cut its items into `max` fixed chunks and ran
  each chunk on a task of its own. One slow item held up every item after it
  in its chunk while the other tasks sat idle.
- `task.all(policy, jobs)` started `max` jobs, waited for all of them, then
  started the next `max`. One slow job held up the whole next batch.

Both are eager: they consume an owned `Vec` and answer the complete result
`Vec`. Code that wants results one at a time, stops early, or maps an input
that is never collected (a range, a stream read as it goes) had only the
sequential `Iterator.map`, or a hand-written loop over `task.start`.

And none of the combinators stated its allocator: each hard-coded
`mem.SystemAllocator`, against the library's rule that every allocating
function has a system form and an `_in` form.

The wording of the guide and the library also described `.Threads(max)` as
"worker threads". A task inherits its starter's Io (ADR 0265): under
`io.system()` each job is an operating-system thread, but on a loop it is a
fiber pinned to one of the loop's carriers, so `.Threads(2)` inside a
one-carrier loop runs two fibers on one thread.

## Decision

### 1. One window schedules every mapped job

`task.LazyMap` is the one scheduler for `lazy_map`, `map` and `all`. It holds
the source iterator, the function, and a ring of places, one for each item it
pulled and has not yet yielded. Each place holds the item's job, running on a
task of its own, or the result the job answered. It keeps two bounds:

- at most `running` jobs run at once (`max` of `.Threads(max)`);
- at most `ahead` pulled items wait to be yielded, running or answered.

An item is pulled only when both bounds leave room. When the item at the
head of the order is still running, the caller waits on a runtime wait set
that watches every running job's handle, and takes **whichever job answers
first**: its result goes to its place, its task is joined, and the next item
starts at once. The head's result is yielded when it arrives, so results
leave in input order while the other jobs keep running.

`lazy_map` keeps `ahead` at `2 * max`: `max` jobs running and up to `max`
more answered and waiting for an earlier item. `map` and `all` collect every
result anyway, so their `ahead` is the input's length and a slow item holds
up no other item at all.

`.Sequential` and `.Threads(1)` start no task and allocate nothing: `next`
calls the function on the caller, one item at a time, so the same program
yields the same results in the same order. A `max` of 0 stops the program,
as 0253 decided.

Each job's task is started before its item is given to it: the task's
session receives the item and sends back the result. A task that cannot be
prepared therefore leaves the item with the caller, which maps it there
(§3), and no captured item has to be recovered from a body that never ran.

The wait set is the runtime's, used directly: the map registers each handle
it keeps and maps the set's slot back to the job's place, so registering a
job allocates nothing from Linea's allocators; the runtime grows its own
record of slots, 64 at a time, and stops the program when the system refuses
that memory, as it does for a task's record. `task.WaitSet` would
erase each registration into a `mem.Closure` from the system allocator,
which the `_in` forms could not name.

### 2. A lazy map is linear and is settled explicitly

A running job cannot be stopped from outside (ADR 0265, "No task is stopped
from outside"), and discarding a value never runs cleanup, so a value that
holds running jobs must be settled on every path. `LazyMap` is `@linear`:

- `for x in task.lazy_map(...)` is refused by [O-LinearWalk], and the help
  teaches the lent walk `for x in &mapped`;
- a path that leaves with the map still bound is refused by [O-Leak];
  `tests/tasks/a_lazy_map_is_settled_on_every_path.lin` records both.

Three operations settle it:

- `release()` (and so `defer var mapped = task.lazy_map(...)`) stops
  pulling, joins every job already started, releases every result not yet
  yielded, and releases the source. It needs `Release` on the results and the
  source.
- `stop()` stops pulling; walking the map afterwards yields only the results
  of jobs already started, so results that have no `Release` reach their
  owner.
- `finish()` answers the source, as far as it advanced, once every pulled
  item has been yielded, and answers the map back as `Err` otherwise.

Settling after `k` results runs at most `k + 2 * max` jobs in all: the window
bounds what was started, and settling starts nothing.

### 3. A failure keeps the policy `task.map` had

A job that panics stops the program, as before. A function answering a
`Result` gives every item's result, failures included (ADR 0270).

A task that cannot be prepared (its bytes refused, or its stack) no longer
stops the program: the item's job runs on the caller and its result takes its
place. When the places themselves are refused, every job runs on the caller.
A job run on the caller ends that round of pulling, so refused tasks never
make the map compute ahead on the caller. A refusal therefore changes where
the work runs and never which results are yielded, as a task `http.serve` cannot make leaves its share to the calling
task (0253 §5). A result the collecting `Vec` cannot take still stops `map`
and `all`, as it did. `join`, `join3` and `join4` keep stopping the program
when a task cannot be prepared: each runs a fixed set of closures of
different types, which no window holds.

### 4. Every combinator states its allocator

`join_in`, `join3_in`, `join4_in`, `all_in`, `map_in` and `lazy_map_in` take
an allocator first. Each started job's bytes come from it, and for `map_in`
and `all_in` the result vector and the window's places too; `lazy_map_in`
takes its places from it. `items` and `jobs` keep the allocator they were
built with. The system forms forward to them with `mem.system()`. A started
job's handle keeps carrying the allocator without naming the body's type
(`Chan.detach_body`, defined for an `Owned` body), so an allocator that
borrows an arena or an allocation log keeps its owner alive until every job
is joined.
`tests/tasks/a_lazy_map_keeps_its_allocator_borrowed.lin` records the
refusal of releasing a log while a lazy map that allocates from it lives.

### 5. What `.Threads(max)` runs on is the current Io

`.Threads(max)` bounds how many jobs run at once. Each job is a task started
on the caller's Io: its own operating-system thread under `io.system()`, a
fiber pinned to one of the loop's carriers under a loop, so at most as many
jobs run simultaneously as the loop has carriers, and a fiber scheduled from
the seed inside a simulation. The guide, `std/README.md` and the library's
comments say so.

## Consequences

1. `task.map` starts a task for every item instead of one for every chunk. A
   map over many tiny items pays a task start for each where it paid one for
   each chunk; a map whose items vary in cost no longer waits on its slowest
   chunk. A caller with many tiny items maps chunks itself.
2. `task.all` keeps `max` jobs running until the last one starts, instead of
   waiting for each batch. On a loop whose carriers are busy with jobs, the
   caller hands each new job its item when the job's fiber first runs, so
   starting the next job can wait for a carrier.
3. A loop over a stream that does costly work per item writes
   `defer var results = task.lazy_map(policy, items, f)` and walks
   `&results`; stopping early waits only for the window.
4. The `_in` forms let a test count each combinator's allocations with an
   allocation log and walk the maps' refusal paths, and let a server take a
   job's bytes from an arena.
5. A lazy map holds a runtime wait set while it has started a job, and the
   wait set belongs to the Io it was opened on. A map moved into a task on
   another Io stops the program at its next `next`, as a task's handle used
   there does; its type does not refuse the move.
6. The window reserves its places for `2 * max` items and its wait-set names
   for `max` jobs at the first `next`, whatever the source holds; `map` and
   `all` reserve for no more jobs than they have items.

## Alternatives considered

- **A retained pool of worker tasks shared between calls:** rejected by 0253
  §3 and its *Alternatives considered*: a pool kept between calls is an
  unjoined worker, which [T-ThreadStart] rules out. The window starts and
  joins its tasks inside the calls that use them.
- **`max` worker tasks per call, each pulling items from the caller:** each
  worker asks for its next item, so the caller must answer whichever asks
  first, which is the same wait on several handles the window does, plus a
  protocol and a task kept alive between items.
- **Eager `map` only, with callers chunking a stream themselves:** what was
  there; it cannot stop early, it holds every result, and a caller that wants
  the first match maps everything.
- **Unbounded spawning (a task per item as fast as the source yields):** the
  memory held grows with the input, since each task keeps a stack until it is
  joined, and stopping early would have to wait for every task started.
- **An in-order window without a wait set:** waiting on the head's handle
  alone keeps finished jobs holding their tasks, since a send waits for its
  receiver, so one slow head stalls every other worker; that is the batch
  behaviour `all` had.
- **`task.WaitSet` for the window:** each registration erases its value into
  a system-allocated closure, so `lazy_map_in` could not keep its promise
  about where it allocates.
- **Dropping a lazy map joins its tasks:** discard never runs cleanup
  ([O-Leak], ADR 0124); a drop that waited on tasks would be cleanup the
  program never wrote.
- **Panicking when a task cannot be prepared, as `task.map` did:** a lazy map
  would have to answer `Result` from every `next`, and an allocation log could
  not walk its refusal paths in a test; running the job on the caller answers
  the same result.
