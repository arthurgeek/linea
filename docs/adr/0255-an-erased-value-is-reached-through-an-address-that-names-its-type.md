# 255. An erased value is reached through an address that names its type

Status: Accepted — 2026-11-01. Supersedes the clause of
[0193](0193-a-closure-may-hold-a-place-lent-inout.md) that has writer
containment follow every type argument, and the clause of
[0250](0250-tasks-are-structured-through-linear-sessions.md) that has the
`Shareable` table do the same; extends
[0254](0254-a-newtype-takes-type-parameters.md).

## Context

Two containment tables decide what a value may hold that its fields do not
show: the writer table ([0193](0193-a-closure-may-hold-a-place-lent-inout.md))
and the `unshareable` table
([0250](0250-tasks-are-structured-through-linear-sessions.md)). Both follow
every type argument of every instance, phantom ones included, because the
library keeps values where no field names them: behind a `UInt64` address.

The rule is sound and too strict. `task.Client[S]` borrows an `Owner[S]`,
which holds a call queue and the session it joins its task through; neither
holds an `S`, which lives on the owning task's stack. Because `S` is a type
argument, `Client[S]` is unshareable whenever `S` is, so an owning task over
unshareable state cannot give a client to another task. That is the case
owning tasks exist for.

Nothing in the language said which declarations erase which parameters,
because erasure was not visible in a type. It happened in four ways, all
inside `std.mem`:

1. `slot_put`, `slot_take`, `slot_place` and `slot_span` took a raw address
   and length beside a `Storage[T, A]` whose `T` is phantom. The storage is a
   typing token; the bytes were linked to `T` by convention.
2. `Closure.erase` and `keep_body` put a value into a `Storage` and then took
   the storage apart, or disposed of it while it was full, keeping only the
   address.
3. `call_owner` captured the address of its answer slot in the job it queued,
   and the job rebuilt a `Storage` over that address on the owning task's
   thread.
4. The runtime received addresses as `UInt64`s: a channel or owner queue
   copied the bytes to the other side before the call returned, and
   `linea_task_start` kept them for the new thread.

A rule that follows only what a type names cannot be sound while any of these
can put a `T` where no type names it. Marking parameters `erased` would not be
checked either: the leak is an address flowing anywhere a `UInt64` can, which
a parameter mark does not see.

## Decision

### 1. An address names what it points at

`std.mem.address` declares `Address[phantom T]`, a copyable newtype over
`UInt64` ([0254](0254-a-newtype-takes-type-parameters.md)). It is `@opaque` in
a module of its own, so no other module, `std.mem` included, can build one
from a number or read the number in one. The module offers two operations:
`nowhere()`, the address of a value with no size, and `raw(at)`, the number.
The checker certifies that it declares nothing else, since a function added
beside them could build an address. The compiler offers a third,
`mem.address_in(buffer, offset)`, the address of `T` slots at `offset` within
a buffer, checked against its length.

- `Storage[T, A]` holds `at: Address[T]`.
- `slot_put`, `slot_take` and `slot_place` take no address: they read the
  slots' address and extent from the storage they are given, so a slot outside
  the storage's own bytes cannot be named.
- The writer and `unshareable` tables follow an `Address[T]` to `T`, as they
  follow certified storage and `Slice` to their elements. The dependency table
  does not: an address is a number, and the storage that owns its bytes
  carries the dependencies of what is kept there.

Wherever a `T` is kept in bytes, then, a value of a type that names `T` holds
it: a field of type `Address[T]` or `Storage[T, A]`.

### 2. An address becomes a number only where the runtime is told what to do with it

A runtime symbol's parameter that is the address of typed bytes is marked in
`runtime_symbols.zig`. The marked parameters are where the runtime copies the
bytes to another task before the call returns (`linea_chan_send`,
`linea_owner_call`'s request, `linea_owner_answer`), writes bytes another task
sent (`linea_chan_recv`, `linea_chan_recv_until`, `linea_owner_next`,
`linea_owner_call`'s answer), or keeps them for a task it starts
(`linea_task_start`, whose body crossing is held to [O-Cross] by the
certified `Slot.start`).

[T-RawAddress] accepts a call of `address.raw` in two places: as the argument
for a marked parameter, and as the `at` of a `mem.Closure` construction, the
one type certified to erase what it holds. It refuses one anywhere else, and
it refuses an `extern` whose signature names an `Address`, so no address
reaches C as an integer it may keep. The argument for a marked parameter is a
call of `raw` and nothing else, so the runtime never reads or writes values
at a number no type names; a default the declaration gives the parameter is
such a number too.

The runtime functions of tasks, owning tasks and sessions are declared only
by the standard library module whose types keep what they hand out and take
in ([T-ExternRuntime]): `task` declares the parked thread's and the call
queue's, `session` an endpoint's choice and close, and `mem` the ones that
copy typed bytes. Each row of `runtime_symbols.zig` states which declarations
may name its symbol, as a field with no default, so a symbol added later is
confined or opened by a decision. A row that takes the address of typed bytes
or a callback, or starts a thread, must be confined, which the table's own
test holds. Without this, a module granted `extern` in any root could declare
`linea_owner_free` and free a queue twice, discard what `linea_task_prepare`
answers and leave a parked thread, or close an endpoint it made up: each
number is safe only inside the linear type that holds it. A symbol lowering
replaces is confined to `mem` by the same field.

The other direction is written only by the compiler. A callback the runtime
calls with an address it was given, a task's entry and release, is marked at
that parameter, and the function a program passes for it may declare the
parameter as an `Address[T]`, which crosses as its `UInt64`. The entry the
compiler generates for the callback passes the number on, and MIR verification
holds the entry to the `extern`'s callback type with each newtype read as its
base, so no source form turns a `UInt64` into an `Address`.

`call_owner`'s answer stops travelling as a captured address. The job the
owner runs hands its answer to `linea_owner_answer`, which copies it into the
answer bytes the caller named in `linea_owner_call`; the owner calls
`linea_owner_done` once the job is released, so a call still returns after
everything the job captured is released. A task's release callback
is given the address of the buffer kept after its body, so it takes an
`Address[Buffer[A]]` rather than computing one from the body's.

### 3. The tables follow what a type holds

The writer and `unshareable` tables follow fields, observed referents,
`Address[T]`, certified storage, `Slice`, `Carried` and the callable a
`ClosureEntry` stands for, and no other type argument. A phantom parameter is
otherwise never followed. `mem.Closure` stays certified `@unshareable`, since
it erases a callable that none of its arguments names, and its `settle` field
makes it a writer.

`Owner[S]` holds a queue and a session endpoint, and `Chan[P, H]` an endpoint
number and its body's `Carried[H]`. Neither holds an `S`, so `Client[S]` is
`Shareable` for every `S` an owning task can keep.

## Consequences

- An owning task over unshareable state gives its clients to other tasks.
- A library declaration that erases a value holds an `Address[T]` or a
  `Storage[T, A]` naming it, and the tables count it from that field. A
  declaration added later is covered without anyone remembering it, because a
  `UInt64` cannot reach a slot.
- Every runtime symbol that takes an address of typed bytes carries a mark,
  and every symbol states which declarations may name it.
- What stays trusted to `std.mem`: which `T` an address of a buffer names
  (`address_in` gives one for any `T`), that the storage a slot is reached
  through is the one that owns its bytes, that a callback names the `T` the
  address handed to it was made with, and that a closure's `at` is its
  storage's. Each is reachable only from the library's raw layer, which no
  other module can call, and an address a mistake there forges still names
  the type its holder is counted for.
- `std.mem`'s raw layer is written over `Address[T]`, and the slot primitives
  lose their address and extent arguments. The runtime's `linea_task_start`
  and `linea_owner_call` take the addresses they hand on, and
  `linea_owner_answer` copies an answer apart from `linea_owner_done`.
- [T-RawAddress] at a use binds only code that can name `address.raw`, which
  is internal to the standard library, so its cases are the checker's own; at
  a declaration it binds any module granted `extern`, and the corpus holds
  that case.
- The soundness matrix meets a scalar's assignments with a closure lent
  `inout` kept in a vector, whose type names it only through its storage, and
  erased into a `mem.Closure`, whose type names it not at all.

## Alternatives considered

- **A certificate for `task.Owner` and `Client` alone:** fixes one type and
  leaves every other erasing declaration trusted.
- **Restricting who calls a task symbol rather than who declares it**, as
  [T-ThreadStart] does for `linea_task_start`: it needs a certified caller per
  symbol, while the module that declares an `extern` already bounds who calls
  it, since an `extern` is private to its module.
- **Parameters marked `erased`:** the leak is an address flowing as a number,
  which a parameter mark does not see, so the mark would be trusted rather
  than checked.
- **Typestate on `Storage` (full or empty):** `Vec` keeps many slots in one
  storage, live and dead, so fullness is not a property of the storage, and
  the hand-off inside `call_owner` crosses a closure the analysis cannot
  follow.
- **`Address[T]` as a one-field struct:** a struct is passed by address, so a
  callback the runtime calls with a number could not declare one; a generic
  newtype is the number.
- **Generated thunks for a task's entry and release:** moves `run_body` into
  lowering for no gain, since the entry C calls is already generated.
