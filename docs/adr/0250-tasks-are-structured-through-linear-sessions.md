# 250. Tasks are structured through linear sessions

Status: Proposed — 2026-10-26; complemented by
[0253](0253-independent-work-runs-through-an-explicit-executor-policy.md)
(independent work and execution policy). Once built, it would extend
[0099](0099-a-phantom-parameter-carries-its-bound.md) (a type's dependencies
come from its fields, and a `mem.Carried` field carries its argument's),
[0193](0193-a-closure-may-hold-a-place-lent-inout.md) (a lend reaches a value
whose type can hold the writer, a `Carried` field for a closure type included)
and [0221](0221-owned-admits-a-type-that-can-carry-no-borrow.md) (`Carried[H]` is
`Owned` exactly when `H` is).

**What is built.** Stages 0 to 4 of §16 exist: `mem.Carried[H]` (§12), which
every other clause rests on; the `Protocol` trait with its combinators in
`std.session` (§4); the `Shareable` bound with the `@unshareable` leaf policy
on `mem.Arena`, `mem.Handle` and `mem.AllocationLog` (§5); [T-Dual] (§4); the
implementation heads postfix session operations need (§15), recorded in
[0252](0252-a-types-own-implementation-may-write-a-parameter-inside-an-argument.md);
and the smallest runtime. Stage 4 builds `std.task` (`prepare`,
`prepare_in`, `start`, `cancel`, `default_stack_bytes`), the endpoint
`session.Chan` with its postfix operations (§1 to §3), the `Owned` payload
bound, [O-Cross] (§5), the answer to the `mem.ReleaseTag` question (§5), one
thread per task with a rendezvous session and the join of §2 in
`runtime/task.c`, thread-safe runtime archives with the checking allocator
under one lock (§10), stack probes and an alternate signal stack on every
thread (§11), the runtime's C tests, a thread sanitizer lane, soundness
matrix cells for an observation a live task holds, corpus cases that run,
and the guide's concurrency chapter. Stage 6 is built in the form
[0253](0253-independent-work-runs-through-an-explicit-executor-policy.md)
records: [T-ThreadStart] makes `Slot.start` the one start of a thread, so no
task is unjoined; `recv_until` on a session (§7); and shared mutable state in
an owning task, `task.own`, whose clients reach the state through `call`, in
place of a many-to-one mailbox, which is not built (§6). Each remaining clause is
delivered by a stage of §16, and a stage's change states the clauses it
builds. The guide and `std/README.md` describe only what is built.

## Context

A Linea process runs one thread. A server answers one connection at a time
([0154](0154-sockets-and-http-follow-go.md)), and every in-process sharing
across requests (a pool, a cache, a count) is out of reach. The open question
in the index asked how ownership extends across tasks: what a task may be
given, what two tasks may see at once, and what a handler's state is when
several handlers run.

Three facts constrain any answer.

**A data race is undefined behaviour in the backend.** LLVM gives a racing
non-atomic load an undefined value. Linea promises a defined result for every
operation at every optimisation level
([0013](0013-no-undefined-behaviour.md), [0091](0091-the-optimiser-is-given-proofs-not-premises.md)),
so the rules must exclude races statically. A race reported at run time would
already be too late.

**The ownership rules already describe a scoped task.** A closure records its
`read` captures as observations of their owners and its `inout` captures as
exclusive lends ([0193](0193-a-closure-may-hold-a-place-lent-inout.md)).
`carries(body)` moves those facts into any value built from the closure.
[O-Borrow] then refuses a write to an observed owner, and any use of a lent
one, until that value's last use. [O-Escapes] keeps a value holding a lend
inside the function that lends it, and [O-Leak] refuses a linear value that a
path abandons. A linear task handle whose constructor carries the body would
therefore keep every capture reserved until the handle is settled, could not
leave the scope that lent its captures, and would have to be joined on every
path.

**Deadlock freedom has one structural condition.** The session-type calculi
that prove deadlock freedom without priorities (GV and its successors) require
that creating a channel and creating the process at its other end be one
operation, so the graph of processes and channels stays a forest. A primitive
that hands both ends of a new channel to one task, or a join that is not a
session step, lets two tasks each wait on the other.

A check of today's compiler found the encoding of protocols as types sound in
every part but one. A handle written `Chan[phantom P, phantom H]` keeps none
of its body's dependencies. Containment, which decides whether a value can
carry a dependency at all, is computed from fields, and a phantom parameter
has none:

```linea
struct Phantom[phantom F] {
    at: UInt64,
}

fn hold[F: sink fn()](sink body: F) -> Phantom[F] where carries(body) {
    body()
    .{ at = 1 }
}
```

`carries(body)` lands in a value that cannot hold it, so the facts are
dropped, and a write to a place the callback held lent `inout` is accepted
while the `Phantom` is live. With a real `F` field the same write is
[O-Borrow]. A real field costs the body's size and a settlement path, so a
handle cannot hold one.

## Decision

Concurrency is **structured concurrency through linear sessions**. One
operation creates a task and the session between the task and its creator.
The creator's endpoint is the task's handle, and closing it is the join. The
first substrate is one operating-system thread per task. Data races, locks,
atomics and memory orderings do not exist in the language: every accepted
program is data-race-free (§10), and state that must be shared mutably is owned
by one task and reached over a session to it.

The signatures below fix the shape each stage builds. Names and conventions
are decided; the stage that builds an operation may refine a parameter label,
and says so in its own change.

### 1. A task is started in one call, or prepared and then started

Creating a task can fail, since the system may refuse a thread or a stack, and
a failure must destroy nothing a program cannot drop.

```linea
pub fn start[P: Protocol, F: Discardable + sink fn(sink me: Chan[P])](sink body: F) -> Result[Chan[P.Dual, (F, mem.SystemAllocator)], PrepareError] where carries(.Ok: body)
pub fn start_in[P: Protocol, F: Discardable + sink fn(sink me: Chan[P]), A: Allocator](allocator: A, sink body: F, stack: UInt64) -> Result[Chan[P.Dual, (F, A)], PrepareError] where carries(.Ok: body, allocator)

pub fn prepare[P: Protocol, F: sink fn(sink me: Chan[P])](sink body: F) -> Result[Slot[P, F, mem.SystemAllocator], Unstarted[F]] where carries(.Ok: body), carries(.Err: body)
pub fn prepare_in[P: Protocol, F: sink fn(sink me: Chan[P]), A: Allocator](allocator: A, sink body: F, stack: UInt64) -> Result[Slot[P, F, A], Unstarted[F]] where carries(.Ok: body, allocator), carries(.Err: body)

impl[P: Protocol, F: sink fn(sink me: Chan[P]), A: Allocator] Slot[P, F, A] {
    pub fn start(sink self: Self) -> Chan[P.Dual, (F, A)] where carries(self)
    pub fn cancel(sink self: Self) -> F where carries(self.body)
}
```

- `task.start(body)` is the everyday form. It prepares and starts in one call,
  and a failure drops the body and answers the reason. That is safe exactly
  when dropping the body is safe, so the body is bounded `Discardable`: it
  owns nothing linear. A body that does own something linear is refused by
  [T-Bound], whose help names the two-step form.
- `task.prepare(body)` takes the body and performs every fallible step: it
  allocates the body's storage and creates the thread parked on a start
  latch. It answers a linear `Slot` that holds the body, so the slot carries
  every dependency the body captured, and a place the body holds lent
  `inout` is as reserved while the slot lives as while the task runs. A
  failure answers `Unstarted[F]`, which holds the body and the
  `PrepareError`, naming allocation or thread creation, so a body owning a
  linear value is handed back to its owner. `Unstarted` implements `Release`
  and `Settle` ([0184](0184-a-failure-holding-an-owned-value-settles-to-its-reason.md))
  when `F` is Discardable, so `task.prepare(body).settled()?` hands the reason
  on; a body owning something linear is taken back from the failure.
- `slot.start()` is the **commit point**. It moves the body into the task's
  storage, releases the latch and answers the handle. It cannot fail. It is
  written in the library over the runtime's `linea_task_start`: it moves the
  body, and after it the `mem.Buffer[A]` that owns the bytes, into those
  bytes, and hands the runtime two fixed library functions as callbacks
  ([T-ExternCallback]), `run_body[P, F]`, which the task's thread calls with
  its endpoint and the bytes' address, and `mem.release_kept_bytes[F, A]`,
  which `close` calls on the joining thread after the join. Both are generic
  functions the compiler instantiates for the start's `F` and `A`, so no
  primitive the compiler replaces is needed. Before it no child code runs,
  and every way out, a failed `prepare` or a `cancel`, hands the body back.
  After it the task owns the body.
- `slot.cancel()` settles an unused slot: it releases the latch with nothing to
  run, joins the parked thread and answers the body.
- A `Slot` is linear and has one owner, so `start` and `cancel` cannot race,
  and [O-Leak] refuses a slot a path abandons.

The handle is `Chan[P.Dual, (F, A)]`: the task keeps the bytes `prepare_in`
acquired from `allocator` until the join, so the handle keeps whatever the
slot carried from the allocator, such as an observation of an arena, and the
arena cannot be released while the task runs. `body` comes before `stack:`,
since a positional argument cannot follow a named one ([S-Args]). The `_in`
forms take the allocator first and the stack size by name, as every
allocating API does
([0220](0220-a-constructor-or-function-that-allocates-pairs-a-system-form-with-an-in-form.md),
[0191](0191-the-caller-chooses-every-allocator.md)).

### 2. The handle is the creator's endpoint, and `close` is the join

`start` answers `Chan[P.Dual, (F, A)]`, the creator's end of the session whose other
end the body receives as `me`. Its contract `carries(body)` gives the handle
every dependency the body captured: each `read` capture is an observation, each
`inout` capture an exclusive lend. [O-Borrow], [O-Escapes] and [O-Leak] then
give structured concurrency with no scope construct. While the handle lives, an
owner the body reads cannot be written, moved or released, and a place the body
holds lent cannot be touched. The handle cannot leave the function that lent a
capture, and every path must close it.

`close` on `Chan[End, F]` releases the child's captures in four steps, in
this order:

1. the endpoint is at `End`;
2. the body has returned;
3. the runtime join of the thread has completed;
4. only then does [O-Borrow] release the handle's dependencies, because the
   handle's last use is the call to `close`, which returns after step 3.

Without step 2, a child could close its end and keep writing through an
`inout` capture while the parent, released by [O-Borrow], read the place. A


There are no detached tasks: every task is joined by a `close` that cannot be
omitted.

### 3. Endpoints are linear, `recv` cannot fail, and cancellation is a branch

A session endpoint `Chan[P, H]` is a linear value whose type is the protocol
state. Each operation consumes the endpoint and answers it at the next state,
so a stale endpoint is refused twice: by [O-Move], and by its type. [O-Leak]
forces every session to `End`.

```linea
@(opaque, linear)
struct Chan[phantom P: Protocol, H = ()] {
    endpoint: UInt64,
    body: mem.Carried[H],
}
```

`H` is `(F, A)`, the body's type and its allocator's, for a task's handle and `()` for a delegated endpoint.
The `mem.Carried[H]` field is what makes the handle carry the body's
dependencies (§12).

The operations are `send`, `recv`, `choose_left`, `choose_right`, `offer`,
`close` and `enter`, which unfolds a named protocol one step and costs nothing
at run time. `recv` answers the value and the next endpoint, and cannot fail: a
peer that wants to stop says so through a branch the protocol offers, and every
frame returns and settles what it owns. A trap in any task ends the process, as
a trap does today ([0017](0017-failure-is-a-trap-or-a-value.md)).

**Deadlines on a session.** `recv_until(c, deadline)` answers the value and the
next endpoint, or `TimedOut(c)`, handing the endpoint back in the same state.
After a timeout the task still holds the endpoint and its obligation: it waits
again or takes the protocol's cancel branch. No task is killed from outside. A
peer asks it to stop through the protocol, and a child that may hang guards
itself with `recv_until`. `close` still blocks until the child ends.

### 4. Protocols and [T-Dual]

A protocol is a type implementing the trait `Protocol`, named through the
prelude ([0060](0060-a-library-declaration-is-named-through-the-prelude.md)):

```linea
pub trait Protocol {
    type Dual: Protocol
    type Step: Protocol
}
```

The combinators are `Send[T, N]`, `Recv[T, N]`, `Offer[L, R]`, `Choose[L, R]`
and `End`, each its own step, with `Send` and `Recv` dual, `Offer` and `Choose`
dual, and `End` its own dual. A named recursive protocol, such as a `Worker`
whose `Step` offers another job or a final report, is a struct with its own
`impl Protocol` naming its dual.

**[T-Dual]** (typing). Every `impl Protocol for X` must satisfy `X.Dual.Dual = X`
and `X.Dual.Step = X.Step.Dual`, compared one unfolding deep, with named
protocols compared by their declared duals. Names are never unfolded twice, so
the check terminates. An associated type defined by a cycle of projections that
never reaches a constructor, such as `type Dual = Pong.Dual` beside
`type Dual = Ping.Dual`, is refused at the declaration. A violation is
unsound, since the two ends would disagree about a payload's type, so this is
a rule and not a library convention.

**Normalisation.** For every `P: Protocol`, `P.Dual.Dual` normalises to `P`.
[T-Dual] proves the involution at each implementation, which justifies the
equation, and generic combinators need it: a function over `P` that builds the
dual's dual must be able to hand it back as `P`. For the same reason
`P.Dual.Step` normalises to `P.Step.Dual`, which is what lets a generic
forwarding protocol, `Fwd[N]` with `type Dual = Fwd[N.Dual]` and
`type Step = N.Step`, pass [T-Dual] over its parameter.

Two inference changes come with it. A lambda's written parameter types settle
the callee's type parameters through the callable bound before the lambda's
body is checked, so a body written inline in `prepare` fixes `P`. An argument
whose constructor cannot match the parameter's head is [T-Mismatch] before any
[T-Infer], so a send on the wrong protocol state names the state. A protocol
loop is written as recursion; [O-Loop] is unchanged.

### 5. What crosses a task boundary: `Owned` and `Shareable`

**Payloads are `Owned`.** `send` and `recv` bound their payload `T: Owned`
([0221](0221-owned-admits-a-type-that-can-carry-no-borrow.md)). An endpoint after
a `send` holds nothing it did not hold before, a `recv` result carries nothing,
and a send moves the value out of the sender and no more. A protocol sends
`text.String`, not `Str`, which holds a view. Read-only data is shared once, at
`start`, through the body's `read` captures, which the handle carries until
`close`.

**`Shareable`** is a built-in capability bound, computed by typing beside
`Owned` over the same containment table, and never implementable by a program:

```text
shareable = not declared unshareable
            and every owned part shareable
            and every observed referent shareable
```

It follows observed referents because a value holding a `borrow T` lets whoever
observes the value read the referent. The leaf policy `@unshareable` may be
declared only in a module its root's manifest grants `extern`, since only such
a module can write a raw store under a `read`; elsewhere it is [M-Extern]. It
is written as a declaration attribute, in the closed set beside `@linear`,
`@copyable` and `@carrier`:

```linea
@(opaque, unshareable)
struct Arena[H: Allocator] {
    slab: Option[Buffer[H]],
}
```

`@unshareable` excludes `@copyable`. Copies of a value reach what it reaches,
so a copyable type declared `@unshareable` would have its copies share state
that no dependency ties together: a copy moved into a task, held in a record
or erased into a `mem.Closure` would cross with nothing to refuse it. A
copyable type reaches shared state through a borrow of an `@unshareable`
owner instead, as `mem.Handle` borrows its `mem.Arena`: the borrow makes the
handle not `Shareable` and not `Owned`, and every copy carries its
observation, which [O-Cross] refuses wherever the copy is taken.

An attribute, because being unshareable is a fact about a type's representation
that the declaration states, as `@carrier` and `@copyable` are. A trait would
be something an `impl` anywhere could claim, and a marker field would put a
policy inside the braces, which hold the representation and nothing else. The
word is the exact negation of the bound: `@unshareable` types are the ones that
are not `Shareable`.

`mem.Arena` and `mem.Handle` are `@unshareable`: a handle's `acquire` takes it
by `read` and advances the arena's cursor, so two tasks reading one handle
would race on that word. `mem.AllocationLog` is too, since its allocator
writes the log's counts under a `read`. Everything holding one is unshareable structurally,
such as a `Vec[T, mem.Handle]`. `Copyable` is not `Shareable`: a handle is
copyable, and every copy writes the one cursor. `Owned` and `Shareable` are
independent. An arena owns its memory and carries nothing, yet is not
shareable. A `borrow` of a shareable place is shareable and not owned.

An unshareable value still crosses a task boundary whole. A `sink` capture or
a payload moves it, and afterwards one task alone holds and reads it; what
[O-Cross] refuses is observing it from two tasks, a `read` capture of it or a
value carrying an observation of it. The policy therefore does not make a type
task-local or confined to its creator.

**[O-Cross]** (ownership). A value crosses a task boundary as a capture of a
task's body. Every observation a capture carries, a `read` capture's own
included, must observe a `Shareable` place. A value moved in by a `sink`
capture is held to the same rule, observation by observation. A value carrying
an exclusive lend crosses only as the capture of the body that holds the lend.
The report is at the capture and names the part that prevents it, as
[O-Universe] names the part that prevents a copy. A payload crosses under its
`Owned` bound. That bound is the whole of the payload rule, by the
decision below.

**A value that writes storage another value owns observes it.** The library's
internal `mem.ReleaseTag` used to hold its `ReleaseLog`'s address as integers
and write the log's words through it when released. It carried no dependency,
so it was `Owned`, and two tags moved into two tasks would both write the log's
count, a race neither `Shareable` nor `Owned` saw. Stage 4 decides it by the
rule that already makes `mem.Handle` observe its arena and
`mem.RefusingAllocator` observe its `AllocationLog`: a trusted module that
writes, through a raw address, storage another value owns states it with an
observation of that value, and a value whose read writes is `@unshareable`. So
a tag observes its log (`log: borrow ReleaseLog`), and `ReleaseLog` is
`@unshareable`. A tag is then not `Owned`, so it is no payload, and a tag moved
into a task by `sink` carries an observation of an unshareable log, which
[O-Cross] refuses. That refusal is not conservative: even one tag moved into
one task would race with its creator reading the log. The library's HTTP
extractor tests are the one place a log is still written through an address
nothing observes: an extractor sees only its request, so the log's address
reaches it in a header, and a private probe in `std.http` records through
`mem.record_release`. Those tests start no task.

Two other answers lost. Refusing to move an unshareable value across a task
boundary would contradict the rule above that such a value crosses whole, and
would forbid moving an arena into the task that uses it, which is race-free. A
log per task would remove the race between two tags, and leave the race
between a task writing the log and its creator reading it. A new policy for a
value whose release writes shared state would be a second mechanism for what an
observation already says, and would need its own soundness argument.

Two `inout` captures of disjoint record fields, in two bodies, are two exclusive
lends of disjoint places, which the overlap relation of [N-Aliased] and
[O-Lent] already keeps apart.

### 6. Shared state lives in an owning task

Many tasks reaching one mutable value is an **owning task**:
`task.own(state)` starts a task that holds the state, and each other task
reaches it through a copyable `task.Client` that borrows the task's linear
`Owner`. `client.call(job)` runs `job`, a function of `inout state`, on the
owning task, one call at a time, and answers what the job answers; `close`
joins the task and answers the state. The job is `Owned`, so it holds no
client: a call never waits on the task that runs it. The client borrows the
owner, so [O-Borrow] refuses `close` while a client is still used, and every
task holding one is joined first.
[0253](0253-independent-work-runs-through-an-explicit-executor-policy.md) §4
records the decision and how the runtime's call queue keeps the edges of §10.

A many-to-one mailbox, in which a task receives messages from many children
through linear senders, was designed here first and is not built. Its senders
were moved and cloned freely, so a task could hold a sender of the mailbox it
received from, or a child could wait on the task that waited for its sender to
close: two waits §9 must rule out, which no user code can write against an
owning task, since none receives from one. Waiting on several sources at once
remains open.

### 7. Timeouts: `recv_until`

`chan.recv_until(timeout)` waits for the peer's send for at most `timeout`,
and answers the value with the rest of the protocol or the endpoint back
unchanged, so a timeout is one more arm of the `match`. Deadlines never
propagate implicitly. A program states each one where it waits.

### 8. Communication is synchronous rendezvous

A session has one slot. A `send` returns once its peer has taken the value. A
`choose` is a send of a label, and an `offer` is its receive.

### 9. No set of tasks ever waits on each other forever

**The theorem.** Under the scheduling assumption below, no finite set of tasks
stays blocked forever while waiting only on each other.

A task blocked on a socket, a file or a clock waits on the world, and a loop
that never ends is not waiting at all. Neither is a deadlock. A program whose
tasks block on I/O is covered: the theorem says that the tasks never wait on one
another in a cycle, not that the world answers.

**The model.** The state of a program is a set of tasks and a graph `G` whose
nodes are tasks and whose edges are live sessions. A session is an edge between
the two tasks holding its two endpoints. An edge is live until both of its ends
are settled. A task
leaves `G` when its body has returned and it has been joined.

**Blocked and enabled.** A task is *blocked on an edge* when its next operation
there (`send`, `choose`, `recv`, `offer`, or a handle's `close`) has not
completed. `recv_until` also waits on the world, and always completes. Two complementary operations on one edge are
*enabled*: `send` with `recv`, `choose` with `offer`, and a handle's `close`
with a child whose endpoint is at `End` and whose body has returned. A child's
`close` of its own end at `End` does not wait.

**The scheduling assumption.** Every enabled operation eventually completes.
One operating-system thread per task, scheduled by the kernel, gives it.

**Invariant 1: `G` is a forest**, with at most one edge between any two tasks.
It holds initially (one task, no edge), and each step preserves it:

- *`prepare` and `cancel`* add and remove a parked thread that runs no code and
  holds no endpoint, so `G` does not change.
- *`start`* adds a node, the child, and one edge from it to its creator. A new
  leaf joined by one edge closes no cycle. A **nested start** is the same step
  taken by a child.
- *Delegation* moves an endpoint of an edge `(A, X)` to another task `B`, either
  sent over an edge `(A, B)` or captured by a body `start` turns into a child
  `B` of `A`. Removing `(A, X)` splits its tree in two, with `X` on one side and
  `A` on the other, and `B` is on `A`'s side: it is joined to `A` by an edge
  other than `(A, X)`, since `B` is not `X` (the forest holds one edge between
  two tasks, and a new child is neither). Adding `(B, X)` joins two different trees, so `G` stays a
  forest. A task cannot send an endpoint over that endpoint's own session,
  since `send` consumes the endpoint it sends on.
- *Communication* of a payload that holds no endpoint, and *unfolding* a
  recursive protocol with `enter`, change no edge. A payload that holds an
  endpoint is delegation.
- *Close* and a *task ending* remove an edge or an isolated node. Removing an
  edge or a node closes no cycle.

**Lemma 2: a stuck edge has at most one stuck end.** The two ends of a session
have dual types, so at any moment one end's next operation is the complement
of the other's. If both tasks were blocked on the same edge, the two operations
would be complementary, hence enabled, hence would complete. A handle's `close`
waits on a child whose end is at `End`, whose only remaining operation there is
its own `close`, which does not wait, so the child is not blocked on that edge.

**The proof.** Suppose a finite non-empty set `T` of tasks stays blocked
forever, each waiting only on tasks in `T`. Choose `t₀ ∈ T` and an edge `e₀` it
is blocked on. Let `t₁` be the other end of `e₀`. It is in `T`, so
it is blocked forever, and by Lemma 2 on some edge `e₁ ≠ e₀`. Repeating gives
an infinite walk `t₀ e₀ t₁ e₁ t₂ …` that never leaves along the edge it arrived
by. In a forest such a walk never revisits a node, since a revisit would close a
cycle, so it is an infinite path in a finite graph. That is impossible:
followed far enough, the walk reaches a leaf, whose only edge is the one it was
entered by, and a leaf in `T` must be blocked on some other edge. So no such
`T` exists.

**What the theorem does not promise:**

- that a session completes, or that a program terminates;
- external progress: a task waiting on a socket may wait forever;
- lock-freedom, that every pending communication eventually completes;
- any order across the callers of one owning task.

**Owning tasks.** A call to an owning task (§6) is not an edge of `G`, and no
task waits on one forever. A caller waits only while the owning task runs the
calls queued before its own, and each of those completes without waiting on
any task: a job is `Owned`, and the handle of every task that can call the
owning task carries that task's client, a borrow of the owner, so no job holds
one. The owning task's own wait for the next call is enabled by any call, and
by `close`, which its holder may reach only once every task holding a client
has been joined.

Each later record that adds a blocking operation (a lock, a `select`, a channel
not created by `start`) must say what it does to this argument.

### 10. The memory model and the runtime contract

**Every accepted program is data-race-free.** Two tasks' accesses to one
location are all reads, or they are ordered by a happens-before edge. The
edges are:

- **start:** everything the parent did before `start` is visible to the body;
- **rendezvous:** everything a task did before a `send` is visible to its peer
  after the matching `recv`;
- **join:** everything the body did is visible after `close`;
- **call:** everything a caller did before `call` is visible to the job the
  owning task runs for it, and everything the job did is visible to the caller
  after `call` returns.

The ownership rules supply the rest. A `read` capture leaves both sides only
reads until `close`. An `inout` capture leaves the place to the child alone
until the join. A `sink` capture, a payload and a call's job are moved, and an owning task's
state is reached only by its own thread. `Shareable` excludes
the one kind of value whose `read` writes. So every non-shared location is
reached by one task between two edges, and every accepted program is
sequentially consistent at every optimisation level.

**The runtime contract** states these edges, so they are a property of the
contract and not of one C implementation. A channel's mutex guards its slot,
and the slot goes from empty to full to empty. A channel is freed only after
both ends have settled. An owning task's call queue keeps one request slot
under one mutex: a caller fills it and waits until the owner has counted its
request finished, and the owner copies the request out under the same mutex
and marks it finished once the job has run, so a call is a rendezvous in both
directions. Both runtime archives are thread-safe. In the checked
archive every piece of global checking state, its regions and spill table
included, is under its lock. Concurrent stress tests cover allocation and free.

*Built.* `runtime/task.h` states the edges and `runtime/task.c` keeps them:
start is a release of the latch under the session's mutex, which the thread
acquires before it reads the body; a send fills the slot under the mutex and
waits until the receiver's copy has emptied it, counting values so a sender
waits for its own and not merely for an empty slot; the join is
`pthread_join`. The handle's endpoint and the task's differ in their lowest
bit, so one record serves both, and it is freed by the handle's `close`
after the join, the only end that waits.

**A payload moves through bytes.** `send` moves the value into bytes from the
system allocator, the runtime copies them straight into the receiver's
bytes once both ends have met, and the receiver moves the value out, so one
copy crosses between the two tasks and the runtime allocates nothing.
Running out of memory for those bytes is a trap, since neither operation can
fail. Moving the value with no bytes of its own, from the sender's frame into
the receiver's, would need the address of a value in a frame, which the
language deliberately never gives, and a lowering of `send` and `recv` the
compiler would own; the copy through bytes the library already writes costs
an allocation per message and nothing else. This stays the payload path until
a measurement shows the allocation matters.

### 11. Stacks

- **Size.** `task.default_stack_bytes` names the stack size `prepare` uses, and
  `prepare_in(allocator, stack:, body)` takes one explicitly. The stack size is
  an allocation size and is never hidden. It is two mebibytes, by
  measurement: the deepest path through the library, parsing and rendering a
  JSON document nested as deeply as the parser accepts while sorting twenty
  thousand numbers and formatting a float, overflows 64 KiB and fits 96 KiB
  optimised, and overflows 512 KiB and fits 768 KiB at `-O 0`. Two mebibytes
  is more than twice the unoptimised need, and costs address space, not
  memory, until it is touched. Below every task's stack lie 64 KiB of guard
  pages.
- **Overflow.** The compiler emits stack probes for every frame larger than the
  guard page, so no frame jumps the guard. Every thread, `main` included, has
  an alternate signal stack allocated at thread start and freed at join, so a
  guard-page fault on any thread runs the fault handler, which reports the
  overflow and aborts the process, on the path `main`'s overflow takes too
  ([0197](0197-a-checking-runtime-makes-a-use-of-freed-storage-abort.md)).
  *Built:* every generated body carries `"probe-stack"="inline-asm"`, and
  the report is `linea: a stack overflowed`. A thread installs its signal
  stack before it parks, so a failure there is `prepare`'s to report. A
  sanitized runtime leaves faults to the sanitizer's own handler.

### 12. `mem.Carried[H]`: a field that carries without owning

`mem.Carried[H]` is a zero-sized standard-library field type. A value holding
one carries every dependency a value of `H` may carry, read observations and
exclusive `inout` lends alike, without holding or owning an `H`.

```linea
@copyable
pub struct Carried[phantom H] {}
```

**It is one predicate in the containment computation.** Containment answers,
for each type, whether its values may carry a dependency and whether they may
hold a writer through a lend. Both tables are computed from one walk over a
type's parts, and `Carried`'s instance names its argument as a part, as
certified storage names the elements it holds. The two tables therefore read
the same edge:

- **Dependency containment.** `Carried[H]` may carry a dependency exactly when
  `H` may. So a holder carries what `carries(body)` gives it, and `Carried[H]`
  is `Owned` exactly when `H` is. A [T-Bound] refusal of an `Owned` argument
  names the path to the `Carried` field and stops there, since its argument is
  not a part a program selects.
- **Writer containment.** `Carried[H]` may hold a writer exactly when `H` may.
  This table already follows every type argument, phantom ones included, so a
  lend that reaches a holder whose `H` is a closure stays exclusive, and one
  that reaches a holder whose `H` can hold no writer becomes a read observation.

From those two answers, and from nothing else, follow its effects on the
ownership rules:

- **[O-Borrow].** While a value holding `Carried[F]` for a callback `F` that
  held a place lent `inout` is live, any use of that place is refused, read
  included. A place the callback read cannot be written, moved or released, and
  can be read beside the holder.
- **[O-Escapes].** A holder carrying an exclusive lend cannot leave the function
  that lends the place, whatever its constructor's contract says.
- **Last use.** The lend and the observations end at the holder's last use, as
  for any value carrying them. A dependency is held by the parts that can carry
  it, so a read of a sibling field that cannot carry one, such as an integer
  `number` beside the `Carried` field, does not use it; passing, matching or
  settling the whole holder does.
- **Nesting.** A type holding `Carried[F]` at any depth carries it: through
  fields of nested structures, enum payloads, tuples, generic wrappers such as
  `Option[T]` or a user's `Boxed[T]`, and closure captures.

**It is zero-sized.** It has no fields, so it adds no bytes to a layout and
nothing to settle.

**Capabilities.** `Carried[H]` is `Copyable` and `Discardable` whatever `H` is.
It holds no `H`, so a copy duplicates no `H` and a drop leaves none unsettled,
and the holder's own declaration decides what the holder may do. A copy of a
copyable holder carries the same facts, an exclusive lend included, so the lent
place stays reserved until the last copy's last use: the copy can write through
nothing, since it holds no writer. A holder whose `H` keeps running after the
holder is gone must be linear, so that it is settled only once that `H` has
finished; `Chan` is `@(opaque, linear)` for this reason, and its `close` is the
settlement.

**`phantom` keeps its meaning.** A phantom parameter still contributes no field,
no word, no obligation and no dependency. A type that wants its argument's
dependencies says so with a `Carried` field, and the parameter is then named in
a field and is not phantom.

### 13. `split_inout`: two exclusive lends of one vector

`Vec.split_inout` lends the two halves of one vector to a callback:

```linea
pub fn split_inout[F: inout fn(inout left: mem.View[T], inout right: mem.View[T])](inout self: Vec[T, A], at: UInt64, inout body: F)
```

`mem.View[T]` is a trusted writable view, written over raw access as
`mem.Slice` is. `at` lies in `0..=len`; a larger `at` is the same trap as an
index out of range. The two views cover the vector without overlap.

Two exclusive lends of disjoint parts of one owner are represented as two
distinct `inout` parameters of the callback. The vector itself is lent `inout`
to `split_inout` for the whole call. Inside the callback, `left` and `right` are
two places, so two task bodies may capture one each `inout`, and the overlap
relation already keeps the captures apart. No sub-place of the vector is
named. A view is neither copyable nor `Owned`, so it cannot be sent, and it
cannot leave the callback.

### 14. `async_map` is its own record

A lazy, bounded, concurrent stream stage, `items.async_map(max: n, body)`,
runs at most `n` tasks and yields in input order, pulling the next input only
when a slot frees. It belongs in the last stage. Its record settles the `max`
default and `max: 0`, whether an unordered variant exists, how a failed or
cancelled task surfaces (as a protocol branch, §3), and buffering bounded by
`max`.

### 15. Session operations are postfix

Session operations are written postfix: `c.send(v)`, `c.recv()`,
`c.choose_left()`, `c.offer()`, `c.close()`. This needs a type's own
implementation head to fix an argument to a pattern such as `Send[T, N]`, a
shape [0182](0182-a-types-own-implementation-may-fix-its-type-arguments.md)
rejected because nothing needed it. The head rule is: **each declared parameter
of the implementation appears exactly once, at any depth, inside the head's
arguments.** The receiver match stays first-order and one-sided. Each parameter
is read from its one position, and repeated variables are never unified.
Coherence is unaffected, since an inherent member's name is declared once per
constructor across all of a type's own implementations. `close` needs no new
rule: `impl[H] Chan[End, H]` is admitted today, and an inherent `close` lets
[O-Leak]'s help name it.

This lands as its own change, before the first stage that ships session
operations. Its record supersedes the head clause of 0182.

**Built** by
[0252](0252-a-types-own-implementation-may-write-a-parameter-inside-an-argument.md),
which states the head rule, the match and the report for a call on the wrong
state.

### 16. Delivery

Each stage lands as its own change, ends green, and states which clauses of this
record it builds. Every stage's exit includes its `docs/learn` update, taught in
the chapter a reader would look in, with programs that run where the stage can
run them. The guide's concurrency chapter arrives with stage 4, whose programs
run; stages 5 to 7 extend it.

0. **`mem.Carried[H]`** (§12). *Exit:* the type in `std.mem`, its tests, the
   containment predicate, corpus cases for each claim of §12 seen to fail
   without it, soundness-matrix cells for an observation held through a
   `Carried` field, and a green `zig build soundness`. **Built.**
1. **What may be shared** (§4, §5). `Shareable`, the `@unshareable` leaf policy
   on `mem.Arena`, `mem.Handle` and every other library type whose `read`
   writes, and the `Protocol` trait with its combinators. *Exit:* the semantics
   defines the bound and the policy; corpus cases for each refusal and each
   acceptance of the bound, the policy refused outside a module granted
   `extern`, and `impl Shareable` refused; the guide teaches `Shareable`,
   `@unshareable` and the difference between `Owned` and `Shareable`.
   **Built.**
2. **[T-Dual]** (§4), with the normalisation of `P.Dual.Dual`, the refusal of
   cyclic associated types, and the two inference changes. *Exit:* a mismatched
   pair and a cycle are refused at the declaration; a generic combinator relying
   on `P.Dual.Dual = P` checks; a send on the wrong state is [T-Mismatch]; the
   guide teaches [T-Dual] and writing a protocol, as far as a protocol can be
   written without the runtime. **Built.** A definition cycle was already
   [T-Impl] ("defined through itself"), and an argument whose constructor
   cannot match its parameter's was already [T-Mismatch] before [T-Infer];
   this stage adds the corpus cases that hold both to sessions. A type
   parameter whose one callable bound takes the endpoint settles `P` as a
   lambda's written parameter types do.
3. **Postfix session operations** (§15), with their own record. **Built**
   by [0252](0252-a-types-own-implementation-may-write-a-parameter-inside-an-argument.md):
   a type's own implementation writes each parameter once at any depth, a
   receiver selects the block whose head it matches, and a call on a state
   whose head refuses it is [T-UnknownOperation] naming the head. There is no
   `Chan` in `std` until stage 4, so the corpus and the guide write their
   own endpoint type over `std.session`.
4. **The smallest runtime** (§1–§3, §8, §10, §11), built in two changes that
   land together. One child, `prepare`, `start`, `cancel`, a rendezvous
   channel, join on `close` with its four steps, thread-safe archives, the
   checked archive's lock, stack probes and an alternate signal stack per
   thread. *Exit:* runtime tests for forced allocation failure, forced thread
   failure, the body still usable after either, `cancel` settling the parked
   thread, a body that never runs before `start`, and an overflow on a worker
   reported rather than killed; the soundness matrix meets an observation
   held by a live task handle with every owner operation (refused before
   `close`, run clean after it); corpus cases print only after the join, so
   their output does not depend on scheduling; [O-Cross] defined in the
   semantics and checked, with corpus cases for each refusal (a `read`
   capture of an unshareable place, a `sink` capture whose observation
   reaches one, an exclusive lend crossing outside the body that holds it)
   and each acceptance, the share-nothing cases (a parent reading what a live
   task reads, disjoint-field lends) included; the `Owned` bound on the
   payloads of `send` and `recv`, refusing `Str`; the program generator's
   coverage table listing `start`, `send` and `recv` as unreached; soundness
   matrix cells for capture crossings; and an answer to the question below;
   a new guide chapter on concurrency covers `prepare` and `start`,
   sessions, `close` as the join, and what crosses a task boundary, with
   programs that run. The runtime's C tests (`runtime/task_test.c` and
   `runtime/task_fault_test.c`, under `zig build test-native-task`) and a
   thread sanitizer lane, which runs the corpus and every native runtime
   test, move here from stage 5, since the runtime they watch arrives here.
   **Built.** The C tests cover prepare, start and cancel, the rendezvous,
   choose and offer, close joining only after the body returns, many tasks
   at once, concurrent allocation under the checked archive's lock and an
   overflow on a worker and on `main`, and inject failures into the record's
   allocation, each mapping, `pthread_create` and `sigaltstack`. The guide's
   chapter is framed against JavaScript's `async`/`await` and Rust's threads
   and futures, and teaches gathering results (`Promise.all`) and a producer
   and consumer. The thread lane instruments the generated code as well as
   the runtime: the emitter writes `sanitize_thread` on every function a
   sanitized module defines, so a race between two tasks' Linea code that the
   compiler accepted is reported at run time, as a compiler defect.

   *Question for this stage.* The library's internal `mem.ReleaseTag` values
   write one shared release log through raw addresses when they are released. Tags moved into two tasks
   would both write that log on release, a race neither `Shareable` (which
   governs reads) nor an `Owned` payload bound (a tag carries no dependency)
   refuses. **Answered** in §5: a tag observes its log, and the log is
   `@unshareable`.
5. **Runtime stress.** *Exit:* concurrent allocation and free under the
   checked allocator, channel stress, and `prepare` failure under load all pass
   on Linux, and the concurrency chapter says what the runtime guarantees under
   load. The thread sanitizer and the runtime's C tests are stage 4's.
6. **The standard library** (§6, §7, §13): `split_inout` over `mem.View`,
   `recv_until`, the owning task of §6, and concurrent `http.serve`.
   *Built*, in the form
   [0253](0253-independent-work-runs-through-an-explicit-executor-policy.md)
   records: [T-ThreadStart] keeps every thread joined; `task.own` with
   `Owner`, `Client` and `call` over a runtime call queue; `http.serve` and
   `listen_and_serve` concurrent by default on `.Threads(128)`, each serving
   task with a handler of its own built by a factory, the listener in an
   owning task that free tasks take connections from; `listen_and_serve_with`
   keeping the routes' shared state in an owning task; and the HTTP examples
   and the guide migrated with it. *Open:* a race against a timeout beside
   `recv_until`, a chat server whose room is an owning task, and waiting on
   several sources at once, which the unbuilt mailbox was to answer.

7. **`async_map`** (§14). *Exit:* its own record accepted and built, and the
   concurrency chapter extended to it with an example of a
   concurrency-limited map, the shape JavaScript writes with `for await`.

## Consequences

Structured concurrency costs no new ownership rule beyond [O-Cross]. The handle
is a value like any other linear value, and the rules that already keep a
closure's captures reserved keep a task's captures reserved, until `close`.

The guide's worked example sends `text.String`, not `Str`, because a payload
is `Owned`.

A server joins its handlers in completion order and bounds them with `max:`.
State shared by every handler is read-only and `Shareable`; state that changes
across requests belongs to one task, reached over a session.

A body can be written inline in `prepare`: its written parameter type settles
the protocol.

`mem.Carried[H]` is available before anything uses it, and a library author can
use it today for any type that keeps a callback's dependencies without storing
the callback. Changing whether a type holds a `Carried` field changes whether it
is `Owned`, which is a public fact, as for any field (0221).

A copyable holder of an exclusive lend keeps the place reserved through every
copy. That is conservative and never unsound, since no copy holds a writer.

## Alternatives considered

**Processes only: a pre-forked worker pool.** No rule changes, since processes
share nothing. It gives up every in-process sharing the open question listed,
and it does not answer how ownership extends across tasks.

**Scoped tasks with no channels.** A linear handle whose only consumer is
`join`, in the shape of `std::thread::scope`. A result can come back only at the
join, so a pipeline, a pool fed over time or a dispatching server needs channels
anyway. Deadlock is impossible only because nothing blocks but the join, and
that property is lost the day a channel is added without a topology rule.

**Free channels with affine endpoints.** A `session.open()` answering both ends,
endpoints that may be dropped with a `cancel`, and a `recv` that can answer
`Closed`. It is the flexibility most implementations end up with, and it gives
up the theorem immediately: a primitive handing both ends of a new channel to
one task is exactly what lets `let (a, b) = open(); a.recv()` deadlock. A
priority discipline would restore it at the cost of a priority on every
blocking step and priority polymorphism for recursion. Linear endpoints also fit
ADR 0017: a failure is a trap or a value, and the value is the protocol's own
branch.

**Behaviours over shared owners**, scheduled with exclusive access to the
owners they name. Behaviours cannot block, so every wait becomes a continuation,
which is a colouring in disguise, and it is a second ownership model beside the
first.

**Stackful fibers first.** The type rules are the same, but the runtime's I/O
blocks and it has no poller, so a fiber would pin its carrier on every read.
Fibers can come later behind the same API, and only the `stack:` argument
touches it.

**One-phase fork,** `fork(sink body) -> Result[Chan[P.Dual, F], ForkError] where
carries(.Ok: body)`, with `fork_in(allocator, stack:, body)`. A failure after
the body was taken would consume a linear capture with nothing to settle it.
Two phases make every fallible step happen while the caller still owns the body.

**A share-nothing boundary.** Requiring every crossing value to be `Owned` and
forbidding `read` captures would give the same guarantee with no `Shareable`, no
leaf policy and no [O-Cross]. It refuses programs the checker proves safe: a
parent reading an owner that a live task also reads, which is race-free because
neither can write it until `close`, two `inout` lends of disjoint fields, and
`split_inout`. The few types whose shared read is unsafe, `mem.Handle` and the
allocators that write a log under a `read`, are named by the `@unshareable`
policy instead.

**Naming the capability `Syncable`,** after Rust's `Sync`. Capabilities are
named for what they permit, as `Owned` names what a value carries.

**A `@protocol` derive that generates the dual.** A derive would still need the
rule for a hand-written dual, and a generated dual would need a name.

**Copyable `Shareable` senders to a mailbox.** Any holder of a sender handle
could post. It breaks the theorem: a task could hold a sender to its own mailbox
and wait on it, or a parent could wait on its mailbox while every sender's
holder waited on the parent. A sender that is never copied, and a child per
source, keeps the forest.

**A `select` expression over endpoints.** New syntax, and every arm must hand
back every endpoint that did not fire. **A fixed-arity `wait_any(a, b)`**
serves channels only, with one function per arity. Waiting on several sources
is left open (§6).

**Deadline scopes and cancellation tokens that propagate implicitly.** Every
blocking call would have to honour them: hidden control flow, and a colouring by
another name.

**Mailbox children free of dependencies.** Each handler would copy the shared
configuration. **A scoped `task.mailbox(|inout mb| …)`** needs a new rule
restricting what a child may capture to the scope's own captures. One shared
environment fixed at open needs neither.

**A dispatcher that joins handlers in accept order.** It lets a slow early
connection delay joining every later one. The serving tasks of
[0253](0253-independent-work-runs-through-an-explicit-executor-policy.md) each
take the next connection from the listener's owning task when they are free,
and what they share, a cache or a count, lives in an owning task.

**Deferring parallel `inout` over one container** until writable views exist.
The callback form needs only a trusted `mem.View[T]`, which the library can
write today. The form that returns two lends needs a contract that creates an
exclusive lend and disjoint synthetic sub-places in the overlap relation, and is
left open.

**Free session functions,** `session.send(c, v)`, which the language admits
today. The postfix form reads as every other operation on a value does, and the
head rule it needs is small and keeps coherence.

**Making `phantom` follow its argument's dependencies.** It would change what
`phantom` means for every type that uses it, and would add conservative
refusals to types whose phantom parameter only names an element type, such as
`mem.Slice[phantom T]`.

**A `phantom carried H` parameter modifier.** New syntax, and a second meaning
for `phantom`. A library field type is a primitive with containment still
computed from fields.

**A real field of the body's type,** such as `ghost: Option[H]`. It costs the
body's size in every handle and needs a settlement path for a value that is
never present.

**`Carried[H]` copying and discarding as `H` does.** A holder of a closure's
dependencies would become non-copyable whenever the closure is, although it
holds no closure. It owns no `H`, so its capabilities follow what it owns,
which is nothing.

**Contained task failure:** ending only the task that trapped and delivering
the failure at `close`. It is sound only where the task owns nothing with an
external obligation and holds no lend of a survivor's owner. It is deferred; a
record that takes it delivers the failure as a protocol branch at `close`, never
as an exception.

**A slot that holds no body: `prepare(body)` reading it, then
`slot.start(body)` taking it.** A failure then left the body with its owner
without a type to hand it back in, but every program wrote the body twice,
once to fix its type and once to move it, and the slot carried none of the
body's dependencies until the start. Moving the body at `prepare` writes it
once, makes the slot carry its captures, and hands it back in `Unstarted` or
from `cancel`; the one-call `start` covers the bodies that own nothing
linear, so the two-step form serves the bodies whose failure the program
must handle.

**A compiler-owned `task_start`**, replaced in lowering as
`mem.closure_entry` is, with a generated thread entry and a generated
release of the body's bytes. Both are ordinary generic functions the library
can write over the typed storage primitives, and [T-ExternCallback] already
hands C a fixed function's address, so the compiler would have owned two
bodies and a signature check for nothing the library could not say.

**Detached tasks.** Nothing in the library or the examples needs one, and the
bound "the body depends on nothing" is a new kind of bound the contract language
does not have.

## Open questions

- **Two exclusive lends returned from one call** (`split_inout` answering both
  halves). Open; it needs an exclusive-lend-creating contract and disjoint
  synthetic sub-places.
- **Contained task failure.** Deferred, as above.
- **A fiber substrate.** Deferred until the runtime has a poller; the rules do
  not change when it arrives.
- **`async_map`'s contract.** Deferred to its own record (§14).
