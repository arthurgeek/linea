# 89. A from-end index is a value the container interprets

Status: Accepted — 2026-08-16

## Context

`a[^1]` should name the last element. Every language that offers this has to
answer one question first: *where does the length come from?* An index is
written at a site that holds a container and a number, and counting back needs
something the site does not have.

Linea has one place where a length is already known without asking anyone: an
array's length is part of its type. Everything else that holds elements is a
container whose count is its own business, reached through `Index`, whose
bracket is a projection — a path, not code (ADR 0088).

So the mechanism has to be one that works for the array and says something
honest about everything else, without a `len` lang item, a second trait member,
or a compiler-known operation on a marker value.

## Decision

**A from-end index is a value.** `^k` is the short spelling of `FromEnd { k }`,
an ordinary public structure the library declares beside `Index`. It is
constructible, passable and returnable like any other value, and
`Index[FromEnd]` is an ordinary implementation of an ordinary trait.

**The caret is a prefix form valid only where an index is written**, and it
desugars in the checker. The tree keeps `^k` as written, because a formatter
prints back what someone typed; every pass below the checker sees a value of a
declared type and no new form. What it counts by is an ordinary `UInt64`
expression, so `a[^(i + 1)]` needs nothing new.

**The container interprets it, and which containers can is decided by what a
projection's body may hold.** An array's interpretation is provided by the
compiler, as a row of the one implementation relation beside `Index[UInt64]`:
the length is part of the type, so nothing has to be asked for it. A written
container's body is a path, and a path cannot subtract — so a container
interprets `^k` by handing the count on to whatever holds its elements, and the
count is held against the array the path reaches. A container that stores its
elements some other way cannot state the interpretation in this tier at all;
that is a consequence of the structural tier rather than a rule added here.

**`^0` is out of range by definition.** It names the position past the last
element, and a count past the length names one before the first. Where the
count is settled, both are `[T-Index]` where they are written; where it is not,
the count is compared against one and against the length **before anything is
subtracted**, and a failing comparison is the ordinary index trap. The order is
the whole of the overflow story: an unsigned subtraction run first would land a
count past the length back inside the array, at a place nobody named and with
nothing left for a check to notice.

**Which values index an array is stated in the relation and nowhere else.** The
bracket over an array admits an index that is not a whole number exactly where
the compiler provides a row for it, found through the lookup a bound is
discharged through. A row nobody seeded is a bracket nobody can write.

## Consequences

**No new mechanism reaches the backend.** `a[^k]` lowers to a comparison, a
comparison and a subtraction over the array's own address arithmetic. No call,
no descriptor, no runtime helper, and no instruction the language did not have.
A settled count is not that either: it names a place the compiler has worked
out, so it folds to the offset that place has — the same offset the same place
reached by counting up folds to. Which end an index was written from changes
what it costs at run time in neither direction, which is nothing.

**A value that travels is a value that can be wrong somewhere else.** `FromEnd`
is ordinary, so it can be built far from the bracket that uses it, and the
count it holds is then settled nowhere. That bracket is checked when the
program runs, exactly as an index in a `var` is; the settled clause covers what
the caret spells out where a reader can see it.

**The library owns the spelling of the count.** `FromEnd` declares one field,
and the compiler reads it by name where it interprets one. A library that
renamed the field would be a library this compiler does not understand — the
same relationship it already has with `Range`'s ends.

**Ranges will want the same shape.** `a[1..3]` is the existing bracket over the
existing value with `Index[Range[UInt64]]` as its key, which is this record's
mechanism with a different row. Nothing here decides what a range in index
position yields.

**`^k` does not compose into range ends.** `a[^3..^1]` is not decided by this
record: a range's ends are integers, and a count back from the end is not one.
It stays open until a use asks for it.

## Alternatives considered

**Negative indexing** — `a[-1]` for the last element. Rejected on type grounds.
An index is a `UInt64`, and admitting a signed index whose sign flips its
meaning moves the decision to run time: `a[i]` where `i` is `-1` through
arithmetic is either a wrap-around or a from-end index, and nothing at the site
says which. It also spends the one spelling that means *this arithmetic went
wrong* on a legitimate index, which is the opposite of what a language with no
undefined behaviour wants.

**An `end` marker with arithmetic** — `a[end - 1]`. Rejected as more mechanism
for the same power. `end` in bracket position is either compiler magic — a name
that means something only there, with the subtraction understood by the
compiler — or it is a real value with real arithmetic, which needs arithmetic
as traits and an `End` type that subtracts to something a container interprets.
The first is a special form the formatter, the resolver and every editor
grammar have to learn; the second is strictly more machinery than a structure
with one field. `^k` reaches everything either reaches, as a pure desugar to a
value.

**A `len` member on `Index`** — let the site ask the container how many
elements it has and subtract. Rejected: it puts a computation at the site,
which needs the container's count to be a value a projection can produce — and
a projection produces a place, not a value. It also makes every container
implementing `Index` answer a question most of them are asked once, and it
states a length in a second place for the array, whose length is already part
of its type.

**A compiler-provided `Index[FromEnd]` for written containers too** — have the
compiler interpret `FromEnd` for any container by consulting its
`Index[UInt64]` implementation and a length from somewhere. Rejected: there is
no somewhere. The length would have to come from a member the trait does not
declare, and a compiler that guessed one would be deciding what a container
means from the outside.
