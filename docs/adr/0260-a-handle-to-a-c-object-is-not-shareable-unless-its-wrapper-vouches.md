# 260. A handle to a C object is not `Shareable` unless its wrapper vouches

Status: Accepted - 2026-11-07

Extends [0228](0228-a-granted-module-calls-c.md), whose handle predicate it
reads and whose list of what a wrapper vouches for it extends, and
[0250](0250-tasks-are-structured-through-linear-sessions.md), whose
`Shareable` it narrows.

## Context

Linea promises that an accepted program has no data race. Two tasks may read
one value at once when its type is `Shareable` ([O-Cross]), and a type is
`Shareable` unless it reaches a type declared `@unshareable`, a callable that
could be one, or a type parameter not bounded `Shareable`. That rule is about
Linea memory: a read of a value writes nothing unless a module trusted with C
says otherwise with `@unshareable`.

A C object breaks that assumption without anyone writing anything. 0228 keeps
one as a sealed linear newtype over its address:

```linea
@(opaque, linear)
type DatabaseHandle = UInt64

extern fn sqlite3_errmsg(read database: DatabaseHandle) -> ffi.CText where borrows(database)
```

The newtype's base is a `UInt64`, so the handle was `Shareable`, and so was
every record holding one. Two tasks could each hold a `read` of one connection
and call `sqlite3_errmsg` from two threads at once. `read` on an `extern`
parameter promises only that C does not change the object as far as
ownership can see; it says nothing about whether C tolerates two threads.
SQLite rewrites the error sentence on the next call on a connection, many C
libraries keep caches or counters inside an object they hand out by `const`
pointer, and nothing checked which kind a wrapper wraps. The guest book was
safe only because `Book`'s public methods take `inout`, which is a property of
one wrapper's API, not of the language.

A copyable sealed newtype is worse. 0228 made `copyable` the way to say a
sealed type is not a handle, but a wrapper may still pass one to C, and then
every copy names the same C object. Copies cross into tasks whole, through
`Owned` alone, so a rule about readers cannot keep two threads apart: two
tasks each holding a copy of a counter's handle called a non-atomic
`counter_add` and lost updates.

No rule over the program's types can see every C object. A wrapper may keep
an address in a plain integer field of a record and call C with it from a
method that takes the record `read`; telling that number from any other
needs provenance through every local and call in the wrapper, which 0228
declined. So the language can close the shape a wrapper is told to use, and
make the wrapper promise to use it.

## Decision

**The contract.** Safe Linea code cannot violate the lifetime and concurrency
invariants of a correctly implemented foreign wrapper; modules granted
`extern` are trusted to preserve those invariants. The compiler proves what
it can read: who holds a handle, which task reads it, which conventions C
receives a copyable sealed value under. The wrapper promises what only C's
documentation can say: that an object outlives every copy naming it, that
`@shareable` operations are safe under concurrent use, that C keeps or frees
nothing behind an integer it was handed. This is the line Rust draws at an
`unsafe impl Sync`: the author of the implementation vouches, and every
caller relies on it.

| Guarantee | Who keeps it |
| --- | --- |
| Exclusive ownership | the compiler, through linear and affine types |
| Concurrent reads | the compiler through `Shareable`, the wrapper through `@shareable` |
| Lifetime of a C object | ownership of its handle, and the wrapper for copyable values |
| Thread affinity | the wrapper and the program's choice of where a task runs |
| A correct wrapper | the module granted `extern`, which a reviewer reads |

`Shareable` and `@shareable` say only whether two tasks may read at once.
They say nothing about lifetime, and nothing about thread affinity: a value
that is not `Shareable` may still move whole to another task, and
`@shareable` never means a thread-affine object may migrate.

**A wrapper keeps C objects in handles, and the compiler holds handles to
one task at a time.** The innermost handle of
[T-ExternHandle], a newtype that is not `copyable` and is sealed (`@opaque`)
in a module its root's manifest grants `extern`, seeds the `unshareable`
table as a type declared `@unshareable` does. Everything that holds one, a
record, an enum payload, an observation of it, a closure capturing it, a
newtype over it, is unshareable through the containment edges already
followed. So a task's body cannot read a connection its creator may read
([O-Cross]), and a connection does not meet a `Shareable` bound ([T-Bound]).

The rule reads three facts the declaration states and nothing else: that it
is a newtype sealed with `@opaque`, its ownership policy, and that the
manifest grants its module `extern`. `intrinsics.sealedUnderGrant` answers
the first and third, `sealsForeignObject` adds "not `copyable`", and the
[T-ExternHandle] predicate that decides how an `extern` takes a handle calls
the same routine, so the type C lends `read` is exactly the type two tasks may
not read. No type, module or library is named. A wrapper written later is
covered the moment it follows 0228's shape.

**A copyable sealed newtype under a grant is declared only with
`@shareable`** ([T-ExternHandle]). Every copy names whatever the sealed number
names and reaches any task, so the compiler cannot keep its object to one
thread; the wrapper must vouch that C allows it, or drop `copyable` and let
the handle rule above hold. std declares one: `io.core.Descriptor`. POSIX
lets two threads call `read` and `write` on one descriptor at once and keeps
the descriptor's own state consistent; the calls may still interfere in
meaning, two readers consuming different parts of a stream, and whatever owns
the descriptor must keep it open while any copy is used, since a closed number
may be reused. `@shareable` vouches for the first; the second is the owner's
lifetime promise, not something `@shareable` or `read` establishes.

**A copyable sealed newtype crosses to C only `read`, and no `extern`
answers one** ([T-ExternHandle]). Its object must outlive every copy, and
nothing the compiler tracks keeps it alive: a wrapper that took a copyable
handle by value in `counter_close` let a copy read the counter after it was
freed. So an `extern` takes such a newtype, or a newtype wrapped around one,
only as a `read` parameter, which for this type promises that C neither keeps
nor frees the object, and an `extern` answering one is refused, since what C
handed over would have no owner. The same holds at every position a value
crosses: an `extern`'s parameters and its result, the `R` an `ffi.Errno[R]`
answer carries, a callback's parameters (C hands them to Linea) and its
result (Linea hands it to C), and an exported function's parameters and
result. Only a `read` parameter of an `extern` admits one.
`intrinsics.namesCopiedForeignObject` decides the type, from the same three
declaration facts, at any layer of newtypes: a newtype wrapped around a
copyable sealed newtype names the same object, whether the wrapper is sealed
or not, copyable or not, in the same module or another. A linear wrapper
around one does not own the object, since copies of the inner value may
still name it, so it crosses only `read` too. The reverse, a copyable
newtype around a handle, is refused already: a copyable type cannot own a
value that cannot be copied ([O-Universe]).

**The callback context is exempt.** An `extern`'s `inout` context parameter,
the one a callback receives first, may be of a copyable sealed type. C
receives the address of the Linea place that holds the value, never the value
itself, and hands that address back only during the call (0228's promise
that C calls a callback only during the call that passed it). The callback
reads the place through an `inout` parameter, so any copy it makes is a copy
of a value the program already held, under the same lifetime promise as
every other copy. A context retained by C past the call, or used from
another thread, breaks 0228's promise, which no rule over the program's
types can see. A C object that is freed
lives in a non-copyable handle. A copyable sealed newtype fits an object
that outlives every copy by some means the wrapper guarantees: one that lives
as long as the program, a reference count C keeps, or a descriptor its owner
keeps open, as `io.core.Descriptor`'s borrowed descriptors are, which std
never closes through one: a file closes the raw descriptor it owns. A wrapper
that takes the address out of one and frees it through an `extern` taking an
integer breaks that guarantee where the compiler cannot see it; that is the
wrapper's responsibility, as every integer it hands C is.

**What the rule closes, and what it does not.** It closes the canonical shape
0228 prescribes, under one more promise the wrapper makes: every C object
reachable from more than one task, by a read or through a copy, is kept in a
non-copyable handle, or the wrapper vouches that its read paths are safe for
concurrent use. A record
holding an address in a plain integer field, or a granted root keeping C state
in a sealed newtype of a library that is not granted, is outside the rule and
inside that promise. A handle moved whole into another task is accepted, so a
C library whose objects must stay on the thread that created them is not
modelled either. An owning task runs every call against its state on one
thread, which serialises access, but a value made elsewhere and moved in was
created on another thread: a library that needs one thread for creation, use
and destruction is satisfied only when the owning task creates the object
itself, and destroys it before it ends.

**A wrapper vouches with `@shareable`.** A C library that documents an object
as safe for concurrent reads is declared so on the handle:

```linea
@(opaque, linear, shareable)
type Handle = UInt64
```

The compiler believes it, as it believes an `extern` signature. The attribute
lifts only the declaration's own reason: a newtype over a `@shareable`
handle, or a record holding one, is `Shareable` where its other parts are. It
is accepted only where it can mean something, and refused elsewhere by
[S-Entry]: on a struct or an enum (shareable where its parts are), on a newtype
that is not sealed (any module could make one from a number, so it names no
object), on a sealed newtype whose base is not `Shareable` (the type would
stay unshareable, so the mark would change nothing), beside `unshareable`,
or written twice. On a copyable sealed newtype it is required, as above.
Like `@unshareable`, it is declared only in a module the manifest grants
`extern` ([M-Extern]): only code trusted with C can vouch for C.

**The refusal says why and what to do next.** [O-Cross] and [T-Bound] find
the handle over one witness search, the finished typing's
`unshareableWitness`, which walks the edges the `unshareable` table was built
from, so an optional, a vector or a closure holding a counter names the same
handle in both. [O-Cross] says "a `Counter` is not `Shareable`: it reaches a
`counter.Handle`, which names an object C holds", and both helps offer the
edits that answer it: move the value into one task, keep it in an owning task
and hand other tasks its client, or, if the C library guarantees concurrent
access is safe for every operation the wrapper exposes through shared reads,
mark the handle's declaration `@shareable` in that trusted wrapper.

**What a wrapper vouches for**, added to 0228's list:

- every C object reachable from more than one task, by a read or through a
  copy, is kept in a non-copyable handle, or the wrapper vouches that its
  read paths are safe for concurrent use;
- a handle declared `@shareable` names an object that C lets two threads use
  at once through every `extern` the wrapper declares on it, and a copyable
  sealed newtype declared `@shareable` names one that C lets any number of
  threads use at once through every copy, and that is never freed while a
  copy lives: the wrapper never frees it through an address it took out of
  one.

## Consequences

- An owning task is the ordinary way to use a C object from many tasks. Every
  call runs against its state on the owning task's thread, one at a time, so
  C never sees two threads use the object at once, and `task.own(counter)` is
  accepted for an unshareable counter as for an arena. It does not by itself
  satisfy a library that needs creation, use and destruction on one thread;
  the owning task must create the object for that.
- `@shareable` is independent of `copyable`, as `Sync` is of `Copy`: a linear
  `@shareable` handle may be read by two tasks and closed once both have
  joined, which `tests/ffi/a_shareable_c_object_is_read_by_two_tasks` runs.
- **Known over-refusal.** The rule classifies by the declaring module's grant,
  not by what the value names: every non-copyable sealed newtype in a granted
  module is a handle, so a logical token such as
  `@(opaque, linear) type TransactionId = UInt64` there is unshareable, and
  every copyable sealed newtype there must carry `@shareable` even when it is
  a plain number. The conservative default keeps a forgotten handle from
  slipping through. The options, left open: keep the implicit rule; an
  explicit `@foreign` marker on what names a C object; the implicit rule plus
  a narrowly scoped trusted exemption for a value that names nothing, tested
  never to reclassify a real handle; or a separate declaration form for C
  objects.
- A handle moved whole into a task is still accepted: only that task reads it.
  A C library whose objects belong to the thread that made them is not
  modelled; its wrapper keeps them in an owning task.
- The guest book's `Book` and `sqlite.Database` are unshareable, as they
  should be: SQLite's error sentence is per connection, and nothing in the
  wrapper serialises reads. The wrapper writes no `@shareable`.
- `shareable` becomes a reserved word, as `unshareable` is.
- std's `io.core.Descriptor` is `@shareable`, and it is the only declaration
  in std the copyable rule reaches.
- What the compiler believes grows by one sentence per `@shareable`
  declaration, each in a module a reviewer was already told to read.

## Alternatives considered

**A type is not `Shareable` when it appears in an `extern` signature.** That
reads the declaration's use rather than what it is. It misses a handle that a
library declares and a program's own `extern` takes, and it would make an
ordinary record unshareable because some wrapper passes it to C once. The
handle predicate already decides what names a C object; reading a second
answer to that question would put one sentence in two functions.

**Every `@opaque` type in a granted module is unshareable.** Granted modules
hold ordinary types beside their handles; std's `mem` module seals
`Vec` there, and std's runtime records (`task.Owner`,
`session.Chan`) hold their C state in integer fields of records whose
operations take them `inout`, `sink`, or reach a queue built for several
threads. Refusing them all would force `@shareable` onto types that need no
promise, so the attribute would stop meaning one.

**An opaque newtype whose base is an integer or an address.** Close to the
chosen rule, but the base adds nothing: [T-ExternHandle] already treats a
sealed non-copyable newtype of any base as a handle, and two rules about
"what names a C object" would drift.

**A written `Shareable` certificate**, `impl Shareable for Handle`. `Shareable`
is decided by the compiler and an implementation of it is [T-Bound], so the
promise would sit in a form that is refused everywhere else and could be
written away from the declaration it vouches for. An attribute sits on the
handle, beside `@opaque` and `@linear`, where a reviewer reading the wrapper
against its C header looks.

**Refusing every copyable sealed newtype under a grant.** A wrapper would
then lose the plain value it needs for an object C never frees, such as a
borrowed file descriptor, and std's `Descriptor` would have to become a
handle every reader borrows. Holding the copyable type to `read` at the
boundary keeps those uses and refuses only the ones that could free or keep
the object.

**Keeping the rule in the wrapper**, by taking every C call `inout`. That is
what made the guest book safe, and nothing checks it: a wrapper that adds one
`read` method reopens the race.
