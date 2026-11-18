# 276. Independent jobs run through one bounded window of workers, and a lazy map yields from it

Status: Accepted — 2026-11-16. Supersedes the clause of
[0253](0253-independent-work-runs-through-an-explicit-executor-policy.md) §1
that `task.map` and `task.all` divide their items among at most `max` tasks.
Extends 0253 §2 with `task.lazy_map` and the `_in` forms of every
combinator.
Extended by
[0288](0288-a-session-send-leaves-its-value-queued-and-returns.md), whose
queued sends remove the handoff's wait for the receiver and under which
`finish` tells every worker to stop before it joins the first.

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

A worker's session is a named protocol: after answering the results of the
chunk it started with, the worker is offered another chunk, as a `Vec`, and
answers its results, or is stopped. The map keeps a ring of places, one for
each chunk it handed out and has not yet yielded; a place says the chunk is
still being mapped or holds its results. Free busy entries are kept on a
stack, so taking and returning one costs the same however many workers
there are.
It keeps two bounds:

- at most `max` workers;
- at most `ahead` pulled items wait to be yielded, being mapped or answered.

When the item at the head of the order is still being mapped, the caller
waits for **whichever busy worker answers first**: it keeps that chunk's
results in their places and hands the worker the next chunk at once. The
head's result is yielded when it arrives, so results leave in input order
while the other workers keep busy.

A new worker is started holding its first chunk, so a worker's first chunk
costs no handoff: in the uniform case a worker costs what one of the old
fixed chunks did, one start, one answer and one join, and one handoff more.
A chunk is one item when the source's length is unknown, as for any
`lazy_map`. For `map` and `all`, which know their length `n`, each worker's
first chunk is its share `n / max` less an eighth of a share, and the
eighths left, about `n / 8` items, go out in chunks of an eighth of a share
to whichever worker finishes first. A slow item therefore holds up at most
the rest of its own first chunk, while the free workers take the eighths; a
short map hands out single items.

`lazy_map` keeps `ahead` at `2 * max`: `max` items being mapped and up to
`max` more answered and waiting for an earlier item. `map` and `all` collect
every result anyway, so their `ahead` is the input's length and results move
into the collected `Vec` as each chunk's run of ready results arrives.

`.Sequential` and `.Threads(1)` start no task and allocate nothing: `next`
calls the function on the caller, one item at a time, so the same program
yields the same results in the same order. A `max` of 0 stops the program,
as 0253 decided.

The map waits for the first of several busy workers through one runtime
wait set, opened with the map's places, that watches every busy worker from
when it takes a chunk until it answers; the set answers the slot the worker
was registered in, and the map keeps which busy entry each slot watches.
Handing out a chunk and waiting for an answer therefore cost the same
however many workers there are. A map is a value and may move into a task on
another Io; the set then follows it. The runtime gains one operation for
this, `linea_waitset_rehome`, which moves a set whose registrations are all
session endpoints to the calling task's Io and traps for any other set,
and for a move into or out of a simulation, with the message every session
crossing a simulation's boundary gives
(`tests/io/simulation/a_lazy_map_walked_inside_a_simulation_traps.lin`). A
session endpoint is signalled by its peer wherever the peer runs, so nothing
the set watches belongs to the Io it was opened on; a timer, a descriptor or
a signal is watched through that Io's kernel queue and would not move. The
map rehomes its set before each registration, wait and close, so a map moved
after its first result keeps working on the new Io
(`tests/tasks/a_lazy_map_moves_to_a_task_on_another_io.lin`). `task.WaitSet`
does not move, as before. The set numbers its slots below `max` while it reuses
them, and a new number each time it retires a slot whose generation would
wrap, so the map's names for the slots grow when a slot's number reaches
them.

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

`task.map(.Threads(8), items, f)` on main (fixed chunks) and with each design
tried for this record, both compilers built `-Drelease` and the program with
`linea build -O 2`, on an 8-core Apple-silicon Mac. Each figure is the
fastest of 200 runs (10 000 items), 100 runs (100 000 items) or five runs
(16 items of 30 million steps), as a range over two or three runs of the
program. Main was measured beside each design in the same session, since
the machine's load moved between sessions; the trivial item is `n + 1`. The first
two rows were measured at a load average of 7 to 10; an independent run of
the same comparison measured 1.17–1.25× at 10 000 items and 1.12–1.28× at
100 000. The
last six rows were measured earlier with the fastest of five or forty runs,
and the task-per-item row and its main in a separate run of the same
program.

| Design | 10 000 trivial | 100 000 trivial | 16 heavy |
| --- | --- | --- | --- |
| Main, in the session of the decided design | 378–410 µs | 1 210–1 433 µs | 450.9–474.6 ms |
| **Decided:** each worker starts holding its share less an eighth; eighths handed out; free entries on a stack; one wait set for the map's life | 455–473 µs | 1 304–1 633 µs | 457.0–458.0 ms |
| Main, in an earlier session | 332–358 µs | 1 026–1 109 µs | 260.4–264.8 ms |
| The decided design before free entries moved to a stack | 395–512 µs | 1 216–1 230 µs | 260.4–264.1 ms |
| Main, in the session of the next row | 293–342 µs | 998–1 012 µs | 255.6–268.2 ms |
| Each worker starts holding its whole share; nothing handed out after | 330–361 µs | 1 114–1 127 µs | 268.9–270.5 ms |
| Main, in the session of the next row | 344–416 µs | 986–1 025 µs | 241.9–244.0 ms |
| Chunks of `n / (2 * max)` handed out over sessions; places kept per chunk | 545–666 µs | 1 308–1 387 µs | 247.8–248.8 ms |
| Main, in the session of the next row | 334–515 µs | 1 018–1 204 µs | 242.1–299.7 ms |
| Chunks shrinking as the input runs out; places kept per item | 949–2 098 µs | 2 843–3 634 µs | 243.2–248.8 ms |
| Main, in the session of the next row | 482–597 µs | 1.81–1.94 ms | 435–519 ms |
| A task per item | 338–429 ms | 3.44–3.64 s | 462–529 ms |

How the cost follows `max`, over 20 000 trivial items (a lazy map walks
`1..=20000`), fastest of five or fifty runs for `map` and `all`, one walk
for a lazy map, two runs each:

| `max` | 8 | 1 000 | 10 000 |
| --- | --- | --- | --- |
| `map`, main | 518–523 µs | 77.8–83.7 ms | stops the program (`called Result.unwrap on Err`) |
| `map`, decided | 658–681 µs | 163–171 ms | 7.4 s |
| `all`, main | stopped the program once (`Illegal instruction`), 778 ms once | 1.66 s | — |
| `all`, decided | 585–624 µs | 155 ms | 7.6 s |
| `lazy_map`, decided | 328–359 ms | 1.15–1.19 s | 6.8–7.3 s |
| `lazy_map`, a wait set for each wait and entries found by scanning | 469 ms | about 5 s | 20.4 s |

A lazy map of 100 000 trivial items at `max` 8 takes 1.52 s, and of 20 000
at `max` 2, 8, 64 and 256 takes 204, 216, 254 and 362 ms. Handing out a chunk
and waiting for an answer each visit one busy entry however many workers
there are, which `a_map_visits_each_worker_entry_a_fixed_number_of_times_per_chunk`
holds for `max` 2 and 64 by counting the entries visited. What still grows
with `max` is the operating system's share: every worker is a thread with a
2 MiB stack, starting ten thousand of them takes seconds on macOS, and a
handoff wakes a thread more slowly when thousands of threads are parked. A
lazy map hands out one item at a time, so each of its items pays a
handoff of a few microseconds; it suits work that costs more than that.
`task.all` over 100 000 trivial jobs, which stopped the program on main, is
`tests/tasks/all_answers_a_hundred_thousand_jobs_on_eight_workers.lin`.

What each step cost, from these rows and from timing the operations alone:

- A task's start and join take 29–39 µs, and main spends almost all of a
  map of cheap items on eight of them.
- A handoff (choose, send, and the answer's receive) takes about 5 µs at
  best: each send waits until the other task has woken and copied the
  value. Handing every worker its first chunk over its session instead of in
  its captures cost one handoff a worker and waited for each new thread to
  come up.
- Keeping a place for every item, rather than for every chunk, cost the
  caller several moves per item, which doubled a map of 100 000 cheap items
  on its own.
- The decided design costs, beyond holding whole shares, one handoff a
  worker for the eighths and one choice a worker to stop it, about 60 µs for
  eight workers; holding whole shares costs, beyond main, the stop and the
  wait set's registrations.

Matching main within 10 % while keeping a slow item from holding up the
items behind it would need the workers to take the eighths without the
caller answering each one, from a queue that every worker updates. The only
mutable state the language lets tasks share is an owning task's, whose
every call is a round trip like a handoff, so that design is not taken here.

## Consequences

1. `task.map` and `task.all` over cheap uniform items cost 1.1–1.25× of
   fixed chunks at 10 000 items and 1.1–1.3× at 100 000 (see
   Measurements), and costly items cost the same; a map whose items vary in
   cost no longer waits on a slow chunk while the other tasks sit idle.
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
  session rendezvous between tasks, which a cheap item does not repay.
- **Chunks that shrink as the input runs out (guided scheduling), places kept
  per item:** the last items go out one at a time, which suits uneven work
  best, but a long map of cheap items made a hundred or more handoffs and
  moved every item through the ring, three to five times slower than fixed
  chunks.
- **Chunks of `n / (2 * max)` handed out over sessions:** two handoffs a
  worker, the first waiting for its thread to come up, cost 1.3–1.9× of
  fixed chunks.
- **Whole shares held from the start, nothing handed out after:** within
  about 1.1× of fixed chunks, but a slow item then holds up every item after
  it in its share, as fixed chunks did.
- **A shared queue the workers take from:** the only fast form needs a value
  several tasks write, which only an owning task provides, at a round trip
  per take.
- **Eager `map` only, with callers chunking a stream themselves:** it cannot
  stop early, it holds every result, and a caller that wants the first match
  maps everything.
- **Unbounded spawning (a task per item as fast as the source yields):** the
  memory held grows with the input, since each task keeps a stack until it is
  joined, and stopping early would have to wait for every task started.
- **An in-order window without waiting for the first worker to answer:**
  waiting on the head's worker alone keeps workers that finished idle behind
  it; that is the batch behaviour `all` had.
- **A wait set opened for each wait:** it moved with the map for free, but
  each wait registered and withdrew every busy worker, so a lazy map's cost
  per item grew with `max` (about 23 µs an item at `max` 8 and 1 ms at
  `max` 1 000 on 20 000 items).
- **A set kept for the map's lifetime that stays on its Io:** a map moved to
  a task on another Io stopped the program at its next wait. Opening a new
  set there was not possible either: the old one holds the workers'
  registrations, and closing it from another Io traps.
- **Scanning the busy entries for a free one, and for the one that
  answered:** each handoff and each wait cost `max` steps, so a map of
  20 000 items took 13 s at `max` 10 000.
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
