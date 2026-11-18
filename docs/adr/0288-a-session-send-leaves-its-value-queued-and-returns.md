# 288. A session send leaves its value queued and returns

Status: Accepted — 2026-11-18. Supersedes
[0250](0250-tasks-are-structured-through-linear-sessions.md) §8 (communication
is a synchronous rendezvous) and the clauses of 0250 §10 that build it (a send
waits until the receiver's copy has emptied the slot), and the reason 0265
§4.1 gives for an endpoint's readiness being a reservation. Extends 0250 §9
with what a queued value does to its argument.

## Context

A session has had one slot, and a `send` returned only once the peer had
taken the value. A `choose` is a send of its branch, so it waited the same
way. When the receiver was parked, each send therefore cost the sender the
time the system took to wake the receiver and let it copy the value: about
5 µs on an 8-core Apple-silicon Mac between threads, during which the sender
did nothing.

`task.map` and `task.all` pay it on their critical path. ADR 0276's window
hands a free worker its next chunk with `choose_left()` and `send(chunk)`, two
sends that each waited for the worker to wake, and stops every worker with
`choose_right()`, which waited for each worker in turn before the next was
told. A worker's `send` of its results waited for the map to wake and receive
them, so a free worker sat in its send while the map was busy. 0276 measured
the window at 1.1–1.25× of fixed chunks on 10 000 cheap items and 1.1–1.3×
on 100 000, and named the handoff as the cost.

Nothing a program can write depends on the sender's wait. A payload is
`Owned`, so the sender keeps no view of it, and the only ordering a program
can observe through a session is the one the receiver needs: what the sender
did before the send is visible after the matching `recv`. The reverse
ordering a rendezvous also gave, the receiver's work before its `recv`
visible to the sender after its `send`, orders nothing: the two tasks share
no place either could write, and every place a task reads or holds lent is
ordered by `start` and the join.

## Decision

### 1. A send queues its value and returns

A session holds a queue of at most two values, sent by one end and not yet
received by the other. `send` copies the value into the queue and returns; it
waits only while the queue already holds two values, until the receiver has
taken one. `choose` is a send of its branch, and waits the same way. `recv`
and `offer` take the oldest value, waiting while the queue is empty;
`recv_until` gives up after its timeout as before, leaving the queue as it
was. Values are received in the order they were sent.

The bound is two because the longest run of sends with no receive between
them in the library's own protocols is a choice followed by its payload (the
window's `choose_left().send(chunk)`), and every value a session holds is
memory the receiver has not asked for. A protocol that sends longer runs
waits at its third send until the receiver catches up, which is the
backpressure a rendezvous gave, one value later.

The queue holds the value's bytes: in the session's record when they are 32
bytes or fewer, which covers a branch, a scalar and a `Vec`, and in bytes the
runtime allocates otherwise, released when the value is received. Running out
of memory for those bytes stops the program, as running out for the bytes a
payload moves through already did.

### 2. The ordering a program sees

The happens-before edge of a session is unchanged: everything a task did
before a `send` is visible to its peer after the matching `recv`. The edge
from the receiver back to the sender is gone, and nothing used it (Context).
So the memory model of 0250 §10 holds with **send** in place of
**rendezvous**, and every accepted program stays data-race-free.

A `send` returning no longer tells the sender that its peer has the value.
A program that needs to know writes the answer into its protocol, as one
whose peer acknowledges already does.

### 3. No set of tasks waits on each other forever

0250 §9's argument holds with one change to what *enabled* means. A `send`
is blocked only while the queue holds two values from its own end; the
receiver's next operation on that session is then a `recv` or an `offer`
(its protocol is dual to the sender's, two steps behind), and a value waits
for it, so the pair is enabled and the receiver's operation completes. A
`recv` is blocked only while the queue is empty; the sender is then not
ahead, so by duality its next operation is the matching send, which an empty
queue lets complete. Lemma 2 — a stuck edge has at most one stuck end —
therefore still holds, and the proof goes through unchanged.

A value in the queue that holds an endpoint is delegation in flight. It
belongs to the receiving task from the moment it is queued, since the
receiver's next operation on that session is the `recv` that takes it,
which is enabled; the forest of 0250 §9 is the same forest with the edge
drawn to the receiver one step early.

A session cannot end with a value in its queue: the two ends follow dual
protocols to `End`, so every value sent is received before the receiving end
closes. The runtime checks it when the handle's `close` frees the session,
and stops the program (`linea: a session ended holding a value its receiver
never took`) rather than freeing bytes a value owns, but an accepted program
never reaches the check.

### 4. A wait set's registration is still a reservation

0265 §4.1 says a peer that made an endpoint ready keeps it ready until the
endpoint's owner receives. That holds for a stronger reason now: the value
is in the queue, and only `recv` or `offer` takes it. `received` and
`offered` are ready once a value from the peer waits in the queue. Taking
the endpoint back with `take` or `close` leaves the value queued, and a later
`recv` answers it at once.

### 5. The window stops a worker as soon as it has nothing left to give it

With `choose_right()` returning at once, telling a worker to stop costs the
map nothing, so 0276's window stops each worker at the first moment it is
known to be done rather than one at a time in `finish`:

- once the source is spent, a worker that answers is told to stop as its
  results are received, and the workers already free are told when the map
  finds the source empty;
- `finish` tells every worker still free to stop before it joins the first
  one.

The stopped workers end side by side while the busy ones finish their
chunks, and `finish` joins tasks that have mostly ended. The map keeps the
stopped workers' endpoints in one more vector reserved beside the others,
with room for `max` workers, so `lazy_map_in` still allocates only where 0276
§4 says. None of 0276's properties moves: at most `max` workers, a free
worker takes the next chunk at once, results in input order, and settlement
as before.

## Measurements

`zig build bench-tasks -Drelease` runs `bench/tasks.lin`, which times
`task.map(.Threads(8), items, n + 1)` and `task.all` over the same number of
jobs against fixed chunks (eight equal shares, a task started for each with
`task.start`, which is the design 0276 replaced), each design in turn within
every round, and a lazy map at `.Threads(2)` over 20 000 items, where every
item is one handoff to a worker and one answer back. The figures are medians
over 200 rounds (10 000 items) or 60 rounds (100 000 items), on an 8-core
Apple-silicon Mac, compilers built `-Drelease`. Main and this record were
run four times each, alternately, at a load average of 10 to 14 from other
work on the machine; each cell gives the range over the four runs.

| | 10 000 items | 100 000 items | lazy map, per item |
| --- | --- | --- | --- |
| Main: fixed chunks | 388–456 µs | 1 112–1 137 µs | |
| Main: `task.map` | 495–586 µs (1.23–1.29×) | 1 278–1 320 µs (1.14–1.18×) | 7.6–8.0 µs |
| Main: `task.all` | 484–584 µs (1.24–1.28×) | 1 266–1 282 µs (1.13–1.15×) | |
| Queued sends: fixed chunks | 325–354 µs | 1 014–1 018 µs | |
| Queued sends: `task.map` | 396–414 µs (1.13–1.22×) | 1 046–1 067 µs (1.03–1.05×) | 4.4–6.3 µs |
| Queued sends: `task.all` | 394–416 µs (1.18–1.21×) | 1 045–1 078 µs (1.03–1.06×) | |

The ratios are against fixed chunks built with the same runtime, which
queued sends make faster too, since a worker of fixed chunks no longer waits
for the caller to take its results. Against the fixed chunks main had,
`task.map` now takes 0.87–1.07× at 10 000 items and 0.92–0.96× at 100 000.

Where the time went, from runs of the same program on a quieter machine
while each part of the decision was added in turn:

- queued sends alone halved a lazy map's item (about 7 µs to 3–4 µs) and
  brought 100 000 items to 1.06×, while 10 000 items stayed at 1.23–1.44×,
  since fixed chunks gained as much there;
- stopping every free worker before joining the first brought 10 000 items
  to 1.15–1.18×;
- stopping each worker as soon as the source is spent brought it to
  1.11–1.18×;
- giving each worker its whole share and handing out nothing after, which
  0276 rejected because a slow item then holds up its whole share, measured
  1.05–1.08× in the same session.

The same program, after fiber migration and work stealing landed (ADR
0282), also runs every measurement inside a task on a loop of eight
carriers, where every task is a fiber. Four alternating runs each at a load
average of 3 to 5:

| | 10 000 items | 100 000 items | lazy map, per item |
| --- | --- | --- | --- |
| Main, system Io: `task.map` / `task.all` | 1.26–1.29× / 1.26–1.31× | 1.15–1.18× / 1.16–1.17× | 7.2–7.7 µs |
| Queued sends, system Io | 1.17–1.20× / 1.17–1.20× | 1.03–1.05× / 1.03–1.05× | 4.9–5.5 µs |
| Main, loop: fixed chunks | 973–1 162 µs | 1 817–1 956 µs | |
| Main, loop: `task.map` / `task.all` | 2.40–2.46× / 2.42–2.50× | 1.82–1.89× / 1.78–1.90× | 164–173 µs |
| Queued sends, loop: fixed chunks | 266–285 µs | 1 142–1 166 µs | |
| Queued sends, loop: `task.map` / `task.all` | 2.08–2.10× / 2.06–2.11× | 1.18–1.20× / 1.19–1.20× | 46–52 µs |

On a loop a send no longer switches the sending fiber out until its
receiver runs, so fixed chunks there take a quarter of the time they did
and `task.map` a fifth to a quarter. A handoff between fibers still costs
about ten times one between threads, so the window's extra handoffs weigh
more there than on threads.

What is left at 10 000 items is the eighth of each share that 0276 hands
out after the first chunks. In the uniform case every worker takes one, and
each takes two wakes of a parked thread the fixed design does not pay: the
worker's, when its eighth arrives, and the caller's, when the answer does,
before the worker can be told to stop. A wake costs several microseconds on
macOS whatever is queued, so 10 000 items, about 330 µs in all, stay above
1.1×, while 100 000 items, where those wakes are a smaller share, are within
it.

## Consequences

1. A worker answering a chunk goes straight to waiting for its next one, and
   the map hands a free worker its next chunk without waiting for it to wake.
2. A task that sends several values in a row runs ahead of its peer by up to
   two values.
3. Under a simulation, a send no longer gives the scheduler a turn, so a
   seed's interleaving differs from what it was; every seed still repeats
   exactly.
4. Each session's record holds about 70 more bytes, beside the stacks it
   already holds, and a value larger than 32 bytes costs the runtime an
   allocation while it is queued.

## Alternatives considered

- **Keep the rendezvous:** every handoff keeps costing the sender a wake of
  its peer, which is what kept the window above 1.1× of fixed chunks.
- **A queue of one value:** the window's `choose_left().send(chunk)` would
  still wait for the worker to take the branch before it could queue the
  chunk, one wake per handoff on the caller.
- **An unbounded queue:** a sender that outruns its receiver would hold
  memory without limit, and the language would lose the backpressure a
  session gives a producer for free.
- **Moving the sender's own bytes into the queue instead of copying them:**
  the receiver would release bytes the sender's allocator lent, which needs
  the payload's bytes and their allocator to cross the runtime as a value;
  the copy of at most a few dozen bytes costs less than the bookkeeping.
- **A thread that watches the session for a few microseconds before it
  sleeps:** waking a thread from a condition variable takes about as long as
  a handoff, so a park that first watched an unpark count for 10 µs avoided
  most wakes on a quiet machine (10 000 items: 0.93× of fixed chunks in one
  run). On a loaded machine the watching threads took the processors the
  working ones needed: fixed chunks themselves slowed from 360–620 µs to
  640–650 µs and a lazy map's item from about 9 µs to 22–25 µs. A wait that
  costs the processors it waits on is not cheaper in general, so every park
  still sleeps at once.
- **Folding a choice and its payload into one message for the window:** it
  would make the window's protocol `Send[Option[Vec[T]], …]` and speed only
  the library, while every program's sessions kept the wake per send.
