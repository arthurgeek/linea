# 255. An erased value is reached through an address that names its type

Status: Accepted — 2026-11-01. Supersedes the clause of
[0193](0193-a-closure-may-hold-a-place-lent-inout.md) that has writer
containment follow every type argument, the clause of
[0250](0250-tasks-are-structured-through-linear-sessions.md) that has the
`Shareable` table do the same, the clause of
[0171](0171-the-standard-library-is-an-ordinary-library.md) that lets a
granted root call the runtime's functions directly, and the clauses of
[0197](0197-a-checking-runtime-makes-a-use-of-freed-storage-abort.md) that let
a root granted `extern` hold an address, keep corpus cases that reach freed
storage through the runtime, and pass over a case recording a storage report;
extends [0254](0254-a-newtype-takes-type-parameters.md).

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

A runtime function that takes or answers a number something must own is
declared only by the standard library module whose types keep that number
([T-ExternRuntime]). `task` declares the parked thread's and the call queue's,
`session` an endpoint's choice and close, and `mem` the ones that copy typed
bytes. The same holds for the allocator and every descriptor and byte the
runtime is handed: `mem` declares `linea_alloc` and `linea_free`, whose
allocation a linear `Buffer` owns; `linea_close` and every call that reads,
writes, opens or names a file through a descriptor or an address of bytes
(`linea_read_some`, `linea_write_some`, `linea_read_at`, `linea_write_at`,
`linea_open_parent`, `linea_open_at`, `linea_mode_at`, `linea_publish_at`,
`linea_unlink_at`, `linea_random_bytes`); the decimal parsers
`linea_float64_parse` and `linea_float32_parse`, which read bytes at an
address; and `linea_arg_at` and `linea_env_at`, which answer one. `fs`
declares `linea_set_mode`, and `net` the socket calls, each of which answers or
takes a descriptor a linear `Listener` or `Connection` owns. What stays open to
any granted module neither takes nor answers such a number: argument and
environment counts and lengths, the errno and its category, two random words,
the clocks, and float formatting from bits.

Each row of `runtime_symbols.zig` states which declarations may name its
symbol, as a field with no default, so a symbol added later is confined or
opened by a decision. A parameter is marked as the address of typed bytes, the
address of bytes a buffer or a slice holds, a descriptor or an allocation, and
a result as one of the last three, and a row with any mark, a callback or a
thread start must be confined, which the table's own test holds. Without
this, a module granted `extern` in any root could declare `linea_free` and
free an allocation twice, `linea_close` and close a descriptor the standard
library still owns, `linea_float64_parse` and have the runtime read at a
number no value holds, `linea_owner_free` and free a queue twice, or discard
what `linea_task_prepare` answers and leave a parked thread: each number is
safe only inside the linear type that holds it. Confinement covers the
runtime's own symbols and nothing else, so it is defence in depth rather than
a guarantee: a module granted `extern` can declare the C library's `close` or
`free` itself and misuse a number through it, and no rule refuses that
declaration. What confinement gives is that the runtime's entry points
taking or answering such a number are reached only through the standard
library's checked wrappers. A symbol lowering replaces is
confined to `mem` by the same field.

The addresses of bytes are typed, as the addresses a task hands on are. Every
runtime parameter that is the address of bytes the runtime reads, writes or
frees is marked: `linea_read_some`, `linea_write_some`, `linea_read_at` and
`linea_write_at`'s bytes, `linea_random_bytes`'s, the paths of
`linea_open_parent`, `linea_open_at`, `linea_mode_at`, `linea_unlink_at` and
both of `linea_publish_at`'s, the text of `linea_float64_parse` and
`linea_float32_parse`, and the allocation `linea_free` takes. [T-RawAddress]
then accepts only `address.raw` there, so confinement is not the only bound:
inside `mem`, a number computed beside a buffer cannot reach the runtime
either. The library makes each address from what owns the bytes:
`address_in[UInt8]` from a buffer at an offset it checks against the buffer,
and `slice_address`, a new primitive lowering reads from the slice, from a
slice. `Buffer.at` and `Slice.at` stay `UInt64` fields: the storage primitives
lowering replaces take them, and `std.ffi` lends a slice's address to C and
reads bytes at an address C handed back, which no `Address` names; each of
those accesses is checked against an extent instead. The runtime's sources
name each marked parameter `at`, `from`, `to` or `…_at`, and a test of the
table holds every such name to a mark and every mark to such a name, so a
function added to the runtime cannot take a plain address.

**The standard library is the source the compiler carries ([M-Standard]).**
Confinement names a module of the library, and a root whose manifest names it
`std` is compiled as the library. The name is anyone's to write, so a library
calling itself `std` would be trusted to declare every confined symbol, and
with them to free twice. A root named `std` is therefore the library only
where each file it loads is, byte for byte, the carried copy's file at the
same path; any other file is refused wherever a root is read from disk to be
compiled. A copy of the library's directory
compiles as the library wherever it sits, and an edited copy compiles once
the compiler is built from it.

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
- Every runtime symbol that takes an address of typed bytes or of a buffer's
  bytes, a descriptor or an allocation carries a mark, every symbol states
  which declarations may name it, and every marked symbol is confined. A
  granted module calls the runtime for counts, errno, the clocks and float
  formatting only; anything else goes through the standard library's types.
- No accepted program reaches one of the checking allocator's reports, so no
  corpus case records one. The cases that freed twice and read or wrote freed
  storage through `linea_alloc`, `linea_free`, `linea_write_some` and
  `linea_float64_parse` cannot be written, and the native runtime test holds
  every report instead: a second disposal, a disposal at another size or of no
  allocation, a store beside an allocation, an access past one, a load or
  store of freed storage, and `linea_write_some`, `linea_read_some` and
  `linea_random_bytes` handed freed or overlong bytes. The conformance runner
  fails a case whose golden records such a report and never records one under
  `--update`.
- A standard library edited in place is refused on the command line by a
  compiler built before the edit, until the compiler is built again. An
  editor's in-memory root keeps loading, as it does past a grant naming no
  module, since nothing it holds is built. The transcripts that edited a copy of the library to reach its
  internals are unit tests over library modules built in memory: a storage
  primitive recognised by its signature, and a primitive's methods split
  across inherent blocks. The case of a tag moved into a task beside its
  unshareable log is a program's own types.
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
- **Confinement alone for the addresses of bytes:** only `mem` could pass
  one, but `mem` could still pass any number it computed, so a mistake in the
  library would reach the runtime unchecked.
- **`Buffer.at` and `Slice.at` as `Address` fields:** the storage primitives
  take a plain address, because `std.ffi` reads bytes at addresses C hands
  over, and an arena carves a buffer out of another by arithmetic on its
  address; every one of those would need a primitive of its own, for no check
  the two address-making primitives do not already give.
- **Recognising the standard library by where it sits or by an option:** a
  path is the user's to choose and an option is anyone's to pass, while the
  carried text is fixed when the compiler is built.
- **`Address[T]` as a one-field struct:** a struct is passed by address, so a
  callback the runtime calls with a number could not declare one; a generic
  newtype is the number.
- **Generated thunks for a task's entry and release:** moves `run_body` into
  lowering for no gain, since the entry C calls is already generated.
