# 261. An owning task holds nothing that waits

Status: Accepted — 2026-11-07. Supersedes the owning-task clause of
[0250](0250-tasks-are-structured-through-linear-sessions.md) §9 and the
`Owned` job clause of
[0253](0253-independent-work-runs-through-an-explicit-executor-policy.md) §4;
extends [0250](0250-tasks-are-structured-through-linear-sessions.md) §5 with a
third containment bound beside `Owned` and `Shareable`.

## Context

An owning task runs the calls its clients queue, one at a time, on its own
thread ([0253](0253-independent-work-runs-through-an-explicit-executor-policy.md)
§4). The deadlock-freedom argument of
[0250](0250-tasks-are-structured-through-linear-sessions.md) §9 keeps calls out
of the session graph `G`: a caller waits only while the calls queued before
its own run, and each of those "completes without waiting on any task: a job
is `Owned`, … so no job holds" a client.

That covers a client and nothing else. `Owned` says a value carries no
borrow, and a detached endpoint `Chan[P, ()]` carries none: it must be `Owned`,
since a payload is, and delegation sends endpoints as payloads. The checker
accepted this program, and it never finishes:

```linea
struct Desk {
    line: Chan[Send[Bool, Recv[UInt64, End]]],
}

impl Release for Desk {
    fn release(sink self: Self) {
        let Desk { line } = self
        let (_, done) = line.send(true).recv()
        done.close()
    }
}

fn main() -> UInt8 {
    let tally = task.own(UInt64(0)).unwrap()
    let counter = tally.client()
    let clerk = task.prepare(
        sink [sink counter = copy(counter)] |sink me: Chan[Send[Bool, Recv[UInt64, End]]]| {
            let desk = Desk { line = me }
            counter.call([sink _desk = desk] |inout n: UInt64| n += 1)
        },
    ).unwrap().start()
    let (_, rest) = clerk.recv()
    let seen = counter.call(|inout n: UInt64| n)
    rest.send(seen).close()
    let _ = tally.close()
    0
}
```

The clerk's job holds the clerk's own end of its session with `main`. The
owning task runs the job and then releases it, before it answers the clerk,
and the release waits for `main`'s number. `main` first calls the same owning
task, and that call is queued behind the job being released. The `Release`
bound on a job did not stop it: a linear endpoint is not `Release`, but a
record of the program's own that holds one and implements `Release` is.

In the terms of §9, the call moved an endpoint into the owning task by a path
that is not an edge of `G`. Delegation keeps `G` a forest because an endpoint
moves only along a session or into a body `start` makes a child; a job is
neither, so the endpoint's new edge, between the owning task and `main`, sat
beside the edge the owner's handle already makes between them, a cycle of
length two.

The state was held to `Owned` alone as well. A state can hold an endpoint only
from `own`, whose send to the new task is delegation along its handle, so no
cycle came from it in the programs tried. But with an endpoint in the state, a
job waits on another task, and the argument that a call completes no longer
says why; it would rest on a forest argument over the owning task's own
subtree that nobody wrote.

## Decision

**`Isolated`** is a built-in capability bound beside `Owned` and `Shareable`,
computed by typing over the same containment edges `Shareable` follows, and
never implementable by a program:

```text
isolated = not session.Chan
           and not mem.Closure
           and every owned part isolated
           and every observed referent isolated
```

`session.Chan` is an end of a session, and every task's handle is one. It is
the declaration the checker names in `RawAccesses` as the endpoint, as it
names `mem.Carried` and `mem.Storage`, so the seed is a fact about the
library's declaration and not a spelling the program can reach. `mem.Closure`
seeds too: its type does not say what the callable it erased holds. An open
type, a closure whose descriptor is not recorded, and a type parameter not
bounded `Isolated` or `Integer` seed it as they seed the other tables. A
function value names a function and holds nothing, so it is isolated.
Following observed referents makes `task.Client`, which observes an `Owner`,
not isolated, though it is not `Owned` either.

`task.own` bounds its state `S: Owned + Isolated`, and `Client.call` bounds its
job `F: Owned + Isolated + Release`. Both are the whole of what the owning
task's thread reaches: the state, and each job together with its release. A
refusal is [T-Bound] at the `own` or `call`, naming the path to the endpoint:

```text
error[T-Bound]: `F` requires `Isolated`, and `<closure>` is not `Isolated`: `_desk.line` is a `Chan[Send[Bool, Recv[UInt64, End]], ()]`, an end of a session, through which a call could wait on another task
```

The library's generic callers state the bound where they name an owning task's
state: the listener a serving pool keeps in its owning task
(`net.serve_workers`, `http.serve` and their helpers) and the state of
`http.listen_and_serve_with` and `listen_and_serve_with_in`.

**The argument of 0250 §9 for owning tasks** is then: a caller waits only
while the calls queued before its own run, and each of those completes
without waiting on a task that waits for a call. A job and the state hold no
endpoint, owner or client, so the only tasks a job can wait on are tasks it
starts itself, whose bodies capture only what the job owns: no client of any
owning task, and no endpoint from outside. Such a task's subtree is joined to
the rest of `G` by the one edge to the owning task, and the theorem of §9
applies to it unchanged. The owning task's own wait for the next call is
enabled by any call, and by `close`, which its holder may reach only once
every task holding a client has been joined.

A job's answer `R` stays `Owned` only. It moves out of the owning task, to the
caller, so it can hold an endpoint of a task the job started without closing
any cycle.

## Consequences

- `tests/tasks/a_call_cannot_hold_an_endpoint.lin` is the program above;
  `tests/tasks/an_owning_task_holds_nothing_that_waits.lin` refuses a state
  holding an endpoint in an option, a record, a vector and a closure, and an
  owner held by another owning task.
- The semantics document defines `Isolated` beside `Shareable`, and the guide's
  concurrency chapter says what an owning task's state and job may hold.
- A fourth containment table, `connected`, is built beside the `unshareable`
  one over the same edges, and only the checker reads it; its witness explains
  a refusal the way `Shareable`'s does.
- An owning task cannot route sessions: a state that keeps workers' endpoints
  and a job that drives them are refused. Work that needs it gives each worker
  a session of its own, or keeps the endpoints in the task that started the
  workers.

## Alternatives considered

**Bounding only the job.** The deadlock above comes through the job, and an
endpoint enters the state only along the owner's handle. It would keep a state
that holds endpoints, at the price of an argument that a job waiting on a task
in the owning task's subtree terminates, which has to rule out every path by
which an endpoint whose peer holds a client could reach that subtree. One
bound on both says what an owning task's thread may reach, and the argument
stays the one sentence §9 already had.

**Making an endpoint not `Owned`.** Payloads are `Owned`, and delegation sends
an endpoint as a payload, so §9's own steps would stop being expressible.

**Marking the endpoint with a declaration attribute, as `@unshareable` is.** An
attribute is a policy a library module writes on its own type. The endpoint
is one declaration the runtime's session calls are confined to, so naming it
in `RawAccesses` ties the seed to the declaration the checker already
certifies, and no other module can declare a type the seed misses: a type
that waits on another task holds a `Chan` or reaches the runtime's session
calls, which [T-ExternRuntime] confines to `std.session` and `std.mem`.

**Treating a call as an edge of `G`.** A call would then be a session step
between caller and owner, and the forest invariant would refuse a second
client: every caller holds an edge to the one owning task, and two callers
joined to their common parent close a cycle. Owning tasks exist for many
callers.
