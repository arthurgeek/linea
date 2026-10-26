# 250. Tasks are structured through linear sessions

Status: Proposed — 2026-10-26. Once built, it would extend
[0099](0099-a-phantom-parameter-carries-its-bound.md) (a type's dependencies
come from its fields, and a `mem.Carried` field carries its argument's),
[0193](0193-a-closure-may-hold-a-place-lent-inout.md) (a lend reaches a value
whose type can hold the writer, a `Carried` field for a closure type included)
and [0221](0221-owned-admits-a-type-that-can-carry-no-borrow.md) (`Carried[H]` is
`Owned` exactly when `H` is).

**What is built.** Of this record, only `mem.Carried[H]` (§12) exists. It is the
precondition every other clause rests on, and it lands first. Nothing else
described here is available: there is no `std.task`, no `std.session`, no
mailbox, no `Shareable` bound and no runtime thread. Each remaining clause is
delivered by a stage of §16, and a stage's change states the clauses it builds.
The guide and `std/README.md` describe only what is built.

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

### 1. A task is prepared, then started

Creating a task has two phases, so that a failure destroys nothing.

```linea
pub fn prepare[P: Protocol, F: sink fn(sink me: Chan[P])](read body: F) -> Result[Slot[P, F, mem.SystemAllocator], PrepareError]
pub fn prepare_in[P: Protocol, F: sink fn(sink me: Chan[P]), A: Allocator](allocator: A, stack: UInt64, read body: F) -> Result[Slot[P, F, A], PrepareError] where carries(.Ok: allocator)

impl[P: Protocol, F: sink fn(sink me: Chan[P]), A: Allocator] Slot[P, F, A] {
    pub fn start(sink self: Self, sink body: F) -> Chan[P.Dual, F] where carries(body)
    pub fn cancel(sink self: Self)
}
```

- `task.prepare` performs every fallible step. It reads `body` only to fix `F`
  and its layout, allocates the task's record and the body's storage, and
  creates the thread parked on a start latch. It answers a linear `Slot` that
  holds no dependency of the body. A failure answers `PrepareError`, naming
  allocation or thread creation, and the body is untouched.
- `slot.start(body)` is the **commit point**. It moves the body into the
  task's storage, releases the latch and answers the handle. It cannot fail.
  Before it the caller owns everything, and no child code runs. After it the
  task owns the body.
- `slot.cancel()` settles an unused slot: it releases the latch with nothing to
  run and joins the parked thread.
- A `Slot` is linear and has one owner, so `start` and `cancel` cannot race,
  and [O-Leak] refuses a slot a path abandons.

A body capturing a linear value therefore survives a failed `prepare` and is
settled by its owner afterwards. The `_in` form takes the allocator first and
the stack size by name, as every allocating API does
([0220](0220-a-constructor-or-function-that-allocates-pairs-a-system-form-with-an-in-form.md),
[0191](0191-the-caller-chooses-every-allocator.md)).

### 2. The handle is the creator's endpoint, and `close` is the join

`start` answers `Chan[P.Dual, F]`, the creator's end of the session whose other
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
mailbox join (§6) follows the same order.

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

`H` is the body's type for a task's handle and `()` for a delegated endpoint.
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
dual's dual must be able to hand it back as `P`.

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
shareable = not declared unshared
            and every owned part shareable
            and every observed referent shareable
```

It follows observed referents because a value holding a `borrow T` lets whoever
observes the value read the referent. The leaf policy `unshared` may be declared
only in a root whose manifest grants `extern`, since only such a root can write
a raw store under a `read`. `mem.Arena` and `mem.Handle` are `unshared`: a
handle's `acquire` takes it by `read` and advances the arena's cursor, so two
tasks reading one handle would race on that word. Everything holding one is
unshared structurally, such as a `Vec[T, mem.Handle]`. `Owned` and
`Shareable` are independent. An arena owns its memory and carries nothing, yet
is not shareable. A `borrow` of a shareable place is shareable and not owned.

**[O-Cross]** (ownership). A value crosses a task boundary as a capture of a
task's body. Every observation a capture carries, a `read` capture's own
included, must observe a `Shareable` place. A value moved in by a `sink`
capture is held to the same rule, observation by observation. A value carrying
an exclusive lend crosses only as the capture of the body that holds the lend.
The report is at the capture and names the part that prevents it, as
[O-Universe] names the part that prevents a copy. A payload crosses under its
`Owned` bound and needs no rule of its own.

Two `inout` captures of disjoint record fields, in two bodies, are two exclusive
lends of disjoint places, which the overlap relation of [N-Aliased] and
[O-Lent] already keeps apart.

### 6. The mailbox: many children, one receive end

Waiting on several sources is a **mailbox**. A task owns one linear
`Mailbox[M, E]` receive end. `M` is the program's own enum of messages, and
waiting on several sources is a `match` on the message, with no syntax added.
Session channels stay two-party and typed by their protocol; the mailbox is the
many-to-one channel beside them.

```linea
impl[M: Owned, E: Shareable] Mailbox[M, E] {
    pub fn open(read env: E) -> Self where borrows(env)
    pub fn recv(sink self: Self) -> Received[M, E] where carries(self)
    pub fn send_after(inout self: Self, after: time.Duration, sink message: M) -> Timer[M]
}

impl[P: Protocol, F: sink fn(sink me: Chan[P]), A: Allocator] Slot[P, F, A] {
    pub fn start_into[M: Owned, E: Shareable, G: Owned + sink fn(read env: E, sink out: Sender[M])](sink self: Self, inout mailbox: Mailbox[M, E], sink body: G)
}
```

The bounds on `start_into` are the rule; how a slot prepared for a mailbox child
is typed is the mailbox stage's to fix.

- **The shared environment is fixed at open.** A mailbox's type does not
  change as children join, so nothing per child can carry one child's captures.
  `Mailbox.open(read env)` takes one `Shareable` environment and answers a
  mailbox that observes it. The read lasts until the mailbox is settled, which
  happens only by `Closed`, after every child has returned. A child's body is
  `Owned`: it owns its captures, holds no `inout` lend, and receives `env` as a
  `read` parameter.
- **Senders are linear.** A child's one endpoint to the mailbox's owner is a
  stream, `Send[M, …]` repeated, then `End`. A sender is never copied. It moves
  like any endpoint, as a capture or as a delegated payload. Fan-in from a task
  that is not a child is a child forked for it, or a sender moved to it.
- **Receiving.** `recv(sink mb)` waits on any live child and answers
  `Message(m, mb)`, or `Closed` when the mailbox has no live child and no
  pending timer. `Closed` settles the mailbox, so nothing can join it
  afterwards.
- **Joining.** The mailbox joins a child when its stream has ended and its body
  has returned, in the four steps of §2. A child leaves the mailbox only then.
- **Order.** Messages from one child arrive in the order it sent them. There is
  no order across children.
- **Payloads** are `M: Owned`, the bound sessions use.

`http.serve` opens its mailbox over its server state, starts a handler into it
per connection, and joins handlers in the order they complete. Its `max:`
bounds the live children: while the mailbox is full, it accepts nothing. A slow
early connection therefore delays no later one, and the number of open
connections is bounded.

### 7. Timers: `send_after`

`mailbox.send_after(after, message)` posts `message` to the mailbox later, from
a runtime timer that waits on no task, so a timeout is one more arm of the
`match`. A pending timer counts as a live child: `recv` does not answer `Closed`
while one is pending. It answers a linear `Timer[M]`. `timer.cancel()` answers
`Cancelled(message)`, handing back a message that was never sent, or `Fired`
when it was delivered, and either answer settles the handle.

Deadlines never propagate implicitly. A program states each one where it waits,
with `recv_until` on a session or `send_after` on a mailbox.

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
the two tasks holding its two endpoints. A mailbox child's stream is an edge
between the child and the task holding the mailbox. A timer is not a node: it
waits on no task. An edge is live until both of its ends are settled. A task
leaves `G` when its body has returned and it has been joined.

**Blocked and enabled.** A task is *blocked on an edge* when its next operation
there (`send`, `choose`, `recv`, `offer`, or a handle's `close`) has not
completed. A mailbox receive is blocked on every edge of the mailbox's live
children at once. `recv_until` and a receive with a pending timer also wait on
the world, and always complete. Two complementary operations on one edge are
*enabled*: `send` with `recv`, `choose` with `offer`, and a handle's `close`
with a child whose endpoint is at `End` and whose body has returned. A mailbox
receive is enabled when any live child's stream has a pending `send`, or when
the mailbox has no live child and no pending timer, in which case it answers
`Closed`. A child's `close` of its own end at `End` does not wait.

**The scheduling assumption.** Every enabled operation eventually completes.
One operating-system thread per task, scheduled by the kernel, gives it.

**Invariant 1: `G` is a forest**, with at most one edge between any two tasks.
It holds initially (one task, no edge), and each step preserves it:

- *`prepare` and `cancel`* add and remove a parked thread that runs no code and
  holds no endpoint, so `G` does not change.
- *`start`* adds a node, the child, and one edge from it to its creator. A new
  leaf joined by one edge closes no cycle. A **nested start** is the same step
  taken by a child.
- *Mailbox registration* (`start_into`) adds a child and one edge to the task
  holding the mailbox: a new leaf again.
- *Delegation* moves an endpoint of an edge `(A, X)` to another task `B`, either
  sent over an edge `(A, B)` or captured by a body `start` turns into a child
  `B` of `A`. Removing `(A, X)` splits its tree in two, with `X` on one side and
  `A` on the other, and `B` is on `A`'s side: it is joined to `A` by an edge
  other than `(A, X)`, since `B` is not `X` (the forest holds one edge between
  two tasks, and a new child is neither). Adding `(B, X)` joins two different trees, so `G` stays a
  forest. A task cannot send an endpoint over that endpoint's own session,
  since `send` consumes the endpoint it sends on. Moving a mailbox moves each of
  its children's edges, one at a time, by the same argument.
- *Communication* of a payload that holds no endpoint, and *unfolding* a
  recursive protocol with `enter`, change no edge. A payload that holds an
  endpoint is delegation.
- *Stream end*, *close*, a *mailbox join* and a *task ending* remove an edge or
  an isolated node. Removing an edge or a node closes no cycle.
- *A timer firing* posts a message and changes no edge.

**Lemma 2: a stuck edge has at most one stuck end.** The two ends of a session
have dual types, so at any moment one end's next operation is the complement
of the other's. If both tasks were blocked on the same edge, the two operations
would be complementary, hence enabled, hence would complete. A handle's `close`
waits on a child whose end is at `End`, whose only remaining operation there is
its own `close`, which does not wait, so the child is not blocked on that edge.
A mailbox child's stream only sends and ends; a pending send would make the
receive enabled, so a child of a blocked receive is not blocked on its stream.

**The proof.** Suppose a finite non-empty set `T` of tasks stays blocked
forever, each waiting only on tasks in `T`. Choose `t₀ ∈ T` and an edge `e₀` it
is blocked on; a blocked mailbox receive has at least one live child, since one
with none answers `Closed`. Let `t₁` be the other end of `e₀`. It is in `T`, so
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
- any order across a mailbox's children, or that a child with a pending send is
  served before another child's later send.

Each later record that adds a blocking operation (a lock, a `select`, a channel
not created by `start`) must say what it does to this argument.

### 10. The memory model and the runtime contract

**Every accepted program is data-race-free.** Two tasks' accesses to one
location are all reads, or they are ordered by a happens-before edge. The
edges are:

- **start:** everything the parent did before `start` is visible to the body;
- **rendezvous:** everything a task did before a `send` is visible to its peer
  after the matching `recv`;
- **join:** everything the body did is visible after `close`, or after the
  mailbox join of that child.

The ownership rules supply the rest. A `read` capture leaves both sides only
reads until `close`. An `inout` capture leaves the place to the child alone
until the join. A `sink` capture and a payload are moved. `Shareable` excludes
the one kind of value whose `read` writes. So every non-shared location is
reached by one task between two edges, and every accepted program is
sequentially consistent at every optimisation level.

**The runtime contract** states these edges, so they are a property of the
contract and not of one C implementation. A channel's mutex guards its slot,
and the slot goes from empty to full to empty. A channel is freed only after
both ends have settled. Both runtime archives are thread-safe. In the checked
archive every piece of global checking state, its regions and spill table
included, is under its lock. Concurrent stress tests cover allocation and free.

### 11. Stacks

- **Size.** `task.default_stack_bytes` names the stack size `prepare` uses, and
  `prepare_in(allocator, stack:, body)` takes one explicitly. The stack size is
  an allocation size and is never hidden.
- **Overflow.** The compiler emits stack probes for every frame larger than the
  guard page, so no frame jumps the guard. Every thread, `main` included, has
  an alternate signal stack allocated at thread start and freed at join, so a
  guard-page fault on any thread runs the fault handler, which reports the
  overflow and aborts the process, on the path `main`'s overflow takes too
  ([0197](0197-a-checking-runtime-makes-a-use-of-freed-storage-abort.md)).

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

### 16. Delivery

Each stage lands as its own change, ends green, and states which clauses of this
record it builds.

0. **`mem.Carried[H]`** (§12). *Exit:* the type in `std.mem`, its tests, the
   containment predicate, corpus cases for each claim of §12 seen to fail
   without it, soundness-matrix cells for an observation held through a
   `Carried` field, and a green `zig build soundness`. **This change.**
1. **Ownership across the boundary** (§5). `Shareable`, the `unshared` leaf
   policy on `mem.Arena` and `mem.Handle`, [O-Cross], and the `Owned` payload
   bound. *Exit:* the semantics defines both rules; corpus cases for each
   refusal and each acceptance, the share-nothing cases (a parent reading what
   a live task reads, disjoint-field lends) included; the program generator's
   coverage table lists `start`, `send` and `recv` as unreached.
2. **[T-Dual]** (§4), with the normalisation of `P.Dual.Dual`, the refusal of
   cyclic associated types, and the two inference changes. *Exit:* a mismatched
   pair and a cycle are refused at the declaration; a generic combinator relying
   on `P.Dual.Dual = P` checks; a send on the wrong state is [T-Mismatch].
3. **Postfix session operations** (§15), with their own record.
4. **The smallest runtime** (§1–§3, §8, §10, §11): one child, `prepare`,
   `start`, `cancel`, a rendezvous channel, join on `close` with its four steps,
   thread-safe archives, the checked archive's lock, stack probes and an
   alternate signal stack per thread. *Exit:* runtime tests for forced
   allocation failure, forced thread failure, the body still usable after
   either, `cancel` settling the parked thread, a body that never runs before
   `start`, and an overflow on a worker reported rather than killed; the
   soundness matrix meets an observation held by a live task handle with every
   owner operation (refused before `close`, run clean after it); corpus cases
   print only after the join, so their output does not depend on scheduling.
5. **Runtime stress.** *Exit:* concurrent allocation and free under the
   checked allocator, channel stress, and `prepare` failure under load all pass
   on Linux.
6. **The standard library** (§6, §7, §13): `split_inout` over `mem.View`, the
   mailbox with `send_after` and its timers, `recv_until`, and `http.serve`
   over a mailbox with `max:`. *Exit:* every `pub fn` tested beside its
   definition, a guide chapter whose programs run, and an example that serves
   connections concurrently.
7. **`async_map`** (§14). *Exit:* its own record accepted and built.

## Consequences

Structured concurrency costs no new ownership rule beyond [O-Cross]. The handle
is a value like any other linear value, and the rules that already keep a
closure's captures reserved keep a task's captures reserved, until `close`.

The guide's worked example sends `text.String`, not `Str`, because a payload
is `Owned`.

A server joins its handlers in completion order and bounds them with `max:`.
State shared by every handler is read-only and `Shareable`; state that changes
across requests belongs to one task, reached over a session.

A body cannot be written inline in `prepare` until stage 2's inference change;
until then it is bound with `let` first.

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
`split_inout`. The one type that makes a shared read unsafe, `mem.Handle`, is
named by the `unshared` policy instead.

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
serves channels only, with one function per arity. The mailbox does both with a
`match`.

**Deadline scopes and cancellation tokens that propagate implicitly.** Every
blocking call would have to honour them: hidden control flow, and a colouring by
another name.

**Mailbox children free of dependencies.** Each handler would copy the shared
configuration. **A scoped `task.mailbox(|inout mb| …)`** needs a new rule
restricting what a child may capture to the scope's own captures. One shared
environment fixed at open needs neither.

**A dispatcher that joins handlers in accept order**, or **N workers with
per-worker state built by a factory.** Joining in accept order lets a slow early
connection delay joining every later one. Per-worker state partitions what a
cache or a count would share. The mailbox joins in completion order, and its
`max:` bounds what is open.

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

**Detached tasks.** Nothing in the library or the examples needs one, and the
bound "the body depends on nothing" is a new kind of bound the contract language
does not have.

## Open questions

- **The value of `task.default_stack_bytes`.** Open until the runtime stage,
  which measures the library's deepest frames and states the value with its
  reason.
- **Two exclusive lends returned from one call** (`split_inout` answering both
  halves). Open; it needs an exclusive-lend-creating contract and disjoint
  synthetic sub-places.
- **Contained task failure.** Deferred, as above.
- **A fiber substrate.** Deferred until the runtime has a poller; the rules do
  not change when it arrives.
- **`async_map`'s contract.** Deferred to its own record (§14).
