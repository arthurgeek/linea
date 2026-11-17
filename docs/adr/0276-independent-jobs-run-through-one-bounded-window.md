# 276. Independent jobs run through one bounded window of workers, and a lazy map yields from it

Status: Accepted — 2026-11-16. Supersedes the clause of
[0253](0253-independent-work-runs-through-an-explicit-executor-policy.md) §1
that `task.map` and `task.all` divide their items among at most `max` tasks.
Extends 0253 §2 with `task.lazy_map` and the `_in` forms of every
combinator.

## Context

ADR 0253 gives independent work an explicit `task.Policy` and five
combinators. Two of them shared no scheduler and neither kept its tasks
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

None of the combinators stated its allocator: each hard-coded
`mem.SystemAllocator`, against the library's rule that every allocating
function has a system form and an `_in` form.

The wording of the guide and the library described `.Threads(max)` as
"worker threads". A task inherits its starter's Io (ADR 0265): under
`io.system()` each job is an operating-system thread, but on a loop it is a
fiber pinned to one of the loop's carriers, so `.Threads(2)` inside a
one-carrier loop runs two fibers on one thread.

## Decision

### 1. One scheduler: at most `max` workers per call, pulling chunks

`task.LazyMap` is the one scheduler for `lazy_map`, `map` and `all`. It
starts a worker task only when an item is ready for it and no started worker
is free, so a call starts at most `max` tasks however many items it maps,
and joins every one before it is settled. No worker outlives the call that
started it, so [T-ThreadStart] and 0253's refusal of a retained pool stand.

A worker's session is a named protocol: the map chooses to hand it a chunk
of items, as a `Vec`, and receive their results, or to stop it. The map
keeps a ring of places, one for each item it pulled and has not yet
yielded; a place says the item is still being mapped or holds its result.
It keeps two bounds:

- at most `max` workers;
- at most `ahead` pulled items wait to be yielded, being mapped or answered.

When the item at the head of the order is still being mapped, the caller
waits for **whichever busy worker answers first**: it keeps that chunk's
results in their places and hands the worker the next chunk at once. The
head's result is yielded when it arrives, so results leave in input order
while the other workers keep busy.

A chunk is one item when the source's length is unknown, as for any
`lazy_map`. For `map` and `all`, which know their length `n`, a chunk is
`n / (2 * max)` items, at least one: every worker maps about two chunks, so
a long map of cheap items costs about two handoffs a worker, and a slow item
holds up only the other items of its chunk while the free workers take the
rest. A short map hands out single items. `map` and `all` start all their
workers before handing out the first chunk, so the workers come up together
rather than one after another.

`lazy_map` keeps `ahead` at `2 * max`: `max` items being mapped and up to
`max` more answered and waiting for an earlier item. `map` and `all` collect
every result anyway, so their `ahead` is the input's length and results move
into the collected `Vec` as each chunk's run of ready results arrives.

`.Sequential` and `.Threads(1)` start no task and allocate nothing: `next`
calls the function on the caller, one item at a time, so the same program
yields the same results in the same order. A `max` of 0 stops the program,
as 0253 decided.

Waiting for the first of several busy workers opens a runtime wait set for
that wait alone, registers the busy workers' sessions, and closes it before
the wait returns. One busy worker is waited on directly. The map therefore
holds nothing tied to one Io between calls, and a map moved into a task on
another Io, after its first result or at any other point, keeps working
there (`tests/tasks/a_lazy_map_moves_to_a_task_on_another_io.lin`).

### 2. A lazy map is linear and is settled explicitly

A running task cannot be stopped from outside (ADR 0265, "No task is stopped
from outside"), and discarding a value never runs cleanup, so a value that
holds workers must be settled on every path. `LazyMap` is `@linear`:

- `for x in task.lazy_map(...)` is refused by [O-LinearWalk], and the help
  teaches the lent walk `for x in &mapped`;
- a path that leaves with the map still bound is refused by [O-Leak];
  `tests/tasks/a_lazy_map_is_settled_on_every_path.lin` records both.

Three operations settle it:

- `release()` (and so `defer var mapped = task.lazy_map(...)`) stops
  pulling, waits for every chunk already handed out, releases every result
  not yet yielded, stops every worker and releases the source. It needs
  `Release` on the results and the source.
- `stop()` stops pulling; walking the map afterwards yields only the results
  of items already pulled, so results that have no `Release` reach their
  owner.
- `finish()` stops the workers and answers the source, as far as it
  advanced, once every pulled item has been yielded, and answers the map
  back as `Err` otherwise.

Settling after `k` results maps at most `k + 2 * max` items in all: the
window bounds what was pulled, and settling pulls nothing.

### 3. A failure keeps the policy `task.map` had

A job that panics stops the program, as before. A function answering a
`Result` gives every item's result, failures included (ADR 0270).

A worker that cannot be prepared (its bytes refused, or its stack) no longer
stops the program: the chunk it would have taken is mapped on the caller and
its results take their places, and that round of pulling ends, so refused
tasks never make the map compute ahead on the caller. When the places
themselves are refused, every item is mapped on the caller. A refusal
therefore changes where the work runs and never which results are yielded,
as a task `http.serve` cannot make leaves its share to the calling task
(0253 §5). A chunk or a results vector the system allocator refuses, and a
result the collecting `Vec` cannot take, still stop the program. `join`,
`join3` and `join4` keep stopping the program when a task cannot be
prepared: each runs a fixed set of closures of different types, which no
window holds.

### 4. Every combinator states its allocator

`join_in`, `join3_in`, `join4_in`, `all_in`, `map_in` and `lazy_map_in` take
an allocator first. Each started task's bytes come from it, and for `map_in`
and `all_in` the result vector and the window's places too; `lazy_map_in`
takes its places from it. `items` and `jobs` keep the allocator they were
built with. The chunks a worker is handed and the results it answers move
between tasks in vectors from the system allocator, since a session's
payload is `Owned` and a vector over an arena or a log is not. The system
forms forward to the `_in` forms with `mem.system()`. A worker's session
keeps carrying the allocator without naming the body's type
(`Chan.detach_body`, defined for an `Owned` body), so an allocator that
borrows an arena or an allocation log keeps its owner alive until every
worker is joined; `tests/tasks/a_lazy_map_keeps_its_allocator_borrowed.lin`
records the refusal of releasing a log while a lazy map that allocates from
it lives.

### 5. What `.Threads(max)` runs on is the current Io

`.Threads(max)` bounds how many jobs run at once. Each worker is a task
started on the caller's Io: its own operating-system thread under
`io.system()`, a fiber pinned to one of the loop's carriers under a loop, so
at most as many jobs run simultaneously as the loop has carriers, and a
fiber scheduled from the seed inside a simulation. The guide,
`std/README.md` and the library's comments say so.

## Measurements

`task.map(.Threads(8), items, f)` before this record (main at 2678ddc5, which
chunks) and with it, both compilers built `-Drelease` and the program with
`linea build -O 2`, on an 8-core Apple-silicon Mac; each figure is the
fastest of forty runs (five for the costly items), from two runs of the
program, at a load average of about 2.5:

| Workload | Main (fixed chunks) | This record (workers pulling chunks) |
| --- | --- | --- |
| 10 000 trivial items | 344–416 µs | 545–666 µs |
| 100 000 trivial items | 986–1 025 µs | 1 308–1 387 µs |
| 16 items of 30 million steps each | 241.9–244.0 ms | 247.8–248.8 ms |

A task per item, the first form of this record, took 338–429 ms for 10 000
trivial items and 3.44–3.64 s for 100 000 on the same machine.

## Consequences

1. `task.map` over cheap items stays within a small factor of fixed
   chunking, and a map whose items vary in cost no longer waits on a slow
   chunk while the other tasks sit idle.
2. `task.all` keeps its workers busy until the last job is handed out,
   instead of waiting for each batch.
3. A loop over a stream that does costly work per item writes
   `defer var results = task.lazy_map(policy, items, f)` and walks
   `&results`; stopping early waits only for the window. A lazy map hands
   out one item at a time, so it suits work that costs more than a session
   round trip per item.
4. The `_in` forms let a test count each combinator's allocations with an
   allocation log and walk the maps' refusal paths, and let a server take a
   task's bytes from an arena.
5. The window reserves its places for `2 * max` items and room for `max`
   workers at the first `next`, whatever the source holds; `map` and `all`
   reserve for no more workers than they have items.
6. On a loop whose carriers are busy with jobs, handing a worker its next
   chunk waits until the worker's fiber runs, so a free worker may wait for a
   carrier before it starts again.

## Alternatives considered

- **A retained pool of worker tasks shared between calls:** rejected by 0253
  §3 and its *Alternatives considered*: a pool kept between calls is an
  unjoined worker, which [T-ThreadStart] rules out. The workers here are
  started and joined inside the call that uses them.
- **A task per item, as many at once as the bound allows:** built first. It
  kept uneven jobs busy and needed no protocol, but every item paid a task's
  start and join, about 35 µs on macOS, so `task.map` over cheap items was
  three orders of magnitude slower than fixed chunks (see Measurements).
- **Fixed chunks, as `task.map` had:** the fewest handoffs, but one slow item
  holds up its whole chunk while the other tasks are idle, and a stream of
  unknown length cannot be divided ahead.
- **One item per handoff for `map` and `all`:** each handoff is three
  session rendezvous between tasks, tens of microseconds on a loaded Mac,
  which a cheap item does not repay.
- **Chunks that shrink as the input runs out (guided scheduling):** the last
  items go out one at a time, which suits uneven work best, but a long map
  of cheap items made a hundred or more handoffs and stayed three to five
  times slower than fixed chunks; two chunks a worker kept it within 2×.
- **Places kept per item rather than per chunk:** every item then cost the
  caller several more moves through the ring, which doubled the time of a
  map of cheap items on its own.
- **Eager `map` only, with callers chunking a stream themselves:** it cannot
  stop early, it holds every result, and a caller that wants the first match
  maps everything.
- **Unbounded spawning (a task per item as fast as the source yields):** the
  memory held grows with the input, since each task keeps a stack until it is
  joined, and stopping early would have to wait for every task started.
- **An in-order window without waiting for the first worker to answer:**
  waiting on the head's worker alone keeps workers that finished idle behind
  it; that is the batch behaviour `all` had.
- **A wait set kept for the map's lifetime:** it belongs to the Io it was
  opened on, so a map moved to a task on another Io stopped the program at its
  next wait. Opening one for each wait costs a runtime record per wait, which
  a chunk's work repays.
- **`task.WaitSet` for the waits:** each registration erases its value into
  a system-allocated closure, so `lazy_map_in` could not keep its promise
  about where it allocates.
- **Dropping a lazy map joins its workers:** discard never runs cleanup
  ([O-Leak], ADR 0124); a drop that waited on tasks would be cleanup the
  program never wrote.
- **Panicking when a task cannot be prepared, as `task.map` did:** a lazy map
  would have to answer `Result` from every `next`, and an allocation log could
  not walk its refusal paths in a test; mapping the chunk on the caller
  answers the same results.
