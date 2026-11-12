# 265. Waits go through the runtime's poller, and a loop runs tasks as fibers

Status: Proposed — 2026-11-07. It builds on
[0261](0261-an-owning-task-holds-nothing-that-waits.md). Phases 1 to 7 of §13
state what is built when. Phase 1 is being built: nonblocking sockets with
deadlines, `io.Io`, `io.system()`, `io.current()`, the loop table of §8 and
the simulation of §12 for one task. In it §1's in-place and simulated backends
each have one party, the calling thread, so §2's guarantees hold because the
thread that attempts an operation is the one that answers it, without a state
word. Of §12, printing a failing test's seed is not built yet: a test reads
`sim.fingerprint()` and names its own seed. Phase 2 is built: the park routine
of §3 on threads, which every condition-variable wait of `runtime/task.c` goes
through; the wait set of §4 with its keys and registration protocol; signals
as a source (§4.5); and §5's three properties in the semantics document.
Nothing else is built.
Once built, it would change these sentences of existing records:

- [0154](0154-sockets-and-http-follow-go.md),
  that the request is read into the arena before the handler runs, which §6
  replaces from phase 3 with a body the handler reads as a stream;

- [0250](0250-tasks-are-structured-through-linear-sessions.md) §6, "Waiting on
  several sources at once remains open", which §4 answers;
- 0250 §10, "the join is `pthread_join`", which §3 replaces: a handle's
  `close` parks until the task's thread has marked its body finished under
  the record's lock, which is the edge the close promises, and `pthread_join`
  then only reclaims the thread;
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
  objects like `TcpListener` and `File`", which §8 replaces: the execution
  substrate is a property of the task that performs the I/O, so `Io` is passed
  where tasks start, and a descriptor owns its socket or file and no
  scheduler.

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
| `Io` is a capability passed like an allocator, and a handler never takes an `io` parameter. Replaced in part by §8: `Io` is passed where tasks start; a descriptor does not carry it, has no outstanding operation or registration when its ownership moves, and is not made nonblocking by the task's poller where its kind cannot be polled. | decisions #26 |
| `Allocator`, `Io`, `Policy` and sessions are four orthogonal resource capabilities; the process heap has open stateless naming. | decisions #28; [0095](0095-the-system-allocator-is-named-rather-than-received.md) |
| No task is stopped from outside. A deadline is stated where a task waits; cancellation is a protocol branch; deadline scopes and cancellation tokens that propagate implicitly are rejected. | decisions #3, #14; 0250 §3, §7 and Alternatives |
| No unjoined thread: only `Slot.start` may start Linea code on a thread of its own. | [0253](0253-independent-work-runs-through-an-explicit-executor-policy.md) §3, [T-ThreadStart] |
| No set of tasks waits on each other forever: the task graph is a forest and a blocked task waits on its own edges. Every later blocking operation must say what it does to that argument. Copyable senders to a mailbox broke it. | 0250 §9 and §6; decisions, "External review, and keeping deadlock freedom" |
| An owning task's state and its jobs are `Isolated`: they hold no session endpoint, so a job never waits on a task. | [0261](0261-an-owning-task-holds-nothing-that-waits.md) |
| A linear-sender inbox merging children's streams, with timers as producers that wait on no task, keeps the forest. | decisions #13 (revised), #16 |
| `http.serve` is concurrent by default on `.Threads(128)`, with a handler per serving task. | 0253 §5; `CLAUDE.md` |
| A foreign call is made through a granted module's `extern`; a callback with a context is called during the call, on the calling thread. | [0228](0228-a-granted-module-calls-c.md), [0229](0229-an-application-depends-on-a-library-by-path.md), [T-ExternCallback] |
| Non-blocking I/O, asynchronous I/O, timeouts and cancellation were deferred by the socket and text designs. | `linea-design/specs/2026-09-23-tcp-http-server-design.md` §3, "Out of scope"; `2026-09-08-owned-text-borrows-and-io-design.md`, "Deferred" |
| The poller is the runtime's own C over direct system calls (kqueue, epoll, later io_uring), no event-loop library, shaped around completion; Windows is not a target. | this record |

What is new here: the operation and its state machine (§1, §2), the fiber's
scheduling state (§3), the wait set, its keys and its registration protocol
(§4), operating-system signals as a source (§4.5), the theorem split into three properties (§5), the dispatcher and its
HTTP/1.1 policy (§6), pinned fibers and the migration invariant (§7), the loop
and `Io` (§8), blocking and thread-affine foreign calls and callback mode
(§9), a simulated `Io` (§12), and the phases (§13).

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
| tests run against a real backend, with real time | a simulated `Io` with a virtual clock and network runs tests deterministically from a seed (§12) |

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
fibers, rendezvous, timers nor a scheduler; §13's measurement plan does.

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
  `poll` the one descriptor for what remains of the deadline, rounded down to
  poll's whole milliseconds with the last fraction slept so a wait ends by the
  deadline, never after it; try again.
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
deadline is checked against the monotonic clock on entry, so one already past
answers before anything is consumed, and again whenever an attempt would wait,
and is the timeout of each wait, and completion may be observed later than the deadline
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
| idle | armed | the submitter, after its attempt answered `EAGAIN` | the swap, after the registration and the deadline are published; only the carrier that polls the registration arms it (§8.1), so no event can reach the slot before the swap |
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

The runtime stops a task in one routine and wakes it in one
(`runtime/park.h`):

```c
/* Holding p's lock: wait until unparked or until the monotonic clock reaches
 * deadline_ns (0 for none). Answers 1 once the deadline has passed. */
int linea_park(struct linea_park *p, unsigned long deadline_ns);
/* Holding p's lock: wake every party parked on p. */
void linea_unpark(struct linea_park *p);
```

A park is kept in the record a task waits on and holds the lock that guards
that record: a session's record, a task's start latch, the owning task's call
queue, and the wait set. The parker holds the lock, checks the condition it
waits for, and parks while it does not hold; the party that makes it hold
does so under the same lock and unparks. A park may return without a wake, so
the parker checks again. Session rendezvous, `recv_until`, the owning task's
call queue, a task's start latch and `close`'s join all use it: the join
parks until the task's thread marks its body finished under the record's
lock, which is also the event `returned` (§4) waits for, and only then joins
the thread, which by then has nothing left to run. On a thread a park is a
condition-variable wait under that lock. A timed park may answer 0 at its
deadline and 1 only on a later call, so a parker with a deadline parks again
until its condition holds or the park answers 1.

Two waits on a thread are not parks, because no other party wakes them. The
in-place backend's wait for one descriptor (§1) is `poll`, which the kernel
ends; `linea_io_perform` parks only on a fiber (phase 4). A wait set's `next`
on a thread parks on the set's own park while the set holds only sources the
runtime signals itself (a session's peer, a body's return, a timer), and waits
in the set's own kernel queue (`kevent`, `epoll_wait`) once it holds a
descriptor or a signal, with the nearest deadline as the timeout; the set's
user event then wakes it for the sources the kernel does not see (§4.2,
§4.5). On a fiber a park is the machine below.

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
a value into the set with a function that wraps it into the program's own
type `M` once it is ready, and answers a key:

```linea
enum Waited {
    Answer(session.Chan[Recv[text.String, End], ()]),
    Late,
}

// Ask a peer and give up after `limit`. Whichever comes first is answered; the
// other is taken back by its key, so nothing registered is lost.
fn ask_within(sink peer: session.Chan[Recv[text.String, End], ()], limit: time.Duration) -> Asked {
    var waiting = task.WaitSet[Waited].open()
    let answer = &waiting.received(peer, |sink ready| Waited.Answer(ready))
    let timer = &waiting.after(limit, (), |sink _late| Waited.Late)
    let asked = match &waiting.next() {
        Some(Answer(peer)) => {
            let _unfired = &waiting.take(timer)   // the timer's message, `()`, unfired
            let (text, peer) = peer.recv()
            peer.close()
            Asked.Answered(text)
        },
        Some(Late) => Asked.TimedOut(&waiting.take(answer).unwrap()),  // the endpoint, still at Recv
        None => panic("two sources were registered"),
    }
    waiting.close().finish().unwrap()   // empty: both keys were taken
    asked
}
```

The sources, each a value and a wrap:

- `readable(holder, wrap)`, `writable(holder, wrap)`: a value whose type
  implements `io.Pollable` (a listener, a connection, a buffered reader over
  one), ready when its descriptor is. Watching a descriptor takes the set's
  kernel queue, which the system may refuse to make or extend, so each
  answers `Result[Registered[T], Unregistered[T]]` and a refusal hands the
  value back beside its `io.IoError`;
- `received(chan, wrap)`: an endpoint whose next operation is `recv`, ready
  when the peer's `send` is waiting; `offered(chan, wrap)`: one whose next
  operation is `offer`, ready when the peer's `choose` is. Each parameter's
  type is the endpoint at that state (`Chan[Recv[T, N], H]`,
  `Chan[Offer[L, R], H]`), so an endpoint at `Send`, at `Choose`, at `End` or
  at a named protocol not yet entered is [T-Mismatch]. A named protocol is
  registered after `enter`, since its own type says nothing of its first
  step. Two names are needed because one type's members are unique per name
  whatever their heads, and a trait over both states would let a program's
  own type claim to be one;
- `returned(handle, wrap)`: a task's handle at `End`, `Chan[End, (F, A)]`,
  ready when the body has returned. Only a handle carries `(F, A)`, so a
  task's own end at `End`, whose close never waits, is [T-Mismatch];
- `after(duration, message, wrap)`: a timer, which delivers `wrap(message)`
  once `duration` has passed on the clock of the task's loop. Taking its key
  back answers `message` in its own type. A set's `M` that holds an endpoint
  is linear, and a timer whose message were an `M` could not be dropped once
  taken, so a timer's message is a value of its own, `()` where it carries
  nothing;
- `signal(sig, wrap)` and `signal_with(share, wrap)`: an operating-system
  signal (§4.5).

The wrap is a `fn(sink ready: T) -> M` that is also `Release`: the set keeps
it, erased, until the value is delivered, and releases it when the value is
taken back or closed instead. Its parameter is `sink`, since the wrap moves
the value into the message.

`next` waits until a source is ready, delivers exactly one, the one signalled
earliest, and answers it wrapped. `take(key)` withdraws one registration and answers its value in its
**own type**: taking the answer key gives back the endpoint and taking a
timer's key gives back its message. `take_if_registered(key)` does the same
only while the source has not been signalled, and answers `.None` once it has,
so a program can withdraw a source exactly when it is not ready (§6 evicts idle
connections by it). Before either answers for a timer, a descriptor or a
signal, the set observes what is ready without waiting (the timers past their
deadline, what its kernel queue has to report), so a timer that has expired
or a descriptor the kernel already reports counts as signalled whether or not
`next` has looked. `close` answers a `Vec[M]` of every registration still
held, wrapped, in the order of their slots, for a set whose keys the program
did not keep. An empty set answers `.None` from `next` without waiting.

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
pub enum Readiness[T] { Now, Wait(io.Source[T]) }
pub trait Pollable { fn readiness(self: Self, interest: Interest) -> Readiness[Self] where borrows(self) }
```

`Now` covers what user space already knows: a buffered reader holding bytes, a
value whose next read answers end or an error. `Wait` hands the set an opaque
`io.Source` the runtime makes from a descriptor, which the set arms on
registration, through a duplicate of its own (§4.2), and disarms before the
value leaves the set by delivery, `take` or `close`. A `Source[T]` holds a
`borrow T` of the value it came from, and `readiness` declares
`where borrows(self)`, so a source, though copyable, borrows its value: a
program that keeps one, even inside a value of its own that it registers,
cannot close or move that value while the copy lives ([O-Borrow]), and a set
never watches a descriptor nothing owns. A value that answers another's
readiness, as a buffered reader answers its connection's, answers
`inner.readiness(interest).within(self)`, which borrows the holder and
carries what the inner readiness borrowed. The borrow is the rule that
refuses the program; the compiler needs nothing of its own for it, since a
`borrow` field and a `borrows` clause already mean this. A value with an operation in progress cannot be registered: the
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
| — | registered | `received`, `offered`, `returned`, `readable`, `writable`, `after`, `signal`, `signal_with`: the value's bytes move into the set, then the source's mark is published, then the source is checked once (below) |
| registered | signalled | the source: a peer entering `send` or `choose` (under the session's lock, after filling the slot), a body returning (under the task's lock), a descriptor event of the current generation, a timer's expiry, a signal's count passing the one the registration recorded (§4.5); after the swap the registration is queued on the set under the set's lock and the owner is woken: unparked, or through the set's user event (`EVFILT_USER`, an `eventfd` write) once the set has a kernel queue (§3) |
| signalled | delivered | `next`: it swaps the earliest-signalled registration, then clears the mark and moves the value out wrapped; one `next` delivers one value |
| registered or signalled | withdrawn | `take` or `close`: the swap, then the mark is cleared and the value moved out |
| registered | withdrawn | `take_if_registered`: the swap fails, and answers `.None`, if the source was signalled first |

- **Where the state lives.** The runtime keeps each registration's state
  word, slot and generation (`runtime/waitset.c`); the value stays in bytes
  the `WaitSet` owns, beside the erased wrap, and moves only after the
  runtime's swap has said which call takes it. A session's record holds the
  mark for each of its two ends, under the record's lock.
- **No lost wakeup.** Registration publishes its mark and checks the source
  (the slot full, the body returned) under the session's lock, and a peer
  fills the slot, or a body marks itself returned, and reads the mark under
  the same lock. Either the source sees the mark and swaps, or the
  registration's check sees the source and swaps. A value whose `readiness`
  answers `Now` is signalled as it is registered; a timer and a descriptor
  are the owner's own to observe. The owner then checks the queue of
  signalled registrations and begins to wait under the set's lock, which a
  source takes to queue one, so a wake is never between the two.
- **Who may signal after a withdrawal.** `take` and `close` swap first and
  disarm second: the mark is cleared under the session's lock, the
  registration leaves the router's list under the router's lock, the
  descriptor leaves the kernel queue, the timer leaves the heap. A source
  that had swapped before the withdrawal has queued the registration by the
  time the disarm returns, since it queues under the lock the disarm takes;
  the withdrawal then removes it from the queue. Only after the disarm does
  the slot's generation move on. The locks are taken in one order: a
  session's, then the router's, then a set's.
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
- **Ties.** Inside a simulation, and wherever the set observes without
  waiting, descriptors that are ready are signalled before timers that have
  expired, so of a readiness and an expiry at one instant the readiness is
  delivered first, as §1's tie rules answer a read.
- **Timers.** A timer that expires together with another source is signalled
  like any source; `next` picks one winner by its swap, and the loser stays
  registered or signalled. A timer's message moves out only when it is
  delivered, taken or closed; expiry alone consumes nothing.
- **`returned` and the join.** `returned` reports that the body has returned
  and the child's end is settled. It does not finalize the handle: `close`
  still joins the thread or retires the fiber and then releases the captures,
  the four steps of 0250 §2, but it waits on no task.
- **A set belongs to its loop.** A set is used on the loop it was opened on,
  and an operation on it from another traps, as a set returned from a
  simulation's `run` and closed outside it does. A signal's share belongs to
  the loop it was taken on too: a simulation's share holds none of the
  process's disposition, so registering it in a set of another loop traps
  rather than leave a registration that keeps no handler installed. Inside a simulation a timer runs
  on the virtual clock, a descriptor is the simulation's, and a signal is
  delivered by `world.deliver`; an endpoint or a handle cannot be registered
  there until tasks inside a simulation are fibers (§12), which traps with
  `linea: a simulation runs one task until fibers`.
- **A registration watches a descriptor of its own.** The set duplicates the
  descriptor a value's `Source` names when the value is registered, arms the
  duplicate, and disarms and closes it when the registration leaves. A kernel
  queue keys a watch by descriptor number, and one descriptor can be
  registered more than once: a copied `Source` in two registrations, or a
  connection readable in one and writable in another. On one number `epoll`
  refuses the second (`EEXIST`) where `kqueue` replaces the first, and taking
  either back would remove the other's watch, losing its readiness. Through
  its own duplicate each registration is a watch of its own on both systems.
  The `Source` borrows its value (above), so the descriptor the duplicate was
  made from stays open, and owned, while the registration lives. Each
  registration costs a second descriptor, which phase 3's idle connections
  count against the process's limit; a refused duplicate answers
  `Unregistered`.

A set carries the dependencies of what it holds exactly as a `mem.Vec[M]` of
the same values does, so a set holding a handle whose body read the parent's
values keeps those values reserved until the handle leaves the set and is
closed. A set holding such a value is not `Owned`. `WaitSet[M]` exposes `M` to
no table: its values are held behind erased callables (`mem.Closure`), whose
type says nothing of what they hold. So a set is never `Owned`, `Shareable` or
`Isolated`, whatever `M` is, by the containment tables' existing rule for
`mem.Closure` and for raw storage, with no rule of its own: it cannot be an
owning task's state ([0261](0261-an-owning-task-holds-nothing-that-waits.md)), be captured by a job, or be sent over a
session. Sending would also be unsound: a registration's value need not appear
in `M` (a wrap may close a handle and answer a number), so a set's type alone
cannot say it carries a borrow. A set moves to another task only inside a body
`start` makes a child of, which is delegation.

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
That was not enforced: `task.own` bounded the state by `Owned` and `call` the
job by `Owned + Release`, which a detached endpoint (`Chan[P, ()]`) meets. A
clerk task wrapped its own endpoint in a record whose `Release` sends and then
waits, and called the owner with a job capturing it; the creator's next call
queued behind that release, so neither side could move, and `linea check`
accepted it (`tests/tasks/a_call_cannot_hold_an_endpoint`). Endpoints held in
the state itself, in an `Option`, a record, a `Vec`, a closure or another
owner, were accepted too (`tests/tasks/an_owning_task_holds_nothing_that_waits`).

[0261](0261-an-owning-task-holds-nothing-that-waits.md) closes it with a built-in bound, `Isolated`, decided by a
containment table over the edges `Shareable` follows and seeded by
`session.Chan` through its declaration: `task.own`, `Owner` and `Client` take
`S: Owned + Isolated`, and `call` takes `F: Owned + Isolated + Release`. A wait
set is never `Isolated`, whatever it holds (§4.2), so the rule covers
it with no addition here. Phase 2 begins once 0261 has landed.

#### 4.5 Operating-system signals as a source

**Decision: a signal is a wait-set source, built in phase 2**, so a program
waits on its connections, its timers and a shutdown signal in one `next`;
`http.serve` uses it to shut down gracefully by default from phase 3 (§6.1):

```linea
// `Reading` and `Served` are the dispatcher's types of §6.
enum Woke { Ready(Reading), Done(Served), Stop(io.SignalShare) }

var waiting = task.WaitSet[Woke].open()
let stop = &waiting.signal(.Terminate, |share| Woke.Stop(share))?   // refused when SIGTERM is ignored
```

- **Which signals.** `io.Signal` names `Terminate` (`SIGTERM`), `Interrupt`
  (`SIGINT`), `Hangup` (`SIGHUP`), `User1` and `User2` (`SIGUSR1`,
  `SIGUSR2`). Every other signal is outside the source: `SIGSEGV` and
  `SIGBUS` belong to the runtime's fault handler (0250 §11), `SIGPIPE` to its
  write path (`runtime/pipe_signal.h`), `SIGKILL` and `SIGSTOP` cannot be
  caught, `SIGCHLD` waits for a process record, and the timer signals are not
  offered, since timers are `after`.
- **Delivery.** While at least one share of a signal exists (below), the
  runtime's signal router has a handler installed for it with `SA_SIGINFO`,
  `SA_ONSTACK` and `SA_RESTART`. The handler is async-signal-safe and does
  three things: it increments the signal's 64-bit delivery count with a
  lock-free atomic, writes one byte to the router's wake descriptor (a pipe
  on macOS, an `eventfd` on Linux, both nonblocking, a full pipe being already
  awake), and restores `errno`. Nothing else runs in the handler. Every wait
  set holding a signal registration also watches the wake descriptor; the first
  to see it readable drains it under the router's lock, reads each count, and
  swaps every registration of each signal whose count moved from `registered`
  to `signalled`, posting each set's user event (§4.2). One delivery
  therefore wakes every registration for that signal, in every set, which is
  what shutdown across a dispatcher and its helpers needs.
- **Coalescing.** As POSIX signals do, deliveries coalesce. A registration
  records the signal's count when it is made and is signalled by the first
  count past it, once, however many deliveries arrive before `next` delivers
  it; like a timer it fires once, and a program that wants the next delivery
  registers again, with `signal_with` to keep a delivered share (below). A delivery made before a registration existed does not
  signal it: deliveries are not queued for registrations to come.
- **Masking.** The runtime blocks none of these signals on any thread and
  changes no thread's mask for them. A delivery lands on whichever thread the
  kernel chooses that does not block it (a carrier, a task's thread, a pool
  thread, a host thread), and the handler is the same on every one. Every
  thread the runtime makes has an alternate signal stack, so on those threads
  the handler runs there, beside the fault handler, which it never interrupts
  in a way that matters: it touches only the router's count and descriptor.
  `SA_RESTART` and the runtime's own `EINTR` retries (§1) keep an interrupted
  system call from surfacing.
- **Disposition, and what a registration owns.** A signal registration holds
  a linear `io.SignalShare`: one share of the signal's disposition. The first
  share of a signal saves the action in place and installs the router's
  handler; the saved action is restored only when no share of that signal
  remains. `wrap` receives the share, so a delivered message carries it: the
  share moves into the message, and the handler stays installed until the
  program settles the message's share (`share.settle()`, or its release) or
  registers again with it (`waiting.signal_with(share, wrap)`), which moves the
  same share into a new registration and leaves no window in which the saved
  action is back. A registration taken or closed answers its share undelivered
  (`share.delivered()` tells the two apart). So the saved action returns once
  no registration and no unsettled delivered message remain, and a second
  signal that arrives after that ends the process as it would have without
  Linea, the conventional second signal.
- **An ignored signal cannot be overridden.** Registration is refused with
  `io.SignalError.Ignored` when the saved action is `SIG_IGN`. The launcher
  asked for the signal to be ignored (`nohup` ignores `SIGHUP`, a supervisor
  may ignore `SIGINT`), and a Linea program cannot override that: it learns the
  signal is ignored and carries on without it.
- **A host's handler.** When the saved action is a handler a host installed,
  the router calls it after counting and waking, with the same arguments, so
  an embedding host still sees its signal.
- **The wake descriptor** is made by the first share and never closed, so the
  handler can write it whenever it runs.
- **Carriers** need nothing of their own: on a loop, a fiber parked in `next`
  has its set's kernel queue armed on its carrier's poller, and the wake
  descriptor is in that queue.
- **The deadlock argument.** A signal is the world: a registration waits on no
  task, as a timer does (§5).
- **Simulation.** Inside a simulation (§12) a share installs nothing and the
  router is replaced by `world.deliver(.Terminate)`, which signals every
  registration for the signal made inside that simulation, with no real
  signal, so shutdown is tested deterministically.

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
conditional.

**Decision: conditional progress first; time budgets and yield points before
fibers become the default.** Phase 4 introduces opt-in pinned fibers with
cooperative scheduling. Scheduler progress is conditional on every runnable
fiber eventually reaching a suspension point, and this limitation is stated in
the language's progress guarantees (the semantics document and the guide).
After measuring the cooperative implementation, the runtime gains scheduler
time budgets and the compiler gains yield points. That design must specify
yield points on every potentially unbounded Linea path (loop back-edges,
recursion through function entries), the scheduler's mechanism for requesting
a yield once a fiber's budget expires, how generated code observes the
request, and the explicit exceptions: foreign calls and any other code the
compiler does not instrument. A time budget plus safe points gives bounded
cooperative preemption of instrumented Linea code, not preemption of
arbitrary native code; a fiber looping inside C cannot be stopped by Linea's
polls. Fibers do not become the default substrate anywhere until scheduler
fairness for instrumented Linea code is established and tested, and blocking
foreign code stays under its own contract (§9). Under fibers the promise of
0250 §9 is therefore conditional: **if every fiber reaches a park point within
finite time**.

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
the next request's bytes is ready on registration (its `readiness` is `Now`).  When serving ends, the dispatcher takes
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
  and a value past `max_body_bytes` (or past 64 bits) is `413`.
  `Transfer-Encoding` alone is `501`; beside `Content-Length` it is `400`. A
  request with neither has an empty body. A body shorter than its length when
  the connection ends is `400`.
- **Decision: agreeing `Content-Length` duplicates stay accepted**. Linea accepts several `Content-Length` headers
  when every value is a valid nonnegative decimal integer that does not
  overflow and all of them parse to the same number, as RFC 9112 §6.3 permits
  and the parser's tests already hold. They are normalized to one canonical
  body length before framing, so every component reads one length.
  Disagreeing or malformed values are `400`; an overflowing value is `413`,
  as a length past every body limit; each closes the connection; a request carrying both `Transfer-Encoding` and
  `Content-Length` is `400` and closes. A comma-separated list in one header
  (`Content-Length: 5, 5`) is not a decimal integer to the parser and is
  refused as malformed; this record does not widen the parser to accept it.
  Persistent connections use exactly the framing rules nonpersistent ones do.
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
  closing the connection, as every response is now. **Chunked request bodies
  are the next HTTP change after phase 3**, read through the body reader
  below, and never beside `Content-Length`; chunked responses come with them.
- **New: a request body is read as a stream.** Today the server reads the
  whole body into the request arena before the handler runs, so an upload is
  bounded by memory and `request_arena_bytes` must hold `max_body_bytes`. From
  phase 3 a raw handler receives an explicit `inout RequestBody[P]` beside
  its copyable `Request[P]` metadata. The body exclusively owns its buffered
  input position and is bounded by `Content-Length` and `max_body_bytes`;
  each read waits through
  the loop's poller as any other read does, so a slow upload parks its fiber
  instead of holding a thread. Reading the whole body into the arena stays
  one call for the handlers that want it: `body.materialize(request)` caches
  the remaining bytes and form fields in the request arena and returns an
  immutable request view. Repeated materialization reuses that cache; after
  incremental reads it contains only the unread remainder. Typed endpoints
  materialize once before their extractors (forms, JSON) run, so several
  extractors can read the same view without lending the stream mutably again.
  A response may observe the cached body until it is written. Output uses a
  writer borrowing the connection; only after that writer and the response
  are settled is the input drained or returned to the dispatcher. A body the handler leaves unread is drained, within
  `max_body_bytes` and `read_timeout_ms`, before the connection's next
  request; past either bound the connection is closed after the response,
  since the next request's first byte cannot be found.
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

**Decision: evict the longest-idle connection when a newcomer needs the
room**. The dispatcher keeps watching the
listener's readiness at `open_connections`. When the budget is exhausted and a
new client is waiting, it closes the keep-alive connection that has been idle
longest and accepts the newcomer, so idle clients cannot hold the whole
budget while new ones wait with no request in progress. Only a genuinely idle
connection is evictable: never one being served, and never an idle one already
marked ready, whose registration is signalled by request bytes in the kernel or
in its buffer. The dispatcher withdraws a candidate with
`take_if_registered(key)`, which swaps only `registered` to `withdrawn` and
answers `.None` for a registration already signalled, so the readiness check
and the eviction are one atomic step. If no connection is evictable, the
listener is withdrawn by its key and the dispatcher stops accepting until a
connection closes; the kernel backlog provides the backpressure. Idle timeouts
stay, and reclaim connections when no new client arrives. A request a client
sends in the instant its idle connection is evicted is lost to the server, as
with any server's close of an idle keep-alive connection; RFC 9112 §9.3.1 lets
a client retry an idempotent request on a connection closed before any
response. Ready readers that find no free serving task wait in a queue bounded
by `open_connections`.

`serve`'s listener bound gains `io.Pollable`, to
`L: net.Acceptor + io.Pollable`. `ScriptedListener` implements
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

#### 6.1 A server shuts down gracefully on `SIGTERM` and `SIGINT`

**Decision: graceful shutdown is on by default.** Every server stops
gracefully on `SIGTERM` and `SIGINT` unless told otherwise. `http.serve`,
`serve_in`, `listen_and_serve` and `listen_and_serve_with` take
`shutdown: http.Shutdown = .OnSignals`; `.Manual` leaves both signals alone.

With `.OnSignals`, the dispatcher registers `Terminate` and `Interrupt` in its
own set (§4.5) when serving begins. A registration refused as `Ignored` is
left out: that signal is ignored, and the server serves on without it. When
either signal is delivered, the dispatcher:

1. withdraws the listener by its key and accepts nothing more; connections
   that complete the handshake afterwards wait in the backlog and are reset
   when the listener closes;
2. settles the delivered message's share and withdraws the other signal's
   registration, so the saved actions return at once and a second `SIGTERM`
   or `SIGINT` during the drain ends the process as it would have (§4.5);
3. finishes every request in flight: a serving task answering a request
   completes it, and a reader whose request bytes have already arrived (ready
   in the set or queued for a serving task) is served too; each of these
   responses carries `Connection: close`;
4. closes every idle connection, taking the idle readers out of the set by
   `close`, and closes a reader that turns ready after the signal without
   serving it;
5. takes the end branch on every serving task, joins them, closes the
   listener, and returns.

`serve` then answers `.Ok(())`, as it does when it reaches `Limits.connections`:
a stop the program asked for is not a failure, and a failure found while
draining (a serving task that could not take its buffers, the listener's close)
is answered as it is now. The drain is bounded by what bounds every request:
`read_timeout_ms` and `write_timeout_ms` end a slow client, and a handler that
computes forever holds the drain as it holds any request.

- **A program that registers the signals itself.** Deliveries reach every
  registration (§4.5), so the program's own set wakes as the server's does,
  and the server still drains. A program that wants to decide when the server
  stops passes `.Manual`; `serve` then registers nothing, and the program's
  registrations alone own the dispositions.
- **`.Sequential`.** The dispatcher is the serving thread. A signal is a source
  in the same set; the dispatcher sees it at its next `next`, after it has
  answered the request it is serving, then drains as above. A long request
  delays the reaction by its own length. Its current response is framed
  before the dispatcher observes the signal and may therefore advertise
  persistence; the connection is closed after that response. Ready requests
  served after the signal is observed carry `Connection: close` as above.
- **Embedding.** In a host process the registrations chain to a handler the
  host installed (§4.5); a host that owns its signals passes `.Manual`.
- **Phases.** The signal source is phase 2; `serve`'s use of it is phase 3.

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

**`Shareable` is not thread affinity.** Five properties have five separate
guards, and none implies another:

| Property | What holds it |
| --- | --- |
| One owner at a time | linear and affine types |
| Several tasks reading at once | `Shareable`, and a C handle's `@shareable` (0260) |
| A C object used on the thread that made it | `thread_affine` (§9) and the wrapper's discipline |
| A C object outliving every use | ownership and the wrapper's promise (0260) |
| A wrapper's C calls being correct | the module granted `extern` |

So a `@shareable` handle is never permission to move a thread-affine object
to another carrier, and a handle that is not `Shareable` never pins its fiber:
it may still move to another thread, one owner at a time. Migration (phase 6)
reads `foreign_depth` and `thread_affine` alone.

**[T-ThreadStart].** The runtime's fiber start is marked like
`linea_task_start` and may be named only inside `task.Slot.start`, so a fiber
is joined by `close` as a thread is.

### 8. A loop lasts until exit for now, and `Io` names it

`io.Io` is a concrete copyable value the runtime hands out. It holds no
borrow, so it is `Owned` and `Shareable`. Its representation is a **stable
loop identity**: an index into the runtime's loop table and the slot's
generation, never a pointer, and every use looks the loop up and checks the
generation. A loop's lookup cannot fail while loops last until exit; a
simulation's can from phase 1, since a simulation ends (§12), which is why the
check exists from the first phase. A stale `Io` traps with `linea: an Io names
a loop that has ended` instead of reaching freed carriers, and a scoped loop
(§8.2) can come later without changing the public model.

- `io.system()` names the system: a task started on it is a thread of its own,
  and its operations are performed in place. It is stateless and open, as
  `mem.system()` is (0095).
- `io.Loop.open(carriers: n)` makes a loop and answers its `Io`, or why it
  could not (a thread, a mapping or the poller refused). A loop is `n`
  carriers, each with its own poller, deadline heap and run queue, and a pool
  for modules that block (§9). It lasts until the process exits; while it has
  no fiber its threads wait and run nothing. Each loop keeps its carriers,
  pollers and pool until exit, so a program opens its loops once; opening
  loops repeatedly is a resource leak by design in these phases.
- **`carriers:` is always written** and must be positive; it is a resource
  size and is never derived silently. `env.available_parallelism()` answers
  the processors this process may run on, for a program that wants a count
  from its environment (`io.Loop.open(carriers: env.available_parallelism())`):
  on Linux the CPUs of the process's affinity mask (`sched_getaffinity`),
  lowered to a cgroup's CPU quota where one is set (cgroup v2 `cpu.max`,
  quota divided by period, rounded up), and on macOS the active processor
  count (`hw.activecpu`, since macOS offers no hard affinity). It answers at
  least 1, and it is read when called, not cached, since a container's quota
  can change.

`Io` is passed where tasks are started, as an allocator is passed where memory
is taken: `task.start(body, on: loop)`, `task.prepare_in(allocator, body,
stack:, on: loop)`, and `http.serve(..., on: loop)`. Each defaults to
`io.current()`, the `Io` the starting task runs on: the system for every task
that is a thread, so every existing call keeps its meaning; the loop for a
fiber, so a fiber's children and a server started from a fiber stay on its
loop; the simulation inside `Simulation.run` (§12). A server written for
threads serves on fibers by one argument. A handler never names an `Io`.
`task.Policy` still decides how much independent work runs at once; `Io`
decides what a task runs on.

**Decision: `Io` is passed only where tasks start; a descriptor does not carry
it**. The execution substrate is a property of
the task that performs the I/O, not of the descriptor: a thread performs an
operation in place, a fiber arms it on its own carrier's poller (§8.1). So
ownership and execution stay orthogonal (a `net.Connection` owns a socket,
not a scheduler); a connection accepted on loop A and sent through a session
to a fiber of loop B is simply used by B's poller; no two execution
authorities can disagree about one descriptor; and descriptors gain no field
and no lifetime. `task.Policy` decides concurrency, `Io` the substrate, and
linear ownership access.

- **Invariant.** A descriptor has no outstanding operation and no poller
  registration when its ownership moves to another task: the runtime retires
  every registration of its previous context before the descriptor is used on
  another carrier (the move rule below).
- **Caveat.** A poller chosen by the task does not make every descriptor
  operation nonblocking. A regular file cannot be polled, and foreign
  libraries and other blocking calls still need the blocking pool (§9), or a
  backend that completes them (io_uring, phase 7).

**Decision: process-lifetime loops initially**.
Loops remain alive until process exit in the first implementation. This is an
implementation restriction, not a permanent decision: it avoids new lifetime
rules while the fiber substrate and the poller are established. Scoped,
closable loops are deferred, not rejected (§8.2). Because descriptors do not
carry `Io`, a future scoped loop can put its lifetime dependency on task
handles and other loop-bound resources alone, and the stable loop identities
above keep the runtime from assuming that a loop never ends. Embedding Linea
in a host process and reclaiming a loop's resources are acknowledged
limitations of the initial implementation. A loop that is never closed is the
simplest shape that is sound now. Its carriers run only fibers that `Slot.start` started and their
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

**Decision: when a pool thread cannot be made, phase 5 traps**. The pool reuses idle threads and makes one only when
none is idle, never one per call. A standard-library operation whose
signature can say so answers a recoverable error: the runtime's own blocking
functions answer an `io.IoError` of category `ResourceExhausted` from `fs`
and name lookup, as they answer a refused descriptor. A call into a user
module traps with `linea: the blocking pool could not start a thread`, a
resource-exhaustion report, and only when the runtime cannot obtain a thread
to run it on, never because the foreign function answered an ordinary error.
The call never falls back to running on the carrier, where it could hold up
the fiber it waits for. Recoverable exhaustion is what a production service
wants, and it is a supported future direction: a manifest extension that lets
a user module declare a recoverable pool-acquisition error, delivered through
the wrapper and leaving the C ABI unchanged. It is deferred, not rejected.

What deadlock freedom means here is scoped by §5: the pool adds no edge to the
session graph, and it relies on external progress, that a foreign call
returns. A call that never returns stops its fiber and every join above it.
The pool runs no Linea body of its own. A pool thread runs only `invoke` for a
call whose fiber is parked holding the call's lends, and the callbacks C makes
during that call (§9.1), so it is outside the worker pool 0253 §3 rejected,
which ran a body after the lends it read had ended. Its threads are started by
the runtime's pool, not by a [T-ThreadStart] symbol, because they never run a
body that outlives its caller. A call
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

**Decision: a deadline on connecting and accepting is stated per call.**
`net.connect(address, within_ms: N)` takes a defaulted `within_ms`, and its
default is no deadline: it waits until the kernel answers, as `connect` does
in C, in Zig's standard library and in Rust's `TcpStream::connect`.
`Listener.accept_within(ms)` sits beside `accept()`, which keeps no deadline,
so the `Acceptor` trait and `http.serve` are unchanged. Zero means no bound in
both, as it does for `set_timeouts` and `set_deadline`. Both answer
`TimedOut` once their milliseconds pass, and a connection ready as the time
runs out is answered under §1's tie rules. Two alternatives were weighed:

- *A setter stored on the listener*, `listener.set_accept_timeout(ms)` read by
  every later `accept`, as `set_timeouts` is read by every later read. It
  hides the bound from the call that waits, and a listener lent to a serving
  loop would carry a bound its borrower cannot see. A connection keeps its
  setters because a protocol bounds a session of many reads; an accept is one
  wait, so its bound belongs to the call.
- *A fixed default deadline* on `connect` and `accept`. Every fixed number is
  wrong for some caller, a slow link or a server idle for hours, and a
  default that times out turns a correct program into one that fails under
  load. No deadline is the honest default, as every comparable standard
  library chooses, and a caller that needs one writes it.

### 11. What the checker adds, and what is library and runtime only

| Section | Checker | Library and runtime |
| --- | --- | --- |
| §1–§3 operations, parks | nothing | nonblocking sockets, `linea_io_perform` with its state machine, the deadline heap, `linea_park` |
| §4 wait set | nothing new: the states an endpoint is registered at are the parameter types of `received`, `offered` and `returned`, a key is an ordinary copyable type, what a set carries follows `mem.Vec`'s rule, and the runtime's entries are confined to `std.task` and `std.io` by [T-ExternRuntime]; three rows of the raw-access table under [T-RawAddress]: `task.WaitSet` and `task.Registered` are raw types whose fields only their own members name, `mem.keep_value` and `mem.take_value`, which hand a value back as the type asked for, are called only by a set's members, and `Registered.minted` only by its registrations, so a key names a value of the type it says | `task.WaitSet`, `task.Registered`, `io.Pollable`, the runtime set and its protocol |
| §4.4 prerequisite | none here; 0261's `Isolated` applies, and a set is never `Isolated`, since it holds `mem.Closure` | — |
| §4.5 signals | nothing | `io.Signal`, `io.SignalError`, `io.SignalShare`, `WaitSet.signal` and `signal_with`, the runtime's signal router |
| §5 properties | the semantics document's deadlock clause restated as §5's three properties, with the wait set | — |
| §6 HTTP | nothing | dispatcher, the policy's new rules, `Limits.open_connections` and `idle_timeout_ms`, eviction, `shutdown:` and graceful shutdown |
| §7 fibers | [T-ThreadStart] names the fiber start; the extern call and callback lowering maintains `foreign_depth` and, for an affine module, `thread_affine` | switch, carriers, the fiber's scheduling state, fault record, sanitizer hooks |
| §8 loop | nothing new: `Io` is an ordinary copyable type | `io.Io` as a stable loop identity, `io.current()`, `io.Loop`, the `on:` arguments, `env.available_parallelism()` |
| §9 foreign calls | [M-Blocking] for the `blocking` and `thread_affine` keys; trampolines generated for the externs of a module that blocks; the symbol table marks the runtime's blocking functions | the pool, temporary and persistent leases, callback mode |
| §12 simulation | nothing | `io.Simulation`, the simulated backend, virtual clock and network |

Each rule lands in `docs/linea-semantics.md` with the phase that builds it,
since the compiler may emit no rule name the document does not define.

### 12. A simulated `Io` with a virtual clock

**Decision: a simulated `Io` is designed now and shapes the tests of phases 1
and 2**. A test of a deadline, a timeout or a
wait set should not sleep, and a race between readiness and expiry should be
reproduced exactly, not hoped for.

```linea
test fn a_read_past_its_deadline_times_out() {
    var sim = io.Simulation.open(seed: 7).unwrap()
    let outcome = &sim.run(|inout world| {
        var listener = net.listen(net.loopback(80)).unwrap()
        var client = net.connect(net.loopback(80)).unwrap()
        let Accepted { connection: server, address: _ } = &listener.accept().unwrap()
        var server = server
        &server.set_deadline(time.Instant.now(), within_ms: 200)
        &world.advance(time.Duration.from_milliseconds(199))   // virtual time, no sleep
        ...
    })
    sim.close()
    ...
}
```

- **What it is.** `io.Simulation.open(seed:)` answers a linear simulation:
  a virtual monotonic and wall clock that start at a fixed instant, an
  in-memory network, and a deterministic source of choices seeded by `seed`.
  `&sim.run(body)` runs `body` with the simulation as the `Io` it runs on
  (`io.current()`, §8), and every operation the body makes goes to the
  simulated backend of §1 instead of the system. The body takes the
  simulation's controls as an `inout` parameter (`world`), through which it
  advances the clock and delivers signals, so the body never needs the
  simulation that is running it. `sim.close()` ends it; its
  loop identity is retired, so a stale `Io` naming it traps (§8). The
  simulation is the first `Io` that ends, which is why stable identities are
  in place from phase 1.
- **The clock.** Inside `run`, `time.Instant.now()` and `time.sleep` read and
  advance the virtual clock; a deadline or a timer expires when virtual time
  passes it. Virtual time moves only when the test advances it
  (`world.advance(d)`) or when every task of the simulation is parked and the
  earliest deadline is the next event, which the simulation then jumps to. A
  readiness and an expiry scheduled for the same virtual instant are both
  observed by the claimant, so §1's tie rules are tested as written.
- **The network.** `net.listen` and `net.connect` inside `run` make simulated
  descriptors: entries in the simulation's own table, never real descriptor
  numbers, so no system call is made on one. Each direction of a connection
  delivers bytes after a latency, in chunks, with `EAGAIN`, short reads and
  writes, resets and half-close chosen from the seed within bounds the test
  sets when it opens the simulation (`network:`). The same seed gives the
  same trace, and a failing test prints its seed, as the program generator's
  failures name theirs.
- **Signals.** `world.deliver(signal)` advances the router's count (§4.5)
  with no real signal.
- **Simulated descriptors stay inside.** A simulated descriptor that leaves
  `run` (returned from the body) names nothing outside it: an operation on it
  from any other `Io` traps with `linea: a simulated descriptor was used
  outside its simulation`. Releasing it outside a run takes no effect until
  the simulation's next operation, which closes it in the order the program
  released it; once the simulation is closed, releasing it only forgets its
  table entry.
- **Tasks.** In phases 1 to 3 every task is a thread, and threads scheduled by
  the kernel cannot be made deterministic, so `run` admits one task: a `start`
  inside it traps with `linea: a simulation runs one task until fibers`. A
  wait set inside `run` still waits on any number of simulated sources, so
  phase 2's races between timers, descriptors and signals are deterministic;
  races with a peer task are tested by the C race tests of phase 2 instead.
  From phase 4, tasks started inside `run` are fibers on the simulation's one
  carrier, scheduled in an order drawn from the seed, which makes every
  interleaving of a program's tasks reproducible.
- **What stays real.** Files, foreign calls and the standard streams are
  performed for real and take no virtual time; a test that needs them
  deterministic leaves them out.
- **A real socket inside a simulation traps.** A socket opened before `run`
  and used inside it would wait on the real kernel against a virtual clock: a
  deadline would expire in virtual time while the kernel answered in real
  time, and the trace would depend on the machine. An operation on a real
  socket or listener inside `run` therefore traps with `linea: a real socket
  was used inside a simulation`, the mirror of the trap for a simulated
  descriptor outside. Files stay real, since a file operation does not wait on
  the clock.
- **Where it lives.** The simulated backend is the runtime's (`runtime/sim.c`,
  beside the in-place and poller backends), behind the operation interface of
  §1, so it exercises the same state machine (§2) the real backends do. It
  is available to every program's tests through `std.io`, not only to the
  runtime's own.

### 13. Phases

Each phase is one pull request, or two that land together where it says so.
Each lands green, states which sections it builds, adds its rules to the
semantics document, and updates `docs/learn` in the chapter a reader would look
in. Phase 1 does not wait for the questions later phases raise.

1. **Nonblocking I/O, deadlines and the simulation** (§1, §2 with the
   in-place and simulated backends, §12 for one task).
   `feat(runtime): perform socket operations with deadlines on nonblocking sockets`,
   then `feat(io): run a test against a simulated clock and network`. The
   second introduces `io.Io`, `io.system()`, `io.current()` and the loop table
   with its stable identities (§8), since the simulation is the first `Io`
   besides the system and the first that ends. *Proves* full socket semantics
   on nonblocking descriptors and deadlines that never intentionally wait past
   their time, with no language change and every task still a thread. *Tests:*
   the tie rules and every deadline case run in a simulation, on virtual time,
   with no sleep, and the `std.net` tests that sleep today move to it; the
   same seed reproducing the same trace; a simulated descriptor used outside
   its simulation trapping; and, against the real kernel, `net_test.c` and `net_fault_test.c` cases for
   short reads and writes, `EAGAIN`, `EINTR`, `EINPROGRESS` with `SO_ERROR`,
   resets and half-close on both systems; each tie rule of §1 (a read, an
   accept and a connect whose readiness and expiry coincide); a deadline on
   `accept`, `connect`, `read` and `write`; the existing `std.net` and HTTP
   tests unchanged and green. It gives no multi-source waiting and keeps one
   thread per task.
2. **The park protocol, wait sets and signals** (§3 on threads, §4, §4.5, §5).
   *Prerequisite:* ADR 0261 (`Isolated`) landed.
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
   chat room whose room is a dispatcher. The wait-set races with timers,
   descriptors and signals run in a simulation and are deterministic.
   Signals (§4.5): a `SIGTERM` raised at the process wakes every set holding a
   registration for it; deliveries coalesce; the saved action is restored when
   the last registration leaves, so a second `SIGTERM` ends the process;
   registration under `SIG_IGN` answers `Ignored`; a host handler installed
   before registration is still called; `world.deliver` does the same with no
   real signal; a delivered message whose share is unsettled keeps the handler
   installed, so a second signal is counted, and settling it restores the saved
   action; `signal_with` moves a delivered share into a new registration with
   no window in which a signal would take the saved action.
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
   when nothing is idle. Streamed request bodies: a body larger than
   `request_arena_bytes` streamed through a handler that keeps only a
   running total, with the arena's high-water mark unchanged; a body read
   whole by the extractors as before; a body the handler stops reading
   halfway, drained before the next pipelined request; a body past
   `max_body_bytes` answered 413 whether read or left unread; a client that
   stops sending mid-body ended by `read_timeout_ms`. Graceful shutdown (§6.1), in a child process: a
   `SIGTERM` during an in-flight request completes it with `Connection:
   close`, closes idle connections, refuses new ones and makes `serve` answer
   `.Ok(())`; `SIGINT` does the same; a second `SIGTERM` during the drain ends
   the process; `.Manual` leaves the signals' actions untouched; a program's
   own registration wakes beside the server's; under `SIG_IGN` the server
   serves on; under `.Sequential` the request being served finishes first.
   `.Threads(128)` stays the default; the HTTP examples and the networking
   chapter migrate.
4. **Pinned fibers and the minimal `Io` contract** (§3 on fibers, §7 without
   migration, §8 and §8.1). `test(runtime): hold a context switch to the reference switch`,
   then `feat(runtime): run tasks as fibers pinned to carriers` and
   `feat(io): open a loop and start tasks and servers on it`, landing together.
   This phase owns the public execution contract: `io.Loop.open` with
   `carriers:` and `env.available_parallelism()`, the `on:` arguments of
   `task.start`, `task.prepare_in` and `http.serve`, and socket operations
   armed on the fiber's carrier, so it lands a usable fiber runtime and not a
   private one; tasks inside a simulation become fibers on its one carrier,
   scheduled from the seed. *Proves* that a task blocked on I/O holds no
   thread. *Tests:* the switch suite against `ucontext`; the fiber state
   machine under forced interleavings (a completion that lands while the fiber
   is Parking, an unpark from another carrier, a wake from a thread task), each
   checking that the fiber never runs on two carriers and no wake is lost;
   faults during a fiber's start, teardown, deep recursion and right after a
   switch on both architectures; ten thousand connections on a few carriers; the
   soundness matrix's task cells run on fibers; the thread sanitizer lane with
   fiber annotations; a fiber polling a peer on its own carrier with
   `recv_until(time.Duration.from_milliseconds(0))` lets the peer run, and a hot buffered read does not switch.
   Foreign calls from fibers run on the carrier in this phase.
5. **Foreign calls from fibers** (§9). `feat(ffi): offload blocking calls and keep thread-affine ones on one thread`.
   *Proves* that SQLite and files run from fibers without holding a carrier,
   through typed trampolines, and that a thread-affine library keeps its
   thread. *Tests:* the guest book on a loop with SQLite declared
   `"blocking"`, each serving fiber owning its own connection (ADR 0259): SQLite in multi-thread mode lets a connection's
   calls run on any one thread at a time, and a connection owned by one fiber
   never has two calls running at once;
   a FIFO read and write between two fibers; ten thousand fibers
   that each make one blocking call holding no pool thread afterwards; a C
   library that checks its thread identity across calls, declared
   `"thread_affine"`; a callback during a pool call that performs a session
   operation and starts and joins a task (callback mode); a trampoline per
   argument class (floats, a structure, a hidden result pointer, more than
   eight arguments); [M-Blocking]'s refusals; a refused pool thread answering
   `ResourceExhausted` from `fs`, and trapping with `linea: the blocking pool
   could not start a thread` for a user module, while an ordinary error the
   foreign function answers reaches the caller with no trap.
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

**A descriptor that stores its `Io`** (decision #26 as written). It would
repeat or contradict the waiting task's substrate, give a connection a
scheduler as well as a socket, and need a handoff between substrates when a
thread or another loop's fiber used it (§8).

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

What this record still leaves open:

1. **The yield-point design** (§5): where polls go, how a budget is requested
   and observed, and what they cost. Its own record, after phase 4's
   measurements.
2. **Scoped loops** (§8.2): the contracts of `on:`, `http.serve` and the
   combinators for an `Io` that borrows its loop. Its own record, when a
   program needs a loop to end.
3. **Recoverable pool exhaustion for user modules** (§9): the manifest form
   and how a wrapper delivers the error.
4. **`SIGCHLD` as a source**, with the process record that would own a child.
