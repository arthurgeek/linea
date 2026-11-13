# Tasks and sessions

Until now every program in this guide did one thing at a time. A **task**
lets a program do several: it runs a closure alongside its creator while the
code that started it carries on. Tasks talk to each other through
**sessions**, typed channels whose type says what is sent next and by whom.

If you have written `async`/`await` in JavaScript, or spawned threads and
futures in Rust, much of this will look familiar. This chapter starts from
those, then shows where Linea goes its own way.

## If you know `async` and `await`

Where Linea matches what you know:

- `task.start(body)` starts work that runs alongside yours, as calling an
  `async function` without awaiting it does in JavaScript, or `tokio::spawn`
  and `std::thread::spawn` do in Rust.
- `handle.close()` waits for that work to finish, like `await` on a promise or
  `JoinHandle::join` in Rust. Unlike either, you cannot forget it: a handle
  that is never closed is a compile error.
- A task never outlives the function that started it, like a thread inside
  Rust's `std::thread::scope`.
- A session is a channel, as in Rust's `std::sync::mpsc`, whose type also says
  whose turn it is to send (see
  [A session and its protocol](#a-session-and-its-protocol)).
- A `task.WaitSet` waits for whichever of several things happens first, as
  `Promise.race` does in JavaScript and `select!` does in async Rust (see
  [Waiting on several things at once](#waiting-on-several-things-at-once)).

Where Linea differs:

1. There is no
   [colouring](https://journal.stuffwithstuff.com/2015/02/01/what-color-is-your-function/).
   No function is `async`, nothing is awaited, and any function may block or
   start a task (see [No colouring](#no-colouring)).
2. A task runs on its own operating-system thread by default, or as a fiber
   on an explicitly opened loop. Socket and session waits on a loop let other
   fibers run (see [Threads and fibers](#threads-and-fibers)).
3. Programs have no data races and need no locks. A value two tasks read
   must be
   [`Shareable`](06-borrowing.md#shareable--a-value-many-readers-may-read-at-once),
   and state that changes lives in one task (see
   [No data races and no locks](#no-data-races-and-no-locks)).
4. Tasks waiting on each other can never deadlock, which no mainstream
   `async` runtime promises (see
   [What deadlock freedom promises](#what-deadlock-freedom-promises)).
5. Nothing cancels a task from outside. There is no `AbortController` and no
   dropping a future: a task stops early when its protocol offers it a way
   to, and its creator takes that branch (see
   [Stopping a task early](#stopping-a-task-early)).

The rest of the chapter takes these one at a time.

## Starting a task

From `main`, `task.start(body)` runs `body` on a thread of its own and answers the task's
**handle**. Starting needs a thread and a stack, which the system may refuse,
so it answers a `Result`, and `?` hands a `task.PrepareError` on:

`visits.lin`:

```linea
import std.io
import std.session
import std.task

use session.Chan
use session.End

// Count visits on a task. `task.start` answers the task's handle, or why no
// task could be started, and `?` hands that reason to the caller.
fn count_visits() -> Result[UInt64, task.PrepareError] {
    var visits = UInt64(0)
    // The body is a closure that takes its end of the session as `me`. It
    // holds `visits` lent `inout`, so while the task runs it is the only code
    // that may touch `visits`.
    let body = sink [inout visits] |sink me: Chan[End]| {
        visits += 3
        me.close()
    }
    let handle = task.start(body)?
    // `close` waits for the body to return, then joins the thread.
    handle.close()
    .Ok(visits)
}

fn main() -> Result[UInt8, io.IoError] {
    match count_visits() {
        Ok(visits) => io.println("visits: {visits}")?,
        Err(reason) => io.println("no task: {reason}")?,
    }
    .Ok(0)
}
```

```
visits: 3
```

The body is an ordinary closure with one parameter, `me`, which is the task's
own end of the session. `Chan[End]` says that end has nothing left to do but
`close()`. Here the body holds `visits` lent `inout`, as a closure from
[Borrowing](06-borrowing.md) can, and adds three to it. The later programs in
this chapter write `task.start(body).unwrap()` to stay short, which stops the
program if no thread can be had.

The Rust version spawns a scoped thread and joins it:

```rust
let mut visits = 0;
std::thread::scope(|s| {
    let handle = s.spawn(|| visits += 3);
    handle.join().unwrap();
});
println!("visits: {visits}");
```

`task.default_stack_bytes`, two mebibytes, is the stack a task gets, and
`task.start_in(allocator, body, stack:)` takes another size. A stack costs
address space until the task uses it, not memory. A task whose stack runs
out stops the whole program with `linea: a stack overflowed`, as `main` does.

## `close` is the join

`close()` returns once the body has returned and its thread has been joined.
That is why `count_visits` may answer `visits`: the task is over. It plays
the part of `await` in JavaScript:

```js
const visits = await countVisits(); // waits for the promise
```

JavaScript lets you leave the `await` out, and the promise runs on with
nobody waiting for it. A Linea handle is linear, like the resources in
[Copying, settling and sealing](04-copying-settling-and-sealing.md): every
path must settle it, and the only way to settle it is `close()`. Leaving it
out is refused:

<!-- guide: edit 19-21 let handle = task.start(body)? … handle.close() -->
```linea
    let _handle = task.start(body)?
```

```
error[O-Leak]: `_handle` (a linear `Chan[End, (<closure>, mem.SystemAllocator)]`) is still owned when this path leaves
  --> visits.lin:19:9
   |
19 |     let _handle = task.start(body)?
   |         ^^^^^^^ never settled on the path that reaches the end of this block
21 | }
   | - the block ends here
   |
   = help: settle it first with `_handle.close()`
```

While the handle is open, it carries what the body captured. The body holds
`visits` lent `inout`, so until `close` nobody else may touch `visits`, not
even to read it:

<!-- guide: edit 21 handle.close() -->
```linea
    let _so_far = visits
    handle.close()
```

```
error[O-Borrow]: this operation uses a place lent `inout` to a value that is still used
  --> visits.lin:21:19
   |
15 |     let body = sink [inout visits] |sink me: Chan[End]| {
   |                            ------ lent `inout` here
21 |     let _so_far = visits
   |                   ^^^^^^ this uses the place while it is lent
22 |     handle.close()
   |     ------ a value holding the lend is still used here
   |
   = help: a place lent `inout` is reached only through what holds the lend until that value's last use; use it after that, or through the closure
```

That read could have seen `visits` halfway through the task's write. After
`close` the task is done and `visits` is `count_visits`'s again.

## A body that owns something linear

When `task.start` cannot get a thread, it drops the body and answers the
reason. Dropping is safe only for a body that owns nothing linear, so
`task.start` takes a `Discardable` body. A body that has captured a value
that must be settled is refused, and the help names the form to use:

`one_call_ticket.lin`:

```linea
import std.session
import std.task

use session.Chan
use session.End

@linear
struct Ticket {
    seat: UInt64,
}

fn main() -> UInt8 {
    let ticket = Ticket { seat = 12 }
    let body = sink [sink ticket] |sink me: Chan[End]| {
        let Ticket { seat: _ } = ticket
        me.close()
    }
    task.start(body).unwrap().close()
    0
}
```

```
error[T-Bound]: `F` requires `Discardable`, because a value of it may be dropped without a release, and this closure captures `ticket`, a `Ticket` that must be released
  --> one_call_ticket.lin:18:10
   |
18 |     task.start(body).unwrap().close()
   |          ^^^^^ this body owns a linear value, so a failed start would abandon it; use `task.prepare(body)` and `slot.start()`
```

That form has two steps. `task.prepare(body)` takes the body and does
everything that can fail: it allocates what the task needs and reserves its
execution, so it runs nothing yet. It answers a linear `Slot` holding
the body. On failure it answers `task.Unstarted`, which hands the body back
beside the reason, so nothing the body owns is lost. `slot.start()` lets the
task run and cannot fail, and `slot.cancel()` releases its reserved execution and
gives the body back:

`ticket.lin`:

```linea
import std.io
import std.mem
import std.session
import std.task

use session.Chan
use session.End
use task.Unstarted

// A ticket is handed in exactly once, so a body that captures one owns
// something linear.
@linear
struct Ticket {
    seat: UInt64,
}

fn main() -> Result[UInt8, io.IoError] {
    var seat = UInt64(0)
    let ticket = Ticket { seat = 12 }
    let body = sink [sink ticket, inout seat] |sink me: Chan[End]| {
        let Ticket { seat: taken } = ticket
        seat = taken
        me.close()
    }
    // No machine maps a stack of four exbibytes, so this preparation fails,
    // and `Unstarted` hands the body back, ticket and all, beside the reason.
    let (returned, refused) = match task.prepare_in(mem.system(), body, stack: 4611686018427387904) {
        // `cancel` joins the parked thread and gives the body back too.
        Ok(slot) => (slot.cancel(), false),
        Err(failure) => {
            let Unstarted { body, reason: _ } = failure
            (body, true)
        },
    }
    // With the default stack the preparation succeeds, and `start` cannot
    // fail.
    let slot = task.prepare(returned).unwrap()
    slot.start().close()
    io.println("first try refused: {refused}, seat: {seat}")?
    .Ok(0)
}
```

```
first try refused: true, seat: 12
```

Where a body owns nothing linear, `task.prepare(body).settled()?` drops the
body of a failure and hands its reason on, as
[Errors](03-errors.md) shows for other failures that hold a value.

## A task never outlives its parent

Rust's `std::thread::scope` guarantees that every thread spawned inside it is
joined before the scope ends, so the threads may borrow from the function
around it. Linea makes the same promise for every task, with no scope to
write: a handle carrying a place lent `inout` cannot leave the function that
lends it, so the task is joined there. A closure that tries to hand its
task's handle back to its caller is refused:

`scoped.lin`:

```linea
import std.session
import std.task

use session.Chan
use session.End

// `start_counting` would hand back a handle whose task still holds `count`,
// which lives in `start_counting`'s own frame.
fn start_counting() -> UInt64 {
    var count = UInt64(0)
    var launch = inout [inout count] || {
        let body = sink [inout count] |sink me: Chan[End]| {
            count += 1
            me.close()
        }
        task.start(body).unwrap()
    }
    let handle = &launch()
    handle.close()
    count
}

fn main() -> UInt8 {
    UInt8(start_counting())
}
```

```
error[O-Escapes]: a value holding a place lent `inout` cannot leave the function that lends it
  --> scoped.lin:16:9
   |
12 |         let body = sink [inout count] |sink me: Chan[End]| {
   |                                ----- lent `inout` here
16 |         task.start(body).unwrap()
   |         ^^^^^^^^^^^^^^^^^^^^^^^^^ this value holds the lend
   |
   = help: finish with the value inside this function, or give the closure its own state with a `sink` capture
```

There are no detached tasks. Every task is joined by the `close` of its
handle, in the function that started it.

## Gathering results

JavaScript's `Promise.all` starts several pieces of work and waits for all of
them:

```js
const [a, b, c] = await Promise.all([sum(1, 1e6), sum(1e6 + 1, 2e6), sum(2e6 + 1, 3e6)]);
```

In Linea you prepare every task, start them all, then collect each result
and close its handle. Preparing first matters: if the second preparation
fails, the first slot is cancelled before the reason is handed on, where a
started task would have to be joined. A body sends its result back through
its end of the session before it returns:

`gather.lin`:

```linea
import std.io
import std.session
import std.task

use session.Chan
use session.End
use session.Send

// Add up the whole numbers from `low` to `high`, one by one.
fn sum_between(low: UInt64, high: UInt64) -> UInt64 {
    (low..=high).sum()
}

// Add up 1 to 3000000 in three parts at once, or answer why a task could not
// be started.
fn sum_in_three() -> Result[UInt64, task.PrepareError] {
    let low = sink [] |sink me: Chan[Send[UInt64, End]]| {
        me.send(sum_between(1, 1000000)).close()
    }
    let middle = sink [] |sink me: Chan[Send[UInt64, End]]| {
        me.send(sum_between(1000001, 2000000)).close()
    }
    let high = sink [] |sink me: Chan[Send[UInt64, End]]| {
        me.send(sum_between(2000001, 3000000)).close()
    }
    // Prepare all three first: a preparation that fails cancels the ones
    // before it, so no task is left running when the reason is handed on.
    let first_slot = task.prepare(low).settled()?
    let second_slot = task.prepare(middle).settled() else |reason| {
        let _unrun = first_slot.cancel()
        return .Err(reason)
    }
    let third_slot = task.prepare(high).settled() else |reason| {
        let _unrun = first_slot.cancel()
        let _also_unrun = second_slot.cancel()
        return .Err(reason)
    }
    // Starting cannot fail, and all three start before any is waited for, so
    // they run at once.
    let first = first_slot.start()
    let second = second_slot.start()
    let third = third_slot.start()
    // Collect each result, then join its task.
    let (a, first_done) = first.recv()
    first_done.close()
    let (b, second_done) = second.recv()
    second_done.close()
    let (c, third_done) = third.recv()
    third_done.close()
    .Ok(a + b + c)
}

fn main() -> Result[UInt8, io.IoError] {
    match sum_in_three() {
        Ok(total) => io.println("1 + 2 + ... + 3000000 = {total}")?,
        Err(reason) => io.println("no task: {reason}")?,
    }
    .Ok(0)
}
```

```
1 + 2 + ... + 3000000 = 4500001500000
```

The three sums run at the same time on three threads. `recv()` waits for one
task's result, and `close()` joins it. Writing `task.start(low)?` three times
instead is refused: when the second start fails, `?` would leave with the
first task still running and its handle unclosed.

## A session and its protocol

A task and its creator talk through a session. Each end is a `Chan[P]`, where
`P` is a protocol from
[Copying, settling and sealing](04-copying-settling-and-sealing.md): `Send[T,
N]` sends a `T` and goes on as `N`, `Recv[T, N]` receives one, and `End` is
finished. The body's end follows `P`, and the handle follows `P.Dual`, the
other side of the same conversation:

`squares.lin`:

```linea
import std.io
import std.session
import std.task

use session.Chan
use session.End
use session.Recv
use session.Send

// The task receives a number and sends back its square.
alias Squarer = Recv[UInt64, Send[UInt64, End]]

fn main() -> Result[UInt8, io.IoError] {
    let body = sink [] |sink me: Chan[Squarer]| {
        let (number, answering) = me.recv()
        answering.send(number * number).close()
    }
    // The handle does the dual of `Squarer`: it sends, then receives.
    let asking = task.start(body).unwrap().send(12)
    let (square, done) = asking.recv()
    done.close()
    io.println("12 squared is {square}")?
    .Ok(0)
}
```

```
12 squared is 144
```

Each operation takes the endpoint and answers it at the next step, so
`send(12)` answers a `Chan` whose protocol is `Recv[UInt64, End]`, and
`recv()` answers the value together with the endpoint at `End`. A `send`
returns only once the other end has taken the value: a session has no queue,
so the two tasks meet at every step. A Rust channel's type says only what
travels through it, so either end may send or receive at any time. A
session's type also says whose turn it is, and an operation out of turn is a
compile error rather than a task waiting forever:

<!-- guide: edit 19 let asking = task.start(body).unwrap().send(12) -->
```linea
    let asking = task.start(body).unwrap()
```

```
error[T-UnknownOperation]: `Chan[Send[UInt64, Recv[UInt64, End]], (<closure>, mem.SystemAllocator)]` has no operation `recv`
   --> squares.lin:20:26
    |
20  |     let (square, done) = asking.recv()
    |                          ^^^^^^ this is `Chan[Send[UInt64, Recv[UInt64, End]], (<closure>, mem.SystemAllocator)]`, which `Chan[Recv[T, N], H]` does not match
   ::: std/session/chan.lin
126 | impl[T: Owned, N: Protocol, H] Chan[Recv[T, N], H] {
    |                                ------------------- `recv` is declared for `Chan[Recv[T, N], H]`
```

## A producer and a consumer

A conversation that goes on for as long as one side likes is a named
protocol, and a choice between two ways to go on is `Choose[L, R]` on one
side and `Offer[L, R]` on the other. `choose_left()` and `choose_right()`
tell the other end which way the conversation goes, and `offer()` answers the
branch it was told. Here `main` produces amounts and a counter task consumes
them until `main` asks for the total:

`counter_task.lin`:

```linea
import std.io
import std.mem
import std.session
import std.task

use session.Chan
use session.Choose
use session.End
use session.Offer
use session.Recv
use session.Send

// The counter is offered another amount to add, or asked for its total.
struct Counter {}

// Its client decides which of the two happens next.
struct Client {}

impl Protocol for Counter {
    type Dual = Client
    type Step = Offer[Recv[UInt64, Counter], Send[UInt64, End]]
}

impl Protocol for Client {
    type Dual = Counter
    type Step = Choose[Send[UInt64, Client], Recv[UInt64, End]]
}

// The counter's loop is a recursion: each pass unfolds the protocol with
// `enter` and follows the branch the client chose.
fn count(sink me: Chan[Counter], total: UInt64) {
    match me.enter().offer() {
        Left(adding) => {
            let (amount, next) = adding.recv()
            count(next, total + amount)
        },
        Right(reporting) => reporting.send(total).close(),
    }
}

// The client's side is a recursion too: send the amount at `at` and go on
// from the next one, or ask for the total once none is left. A handle is
// linear, so a loop could not hand it from one pass to the next.
fn add_all[H](sink client: Chan[Client, H], amounts: mem.Slice[UInt64], at: UInt64) -> UInt64 {
    if at < amounts.length() {
        add_all(client.enter().choose_left().send(amounts[at]), amounts, at + 1)
    } else {
        let (total, done) = client.enter().choose_right().recv()
        done.close()
        total
    }
}

fn main() -> Result[UInt8, io.IoError] {
    let body = sink [] |sink me: Chan[Counter]| {
        count(me, 0)
    }
    let amounts = [UInt64(5), 7, 30]
    let total = add_all(task.start(body).unwrap(), amounts.as_slice(), 0)
    io.println("total: {total}")?
    .Ok(0)
}
```

```
total: 42
```

`enter()` unfolds a named protocol to the step it stands for and costs
nothing at run time. A loop over a session is written as a recursion that
passes the endpoint on, on both sides: an endpoint is linear, so a loop could
not hand it from one pass to the next. Where JavaScript would write the
consumer as `for await (const amount of amounts)`, the counter's recursion
reads one amount per call.

## No colouring

Bob Nystrom's essay
["What Color is Your Function?"](https://journal.stuffwithstuff.com/2015/02/01/what-color-is-your-function/)
(2015) names the cost of `async`: functions come in two colours, and "You can
only call a red function from within another red function". In JavaScript a
function that waits must be an `async function`, so every function that
awaits it must be one too, all the way up. Rust's `async fn` spreads the same
way. Linea has no `async`: a function that starts a task and blocks on its
`close` is an ordinary function, and its caller cannot tell:

`plain_function.lin`:

```linea
import std.io
import std.session
import std.task

use session.Chan
use session.End
use session.Send

// An ordinary function: it starts a task, waits for it, and answers a
// number, or why no task could be started. Nothing marks it as one that
// waits.
fn doubled_on_a_task(number: UInt64) -> Result[UInt64, task.PrepareError] {
    let body = sink [read number] |sink me: Chan[Send[UInt64, End]]| {
        me.send(number * 2).close()
    }
    let (doubled, done) = task.start(body)?.recv()
    done.close()
    .Ok(doubled)
}

fn main() -> Result[UInt8, io.IoError] {
    // Called like any other function.
    match doubled_on_a_task(21) {
        Ok(answer) => io.println("answer: {answer}")?,
        Err(reason) => io.println("no task: {reason}")?,
    }
    .Ok(0)
}
```

```
answer: 42
```

## Threads and fibers

A task started on `io.system()` runs on its own operating-system thread, as
Rust's `std::thread::spawn` does. A task started on an `io.Loop` runs as a
**fiber**: it keeps its own stack, but shares a carrier thread with other
fibers. A socket, timer or session wait lets the carrier run another ready
fiber. Each fiber stays on the carrier that first runs it. A computation that
never waits keeps that carrier; regular files and blocking foreign calls also
hold it while they run.

Open a loop once and state its carrier count. This loop has one carrier, yet
the task uses the same session operations as a task on its own thread:

`fiber_answer.lin`:

```linea
import std.io
import std.session
import std.task

use session.Chan
use session.End
use session.Send

fn main() -> Result[UInt8, io.IoError] {
    let home = io.Loop.open(carriers: 1)?
    let body = sink [] |sink me: Chan[Send[UInt64, End]]| {
        me.send(42).close()
    }
    let (answer, done) = task.start(body, on: home).unwrap().recv()
    done.close()
    io.println("answer: {answer}")?
    .Ok(0)
}
```

```
answer: 42
```

The loop keeps its carriers until the process exits, even after its last task
returns. Zero carriers is an error. To choose a count from the process's
available processors, use an explicit resource count:

`available_carriers.lin`:

```linea
import std.env
import std.io
import std.session
import std.task

use session.Chan
use session.End

fn main() -> Result[UInt8, io.IoError] {
    let home = io.Loop.open(carriers: env.available_parallelism())?
    let body = sink [] |sink me: Chan[End]| me.close()
    task.start(body, on: home).unwrap().close()
    .Ok(0)
}
```

`available_parallelism()` returns at least one and reads the count again on
every call. On Linux it counts the process's affinity mask, lowered by a
cgroup v2 CPU quota rounded up; on macOS it reads the active processor count.

`task.start`, `start_in`, `prepare`, `prepare_in` and `own` all accept `on:`.
When it is omitted, the constant `io.inherited` resolves to the starting task's
current Io when execution is prepared. A fiber's children therefore stay on
its loop. `io.current()` captures the concrete Io now, so it can be kept and
passed later; `on: io.system()` explicitly starts a thread. The constant
default selects execution at use time without changing how parameter defaults
are evaluated.

## What may cross to a task

A task runs at the same time as its creator, so the compiler checks what
reaches the task, at two points.

**A value sent through a session is `Owned`.** `send` and `recv` take a
`T: Owned`, a type that holds no view of anything else
([Borrowing](06-borrowing.md)). Sending one hands the whole value over, and
the receiver ends up holding the only copy. A `String` owns its bytes, so it
may be sent:

`greeting.lin`:

```linea
import std.io
import std.session
import std.task

use session.Chan
use session.End
use session.Send

fn main() -> Result[UInt8, io.IoError] {
    // A `String` owns its bytes, so sending one hands the whole value over.
    let body = sink [] |sink me: Chan[Send[String, End]]| {
        me.send("hello from the task".to_owned().unwrap()).close()
    }
    let (greeting, done) = task.start(body).unwrap().recv()
    done.close()
    let printed = io.println("{greeting}")
    greeting.release()
    printed?
    .Ok(0)
}
```

```
hello from the task
```

A `Str` only views bytes somebody else owns, so it may not:

`view_payload.lin`:

```linea
import std.session
import std.task

use session.Chan
use session.End
use session.Send

fn main() -> UInt8 {
    let body = sink [] |sink me: Chan[Send[Str, End]]| {
        me.send("hello from the task").close()
    }
    let (greeting, done) = task.start(body).unwrap().recv()
    done.close()
    UInt8(greeting.length())
}
```

```
error[T-Bound]: `T` requires `Owned`, and `Str` can carry a borrow: it holds a view of storage it does not own
  --> view_payload.lin:10:12
   |
10 |         me.send("hello from the task").close()
   |            ^^^^ `Str` is not `Owned`; pass a value whose type owns everything it holds
error[T-Bound]: `T` requires `Owned`, and `Str` can carry a borrow: it holds a view of storage it does not own
  --> view_payload.lin:12:54
   |
12 |     let (greeting, done) = task.start(body).unwrap().recv()
   |                                                      ^^^^ `Str` is not `Owned`; pass a value whose type owns everything it holds
```

**What the body captures crosses when the task is prepared.** A body may
read what its creator reads, as long as the value is `Shareable`
([Borrowing](06-borrowing.md)): two readers cannot race, because neither may
write the value until `close`. Here the task adds up the prices while `main`
finds the cheapest one, both reading the same array at once:

`shared_prices.lin`:

```linea
import std.io
import std.session
import std.task

use session.Chan
use session.End
use session.Send

fn main() -> Result[UInt8, io.IoError] {
    let prices = [UInt64(300), 450, 125]
    // The body reads `prices` while it runs. So does `main`: two readers of
    // an array of numbers cannot race, and neither may write it until
    // `close` has joined the task.
    let body = sink [read prices] |sink me: Chan[Send[UInt64, End]]| {
        let total = prices.as_slice().copied().sum()
        me.send(total).close()
    }
    let handle = task.start(body).unwrap()
    let cheapest = prices.as_slice().copied().min().unwrap()
    let (total, done) = handle.recv()
    done.close()
    io.println("total {total}, cheapest {cheapest}")?
    .Ok(0)
}
```

```
total 875, cheapest 125
```

Writing the array while the task may still read it is refused, as writing a
borrowed value always is:

<!-- guide: edit 10 let prices = [UInt64(300), 450, 125] -->
```linea
    var prices = [UInt64(300), 450, 125]
```

<!-- guide: edit 20 let (total, done) = handle.recv() -->
```linea
    prices[0] = 275
    let (total, done) = handle.recv()
```

```
error[O-Borrow]: this operation invalidates a place that a later observation still needs
  --> shared_prices.lin:20:5
   |
20 |     prices[0] = 275
   |     ^^^^^^^^^ keep this place available until the last use of its observation
21 |     let (total, done) = handle.recv()
   |                         ------ the observation is still used here
```

Reading never writes an array of numbers, so it is `Shareable`. Two kinds of
value are not. An arena's handle writes the arena's cursor each time it is
read ([Borrowing](06-borrowing.md)). And a handle to an object C holds may be
read by C in ways the compiler cannot see, so it is not `Shareable` unless the
module that wraps the C library vouches for it; [Calling C](11-calling-c.md)
shows the refusal and the `@shareable` mark. Either kind may still move whole
into one task, or live in an owning task, below.

## No data races and no locks

A data race is two threads touching the same memory at once, at least one of
them writing, with nothing ordering the two. JavaScript avoids them by
running all of a program's code on one thread, its event loop, so two
callbacks never run at the same moment. Rust allows threads, and its `Send`
and `Sync` traits decide what may move to another thread and what may be
shared with one; state several threads change goes behind a `Mutex`:

```rust
let total = Arc::new(Mutex::new(0));
let worker = {
    let total = Arc::clone(&total);
    std::thread::spawn(move || *total.lock().unwrap() += 5)
};
worker.join().unwrap();
```

Linea runs tasks on many threads, has no `Mutex`, no atomics and no locks,
and every program it accepts is still free of data races. `Shareable` plays
the part of `Sync`: a value two tasks read at once must be `Shareable`. A
value that is not `Shareable` may not be read by a task and its creator at
once, because reading it writes. An arena handle is one: `acquire` moves the
arena's cursor through a `read`. The rule is `[O-Cross]`, and it names the
part of the value that is the problem:

`arena_cross.lin`:

```linea
import std.io
import std.mem
import std.session
import std.task

use mem.Lender
use session.Chan
use session.End

fn main() -> Result[UInt8, io.IoError] {
    defer let arena = mem.Arena.open(mem.system(), 256)
    let handle = arena.handle()
    let body = sink [read handle] |sink me: Chan[End]| {
        let _bytes = handle.acquire(16)
        me.close()
    }
    task.start(body).unwrap().close()
    io.println("done")?
    .Ok(0)
}
```

```
error[O-Cross]: a task cannot read `handle` while its creator may read it too: a `mem.Handle[mem.SystemAllocator]` is not `Shareable`
  --> arena_cross.lin:13:27
   |
13 |     let body = sink [read handle] |sink me: Chan[End]| {
   |                           ^^^^^^ this capture is read by the task
   |
   = help: reading this value may change it; move it into one task, or give the task a value that reading never changes
```

Moving such a value into the task with a `sink` capture is fine when nothing
else observes it, since then one task alone reads it afterwards.

The rules you already know decide who may touch what:

- a place the body reads may be read by its creator too, and written by
  nobody, until `close`;
- a place the body holds lent `inout` belongs to the task alone until
  `close`;
- a value moved into the body, or sent through a session, is no longer the
  sender's.

So each piece of memory has one writer or many readers, never both, and the
runtime orders the rest: everything the creator did before starting the task
is visible to the body, everything one end did before a `send` is visible to
the other after the matching `recv`, and everything the body did is visible
after `close`.

Two tasks may each hold a different field of one record lent `inout`. The
fields do not overlap, so neither task can reach the other's:

`tally.lin`:

```linea
import std.io
import std.session
import std.task

use session.Chan
use session.End

struct Tally {
    wins: UInt64,
    losses: UInt64,
}

fn main() -> Result[UInt8, io.IoError] {
    var tally = Tally { wins = 0, losses = 0 }
    // Each body holds one field lent `inout`. The fields do not overlap, so
    // the two tasks never write the same place.
    let winning = sink [inout wins = tally.wins] |sink me: Chan[End]| {
        wins += 2
        me.close()
    }
    let losing = sink [inout losses = tally.losses] |sink me: Chan[End]| {
        losses += 1
        me.close()
    }
    let wins_handle = task.start(winning).unwrap()
    let losses_handle = task.start(losing).unwrap()
    wins_handle.close()
    losses_handle.close()
    io.println("wins {tally.wins}, losses {tally.losses}")?
    .Ok(0)
}
```

```
wins 2, losses 1
```

Lending the same field to both bodies is refused before either task starts:

<!-- guide: edit 21 let losing = sink [inout losses = tally.losses] |sink me: Chan[End]| { -->
```linea
    let losing = sink [inout losses = tally.wins] |sink me: Chan[End]| {
```

```
error[O-Borrow]: this operation uses a place lent `inout` to a value that is still used
  --> tally.lin:21:39
   |
17 |     let winning = sink [inout wins = tally.wins] |sink me: Chan[End]| {
   |                                      ---------- lent `inout` here
21 |     let losing = sink [inout losses = tally.wins] |sink me: Chan[End]| {
   |                                       ^^^^^^^^^^ this uses the place while it is lent
25 |     let wins_handle = task.start(winning).unwrap()
   |                                  ------- a value holding the lend is still used here
   |
   = help: a place lent `inout` is reached only through what holds the lend until that value's last use; use it after that, or through the closure
```

Where Rust puts state that several threads change behind a `Mutex`, Linea
gives it to one task, which the others reach over a session. The counter in
[A producer and a consumer](#a-producer-and-a-consumer) is that pattern: it
owns its total, and `main` changes it only by sending an amount.

## What deadlock freedom promises

Stephen Cleary's
["Async/Await – Best Practices in Asynchronous Programming"](https://learn.microsoft.com/en-us/archive/msdn-magazine/2013/march/async-await-best-practices-in-asynchronous-programming)
(MSDN Magazine, March 2013), in its section "Async All the Way", calls `async`
contagious, and shows that blocking on asynchronous code to stop it spreading
deadlocks. Linea has no colour, so there is nothing to stop from spreading,
and blocking is the ordinary way to wait: that deadlock cannot be written.

A deadlock is a set of tasks each waiting for another in the set, forever.
In JavaScript, two promises that each wait for the other never settle; in
Rust, two threads that each lock what the other holds hang. Linea's sessions
rule this out.

A session is made only by starting a task, which joins the new task to its
creator by exactly one session, so the tasks and sessions of a program always
form a tree. The two ends of a session follow dual protocols, so when one
end waits to receive, the other end's next step is to send, and the two
meet. Follow the waits from any waiting task through the tree and you reach a
task that waits on no one, which keeps going. So no group of tasks ever
waits on each other forever, provided the system runs every thread whose
operation can complete, as an operating system does.

A task waiting in a [wait set](#waiting-on-several-things-at-once) waits on
several of its own sessions at once, and the same argument holds: the peer of
each one's next step is the very step that wakes the set. A timer, a socket
and a signal are the outside world, not a task.

What this does not promise:

- that a session completes or a program finishes: a task may loop forever,
  or keep a session going without end;
- that the outside world answers: a task waiting on a socket or a file waits
  as long as the world takes;
- that every pending exchange completes, or any order between tasks beyond
  each session's own steps.

## Stopping a task early

JavaScript stops work early with an `AbortController`, and an async Rust
future stops when it is dropped. Nothing in Linea stops a task from outside:
its frames would be left with what they own unsettled. A task stops early
when its protocol offers it a way to, and its creator takes that branch:

`stop_early.lin`:

```linea
import std.io
import std.session
import std.task

use session.Chan
use session.End
use session.Offer
use session.Send

// The search waits to be told whether its answer is still wanted: it sends
// the answer, or it stops.
alias Search = Offer[Send[UInt64, End], End]

// The first number above `from` that `divisor` divides.
fn first_multiple(from: UInt64, divisor: UInt64) -> UInt64 {
    var candidate = from + 1
    while candidate % divisor != 0 {
        candidate += 1
    }
    candidate
}

fn main() -> Result[UInt8, io.IoError] {
    let body = sink [] |sink me: Chan[Search]| {
        let found = first_multiple(1000, 37)
        match me.offer() {
            Left(answering) => answering.send(found).close(),
            Right(stopping) => stopping.close(),
        }
    }
    let search = task.start(body).unwrap()
    // `main` no longer needs the answer, so it takes the branch that tells
    // the task to stop, then joins it.
    search.choose_right().close()
    io.println("the search was told to stop")?
    .Ok(0)
}
```

```
the search was told to stop
```

A `recv` cannot fail, so there is no "the other end went away" to handle
either. Every way a conversation can end is a branch of its protocol, which
both ends must follow.

## Waiting on several things at once

`recv` waits on one session and `close` on one task. A program often waits
for whichever of several things happens first: a reply or a timeout, the
first of three workers, a connection or Control-C. JavaScript writes that
with `Promise.race`, and async Rust with `select!`. Linea has
`task.WaitSet`.

A wait set is a value you move things into. Each registration takes a value,
a function that wraps it into a message of your own type once it is ready,
and answers a **key**. `next` waits until something registered is ready and
answers its message.

### A reply against a timeout

`ask_within.lin`:

```linea
import std.io
import std.session
import std.task
import std.time

use session.Chan
use session.End
use session.Recv
use session.Send

// The end of a session that receives one number.
alias Reply = Chan[Recv[UInt64, End]]

// What the wait set delivers: the endpoint, once its reply waits, or the
// news that the time is up.
enum Waited {
    Answer(Reply),
    Late,
}

enum Asked {
    Answered(UInt64),
    TimedOut(Reply),
}

// Ask a peer and give up after `limit`.
fn ask_within(sink peer: Reply, limit: time.Duration) -> Asked {
    var waiting: task.WaitSet[Waited] = task.WaitSet.open()
    let answer = &waiting.received(peer, |sink ready| Waited.Answer(ready))
    let timer = &waiting.after(limit, (), |sink _expired| Waited.Late)
    let asked = match &waiting.next() {
        Some(Answer(peer)) => {
            // The reply won. The timer is taken back unfired.
            let _unfired = &waiting.take(timer)
            let (number, done) = peer.recv()
            done.close()
            Asked.Answered(number)
        },
        // The timer won. The endpoint is taken back, still waiting to
        // receive.
        Some(Late) => Asked.TimedOut(&waiting.take(answer).unwrap()),
        None => panic("two sources were registered"),
    }
    waiting.close().finish().unwrap()
    asked
}

// Start a peer that replies `number` after `delay`.
fn replying(number: UInt64, delay: time.Duration) -> Reply {
    let body = sink [sink number, sink delay = copy(delay)] |sink me: Chan[Send[UInt64, End]]| {
        time.sleep(delay)
        me.send(number).close()
    }
    task.start(body).unwrap().detach()
}

fn report(sink asked: Asked) -> Result[(), io.IoError] {
    match asked {
        Answered(number) => io.println("answered: {number}"),
        TimedOut(peer) => {
            let (number, done) = peer.recv()
            done.close()
            io.println("timed out; the reply came later: {number}")
        },
    }
}

fn main() -> Result[UInt8, io.IoError] {
    report(ask_within(replying(7, time.Duration.from_milliseconds(0)), time.Duration.from_seconds(60)))?
    report(ask_within(replying(8, time.Duration.from_milliseconds(300)), time.Duration.from_milliseconds(20)))?
    .Ok(0)
}
```

```
answered: 7
timed out; the reply came later: 8
```

`received` registers an endpoint whose next step is `recv`. It is ready once
the peer's `send` is waiting, and `next` then hands it back wrapped as
`Waited.Answer`. The set never receives for you: the value is still in the
session, and `peer.recv()` takes it at once.

`after` registers a timer with a message of its own, here `()`.

### Nothing registered is lost

When a `Promise.race` settles, the promises that lost keep running with
nobody listening, and a Rust future that loses a `select!` is dropped where
it stood. In Linea the loser is still yours. Every registration answered a
key, and `take(key)` hands the value back in its own type: taking `answer`
gives the endpoint, still waiting to receive, so the late reply is collected
above and its task joined. Taking `timer` gives back the timer's message.

A key is a small copyable value. Once its registration has been delivered or
taken, the key answers `.None`, however many copies of it exist, and a key
of one set answers `.None` from another.

`take_if_registered(key)` takes a registration back only while it is not
ready, and answers `.None` once it is. `close` ends the set and answers a
vector of whatever is still registered, wrapped. A wait set is linear, so a
path that forgets to close it does not compile.

### The first of several tasks

`returned` registers a task's handle. It is ready once the task's body has
returned, so the `close` that follows joins at once.

`first_child.lin`:

```linea
import std.io
import std.session
import std.task
import std.time

use session.Chan
use session.End

// Close a handle taken back from the set, which joins its task.
fn join_if_left[F, A: Allocator](sink taken: Option[Chan[End, (F, A)]]) {
    match taken {
        Some(handle) => handle.close(),
        None => {},
    }
}

fn main() -> Result[UInt8, io.IoError] {
    let quick = sink [] |sink me: Chan[End]| {
        me.close()
    }
    let slow = sink [] |sink me: Chan[End]| {
        time.sleep(time.Duration.from_milliseconds(200))
        me.close()
    }
    var waiting: task.WaitSet[UInt64] = task.WaitSet.open()
    // Each wrap joins the task that returned and answers its number.
    let second = &waiting.returned(
        task.start(slow).unwrap(),
        |sink done| {
            done.close()
            UInt64(2)
        },
    )
    let first = &waiting.returned(
        task.start(quick).unwrap(),
        |sink done| {
            done.close()
            UInt64(1)
        },
    )
    let winner = &waiting.next().unwrap()
    // The other child is still working. Its handle comes back by its key,
    // and closing it waits for the child as any `close` does.
    join_if_left(&waiting.take(first))
    join_if_left(&waiting.take(second))
    waiting.close().finish().unwrap()
    io.println("child {winner} returned first")?
    .Ok(0)
}
```

```
child 1 returned first
```

### Only what the other side can make ready

A wait set waits for the other end of a session to act. An endpoint whose
next step is its own `send` has nothing to wait for, so `received` does not
take it:

`not_ready.lin`:

```linea
import std.session
import std.task

use session.Chan
use session.End
use session.Recv
use session.Send

enum Waited {
    Ready(Chan[Send[UInt64, End], ()]),
}

fn main() -> UInt8 {
    let body = sink [] |sink me: Chan[Recv[UInt64, End]]| {
        let (_, done) = me.recv()
        done.close()
    }
    // `sending` is at `Send`: its next step is this task's own.
    let sending = task.start(body).unwrap().detach()
    var waiting: task.WaitSet[Waited] = task.WaitSet.open()
    let _key = &waiting.received(sending, |sink ready| Waited.Ready(ready))
    waiting.close().finish().unwrap()
    0
}
```

```
error[T-Mismatch]: expected `Chan[Recv[T, N], H]`, found `Chan[Send[UInt64, End], ()]`
   --> not_ready.lin:21:34
    |
21  |     let _key = &waiting.received(sending, |sink ready| Waited.Ready(ready))
    |                                  ^^^^^^^ expected `Chan[Recv[T, N], H]`, found `Chan[Send[UInt64, End], ()]`
   ::: std/task/wait_set.lin
273 | ... nk ready: Chan[Recv[T, N], H]) -> M](inout self: Self, sink chan: Chan[Recv[T, N], H], sink wrap: W) -> Registered[Chan[ ...
    |                                                                 ---- expected because of this parameter
```

The endpoint's type says it sends next, and `received` asks for one that
receives next.

`offered` is the same for an endpoint whose next step is `offer`, ready once
the peer has chosen.

### Timers, sockets and signals

A wait set also waits on the outside world:

- `after(duration, message, wrap)` is a timer.
- `readable(value, wrap)` and `writable(value, wrap)` take a listener, a
  connection or a buffered reader over one, ready when it can be read or
  written without waiting.
- `signal(which, wrap)` waits for an operating-system signal, such as
  `.Interrupt`, which Control-C sends, or `.Terminate`, which a supervisor
  sends to ask a program to stop.

This program ticks once a second until it is told to stop. It runs in a
[simulation](09-networking.md#testing-a-timeout-without-waiting), so the seconds are virtual and the signal is
delivered by the program itself; outside a simulation the same code waits on
the real clock and the real signal.

`ticker.lin`:

```linea
import std.io
import std.task
import std.time

enum Woke {
    Tick(UInt64),
    Stop(io.SignalShare),
}

fn main() -> Result[UInt8, io.IoError] {
    var sim = io.Simulation.open(seed: 1).unwrap()
    let (ticks, seconds) = &sim.run(
        |inout world| {
            let started = time.Instant.now()
            var waiting: task.WaitSet[Woke] = task.WaitSet.open()
            let _stop = &waiting.signal(.Terminate, |sink share| Woke.Stop(share)).unwrap()
            var timer = &waiting.after(time.Duration.from_seconds(1), UInt64(1), |sink n| Woke.Tick(n))
            var ticks = UInt64(0)
            loop {
                match &waiting.next().unwrap() {
                    Tick(n) => {
                        ticks = n
                        if n == 3 {
                            &world.deliver(.Terminate)
                        }
                        timer = &waiting.after(time.Duration.from_seconds(1), n + 1, |sink n| Woke.Tick(n))
                    },
                    Stop(share) => {
                        share.settle()
                        break
                    },
                }
            }
            // The next tick was registered and never fired.
            let _unfired = &waiting.take(timer)
            waiting.close().finish().unwrap()
            (ticks, started.elapsed().nanoseconds() / 1000000000)
        },
    )
    sim.close()
    io.println("stopped after {ticks} ticks and {seconds} seconds")?
    .Ok(0)
}
```

```
stopped after 3 ticks and 3 seconds
```

The message for a signal carries an `io.SignalShare`. While a share exists,
the signal wakes the wait sets that wait for it instead of ending the
program; `share.settle()` gives it back, and once the last share is settled
a second Control-C ends the program as usual. To keep waiting for the next
delivery, register the share again with `signal_with(share, wrap)`. A program
started with a signal ignored, as `nohup` starts one with `Hangup` ignored,
is told so: `signal` answers `.Err(.Ignored)`.

A wait set belongs to the task that opened it. It holds endpoints, so it is
not sent over a session and is not an [owning task's](#the-owning-task-pattern)
state.

## Independent work: `task.all`, `task.map`, and `task.join`

Not all parallel workloads need a stateful conversation between tasks. Many tasks
compute independent, value-producing jobs: they take inputs, run to completion
without back-and-forth rendezvous, and return owned results.

Linea provides three core combinators for independent work:
- `task.all(policy, jobs)` runs a collection of homogeneous jobs (like `Promise.all` in JavaScript or `futures::future::join_all` in Rust) and returns a `Vec[T]` in job order.
- `task.map(policy, items, f)` runs a data-parallel transformation over elements of a `Vec[T]`, bounding concurrency by worker threads while keeping deterministic input order.
- `task.join(policy, f1, f2)` (and `join3`, `join4`) gathers distinct computations of different types into a tuple `(T1, T2)` (like `tokio::join!` in Rust).

Each takes a `policy: task.Policy`:
- `Policy.Sequential`: runs synchronously inline on the caller's stack with zero thread overhead and complete determinism.
- `Policy.Threads(max)`: runs the work on tasks of its own. `map` and `all` divide their items among at most `max` tasks; `join`, `join3` and `join4` run up to `max` jobs at once, on `max - 1` tasks of their own and the caller, and run the jobs in turn on the caller when `max` is 1. A `max` of 0 stops the program.

`independent_work.lin`:

```linea
import std.io
import std.mem
import std.task

fn square(sink n: UInt64) -> UInt64 {
    n * n
}

fn seven() -> UInt64 {
    7
}

fn main() -> Result[UInt8, io.IoError] {
    // `join` runs two jobs at once and answers both results, in order.
    let (sum, product) = task.join(.Threads(2), sink [] || UInt64(2 + 3), sink [] || UInt64(2 * 3))
    io.println("join: {sum} and {product}")?
    // `map` applies `square` to every item on up to two threads, and keeps the
    // items' order.
    var items: mem.Vec[UInt64, mem.SystemAllocator] = mem.Vec.new()
    for n in 1..=4 {
        &items.push(n).unwrap()
    }
    defer let squares = task.map(.Threads(2), items, square)
    for squared in squares.as_slice() {
        io.println("map: {*squared}")?
    }
    // `all` runs jobs of one type, here three calls of `seven`.
    var jobs: mem.Vec[fn() -> UInt64, mem.SystemAllocator] = mem.Vec.new()
    for _ in 0..3 {
        &jobs.push(seven).unwrap()
    }
    defer let sevens: mem.Vec[UInt64, mem.SystemAllocator] = task.all(.Sequential, jobs)
    io.println("all: {sevens.length()} results")?
    .Ok(0)
}
```

```
join: 5 and 6
map: 1
map: 4
map: 9
map: 16
all: 3 results
```

Each job is `Owned`: it takes what it needs with `sink` and holds no view of a
value the caller keeps, so the jobs and the caller never touch one value at
once. `map`'s function is also `Shareable` and `Copyable`, since every thread
calls a copy of it. A job that panics, or a thread that cannot be made, stops
the program; the combinators answer only the results.

## Moving a handler from sequential to concurrent

`http.serve` answers many requests at once, on up to 128 serving tasks unless
its `policy:` says otherwise. No handler is reached by two tasks: each serving
task builds its own, so `serve` takes a function that builds one rather than
one handler. Given `policy: .Sequential`, the same call builds one handler with
that function and answers one connection at a time with it, on the thread
that called `serve`:

```linea
import std.http
import std.net

// Each serving task calls this to build its own router.
fn routes() -> http.Router[()] {
    http.Router.new()
}

// Serve many requests at once, each task with a router of its own.
fn serve_concurrently(sink listener: net.Listener) -> Result[(), http.ServeError] {
    http.serve(listener, routes)
}

// Serve one connection at a time through one router.
fn serve_in_turn(sink listener: net.Listener) -> Result[(), http.ServeError] {
    http.serve(listener, routes, policy: .Sequential)
}
```

A handler that keeps a count every task must see cannot keep it in itself,
since each task has its own handler. It keeps it in an owning task instead,
and `http.listen_and_serve_with` starts one for the state a server's routes
share ([Networking](09-networking.md#shared-state)).

## The owning-task pattern

Where Rust programs often wrap shared state in `Arc<Mutex<T>>` or
`Arc<RwLock<T>>`, Linea gives the state to one task. `task.own(state)` starts
an **owning task** that holds it, and a `task.Client` reaches it: the client's
`call` runs the closure it is given on the owning task, against the state, one
call at a time, and answers what the closure answers. No other task touches
the state, so there is nothing to lock.

An owning task runs every call on its selected Io, one at a time, which is
what a C object that is not safe for two threads needs. Some C libraries ask
more: that one thread create, use and destroy each object. A value made by
`main` and moved into `task.own` was created on `main`'s thread, so for such
a library the owning task must open the object itself, in its first call,
and close it before it ends. Being `Shareable` or not says nothing about
threads either way: a value that is not `Shareable` still moves whole to
another task.

`owning_task.lin`:

```linea
import std.io
import std.session
import std.task

use session.Chan
use session.End

struct Tally {
    count: UInt64,
}

fn main() -> Result[UInt8, io.IoError] {
    // `task.own` starts a task that owns the tally; no other task touches it.
    let tally = task.own(Tally { count = 0 }).unwrap()
    let counter = tally.client()
    // Each task takes its own copy of the client, and `call` runs the closure
    // it is given on the owning task, against the tally, one call at a time.
    let first = task.start(
        sink [sink counter = copy(counter)] |sink me: Chan[End]| {
            counter.call(|inout t: Tally| t.count += 10)
            me.close()
        },
    ).unwrap()
    let second = task.start(
        sink [sink counter] |sink me: Chan[End]| {
            counter.call(|inout t: Tally| t.count += 20)
            me.close()
        },
    ).unwrap()
    first.close()
    second.close()
    // Both tasks holding a client have been joined, so the owning task can be
    // closed, and `close` hands the tally back.
    let Tally { count } = tally.close()
    io.println("total counted: {count}")?
    .Ok(0)
}
```

```
total counted: 30
```

A client borrows the owning task it came from, so `tally.close()` is refused
while a client is still used: every task holding one is joined first, and
`close` hands the state back. A call's closure runs on the owning task's
thread, so it must own what it captures. A client is a borrow, so a closure
holding one is refused: it could call the task that runs it, which would wait
for itself:

`holding_a_client.lin`:

```linea
import std.task

struct Tally {
    count: UInt64,
}

fn main() -> UInt8 {
    let tally = task.own(Tally { count = 0 }).unwrap()
    let counter = tally.client()
    // The closure captures the client, so it borrows the owning task it runs on.
    counter.call(
        [counter] |inout t: Tally| {
            t.count += 1
            counter.call(|inout u: Tally| u.count += 1)
        },
    )
    let Tally { count } = tally.close()
    if count == 2 {
        0
    } else {
        1
    }
}
```

```
error[T-Bound]: `F` requires `Owned`, and `<closure>` can carry a borrow: `counter` is a `borrow task.Client[Tally]`, an observation of another value
  --> holding_a_client.lin:11:13
   |
11 |     counter.call(
   |             ^^^^ `<closure>` is not `Owned`; pass a value whose type owns everything it holds
```

The owning task's state, and every closure a call gives it, must also be
`Isolated`: hold no end of a session. A call waits while the calls queued
before it run, so if one of them could wait on another task through a session,
and that task were itself waiting for a call queued behind it, the two would
wait for each other forever. An endpoint, a task's handle, an `Owner` and
anything holding one are not `Isolated`, so they are refused as an owning
task's state or in a call's closure. Keep endpoints in the task that started
the other task, and give the owning task only the data the tasks share:

`holding_an_endpoint.lin`:

```linea
import std.session
import std.task

use session.Chan
use session.End
use session.Recv

fn main() -> UInt8 {
    // The task waits for one number.
    let listener = task.prepare(
        sink [] |sink me: Chan[Recv[UInt64, End]]| {
            let (_, done) = me.recv()
            done.close()
        },
    ).unwrap().start().detach()
    // The owning task's state would be the end that sends the number.
    let desk = task.own(listener).unwrap()
    desk.close().send(7).close()
    0
}
```

```
error[T-Bound]: `S` requires `Isolated`, and `Chan[session.Send[UInt64, End], ()]` is an end of a session, through which a call could wait on another task
  --> holding_an_endpoint.lin:17:21
   |
17 |     let desk = task.own(listener).unwrap()
   |                     ^^^ `Chan[session.Send[UInt64, End], ()]` is not `Isolated`; pass a value that holds no end of a session
error[T-Bound]: `S` requires `Isolated`, and `Chan[session.Send[UInt64, End], ()]` is an end of a session, through which a call could wait on another task
  --> holding_an_endpoint.lin:18:10
   |
18 |     desk.close().send(7).close()
   |          ^^^^^ `Chan[session.Send[UInt64, End], ()]` is not `Isolated`; pass a value that holds no end of a session
```
