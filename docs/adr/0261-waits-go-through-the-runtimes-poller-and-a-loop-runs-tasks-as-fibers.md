# 261. Waits go through the runtime's poller, and a loop runs tasks as fibers

Status: Proposed — 2026-11-07, revised the same day after two external
reviews. The number is provisional: two branches in
flight may take 0259 and 0260, and this record is renumbered to the next free
number when it lands. Nothing is built. Once built, it would change these
sentences of existing records:

- [0250](0250-tasks-are-structured-through-linear-sessions.md) §6, "Waiting on
  several sources at once remains open", which §4 answers;
- 0250 §9, whose theorem §5 restates as three separate properties, and whose
  list of blocking operations §1, §4 and §7 add to, each with the argument §9
  asks of a later record;
- 0250's Open question "A fiber substrate. Deferred until the runtime has a
  poller", which §7 answers;
- [0253](0253-independent-work-runs-through-an-explicit-executor-policy.md)
  §5, "The listener lives in an owning task that each serving task asks for its
  next connection", which §6 replaces with a dispatcher that also holds idle
  keep-alive connections;
- the [T-ThreadStart] rule of `docs/linea-semantics.md`, which §7 widens from
  "on a thread of its own" to "on a thread or a fiber of its own";
- decision #26 of the 2026-10-15 concurrency review, "carried by service
  objects like `TcpListener` and `File`", which §8 narrows: `Io` is passed to
  what starts tasks, and a descriptor does not store it (Open question 1).

## Builds on

These points were settled before this record and are inherited, not reopened.
Where this record narrows one, the row says so.

| Settled point | Source |
| --- | --- |
| Substrate first is OS threads, 1:1; fibers come later behind the same task API. | `linea-reviews/2026-10-15-concurrency/decisions.md` #2; 0250, Alternatives, "Stackful fibers first" |
| No colouring: no `async`/`await`, no futures in signatures. Stackless async is excluded because Nystrom's rules survive `await`. | `Linea concurrency with linear types.md`, "Fixed guard-paged fiber stacks are the only sound substrate"; `concurrency-discussion.md`, substrate table |
| The only sound fiber substrate is fixed, individually mapped stacks with guard pages: a growable or segmented stack needs every pointer into it found and rewritten, and Linea has pointers into stacks and no collector. | the same section of `Linea concurrency with linear types.md` |
| Under M:N, no thread-affine state may be live across a migration. | the same note, its migration paragraph; §7 states the invariant exactly |
| I/O blocks today; `runtime/net.c` polls only to finish an interrupted `connect`. A fiber substrate needs nonblocking descriptors and a poller, or pins its carrier. | `concurrency-discussion.md` §2 item 3 and §5.4 |
| Zig 0.16's staging, a blocking backend first and evented backends later behind one `Io` value, is the model. | `concurrency-discussion.md`, comparison table; Zig 0.16.0 `lib/std/Io.zig` |
| CPU parallelism (`task.Policy`) and I/O waiting (`Io`) are separate capabilities, and the event loop is its own pillar. | `executor-and-policy-design.md` §9, §10; decisions #23, #26 |
| `Io` is a capability passed like an allocator, and a handler never takes an `io` parameter. Narrowed by §8: it is passed where tasks are started, not stored in descriptors. | decisions #26 |
| `Allocator`, `Io`, `Policy` and sessions are four orthogonal resource capabilities; the process heap has open stateless naming. | decisions #28; [0095](0095-the-system-allocator-is-named-rather-than-received.md) |
| No task is stopped from outside. A deadline is stated where a task waits; cancellation is a protocol branch; deadline scopes and cancellation tokens that propagate implicitly are rejected. | decisions #3, #14; 0250 §3, §7 and Alternatives |
| No unjoined thread: only `Slot.start` may start Linea code on a thread of its own. | [0253](0253-independent-work-runs-through-an-explicit-executor-policy.md) §3, [T-ThreadStart] |
| No set of tasks waits on each other forever: the task graph is a forest and a blocked task waits on its own edges. Every later blocking operation must say what it does to that argument. Copyable senders to a mailbox broke it. | 0250 §9 and §6; decisions, "External review, and keeping deadlock freedom" |
| A linear-sender inbox merging children's streams, with timers as producers that wait on no task, keeps the forest. | decisions #13 (revised), #16 |
| `http.serve` is concurrent by default on `.Threads(128)`, with a handler per serving task. | 0253 §5; `CLAUDE.md` |
| A foreign call is made through a granted module's `extern`; a callback with a context is called during the call, on the calling thread. | [0228](0228-a-granted-module-calls-c.md), [0229](0229-an-application-depends-on-a-library-by-path.md), [T-ExternCallback] |
| Non-blocking I/O, asynchronous I/O, timeouts and cancellation were deferred by the socket and text designs. | `linea-design/specs/2026-09-23-tcp-http-server-design.md` §3, "Out of scope"; `2026-09-08-owned-text-borrows-and-io-design.md`, "Deferred" |
| The poller is the runtime's own C over direct system calls (kqueue, epoll, later io_uring), no event-loop library, shaped around completion; Windows is not a target. | the maintainer, 2026-11-07 |

What is new here: the operation and its state machine (§1, §2), the fiber's
scheduling state (§3), the wait set, its keys and its registration protocol
(§4), the theorem split into three properties (§5), the dispatcher and its
HTTP/1.1 policy (§6), pinned fibers and the migration invariant (§7), the loop
and `Io` (§8), blocking and thread-affine foreign calls and callback mode
(§9), and the phases (§12).

## Context

Every wait in the runtime blocks the OS thread that makes it. `accept`,
`read`, `write` and `connect` block in the kernel; `Connection.set_deadline`
emulates a deadline by rewriting `SO_RCVTIMEO` before every read; `recv_until`
waits on a condition variable; `time.sleep` is `nanosleep`. A task is a thread
with a 2 MiB mapped stack, so a server holds one thread per connection it is
answering and serves at most `.Threads(max)` connections at once.

Four things users ask for cannot be written on that substrate, or not well:

1. **HTTP keep-alive.** `http.serve` answers every request with
   `Connection: close`. A kept-alive connection idle between requests would
   hold a serving task, so 128 idle browsers stop a server on the default
   policy.
2. **A wait on several sources.** A task cannot wait for whichever comes first
   of a peer's message, a socket, a child's return and a timer.
3. **Timers.** `send_after`, a timeout on `offer`, and racing an operation
   against a timeout have no primitive beyond `recv_until`.
4. **Many connections per thread.** A task blocked on I/O holds an OS thread.

**Zig 0.16's `std.Io`**, read from the pinned toolchain (`lib/std/Io.zig`,
`Io/Threaded.zig`, `Io/Kqueue.zig`, `Io/Uring.zig`, `Io/Dispatch.zig`):

| Zig 0.16 | Linea under this record |
| --- | --- |
| `Io` is `{ userdata, vtable }` with about 120 entries: files, directories, processes, network, clock, futex, `async`, `concurrent`, groups, cancellation | `io.Io` names a loop or the system; files, sockets and clocks stay in their own modules (§8) |
| `Io.Threaded`, the one finished backend: blocking system calls, tasks on a pool bounded by `async_limit` and `concurrent_limit` | the system `Io`: an operation is performed on the calling task's own thread, and there is no hidden pool, since every task thread is joined |
| `Io.Kqueue`, `Io.Uring`, `Io.Dispatch`, experimental (`Kqueue.zig` has 58 `TODO` or unimplemented sites): fibers on carrier threads, 4 MiB stacks from the general-purpose allocator with no guard page | fibers on stacks mapped as task threads' are, 2 MiB usable over 64 KiB of guard pages, so an overflow stays a reported trap (§7) |
| `io.async(f)` may run `f` inline; `io.concurrent(f)` must run it concurrently and may fail | `task.Policy`'s `.Sequential` may run inline; `task.start` always makes a task and may fail; the handle is linear, so "must be awaited" is checked |
| `Future.cancel` and `error.Canceled` at every cancellation point | none: a deadline where a task waits, and a protocol's stop branch (§10) |
| `Io.Select(U)` waits for the first of several tasks | `task.WaitSet[M]` waits on descriptors, endpoints, handles and timers, and keeps what did not fire (§4) |
| `operate`, `Batch` and `Io.Timeout` submit operations with deadlines | every wait is an operation with a deadline, through one completion-shaped interface (§1) |

What transfers is the colour replaced by a value, a blocking first backend
with evented ones behind the same surface, and completion-shaped operations.
What does not is external cancellation, an interface that is the whole
operating system, unguarded fiber stacks, and a pool that runs program code
unjoined.

**What a measurement showed.** A spike in C (`cc -O2`) served a 64-byte echo
on loopback from up to 4 000 kept-alive connections, driven by one client
thread through its own kqueue, on an 8-core Apple-silicon Mac under a load
average of about 11 from other jobs, so the figures are indicative:

| Server | Connections | Round trips/s | Resident memory |
| --- | --- | --- | --- |
| a thread per connection, 2 MiB guard-paged stacks, blocking calls | 100 / 1 000 / 4 000 | 95 000 / 90 000 / 89 000 | 4 / 32 / 126 MiB |
| one kqueue thread, nonblocking descriptors | 100 / 1 000 / 4 000 | 104 000 / 93 000 / 94 000 | 1 MiB at every count |

On one connection, a blocking `read` took 28 to 31 µs a round trip, and a
nonblocking `read` that calls `poll` on every `EAGAIN` 32 µs. Threads stayed
within 9 % of the event loop's throughput, so throughput is not the reason to
change substrate. Memory is one (about 31 KiB resident per connection a thread
serves, against nothing measurable for a registration); keep-alive, waiting
on several sources and timers are the others. Phase 1's backend costs about
5 % of a loopback round trip, its worst case. The spike measured neither
fibers, rendezvous, timers nor a scheduler; §12's measurement plan does.

## Decision

### 1. Every wait is an operation, completed by a backend

The poller is the runtime's own C, beside `net.c` and `task.c`, calling the
system directly: kqueue on macOS, epoll on Linux, io_uring later as a second
Linux backend. No event-loop library is linked (Alternatives). Windows is not a
target. The interface is shaped around **completion**: the caller submits an
operation and is resumed with its one result.

```c
/* One operation. It lives in the submitting task's frame, which stays put
 * while the task is parked in `linea_io_perform`. */
struct linea_op {
    _Atomic uint32_t state;     /* §2 */
    uint32_t generation;        /* §2: which arming an event belongs to */
    uint8_t kind;               /* accept, connect, read, write, readable, writable, sleep */
    int fd;
    unsigned long at, len;      /* the bytes a read fills or a write sends */
    unsigned long address;      /* connect's packed address */
    unsigned long deadline_ns;  /* monotonic; 0 for none */
    long result;                /* a count, a descriptor, or a negated errno */
    struct linea_park park;     /* §3 */
};

/* Perform `op` and answer its result. EINTR never reaches the caller. */
long linea_io_perform(struct linea_op *op);
```

A backend is a way to complete operations:

- **In place**, on the thread of a task that is a thread (every task until
  phase 4, and thread tasks after it): try the system call; on `EAGAIN`,
  `poll` the one descriptor for what remains of the deadline; try again.
- **kqueue and epoll** emulate completion. The submitting fiber tries the
  call first, so an operation that would not block costs what it costs now.
  On `EAGAIN` it arms a one-shot registration (`EV_ONESHOT`, `EPOLLONESHOT`)
  and parks; the carrier that sees the descriptor ready claims the operation,
  performs the call on its bytes and makes the fiber runnable (§2).
- **io_uring** (phase 7) submits the operation itself, with a linked timeout
  for its deadline, and resumes the fiber from the completion queue.

`readable` and `writable` complete when the descriptor is ready and do nothing
else; the wait set's descriptor sources use them.

**What the completion shape costs kqueue and epoll.** An operation is a record
that outlives its first system call and lends its bytes' address until it
completes, where a readiness interface would hand the caller a bit and let it
call `read` itself. The record costs no allocation, since it is in the parked
fiber's frame, but a carrier other than the submitter's code touches the
submitter's bytes, which is why §2 fixes the handoff. In return io_uring is a
new backend and not a new interface, and the rule a completion backend needs
(an operation's bytes are lent until the backend can no longer reach them)
holds from the first phase.

**Deadlines.** An operation never intentionally waits past its deadline: the
deadline is checked against the monotonic clock before each attempt and is the
timeout of each wait, and completion may be observed later than the deadline
by scheduling latency, which the runtime does not bound.
`Connection.set_deadline` then stops rewriting socket options before each
read, and `accept` and `connect` take deadlines the same way.

**When readiness and expiry are observed together**, the claimant (§2) applies
the operation's own rule:

| Operation | Rule |
| --- | --- |
| `read`, `write` | one attempt; progress answers its count, since dropping it would lose bytes; `EAGAIN` answers `-ETIMEDOUT` |
| `accept` | one attempt; a connection accepted is answered and owned by the caller, since the kernel has already removed it from the backlog; `EAGAIN` answers `-ETIMEDOUT` |
| `connect` | writability is not success: the claimant reads `SO_ERROR`; zero answers connected, an error answers that error, and a connection still in progress at the deadline answers `-ETIMEDOUT` after the runtime closes the socket it made, which the caller never received |
| `readable`, `writable` | readiness wins, since answering it consumes nothing |
| `sleep` | expiry is its completion |

**Timers.** Every operation's deadline and every timer of §4 sit in one
deadline heap per poller, and the nearest deadline is the timeout of the wait:
`kevent`'s `timespec`, `epoll_pwait2`'s `timespec` on Linux 5.11 and later,
`epoll_wait`'s milliseconds rounded up before it. The heap is chosen over
`timerfd` on epoll because nearly every operation arms and then cancels a
deadline (a read that completes in time cancels its deadline): in a heap that
is an insertion and a removal in user space, where `timerfd` costs a
descriptor per timer and a system call per arm and per cancel. It is chosen
over `EVFILT_TIMER` on kqueue for the same reason, and so that both backends
order, fire and cancel deadlines through one implementation; `kevent`'s
timeout already has nanosecond resolution.

**Socket semantics in full.** Once sockets are nonblocking, every operation
handles short reads and writes, `EAGAIN` and `EWOULDBLOCK`, `EINTR`, `EINPROGRESS`
and `SO_ERROR` for `connect`, a peer's reset and half-close, and the macOS
differences the runtime already handles (`SO_NOSIGPIPE`, `getpeername`'s
`EINVAL` after a reset). A regular file is never polled (`epoll_ctl` refuses
regular files), so under kqueue and epoll a file operation is a call into a
module that blocks (§9); io_uring performs it directly.

### 2. An operation has one terminal result

An operation moves through these states, each change a compare-and-swap on
`state`, so exactly one party makes each transition:

| From | To | By | Linearization point |
| --- | --- | --- | --- |
| idle | armed | the submitter, after its attempt answered `EAGAIN` | the swap, after the registration and the deadline are published |
| armed | claimed | the first of: the carrier that saw readiness, the carrier whose heap expired the deadline, the backend's own completion | the swap; every other claimant's swap fails and it does nothing |
| claimed | complete | the claimant, after its last access to the operation's bytes, after it has disarmed the registration and removed the deadline, and after writing `result` | the swap, with release order |
| complete | runnable | the claimant, by unparking the submitter (§3) | the unpark |

`claimed` names who owns finalization, not what the result is. The claimant
records the event that began it (readiness, expiry, a completion), and the
backend's own machine, internal to `claimed`, decides the result:

- **kqueue, epoll and in place**: the claimant performs the attempt itself
  under the tie rules of §1, so the kernel never holds the bytes after the
  attempt returns, and `complete` follows at once.
- **io_uring**: the kernel holds the bytes from submission. A claim by
  expiry enters an internal **cancelling** phase: the claimant submits a
  cancellation for the operation and waits for the operation's **own**
  completion entry, which arrives after or beside the cancellation's. That
  entry decides the result: a success (bytes read, a connection accepted)
  is answered as the result even though the deadline passed, and
  `-ECANCELED` becomes `-ETIMEDOUT`. Only then is the kernel done with the
  bytes, and only then is `complete` swapped. A claim by completion needs no
  cancellation.

The external contract is the same for every backend; only the machine inside
`claimed` differs.

**Registration storage outlives every event that can name it.** Each poller
keeps a registration table: slots in pages that are never freed while the
poller exists. A slot holds a generation and a pointer to the operation it
currently serves. A kernel cookie (`udata`, `epoll_data.u64`, `user_data`)
names a slot index and its generation, never an operation's address. Arming
takes a slot; `complete` disarms the registration and then releases the slot,
incrementing its generation, after which the operation's frame may be reused.
An event read from the kernel at any time later (a batch returned before a
disarm, an event queued during a rearm, an event for a descriptor number that
has since been reused) looks up a slot that still exists and finds a
generation that no longer matches, and is discarded. A generation is 32 bits;
a slot whose generation would wrap is retired and never reused, so no event
can match a later arming of its slot.

The guarantees, for every backend:

1. **Exactly one terminal result** reaches the submitter: only the claimant
   writes `result`, and only once.
2. **Events are disarmed before the record is reused**, and an event that
   arrives after the disarm reaches only the slot table.
3. **Borrowed bytes stay valid until the backend can no longer reach them.**
   The submitter is parked, and so holds its lends, until `complete`, which
   follows the last access by the claimant and, on io_uring, the operation's
   own completion entry.
4. **No late resume.** An event that arrives after `claimed` fails its swap or
   its generation check; only the claimant unparks, once.
5. **No event is mistaken for a reused descriptor**, by the slot table.

### 3. The runtime's waits are parks, and a fiber has a scheduling state

The runtime stops a task in one routine and wakes it in one:

```c
void linea_park(struct linea_park *p, unsigned long deadline_ns);
void linea_unpark(struct linea_park *p);
```

Session rendezvous, `close`'s join, the owning task's call queue,
`recv_until`, the wait set and `linea_io_perform` all use it. On a thread a
park is the condition-variable wait `runtime/task.c` already does, under the
lock of the record being waited on. On a fiber it is the machine below.

**An operation's machine and a fiber's machine are separate.** §2 decides who
completes an operation and when; this one decides when the fiber that waits
for it may run. Each fiber has a scheduling state word, changed only by
compare-and-swap:

| From | To | By | Meaning |
| --- | --- | --- | --- |
| Running | Parking | the fiber, before it publishes what it waits for (arms an operation, joins a rendezvous, registers a wait set) | from here a completion may arrive at any time |
| Parking | Parked | the carrier, after the switch has saved the fiber's context and the carrier runs on its scheduler stack | the fiber's context is complete and nothing executes on its stack |
| Parking | Notified | the unparker, when the fiber has not finished switching away | the wake is recorded, not acted on |
| Notified | Runnable | the carrier, when its swap to Parked fails and it finds Notified, after the context is saved | the carrier that switched the fiber out queues it |
| Parked | Runnable | the unparker | it queues the fiber |
| Runnable | Running | the fiber's carrier, taking it from its run queue and switching in | |
| Running | Finished | the fiber, when its body returns; its record is retired by the joiner's `close` | |

The handoff is stated by the states, with no lock held across a switch:

- **A fiber never executes on two carriers.** A fiber is queued only from
  Runnable, and it reaches Runnable only after its context has been saved: from
  Parked, which the carrier sets after the save, or from Notified, which the
  saving carrier itself converts. No unparker queues a fiber in Parking.
- **No unpark is lost.** An unpark is a successful swap out of Parking or out
  of Parked. If it lands in Parking, the carrier's swap to Parked fails and the
  carrier queues the fiber itself. §2 and §4.2 give each wait exactly one
  unparker, so no wake is counted twice.
- **Pinned fibers and wakeups from other carriers.** Queueing a pinned fiber
  means pushing it to its home carrier's queue, which other threads push to
  (§8.1); a push posts the carrier's user event when the carrier may be waiting
  in its poller. The push is the release, and the home carrier's pop the
  acquire, of the happens-before edge 0250 §10 asks of the wait.

The handoff between a submitter and whoever completes its operation is then
**publish** (Running to Parking, then arm), **claim** (§2), **complete** (§2,
release order, after the last access to the bytes), **runnable** (the unpark,
out of Parking or Parked). Completion is never visible before the last
access, and a fiber is never runnable before its context is saved.

### 4. A task waits on several sources through a linear wait set

`task.WaitSet[M]` is a linear value owned by one task. Each registration moves
a linear value into the set with a function that wraps it back into the
program's own enum `M` once it is ready, and answers a key:

```linea
enum Waited {
    Answer(session.Chan[Recv[text.String, End], ()]),
    Late,
}

// Ask a peer and give up after `limit`. Whichever comes first is answered; the
// other is taken back by its key, so nothing registered is lost.
fn ask_within(sink peer: session.Chan[Recv[text.String, End], ()], limit: time.Duration) -> Asked {
    var waiting = task.WaitSet[Waited].open()
    let answer = &waiting.received(peer, |ready| Waited.Answer(ready))
    let timer = &waiting.after(limit, Waited.Late)
    let asked = match &waiting.next() {
        Some(Answer(peer)) => {
            let _late = &waiting.take(timer)   // the timer's message, unfired
            let (text, peer) = peer.recv()
            peer.close()
            Asked.Answered(text)
        },
        Some(Late) => Asked.TimedOut(&waiting.take(answer).unwrap()),  // the endpoint, still at Recv
        None => panic("two sources were registered"),
    }
    waiting.close()   // empty: both keys were taken
    asked
}
```

The sources:

- `readable(holder, wrap)`, `writable(holder, wrap)`: a value whose type
  implements `io.Pollable` (a listener, a connection, a buffered reader over
  one), ready when its descriptor is;
- `received(chan, wrap)`: an endpoint whose next operation is `recv` or
  `offer`, ready when the peer's `send` or `choose` is waiting. Implementation
  heads ([0252](0252-a-types-own-implementation-may-write-a-parameter-inside-an-argument.md))
  admit only those states, so registering an endpoint at `Send` is
  [T-UnknownOperation];
- `returned(handle, wrap)`: a handle at `End`, ready when the body has
  returned;
- `after(duration, message)`: a timer.

`next` waits until a source is ready, delivers exactly one, and answers it
wrapped. `take(key)` withdraws one registration and answers its value in its
**own type**: taking the answer key gives back the endpoint and taking a
timer's key gives back its message. `close` answers a `Vec[M]` of every
registration still held, wrapped, for a set whose keys the program did not
keep. An empty set answers `.None` from `next` without waiting.

**A key is a non-owning identifier, validated against the set.**
`task.Registered[T]` is copyable and `Owned` and holds three numbers: the set's
identity, a slot and the slot's generation, with `T` as a phantom.

- **Set identity.** Every set takes its identity from a process-wide 64-bit
  counter when it is opened; identities are never reused. At a billion sets
  opened a second the counter lasts 584 years, and reaching its end is a trap,
  not a wrap. `take` on a set answers `.None` for a key of another set.
- **Slot generation.** A slot's generation increments when its registration is
  delivered, taken or closed. `take` answers `.None` for a key whose generation
  is not the slot's current one, so a copied key, used again after its
  registration was taken and its slot reused, never reaches the replacement. A
  slot whose 32-bit generation would wrap is retired.
- **`T`.** A key is minted only by the registration of a `T` in that set, at
  that slot and generation, so a key that matches names a value of `T`.
- **After `close`.** `close` consumes the set, so no call can name it again;
  its identity is never issued again, so its keys answer `.None` from every
  other set. A key outlives its set harmlessly.

A key that borrowed its set would make every key a live observation of the
set, and [O-Borrow] would refuse `&waiting.next()`, which changes the set,
while any key was held: a program could not keep a timer's key across the
`next` that races it, which is the use keys exist for.

**`io.Pollable` provides readiness; it is not a descriptor accessor.** Its one
method answers what the set should wait for:

```linea
pub enum Readiness { Now, Wait(io.Source) }
pub trait Pollable { fn readiness(self: Self, interest: Interest) -> Readiness }
```

`Now` covers what user space already knows: a buffered reader holding bytes, a
value whose next read answers end or an error. `Wait` hands the set an opaque
`io.Source` the runtime makes from a descriptor, which the set arms on
registration and disarms before the value leaves the set by delivery, `take`
or `close`. A value with an operation in progress cannot be registered: the
operation's task is parked in it with the value lent.

#### 4.1 Two readiness contracts

- **A descriptor's readiness is a hint.** A descriptor reported readable may
  still answer `EAGAIN` (another reader, a spurious wakeup, a checksum
  failure); every operation on it goes through `linea_io_perform`, which
  handles that. `next` promises readiness was observed, not that an operation
  will succeed.
- **An endpoint's readiness is a reservation.** A session `send` or `choose`
  cannot be withdrawn once begun: there is no timed send, and the sender waits
  until its value is taken. So a peer that made an endpoint ready keeps it
  ready until the endpoint's owner performs `recv` or `offer`, whether the
  endpoint is delivered by `next`, withdrawn by `take` or answered by `close`.
  A later record that adds a timed or cancellable send must keep this: a send
  that has signalled a set may not withdraw.

#### 4.2 The registration protocol

Each registration has a state word; its transitions are compare-and-swaps,
and each successful swap is the transition's linearization point.

| From | To | By |
| --- | --- | --- |
| — | registered | `received`, `returned`, `readable`, `writable`, `after`: the value's bytes move into the set, then the source's mark is published, then the source is checked once (below) |
| registered | signalled | the source: a peer entering `send` or `choose` (under the session's lock, after filling the slot), a body returning (under the task's lock), a descriptor event of the current generation, a timer's expiry; the set's user event (`EVFILT_USER`, an `eventfd` write) is posted after the swap |
| signalled | delivered | `next`: it swaps the earliest-signalled registration, then clears the mark and moves the value out wrapped; one `next` delivers one value |
| registered or signalled | withdrawn | `take` or `close`: the swap, then the mark is cleared and the value moved out |

- **No lost wakeup.** Registration publishes its mark before it checks the
  source (the slot full, the body returned, `readiness` answering `Now`, the timer
  past), and a source posts after it fills the slot or returns and then reads
  the mark. Either the source sees the mark and swaps, or the registration's
  check sees the source and swaps; both may try, and one swap fails.
- **A pending peer.** If `take` or `close` withdraws an endpoint whose peer is
  waiting, the endpoint comes back at its `Recv` or `Offer` state with the
  peer still waiting, and the owner's next `recv` completes at once. No
  rendezvous is lost and none is half done: `next` never performs one.
- **Exactly-once ownership.** A value leaves the set by exactly one successful
  swap out of `registered` or `signalled`, so it is delivered, taken or
  closed, never two of these. When a source is signalled and `take` wins the
  swap, `take` answers the value and `next` skips the slot: a signalled timer
  whose message `take` recovered is never delivered afterwards, and an
  endpoint whose peer is waiting comes back with the peer still waiting.
- **Moving a value out.** A descriptor's registration is disarmed before the
  value moves out of the set, so a value never leaves with a registration of
  its previous context still active (§8).
- **Concurrent wakeups.** Several sources may be signalled before one `next`;
  each `next` delivers the earliest and leaves the others signalled.
- **Timers.** A timer that expires together with another source is signalled
  like any source; `next` picks one winner by its swap, and the loser stays
  registered or signalled. A timer's message moves out only when it is
  delivered, taken or closed; expiry alone consumes nothing.
- **`returned` and the join.** `returned` reports that the body has returned
  and the child's end is settled. It does not finalize the handle: `close`
  still joins the thread or retires the fiber and then releases the captures,
  the four steps of 0250 §2, but it waits on no task.
- **One registration per descriptor.** The registered value is moved into the
  set, so a descriptor is in at most one set, once, readable or writable. A
  connection that needs both directions at once is a later decision.

A set carries the dependencies of what it holds exactly as a `mem.Vec[M]` of
the same values does, so a set holding a handle whose body read the parent's
values keeps those values reserved until the handle leaves the set and is
closed. A set holding such a value is not `Owned`.

#### 4.3 What `close` answers

`close` answers `Vec[M]`, and typed `take` is the precise path. Three programs
decide it:

- *A reply against a timeout* (above): both keys are kept, each loser is taken
  back in its own type, and `close` answers an empty vector. A typed residual
  from `close` would add nothing.
- *The first of three children* (`returned` on three handles): the program
  keeps three keys, closes the winner, then takes and closes the other two
  handles, each in its own type. `Vec[M]` would force a `match` with an arm for
  each variant, all of the same shape.
- *A dispatcher shutting down* (§6): hundreds of idle readers, all wrapped as
  `Idle(reader)`, whose keys the dispatcher holds only to time them out. A
  `Vec[M]` of uniform values is what it closes; a typed residual per
  registration would be the same list.

So `close` keeps `Vec[M]` for the uniform case, and a program with
heterogeneous losers takes them by key.

#### 4.4 Prerequisite of phase 2: no job waits on a task

0250 §9's argument for an owning task rests on a job never waiting on a task.
A job reaches only the owner's state and its own captures, so neither may hold
anything a job can wait on. `task.own` bounds the state by `Owned` and `call`
bounds the job by `Owned + Release`, and a detached endpoint
(`Chan[P, ()]`) appears to satisfy `Owned`. If it does, a program can already
put an endpoint in an owner's state and have a job `recv` on it while the
peer's progress depends on another job queued to the same owner: a wait the
argument rules out and the compiler accepts. Phase 2 does not begin until this
is settled, since a wait set holding an endpoint would inherit the hole.

**If the hole exists, the rule is:** a structural predicate, computed from
fields as `Shareable` is, that is false for `session.Chan` and so for every
value holding one (a handle, a wait set holding either, an aggregate holding
any of them); `task.own` requires it of its state and `call` of its job. A
program that puts a waitable value in an owner's state or a job is refused at
the call, naming the field that holds it. The refusal is a corpus case
recorded before the fix, and the predicate's leaves are read from the
library's declarations, so a waitable type added later is covered. The fix
lands on its own, independently of this record.

> **Verification result (pending):** _to be filled by the separate check
> against the compiler: whether the program described above is accepted
> today, the corpus case that shows it, and the fix's change._

### 5. Three properties, each with its own argument

0250 §9 proves one theorem under one assumption. With waits on the world and a
fiber substrate, three properties must be kept apart:

1. **Session deadlock freedom.** No reachable state has a set of tasks each
   blocked on an edge, or on a set of its own edges, whose other end is a task
   of the set. This is structural and holds on every substrate.
2. **Scheduler progress.** A task that is continuously runnable eventually
   runs.
3. **External progress.** A descriptor event, a timer, or a foreign call
   eventually arrives or returns, as far as its own contract promises.

The promise of 0250 §9, that no set of tasks stays blocked forever waiting
only on each other, follows from 1 together with 2 (weak fairness) for the
tasks' own operations. It never depended on 3, since a task waiting on the
world is not waiting on a task.

**Property 1 with wait sets.** A task blocked in `next` is blocked on every edge
it registered with `received` or `returned`. Every value in the set was the
task's own, so every such edge is the task's own; moving a set to another task
moves its endpoints, which is delegation and keeps the forest by 0250's
argument. Lemma 2 extends: if the peer at the other end of a registered edge
`e` were blocked on `e`, its pending operation would be the complement of the
registered one (a `send` or `choose` against a registered `recv` or `offer`,
or the child's own settled `End` against `returned`). By the protocol of §4.2
that operation's arrival either finds the mark or is found by the
registration's check, so the registration is signalled and `next` returns. So
the peer is blocked on another edge, and the walk of 0250's proof leaves every
node by an edge other than the one it arrived by, which a finite forest does
not allow. Timers and descriptors wait on no task. No sender is minted or
copied: a set holds only endpoints that `start` created and delegation moved.

**Property 2 by substrate.** Kernel-scheduled threads are assumed weakly
fair. Cooperative fibers are weakly fair only if every fiber reaches a park
point within finite time. A fiber that computes forever without calling the
runtime keeps every other fiber on its carrier from running; stealing (phase 6)
helps only while some carrier is idle, and nothing in this record establishes
fairness against fibers that compute without waiting.

The runtime distinguishes three cases. An operation that succeeds at once
returns inline, so a hot read of buffered data costs no switch. An operation
that must wait parks. An attempt that makes no progress and answers at once
(`recv_until` with a zero timeout, a deadline already past) yields before it
answers, so a fiber polling a peer on its own carrier lets the peer run. A
fairness poll, when one exists, yields when the scheduler asks.

Safe-point polls alone would not make property 2 unconditional: the scheduler
also needs a time budget after which a running fiber is asked to yield, and
the compiler must poll on every path that can run unboundedly (loop
back-edges, recursion through function entries, long runtime calls such as a
large copy). Until both exist and are verified, the theorem stays
conditional. Under fibers the promise of 0250
§9 is therefore conditional: **if every fiber reaches a park point within
finite time**. The guide states it, and Open question 3 asks whether safe-point
preemption should make it unconditional before fibers serve by default.

**Property 3** is assumed for the world and for foreign calls as their own
contracts say. A foreign call that never returns stops its task, and the
join of every task above it, forever.

### 6. HTTP keeps connections alive through a dispatcher

One dispatcher, the task that called `serve`, holds a wait set over the
listener and every idle connection. The serving tasks are its children, each
with one session:

```linea
// The dispatcher offers each serving task another connection, or the end of
// serving, when the serving task answers what its share reported.
type Serving = Offer[Recv[Reading, Send[Served, Serving]], Send[Result[(), ServeError], End]]  // `enter` unfolds it
enum Served { Idle(Reading), Closed }
// A connection with the bytes already read from it, so a request that
// arrived with the previous one is not lost while the connection waits.
type Reading = io.BufferedReader[net.Connection]
```

When the listener or an idle reader is ready, the dispatcher sends the reader
to a free serving task. A serving task answers one request and sends the
reader back as `Idle`, or reports it `Closed`. The dispatcher waits on busy
endpoints with `received` in the same set and keeps free ones, whose next
operation is its own `choose`, in a vector. An idle reader that already holds
the next request's bytes is ready on registration (its `readiness` is `Now`). Ready
readers that find no free serving task wait in a queue the dispatcher keeps,
bounded by the connection limit below. When serving ends, the dispatcher takes
the end branch on every serving task, which answers what its share reported
(`ServeError.Memory` when it could not take its buffers, as 0253 §5 reports
now), and closes it.

**The framing policy.** Linea serves a restricted HTTP/1.1 and refuses what it
does not support safely, so that no request can be read two ways by Linea and
a proxy in front of it. Most of it is the request parser as it stands
(`std/http/parse.lin`), which keep-alive makes load-bearing; this record adds
the rules marked new.

- **Request line.** `METHOD SP target SP version`, split on single spaces into
  exactly three parts, a method of token characters and an ASCII target with
  no bare CR; anything else is `400`. Longer than `Limits.max_line_bytes`
  (8 KiB by default, CRLF counted) is `414 URI Too Long`.
- **Version.** `HTTP/1.1` and `HTTP/1.0` are served; another well-formed
  version is `505`, a malformed one `400`.
- **Header lines.** Each within `max_line_bytes`, else `431`; at most
  `Limits.max_headers` (100), else `431`. A line without a colon, whitespace
  before the colon, an empty name, a bare CR, a leading vertical tab or a
  folded continuation line is `400`.
- **`Host`.** Required in HTTP/1.1; a duplicate (in either version), an empty
  value, a path, userinfo, a port past 65535 or a malformed IPv6 literal is
  `400`.
- **Body framing.** `Content-Length` of decimal digits frames the body; a
  sign, a letter, an empty value or a trailing control character is `400`,
  and a value past `max_body_bytes` (or past 64 bits) is `413`. Repeated
  `Content-Length` headers that agree are accepted as one, as RFC 9112 §6.3
  permits and the parser does now; disagreeing ones are `400`.
  `Transfer-Encoding` alone is `501`; beside `Content-Length` it is `400`. A
  request with neither has an empty body. A body shorter than its length when
  the connection ends is `400`.
- **New: what follows a response.** Every refusal above closes the connection
  after its answer. When a handler returns without reading the whole body, the
  server reads and discards the rest within `max_body_bytes` and the read
  deadline before the next request; if it cannot, the connection closes.
- **New: connection tokens.** The request's `Connection` header is a
  comma-separated list of tokens, compared ignoring ASCII case; `close` among
  them closes the connection after the response. An HTTP/1.0 request closes
  after its response whatever it says: HTTP/1.0 keep-alive is not offered.
  Handlers cannot set `Connection`, `Content-Length` or `Transfer-Encoding`
  (`std/http/header.lin` refuses them), so the server alone frames responses.
- **New: pipelining.** Requests are answered in order, one at a time: the
  connection is owned by one serving task at a time, and a buffered next
  request makes the returned reader ready at once.
- **New: response framing.** A response is framed by `Content-Length` when its
  length is known. A streamed response of unknown length is followed by
  closing the connection, as every response is now. Chunked requests and
  responses are a later change.
- **New: limits per request.** Every limit applies to each request of a
  connection afresh. `first_byte_timeout_ms` bounds the wait for a
  connection's first request; `read_timeout_ms` bounds each request from its
  first byte, where it is counted from the accept today; between requests the
  connection is idle and `idle_timeout_ms` bounds it.

**Limits and backpressure.** `Limits.connections` keeps its meaning (serving
ends after that many connections). `Limits` gains `open_connections`, the
most connections held at once, serving and idle together, and
`idle_timeout_ms`, the longest a connection may stay idle between requests.
Each idle reader is registered beside an `after` timer and the dispatcher
keeps both keys: a reader that becomes ready has its timer taken; a timer that
fires has its reader taken by key and closed.

At `open_connections`, when the listener is ready and some connection is idle,
the dispatcher **evicts the idle connection that has been idle longest**: it
takes it by key and closes it, then accepts. Without eviction, idle
keep-alive clients could hold the whole budget while new clients waited in the
backlog with no request in progress. A request that a client sends at the
moment its idle connection is closed is lost to the server, as with any
server's close of an idle keep-alive connection; RFC 9112 §9.3.1 lets a client
retry an idempotent request on a connection closed before any response.
When no connection is idle and the budget is full, the dispatcher withdraws
the listener from its set by its key, so new connections wait in the kernel's
backlog, and registers it again when a connection closes. Ready readers that
find no free serving task wait in a queue bounded by `open_connections`.

`serve` takes `L: net.Acceptor + io.Pollable`. `ScriptedListener` implements
`io.Pollable` by forwarding to the listener it wraps, so the tests that script
accept failures keep working. The policy still bounds the serving tasks and
`.Threads(128)` stays the default; an idle connection holds a registration,
not a task. Under `.Sequential` the dispatcher answers each ready connection
itself: keep-alive is supported, and connections make no concurrent progress,
so one slow request holds up every other.

This replaces the listener's owning task of 0253 §5. Every wait in the server
is a session operation, a wait set or the world, so §5 covers it, and a
connection is owned by exactly one task at a time, moved through sessions,
never handed between workers as a descriptor number. The dispatcher's set
holds the serving tasks' handles, so it carries what their bodies capture (the
`make_handler`, a parent allocator, a client of the shared state) by §4.2's
rule, until serving ends.

### 7. A fiber is a task on a fixed, guard-paged stack

A fiber task's stack is mapped as `runtime/task.c` maps a thread's:
`default_stack_bytes` usable, 64 KiB of guard pages below, committed by touch.
The size is policy and may become configurable per loop; the stack never moves
or grows.

**Switching is not migration.** Phase 4 builds fibers **pinned** to the carrier
that started them: they switch, so thousands of tasks waiting on I/O share a
few threads, and they never move. Migration and stealing are phase 6, after
pinned fibers are measured.

**The migration invariant** (phase 6): *a fiber may migrate only at a
suspension point where no active frame depends on the identity or the
thread-local state of its current carrier.* The runtime tracks it with two
fields per fiber, and a third property belongs to each call, not to the fiber:

- `foreign_depth`, temporary: incremented and decremented by the code the
  compiler generates around every `extern` call and every callback entry
  ([T-ExternCallback]). Above zero, C frames are live below the fiber's
  current frame.
- `thread_affine`, persistent: set by the fiber's first call into a module
  that declares itself thread-affine (§9) and kept until the fiber ends,
  because such a library keeps state on the thread between calls (a lock taken
  in one call and released in another, an error queue read by a later call).
  A call into any other granted module leaves it clear.
- *blocking*, per call: whether the call is offloaded to a pool thread (§9).
  It decides where one call runs and leaves no mark on the fiber.

A fiber is migratable at a park exactly when `foreign_depth` is zero and
`thread_affine` is clear. Independently of migration, a park reached with
`foreign_depth` above zero does not switch even on its own carrier: it blocks
the thread, because the C frames below may hold a lock that the next fiber on
the same carrier would wait for. The runtime calls Linea code only at a task's
entry and its release; no runtime function runs a user hook in the middle of
its work, and one that is added must count as a foreign frame.

**The context switch** saves and restores what each ABI requires: the
callee-saved general registers, `d8` to `d15` on aarch64, the frame pointer,
the stack pointer with its alignment (16 bytes), `fpcr` on aarch64, `mxcsr`
and the x87 control word on x86-64. It never touches `x18`, which macOS
reserves. It keeps the frame-pointer chain intact for unwinders and debuggers,
and it never uses `swapcontext`, which also switches the signal mask with a
system call. Before the hand-written switch, phase 4 lands a C test suite that
runs the same scenarios through `ucontext` as a reference: switching inside
deep recursion, with live floating-point and vector values across a switch, at
every optimisation level, on macOS aarch64, Linux aarch64 and Linux x86-64.
The address and thread sanitizers are told of every switch
(`__sanitizer_start_switch_fiber`, `__tsan_switch_to_fiber`).

**Overflow and the fault record.** Stack probes are unchanged. A carrier keeps
its own alternate signal stack. The record the fault handler finds through the
thread-specific pointer names the guard range of the stack executing at every
instruction where a fault can occur: during a switch it names both the
leaving and the entering stack's ranges, from before the stack pointer moves
until after it has moved, so a fault in either guard during the switch is
reported as an overflow. Tests fault on purpose during a fiber's first frame,
during its teardown, in deep recursion, and immediately after a switch, on
both architectures.

**Signals.** `SIGSEGV` and `SIGBUS` are handled as 0250 §11 says, with the
running fiber's guard range. Sockets are written with `MSG_NOSIGNAL` or
`SO_NOSIGPIPE`, which no switch disturbs; a pipe write blocks `SIGPIPE` on the
carrier, writes, takes a pending one and restores the mask before it can park.
The loop installs no handler and changes no disposition.

**Ownership and `Shareable`** are unchanged. Fibers on different carriers run
in parallel, so a fiber's captures obey [O-Cross] exactly as a thread's, and
no rule relaxes for fibers that share a carrier.

**[T-ThreadStart].** The runtime's fiber start is marked like
`linea_task_start` and may be named only inside `task.Slot.start`, so a fiber
is joined by `close` as a thread is.

### 8. A loop lasts until exit for now, and `Io` names it

`io.Io` is a concrete copyable value, an opaque number the runtime hands out.
It holds no borrow, so it is `Owned` and `Shareable`:

- `io.system()` names the system: a task started on it is a thread of its own,
  and its operations are performed in place. It is stateless and open, as
  `mem.system()` is (0095).
- `io.Loop.open(carriers: n)` makes a loop and answers its `Io`, or why it
  could not (a thread, a mapping or the poller refused). A loop is `n`
  carriers, each with its own poller, deadline heap and run queue, and a pool
  for modules that block (§9). It lasts until the process exits; while it has
  no fiber its threads wait and run nothing.

`Io` is passed where tasks are started, as an allocator is passed where memory
is taken: `task.start(body, on: loop)`, `task.prepare_in(allocator, body,
stack:, on: loop)`, and `http.serve(..., on: loop)`, each defaulting to
`io.system()`, so every existing call keeps its meaning and a server written
for threads serves on fibers by one argument. A handler never names an `Io`.
`task.Policy` still decides how much independent work runs at once; `Io`
decides what a task runs on.

A descriptor does not store an `Io`. How an operation waits is decided by the
task that waits: a thread performs it in place, a fiber arms it on its own
carrier's poller (§8.1). A descriptor's stored `Io` would either repeat that or
contradict it, as when a fiber of one loop reads a connection accepted by a
fiber of another (Open question 1).

**Lifetime and shutdown.** A loop lasts until the process exits. This is
the initial restriction, chosen for the phases of this record, not a property
of loops: a host process that embeds Linea, an isolated test runtime, or a
subsystem retired at run time needs a loop it can end, and §8.2 keeps that as
the direction. A loop that is never closed is the simplest shape that is
sound now. Its carriers run only fibers that `Slot.start` started and their
handles join, and a pool thread runs only calls a fiber is parked in, so
nothing on them outlives the lends it reads, which is what [T-ThreadStart]
protects. At exit every task has been joined, since `main` returns only after
its handles are closed, so no operation is pending and the loop's threads are
idle.

**A descriptor moves between tasks or loops only when no registration or
operation of its previous context remains active.** The type system moves the
value; the runtime keeps the rest. An operation is active only while its task
is parked inside it with the descriptor lent, so the value cannot move then.
A wait set disarms a value's registration before the value leaves the set
(§4.2). A one-shot registration that fired and was not rearmed is already
inactive, and its slot's generation discards any event still queued (§2).

| Program | Permitted? | Why |
| --- | --- | --- |
| an `Io` copied into a task body, a struct, a vector or a wait set's message | yes | a number naming a loop that outlives the program's code |
| an `Io` sent over a session or returned from a function | yes | as above; it is `Owned` |
| a connection accepted by a fiber of loop A, sent to a fiber of loop B | yes | it moves with no registration active; B's carrier arms its next operation on its own poller (§8.1) |
| a connection taken out of a wait set and sent to another task | yes | the set disarmed it before it left |
| a connection used by a thread task after a fiber accepted it | yes | the thread performs its operations in place |
| a fiber started on a loop whose body captures a `read` of the parent's value | yes, under [O-Cross] | as for a thread |
| a foreign call in progress while `main` returns | cannot happen | the fiber making it is joined first; if the call never returns, neither does the join (§5, property 3) |
| `loop.close()` | not offered in these phases | §8.2 |

#### 8.2 Closable loops, a future direction

Two shapes of `loop.close()` were weighed for these phases:

- *Static exclusion*: `loop.io()` borrows the loop, so [O-Borrow] refuses
  `close` while anything holds the `Io`. Since descriptors no longer store an
  `Io`, only what is started on the loop would carry the borrow: task handles,
  which already carry their bodies' dependencies through `mem.Carried`. This
  is the shape a scoped or closable loop should take. It is deferred because
  an `Io` that borrows is not `Owned`, so a body that starts more fibers on the
  loop must capture it by `read`, and the `on:` arguments, `http.serve` and
  the generic combinators would each need their contracts written for a
  borrowed capability; that is a change of its own, made when a program needs
  a loop to end.
- *Run-time waiting*: `close` waits for the loop's fibers and registrations to
  end. A task that closes a loop while holding a handle of a fiber on it waits
  on itself, which the language promises cannot happen. Rejected.

#### 8.1 Who owns a poller

Each carrier owns its poller (a kqueue or an epoll descriptor), its deadline
heap and its run queue, and only that carrier's thread changes them. Pinned
fibers make this exact: a fiber's operations are armed by the fiber on its own
carrier, so no other thread registers, rearms or removes them.

- **Wakeups from elsewhere.** A carrier has a user event (`EVFILT_USER`, an
  `eventfd`) and a queue that other threads push to: a fiber on another
  carrier that unparks one of this carrier's fibers, or a thread task's send
  to it. A push posts the event, so a carrier waiting in `kevent` or
  `epoll_wait` wakes.
- **An earlier deadline.** A deadline is inserted by the carrier itself, before
  it next waits, so its next timeout is computed from the new minimum and no
  wakeup is needed. A deadline that another thread needs earlier arrives
  through the queue and its event.
- **Rearming.** Registrations are one-shot; the next attempt that answers
  `EAGAIN` arms again with the next generation.
- **Stale events.** Discarded by generation (§2).
- **Wait sets on a loop.** A set keeps its own kernel queue, which is itself
  pollable; a fiber parked in `next` arms that queue's descriptor on its
  carrier's poller. When migration arrives, a set moves with its fiber and is
  armed on the new carrier, so no registration ever moves between pollers.
- **Shutdown.** None in these phases: a loop lasts until exit (§8.2).

### 9. Foreign calls that block or keep thread state

A granted module may declare two independent properties in its manifest,
beside `"extern"`:

- `"blocking": true`: its calls may wait on the world (a file, a lock, the
  network) for long enough that a carrier must not make them;
- `"thread_affine": true`: it keeps state on the calling thread between calls
  (a lock taken by one call and released by another, a thread-local error
  queue), so every call from one fiber must reach the same thread.

The runtime's own file, `fsync` and name-lookup functions are marked blocking,
and none affine, in `runtime_symbols.zig`, so one added later is covered by the
table. [M-Blocking] refuses either key without `"extern"`. SQLite keeps its
error state per connection rather than per thread, so the guest book's wrapper
declares `"blocking"` alone; a TLS library
with a thread-local error queue declares both.

| Module declares | From a thread | From a fiber |
| --- | --- | --- |
| neither | an ordinary call | on the carrier; it holds the carrier for as long as it runs |
| `blocking` | an ordinary call | on a **temporary lease**: a pool thread taken for this call and returned when it returns |
| `thread_affine` | an ordinary call | on the carrier, and the fiber becomes `thread_affine`, so it never migrates |
| both | an ordinary call | on a **persistent lease**: the fiber's first call takes a pool thread that serves every later call of an affine module from that fiber, until the fiber ends |

So ten thousand fibers that each made one blocking call hold no thread after
their calls return; only fibers of a thread-affine library that also blocks
keep one, which the library's own contract demands.

**The call crosses through a typed trampoline.** For each `extern` signature of
a module that blocks the compiler generates a C-ABI trampoline and a context
record:

```c
struct linea_call { void (*invoke)(void *context); void *context; struct linea_park park; };
```

The context, in the fiber's frame, holds the arguments as the callee takes them
and a slot for its result; `invoke` loads them, calls the callee with the
platform's calling convention, and stores the result. The pool only runs
`invoke(context)`, so floating-point arguments, structures, more than eight
arguments and hidden result pointers are the compiler's ordinary call
lowering. The fiber's frame and every buffer the call was lent stay put while
it is parked, so ownership sees an ordinary call that holds what it lends
until it returns ([0246](0246-a-call-holds-what-it-lends-until-it-runs.md)).

**The pool grows.** It adds a thread whenever a call needs one and none is
idle, and keeps a bounded number idle. With a fixed bound, a fiber reading a
FIFO would hold the only thread while the fiber writing it queued behind, and a
SQLite statement waiting on a lock would hold it while the commit releasing the
lock queued: waits that threads finish and a bounded pool would not. The
threads in use are bounded by the calls in progress plus the persistent
leases.

**When a pool thread cannot be made.** A call whose public contract can say so
answers a recoverable error: the runtime's own blocking functions answer an
`io.IoError` of category `ResourceExhausted` from `fs` and name lookup, as
they answer a refused descriptor. A call into a user module whose `extern`
result has no failure to put it in traps with `linea: the blocking pool could
not start a thread` in the first phase that builds the pool; running it on the
carrier instead could hold up the fiber it waits for. A manifest form that
lets a module say how its calls report this is the later answer (Open
question 6).

What deadlock freedom means here is scoped by §5: the pool adds no edge to the
session graph, and it relies on external progress, that a foreign call
returns. A call that never returns stops its fiber and every join above it.
This is not the worker pool 0253 rejected, which ran a body after the lends it
read had ended: a pool thread runs only a call its fiber is parked in. A call
cannot be cut short at a deadline, since C holds the arguments; a deadline is
checked before the call and after it returns. A program that keeps its
database in an owning task, as 0253 §4 teaches, makes its calls from one task.
CPU work goes through `task.Policy`, not the pool.

The standard streams are not on the pool: `io.print` from a fiber writes
directly, and a write to a full pipe or a stopped terminal holds its carrier
until the reader takes the bytes. A module that blocks without declaring it
holds its carrier for as long as the call takes, which every fiber pinned to
that carrier waits out. The runtime counts carrier stalls, the time a carrier
spends inside a foreign call made on it, and reports them in its diagnostics;
it does not move fibers away (Alternatives, the monitor).

#### 9.1 A callback runs as its caller

When C, during a call made on a pool thread, calls a Linea callback
([T-ExternCallback]), the callback runs in **callback mode**:

- **Task identity.** It runs as the calling fiber, borrowed. The pool thread's
  current-task pointer names the fiber's task for the length of the foreign
  call, so a runtime operation the callback makes (a session operation, a
  `start`, an allocation in the checking archive) is the calling task's.
- **The fiber cannot resume** until the foreign call returns: its scheduling
  state stays Parked (§3), and the only unparker of the call's park is the
  trampoline's return. No code of the fiber runs on two threads at once, since
  the fiber's own frames are suspended below the foreign call and the
  callback's frames run above it on the pool thread.
- **Stack and faults.** The callback runs on the pool thread's own stack,
  which is mapped as a task thread's is, with guard pages and an alternate
  signal stack; while a thread serves a lease the fault record names that
  stack, so an overflow in a callback is reported as on any thread.
- **What it may touch.** What [T-ExternCallback] already allows: the callback
  is a plain function and holds nothing, and it reaches the caller's values
  only through the context the `extern` call lent, which the fiber cannot
  touch while it is parked in the call. It may perform session operations on
  endpoints in that context and start tasks, all as the calling task: the
  edges are the task's own, so §5's argument holds with the callback standing
  for the task. A task it starts is joined before its handle leaves the
  context, as anywhere.
- **Nested waits.** `foreign_depth` is above zero, so a wait in the callback
  never switches: it parks the pool thread on a condition variable, with
  operations performed in place, as on a task's own thread. A blocking call
  made from the callback runs in place on that thread.
- **Contract.** The guarantee covers foreign code that keeps the contract
  [T-ExternCallback] states: a callback with a context is called during the
  call, on the calling thread. A callback without a context, which C may keep
  and call later from a thread of its own, runs on that thread as it does now
  and is never in callback mode.

The same mode applies to a callback during a call on a carrier, with the
carrier in place of the pool thread: the fiber is the running code, so nothing
is borrowed, and `foreign_depth` keeps any wait from switching.

### 10. Timeouts without cancellation

No task is stopped from outside (decision #14). A timeout is stated where a
task waits: a deadline on an operation (§1), `recv_until` on a session, and
`after` in a wait set (§4). A child that may hang guards itself with them, and
a parent that must stop a child sends the protocol's stop branch. A parent can
wait for a child with a timeout (`returned` and `after` in one set); when the
timer fires it still holds the handle, and its `close` still waits. A
timed-out wait hands back what it was given: `TimedRecv.TimedOut` hands back
the endpoint, a timed-out read answers `TimedOut` with the connection still
owned, and a timer in a set leaves the other sources registered.

### 11. What the checker adds, and what is library and runtime only

| Section | Checker | Library and runtime |
| --- | --- | --- |
| §1–§3 operations, parks | nothing | nonblocking sockets, `linea_io_perform` with its state machine, the deadline heap, `linea_park` |
| §4 wait set | nothing new: registration states are implementation heads, a key is an ordinary copyable type, and what a set carries follows `mem.Vec`'s rule | `task.WaitSet`, `task.Registered`, `io.Pollable`, the runtime set and its protocol |
| §5 properties | the semantics document's deadlock clause restated as §5's three properties, with the wait set | — |
| §6 HTTP | nothing | dispatcher, the policy's new rules, `Limits.open_connections` and `idle_timeout_ms`, eviction |
| §7 fibers | [T-ThreadStart] names the fiber start; the extern call and callback lowering maintains `foreign_depth` and, for an affine module, `thread_affine` | switch, carriers, the fiber's scheduling state, fault record, sanitizer hooks |
| §8 loop | nothing new: `Io` is an ordinary copyable type | `io.Io`, `io.Loop`, the `on:` arguments |
| §9 foreign calls | [M-Blocking] for the `blocking` and `thread_affine` keys; trampolines generated for the externs of a module that blocks; the symbol table marks the runtime's blocking functions | the pool, temporary and persistent leases, callback mode |
| §4.4 prerequisite | if the hole exists, the structural predicate that keeps waitable values out of an owner's state and jobs | — |

Each rule lands in `docs/linea-semantics.md` with the phase that builds it,
since the compiler may emit no rule name the document does not define.

### 12. Phases

Each phase is one pull request, or two that land together where it says so.
Each lands green, states which sections it builds, adds its rules to the
semantics document, and updates `docs/learn` in the chapter a reader would look
in. Phase 1 does not wait for the questions later phases raise.

1. **Nonblocking I/O and deadlines** (§1, §2 with the in-place backend).
   `feat(runtime): perform socket operations with deadlines on nonblocking sockets`.
   *Proves* full socket semantics on nonblocking descriptors and deadlines that
   never intentionally wait past their time, with no language change and every
   task still a thread. *Tests:* `net_test.c` and `net_fault_test.c` cases for
   short reads and writes, `EAGAIN`, `EINTR`, `EINPROGRESS` with `SO_ERROR`,
   resets and half-close on both systems; each tie rule of §1 (a read, an
   accept and a connect whose readiness and expiry coincide); a deadline on
   `accept`, `connect`, `read` and `write`; the existing `std.net` and HTTP
   tests unchanged and green. It gives no multi-source waiting and keeps one
   thread per task.
2. **The park protocol and wait sets** (§3 on threads, §4, §5). *Prerequisite:*
   §4.4 settled and, if the hole exists, its fix landed.
   `refactor(runtime): stop a task through one park routine`, then
   `feat(task): wait on several sources through a wait set`. *Proves* the
   registration protocol, the keys and the extended deadlock argument.
   *Tests:* deterministic race tests in C that force each interleaving of
   registration, peer arrival, a body's return, timer expiry, `next`, `take`
   and `close` through injected pauses at each linearization point, checking
   exactly-once ownership and no lost wakeup; `take` racing `next` on a
   signalled endpoint whose sender is waiting (the endpoint returns, the
   sender still waits, a later `recv` completes) and on an expired timer (the
   message returns and is never delivered); a copied key used after its slot is
   reused, and a key of one set used on another, both answering `.None`;
   corpus cases for a reply against a timeout, the first of three children,
   and an endpoint at `Send` refused; the semantics' deadlock clause restated;
   examples of a race against a timeout (JavaScript's `Promise.race`) and of a
   chat room whose room is a dispatcher.
3. **The HTTP dispatcher and keep-alive on threads** (§6).
   `feat(http): keep connections alive through a dispatcher`. *Proves* that a
   bounded number of serving tasks serves many more kept-alive clients safely.
   *Tests:* more idle keep-alive connections than serving tasks, all answered;
   every refusal of the policy closing the connection after its answer, with a
   request-smuggling corpus (disagreeing `Content-Length`,
   `Transfer-Encoding` with `Content-Length`, a folded header); a handler that
   leaves its body unread; pipelined requests answered in order; `Connection:
   close` and HTTP/1.0 closing; the idle timeout; at `open_connections`, the
   longest-idle connection evicted for a new one, and the listener withdrawn
   when nothing is idle. `.Threads(128)` stays the default; the HTTP examples
   and the networking chapter migrate.
4. **Pinned fibers and the minimal `Io` contract** (§3 on fibers, §7 without
   migration, §8 and §8.1). `test(runtime): hold a context switch to the reference switch`,
   then `feat(runtime): run tasks as fibers pinned to carriers` and
   `feat(io): open a loop and start tasks and servers on it`, landing together.
   This phase owns the public execution contract: `io.Io`, `io.Loop.open`, the
   `on:` arguments of `task.start`, `task.prepare_in` and `http.serve`, and
   socket operations armed on the fiber's carrier, so it lands a usable fiber
   runtime and not a private one. *Proves* that a task blocked on I/O holds no
   thread. *Tests:* the switch suite against `ucontext`; the fiber state
   machine under forced interleavings (a completion that lands while the fiber
   is Parking, an unpark from another carrier, a wake from a thread task), each
   checking that the fiber never runs on two carriers and no wake is lost;
   faults during a fiber's start, teardown, deep recursion and right after a
   switch on both architectures; ten thousand connections on a few carriers; the
   soundness matrix's task cells run on fibers; the thread sanitizer lane with
   fiber annotations; a fiber polling a peer on its own carrier with
   `recv_until(0)` lets the peer run, and a hot buffered read does not switch.
   Foreign calls from fibers run on the carrier in this phase.
5. **Foreign calls from fibers** (§9). `feat(ffi): offload blocking calls and keep thread-affine ones on one thread`.
   *Proves* that SQLite and files run from fibers without holding a carrier,
   through typed trampolines, and that a thread-affine library keeps its
   thread. *Tests:* the guest book on a loop with SQLite declared
   `"blocking"`; a FIFO read and write between two fibers; ten thousand fibers
   that each make one blocking call holding no pool thread afterwards; a C
   library that checks its thread identity across calls, declared
   `"thread_affine"`; a callback during a pool call that performs a session
   operation and starts and joins a task (callback mode); a trampoline per
   argument class (floats, a structure, a hidden result pointer, more than
   eight arguments); [M-Blocking]'s refusals; a refused pool thread answering
   `ResourceExhausted` from `fs`.
6. **Migration and scheduling** (§7's invariant), only after phase 4's
   measurements. `feat(runtime): steal runnable fibers between carriers`.
   *Proves* the migration invariant: a fiber with `foreign_depth` above zero
   or `thread_affine` set never moves. A monitor arrives only with a measured
   benefit.
7. **io_uring** on Linux (§1, §2). `feat(runtime): perform operations through io_uring on Linux`.
   *Proves* that a completion backend is a backend. *Tests:* the cancelling
   phase (no completion after `TimedOut` touches the buffer; a read or an
   accept that completes during cancellation answers its result); slot
   generations against events queued across a disarm; an explicit fallback to
   the readiness path or the pool for an operation the kernel does not support,
   chosen by probing the kernel once.

**Measurement plan.** Each phase from 2 measures, against the previous phase
and against thread per connection, with p50, p95 and p99 latency, throughput,
CPU, resident and virtual memory, context switches and wakeups:

- ten thousand idle connections (memory and registration cost);
- ten thousand connections with periodic traffic (wakeups and scheduling);
- mixed CPU and I/O work (fairness and utilisation);
- session-heavy pipelines (rendezvous and switch cost);
- many short calls into a blocking module (pool handoff);
- deadlines under load (timeout latency and tails);
- high connection churn (registration and cleanup);
- many clients on one listener (whether the single dispatcher is a
  serialization point; sharding by carrier or listener only if it is).

Stealing, a monitor, a stack cache and dispatcher sharding are justified by
these numbers or not built.

## Consequences

- A server keeps HTTP connections alive with no change to handlers, refuses
  ambiguous framing, and an idle connection costs a registration.
- A program can race any wait against a timer and wait on several peers
  without new syntax, and nothing registered is lost on the path not taken.
- Session deadlock freedom is kept at every phase. Under fibers the promise
  that no tasks wait on each other forever is conditional on every fiber
  reaching a park point; a fiber that computes without waiting delays the
  fibers on its carrier.
- `Io` adds no type parameter and no field anywhere; a backend is the
  runtime's, and a program cannot write one in Linea.
- A loop cannot be closed in these phases: its threads live until exit, idle
  when unused. A scoped loop is the direction (§8.2).
- A foreign call that blocks in a module not declared blocking holds its
  carrier for as long as it takes.
- The runtime grows a poller per carrier, a wait set, a context switch, a
  scheduler and a pool, each with C tests, and sanitizer integration for
  switches. The switch must be right on three targets.

## Alternatives considered

**`async`/`await`.** Rejected by the colouring constraint: an `async` function
cannot be called where a value is expected, every caller up the stack turns
`async`, and a library is written twice or for one colour. A stackless frame
also makes cancellation a drop at an await point, which is unwinding by another
name and loses the linear values held across it. Zig removed its async
functions for these reasons and replaced the colour with an `Io` value.

**Colourless fibers everywhere, with no `Io` value.** Every task a fiber, one
scheduler for every program. It loses the per-program choice (threads for a
command-line tool, a loop for a server) that decision #2 staged, and makes every
program pay for a scheduler and every C call for the migration bookkeeping.

**Thread per connection, the status quo.** Correct, and competitive on
throughput as *Context* showed. It loses on keep-alive (each idle connection
holds a task against the policy's bound), on waiting on several sources and on
memory.

**An event-loop library** (libuv, libevent, libev). Each brings its own loop
and a callback model: a completion is a call into user code from the loop's
stack, which does not fit a fiber parked in the middle of its own frames.
libuv also runs file operations on a thread pool that nothing joins, which
[T-ThreadStart] and 0253 §3 rule out, and none knows the runtime's guard-paged
stacks, its fault record or its park routine. The runtime is dependency-free C
that `build.zig` compiles, and each backend it needs is a few hundred lines
over system calls; Zig's `std.Io` makes the same choice.

**A readiness interface** (`wait(fd, readable)`, then the caller's own
`read`). Simpler for kqueue and epoll, but io_uring would need the interface
redesigned rather than a backend added, and the rule that bytes are lent until
the backend is done would arrive late.

**`timerfd` on epoll, or `EVFILT_TIMER` on kqueue.** A system call and a
kernel object per arm and per cancel, for deadlines armed and cancelled on
nearly every operation (§1).

**One poller shared by every carrier.** Every registration, rearm and timer
change would take a lock or go through a queue, and an earlier deadline would
have to wake whichever carrier is waiting. A poller per carrier, changed only
by its own thread, needs neither while fibers are pinned (§8.1).

**io_uring first.** Linux only, restricted in some containers, and macOS needs
kqueue anyway. Starting with backends that cover both systems behind a
completion-shaped interface loses nothing.

**A reactor thread feeding sessions.** A hidden runtime thread owning every
descriptor and sending readiness to tasks over channels adds a task the forest
does not show and two switches per readiness. The dispatcher of §6 is this
shape written in Linea over a wait set, so the argument covers it.

**`next` completing the rendezvous** (completion semantics for endpoints).
`next` would answer the received value and the continuation, which for an
`offer` means a branch per label in `M`, and for a protocol carrying an
endpoint, a delegation inside the set. Readiness with a reservation (§4.1)
keeps the protocol's operations where the program writes them.

**An `Io` trait with a backend type per implementation,** as Zig's vtable is,
monomorphised. A type parameter on every descriptor and handler
(`Connection[I]`, `Request[I, A]`), against decision #26, for backends that are
the runtime's.

**A descriptor that stores its `Io`** (decision #26 as written). Stated in §8
and Open question 1.

**A closable loop now**, statically excluded or waiting at run time (§8.2).

**Holding the park lock across the switch** instead of a scheduling state. An
unparker on another carrier would block on a mutex held across a context
switch, and the release after the switch would run on the scheduler's stack
with a lock taken on the fiber's; the states of §3 say the same with no lock
held across a switch.

**Keys that borrow their set.** [O-Borrow] would refuse `next` while any key
lived (§4).

**Keeping the listener's owning task and adding idle connections to its
state.** A serving task's call for the next ready connection would block the
owning task in a wait while another serving task's call to park an idle
connection queued behind it, unwatched. The dispatcher waits on both in one
set.

**A `select` expression or a fixed-arity `wait_any`.** Rejected again for
0250's reasons; the wait set keeps the values that did not fire.

**Cancellation observed at every blocking operation** (Zig's
`error.Canceled`, the linear-types note's proposal). Rejected by decision #14:
the canceller is a token every blocking call must honour.

**A module-wide `"blocking"` flag that also meant thread affinity, with a
lease kept for the fiber's life.** Ten thousand fibers that each made one
blocking call would keep ten thousand threads. Blocking and affinity are
different obligations (§9).

**A fixed-size blocking pool, or one that runs Linea closures.** A fixed size
deadlocks on a FIFO or a lock whose releasing call queues behind its waiting
call (§9). A pool that runs closures lets a job hold an endpoint or a client
and wait on a task while it holds a thread.

**Eight integer arguments per pool call.** Not a C calling convention:
floating-point and vector arguments, structures by value, more than eight
arguments, variadics and hidden result pointers would each need a special
case. A trampoline per signature is the compiler's ordinary call lowering.

**A monitor that moves fibers off a stalled carrier** every 20 µs. Fifty
thousand wakeups a second for a problem that declaring a module as blocking
avoids, on a timer the system may not honour at that resolution, and it
cannot help a carrier held by computation. Deferred to phase 6 and built only
with a measured benefit; carriers' stalls are counted instead.

**Growable or segmented fiber stacks.** Excluded by *Builds on*.

## Open questions

Settled by this record since the second external review (2026-11-07), and no
longer open: key identity (§4), the fiber's scheduling state (§3), blocking
apart from thread affinity (§9), callback mode (§9.1), the cancelling phase
and the slot table (§2), the tie rules (§1), `io.Pollable` (§4), the move rule
(§8), the HTTP policy and its limits (§6), the phase 4 and 5 boundary (§12).
§4.4 is a prerequisite of phase 2 with its verification pending, not a
question. What needs the user:

1. **Whether a descriptor stores its `Io`** (decision #26 as written).
   Recommended: no (§8), which both external reviews accepted. With a poller
   per carrier, the waiting task decides how a wait happens, so a stored `Io`
   would repeat or contradict it.
2. **Fairness under fibers.** Recommended: accept the conditional theorem for
   phases 4 to 6, and build unconditional progress (a scheduler time budget and
   compiler polls on every unboundedly long path, §5) before a fiber loop serves
   by default anywhere.
3. **Closable loops** (§8.2). Recommended: process-lifetime loops for these
   phases; a scoped loop whose `Io` borrows it, carried by task handles, when a
   program needs a loop to end.
4. **Evicting idle connections at the budget** (§6). Recommended: evict the
   longest-idle connection for a new one, as specified; the alternative keeps
   idle clients and refuses new ones until an idle timeout.
5. **Agreeing duplicate `Content-Length`.** The parser accepts them today, as
   RFC 9112 permits. Recommended: keep; refusing them is stricter and also
   permitted.
6. **A refused pool thread for a user module** (§9). Recommended: trap in phase
   5; later, a manifest form saying how a module's calls report it.
7. **`carriers:`.** Recommended: always written, since it is a resource size.
8. **Chunked requests and responses.** Recommended: the next HTTP change
   after phase 3.
9. **Process signals as a wait-set source** (`SIGTERM` for a graceful
   shutdown). It needs the signal blocked process-wide, which 0250 §11 leaves to
   the host. Recommended: later, with its own record.
10. **A simulated `Io` with a virtual clock** for tests. A loop knows when every
    fiber is parked; threads blocked in the kernel do not. Recommended:
    consider after phase 4.
