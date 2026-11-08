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
the handle rule above hold. std declares one: `io.core.Descriptor`, which is
`@shareable` because each operation on a descriptor is one system call the
kernel completes whole.

**What the rule closes, and what it does not.** It closes the canonical shape
0228 prescribes, under one more promise the wrapper makes: every C object a
read could reach from another thread is kept in a non-copyable handle, or the
wrapper vouches that its read paths are safe for concurrent use. A record
holding an address in a plain integer field, or a granted root keeping C state
in a sealed newtype of a library that is not granted, is outside the rule and
inside that promise. A handle moved whole into another task is accepted, so a
C library whose objects must stay on the thread that created them is not
modelled either; such a wrapper keeps its objects in an owning task.

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
and hand other tasks its client, or, where the C library allows concurrent
reads, declare the handle's declaration `@shareable` in its wrapper.

**What a wrapper vouches for**, added to 0228's list:

- every C object a read could reach from another thread is kept in a
  non-copyable handle, or the wrapper vouches that its read paths are safe for
  concurrent use;
- a handle declared `@shareable` names an object that C lets two threads use
  at once through every `extern` the wrapper declares on it, and a copyable
  sealed newtype declared `@shareable` names one that C lets any number of
  threads use at once through every copy.

## Consequences

- An owning task is the ordinary way to use a C object from many tasks. Its
  state lives on one thread and every call runs there in turn, so C sees one
  thread whatever the library promises, and `task.own(counter)` is accepted
  for an unshareable counter as for an arena.
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

**Keeping the rule in the wrapper**, by taking every C call `inout`. That is
what made the guest book safe, and nothing checks it: a wrapper that adds one
`read` method reopens the race.
