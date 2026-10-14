# Borrowing: using a value you do not own

Every value in Linea has one owner. Give it to something that takes it, and it
is gone from where it was. [Copying, settling and
sealing](04-copying-settling-and-sealing.md) covered that side: moves, copies,
and values that must be settled.

This chapter is about the cases where you want to *look* at a value instead of
taking it, and where something that points at it outlives the expression you
wrote. You met such values in the first chapter: a `Str` points into text, and
a `Slice` points into an array. You met them again in
[Iterating](05-iterating.md), where walking a slice hands out each element as a
view. This chapter adds `borrow T`, a view of any
value, and three words that say where a view points — `borrows`, `carries` and
`retains`. Each word answers the same question:

> If I hand you this, what can you give back that still points into it?

Three lines carry the chapter:

- `read` is a temporary look, at a value for one call or one construct.
- `borrow T` is a view that can last: it can be kept, passed on or returned.
- **Provenance** is what a view depends on, the value it points into. `borrows`,
  `carries` and `retains` say where a call's result points.

You meet these words wherever something outlives the call still pointing at an
argument: a function returning a `Str`, a `mem.Slice[T]` or a `borrow T`; a
view stored in a collection or a struct; an allocator handle handed to a
container; a closure that looks at what it captured, or changes what it was
lent; an `inout` parameter that absorbs one. Plenty of Linea needs none of it,
and where only one answer is possible the compiler fills the clause in for
you — but it is not a corner of the language.

## Reading a value takes nothing

A parameter is read by default. This function looks at a station and returns a
number, and nothing it returns points at anything:

```linea
fn describe(station: Station) -> UInt64 {
    station.samples
}
```

No clause, no ceremony. Most functions look like this.

## Some values point at other values

A few types do not own what they show you:

| Type | What it really is |
| --- | --- |
| `Str` | a view of text that a `String` or the program owns |
| `mem.Slice[T]` | a view of elements that a `Vec` or array owns |
| `borrow T` | a view of any value at all, made with `borrow x` |

A view is cheap to copy and pass around, and it keeps working only as long as
the thing underneath it stays put. Here is a weather station that owns its
name, as a `String`, and a function that hands out a view of it:

```linea
import std.io

@derive(Release)
struct Station {
    name: String,
    samples: UInt64,
}

// The returned view points into the station's own name.
fn label(station: Station) -> Str where borrows(station) {
    station.name.view()
}

fn main() -> Result[UInt8, io.IoError] {
    let name = "Harbour".to_owned() else |_| {
        return .Ok(1)
    }
    let station = Station { name, samples = 2 }
    defer station.release()
    let title = label(station)
    io.println("{title} has {title.length()} letters")?
    .Ok(0)
}
```

```
Harbour has 7 letters
```

`"Harbour".to_owned()` copies the literal into memory the station
owns ([Memory](07-memory.md) covers allocators), and `defer station.release()`
frees it when `main` ends. `title` is a `Str` pointing into the station's name.

Linea is strict about the view outliving its owner. Free the station before the
last use of `title`:

```linea
    let title = label(station)
    // Releasing the station frees the name that `title` points into.
    station.release()
    io.println("{title} has {title.length()} letters")?
```

<!-- guide: unchecked the error an edit of the program above produces -->
```
error[O-Borrow]: this operation invalidates a place that a later observation still needs
  --> station_early.lin:22:5
   |
22 |     station.release()
   |     ^^^^^^^ keep this place available until the last use of its observation
23 |     io.println("{title} has {title.length()} letters")?
   |                  ----- the observation is still used here
```

Read that as: *you are getting rid of the station, but a view into it is still
going to be used further down* — and the second label shows where. Move the
`release` below the last use of `title` — or let `defer` do it, as above — and
it compiles. That is the entire idea; the rest of this chapter is how a
function tells its callers which of these views it hands out.

## `borrow T`: a view of any value

`Str` and `Slice` are views of text and of elements. `borrow T` is the general
case: a view of a whole value of any type `T`, made by writing `borrow` before
a place. Here a function picks the larger of two rooms and returns a view of
it rather than a copy:

```linea
import std.io

@copyable
struct Room {
    name: Str,
    seats: UInt64,
}

// The result is a view of whichever room is larger, not a copy of it.
fn larger(first: Room, second: Room) -> borrow Room where borrows(first, second) {
    if first.seats >= second.seats { borrow first } else { borrow second }
}

fn main() -> Result[UInt8, io.IoError] {
    var hall = Room { name = "hall", seats = 120 }
    let studio = Room { name = "studio", seats = 30 }
    let big = larger(hall, studio)
    // A field is read through the view; `*big` is the whole room it points at.
    let booked = copy(*big)
    io.println("The {big.name} seats {big.seats}.")?
    hall.seats = 100
    io.println("Booked the {booked.name} for {booked.seats}; the hall now seats {hall.seats}.")?
    .Ok(0)
}
```

```
The hall seats 120.
Booked the hall for 120; the hall now seats 100.
```

Reading through a view works like reading the value: `big.name` reads the
field of the room `big` points at. `*big` is the whole room, and
`copy(*big)` copies it into a room of its own, `booked`, which is why
changing `hall` afterwards is fine.

`copy(big)`, without the `*`, copies the *view*: you get a second view of the
same room, not a second room. Then `booked` still points at `hall`, and the
change is refused:

<!-- guide: unchecked the error an edit of the program above produces -->
```
error[O-Borrow]: this operation invalidates a place that a later observation still needs
  --> rooms_view_copy.lin:21:5
   |
21 |     hall.seats = 100
   |     ^^^^^^^^^^ keep this place available until the last use of its observation
22 |     io.println("Booked the {booked.name} for {booked.seats}; the hall now seats {hall.seats}.")?
   |                             ----------- the observation is still used here
```

The same protection covers `big` itself. Change `hall` before `big` is read,
with `hall.seats = 90` just above the first `println`:

<!-- guide: unchecked the error an edit of the program above produces -->
```
error[O-Borrow]: this operation invalidates a place that a later observation still needs
  --> rooms_change.lin:20:5
   |
20 |     hall.seats = 90
   |     ^^^^^^^^^^ keep this place available until the last use of its observation
21 |     io.println("The {big.name} seats {big.seats}.")?
   |                      -------- the observation is still used here
```

And a view is for reading. Assigning through it, `big.seats = 100`, is refused
even when `big` is a `var`:

<!-- guide: unchecked the error an edit of the program above produces -->
```
error[N-Immutable]: an observation grants read-only access to its place
  --> rooms_write_var.lin:21:5
   |
21 |     big.seats = 100
   |     ^^^^^^^^^ this place cannot be assigned
```

### `read` or `borrow`?

Both words look at a value without taking it. They differ in how long the look
lasts.

**`read` looks for as long as one call or one construct runs.** It is the
convention a parameter has by default, and the one `for read`, `match read`
and `let read` ask for. The callee looks at the caller's value where it is,
and the look ends when the call returns, so nothing needs a clause and the
caller may change the value straight away:

```linea
import std.io

@copyable
struct Room {
    name: Str,
    seats: UInt64,
}

// `room` is read: the function looks at the caller's room during the call,
// and the number it answers points at nothing.
fn seats_free(room: Room, booked: UInt64) -> UInt64 {
    if booked >= room.seats { 0 } else { room.seats - booked }
}

fn main() -> Result[UInt8, io.IoError] {
    var hall = Room { name = "hall", seats = 120 }
    let free = seats_free(hall, 95)
    // The look ended with the call, so the hall may change straight away.
    hall.seats = 100
    io.println("{free} seats were free; the {hall.name} now seats {hall.seats}.")?
    .Ok(0)
}
```

```
25 seats were free; the hall now seats 100.
```

**`borrow` makes a view that is a value of its own.** `borrow T` is a type, so
a view of that type can outlive the call that made it. Write it when a view has
to last longer than one call:

- **returning it**, as `larger` does, or as an `Option[borrow T]` when there may
  be nothing to return;
- **storing it**, in a struct field or a `Vec`.

Both appear here: a search that answers a view of the room it found, and a
booking that keeps that view. `find_room` takes a `mem.Slice[Room]`, a view of
rooms; `Slice` lives in `std.mem`, so it is written with the module's name:

```linea
import std.io
import std.mem

@copyable
struct Room {
    name: Str,
    seats: UInt64,
}

// Answer a view of the first room with enough seats, or `.None`. The view
// points into whatever `rooms` points into, which `carries(rooms)` says.
fn find_room(rooms: mem.Slice[Room], guests: UInt64) -> Option[borrow Room] where carries(rooms) {
    // A plain `for` takes what it walks, so it walks a copy of the view.
    for room in copy(rooms) {
        if room.seats >= guests {
            return .Some(room)
        }
    }
    .None
}

// A booking keeps a view of its room rather than a copy of it.
struct Booking {
    guest: Str,
    room: borrow Room,
}

fn main() -> Result[UInt8, io.IoError] {
    let rooms = [Room { name = "studio", seats = 30 }, Room { name = "hall", seats = 120 }]
    let found = find_room(rooms.as_slice(), 80) else {
        io.println("No room is large enough.")?
        return .Ok(1)
    }
    let booking = Booking { guest = "Ada", room = found }
    io.println("{booking.guest} has the {booking.room.name}, with {booking.room.seats} seats.")?
    .Ok(0)
}
```

```
Ada has the hall, with 120 seats.
```

A slice is walked with a plain `for`, which takes it and hands out a view of
each element; `for read` is for collections that own their elements, such as
an array. `rooms` is only lent to `find_room`, so walking it directly would
take what the function was lent:

<!-- guide: unchecked the error an edit of the program above produces -->
```
error[O-Move]: `rooms` is lent, and this takes it
  --> rooms_lent.lin:14:17
   |
14 |     for room in rooms {
   |                 ^^^^^ `copy` it, or declare the parameter `sink` to take it
```

`copy(rooms)` is the way out. Copying a slice copies the view, never the rooms
it points at, and the loop takes that copy.

`borrow T` is Rust's `&T`, with the same rules — any number of readers, and no
change while a view is still to be used — and without a lifetime to write.
`find_room` says where its answer points with a clause, `carries(rooms)`,
instead of a `'a`. The next sections explain the clauses.

## `borrows` — my result points into what you gave me

Look again at `label`:

```linea
// The returned view points into the station's own name.
fn label(station: Station) -> Str where borrows(station) {
    station.name.view()
}
```

`where borrows(station)` is a promise to the caller: *the `Str` you get back
points into the station you passed me.* That is what let the compiler catch the
early `release` — it never looked inside `label` to work it out, it just read
the signature.

This one is always written out. Linea will not decide on its own that your
value has to stay put — that is the caller's business, so it belongs in the
signature the caller reads. Leave it off and the function does not compile,
which the section on forgetting a clause shows.

When more than one parameter could be the source, the compiler says so in its
own words. `preferred` works with text from any allocator, so it is generic
over `A: Allocator`, and `String[A]` is text allocated from an `A`;
[Memory](07-memory.md#an-allocator-is-an-argument) explains allocators:

```linea
import std.io

fn preferred[A: Allocator](primary: String[A], fallback: String[A], use_primary: Bool) -> Str {
    if use_primary { primary.view() } else { fallback.view() }
}

fn main() -> Result[UInt8, io.IoError] {
    let home = "home".to_owned() else |_| {
        return .Ok(1)
    }
    defer home.release()
    let work = "work".to_owned() else |_| {
        return .Ok(1)
    }
    defer work.release()
    io.println("{preferred(home, work, true)}")?
    .Ok(0)
}
```

```
error[T-BorrowContract]: the result has more than one eligible observation source
 --> preferred.lin:3:4
  |
3 | fn preferred[A: Allocator](primary: String[A], fallback: String[A], use_primary: Bool) -> Str {
  |    ^^^^^^^^^ the result may borrow from `primary` or `fallback`; add `where borrows(primary)` or `where borrows(fallback)`, or list several sources in one clause
```

The fix is to say both: `where borrows(primary, fallback)`. The program then
prints `home`, and callers know the result might point into either, so both
stay put while it is alive. `larger` above says the same about its two rooms.

A clause can name several sources like that, and `borrows` can also be written
on a parameter's field — `borrows(station.name)` — when only part of what you
were handed is involved.

## `carries` — my result points wherever yours pointed

Now the case that trips people up. What if the thing you were handed is
*already* a view?

```linea
import std.io

// The result points wherever `line` already pointed, not at `line` itself.
fn first_field(line: Str) -> Option[Str] where carries(.Some: line) {
    line.slice(0, 4)
}

fn main() -> Result[UInt8, io.IoError] {
    let record = "2026-09-25,sunny"
    let year = first_field(record) else {
        return .Ok(1)
    }
    io.println("year {year}")?
    .Ok(0)
}
```

```
year 2026
```

`line` is a `Str` — it does not own its text; something else does. So the
shorter `Str` coming back does not point at `line`. It points at whatever
`line` was pointing at. `carries` is the word for that, and it is why you can
pass views around freely while the original text stays pinned. `find_room`
above carries its slice the same way.

The difference in one line:

- **`borrows(x)`** — my result points **at x**.
- **`carries(x)`** — my result points **wherever x pointed**.

If a function depends on nothing at all, say so with an empty `carries()`. It
means "my result is yours outright", and stops Linea inferring a source.

## `retains` — I am putting it inside something of yours

The third situation is storing a view rather than returning it:

```linea
import std.io
import std.mem

// `seen` may afterwards depend on whatever `field` depended on.
fn remember(inout seen: Vec[Str], sink field: Str) -> Result[(), mem.Oom]
    where retains(seen: field)
{
    &seen.push(field).settled()
}

fn main() -> Result[UInt8, io.IoError] {
    let record = "north,south,east"
    defer var seen: Vec[Str] = Vec.new()
    let parts = [record.slice(0, 5).unwrap(), record.slice(12, 16).unwrap()]
    for part in parts {
        if remember(&seen, part).is_err() {
            return .Ok(1)
        }
    }
    io.println("remembered {seen.length()} fields")?
    .Ok(0)
}
```

```
remembered 2 fields
```

`retains(seen: field)` reads *after this call, `seen` may point at whatever
`field` pointed at*. The vector now holds a view, so whatever that view points
into has to stay alive as long as the vector does — and because the signature
says it, every caller is held to it. `Vec.push` itself declares
`retains(self: value)`, which is how `remember` knows the vector now holds the
field, and `settled()` turns a refused push into its reason
([Errors](03-errors.md#failures-that-hand-a-value-back)).

There are two forms, and the `borrow` is the difference. It does not change
what the function does — it changes what the caller may do afterwards. Here a
dashboard shows one room through a view, and it can get that view in two ways:

```linea
import std.io

@copyable
struct Room {
    name: Str,
    seats: UInt64,
}

// A dashboard shows one room, through a view.
struct Dashboard {
    shown: borrow Room,
}

// The dashboard takes over a view the caller already holds, so it shows
// whatever `room` points at.
fn show(inout dashboard: Dashboard, sink room: borrow Room) where retains(dashboard.shown: room) {
    dashboard.shown = room
}

// The dashboard watches the caller's own `room` variable.
fn watch(inout dashboard: Dashboard, room: Room) where retains(dashboard.shown: borrow room) {
    dashboard.shown = borrow room
}

fn main() -> Result[UInt8, io.IoError] {
    var hall = Room { name = "hall", seats = 120 }
    let studio = Room { name = "studio", seats = 30 }
    let lobby = Room { name = "lobby", seats = 0 }
    var dashboard = Dashboard { shown = borrow lobby }

    var selected = borrow hall
    show(&dashboard, selected)
    // Pointing `selected` at another room is allowed: the dashboard never
    // looked at `selected` itself, only at the hall it pointed to.
    selected = borrow studio
    io.println("showing the {dashboard.shown.name}, selected the {selected.name}")?

    var stage = Room { name = "stage", seats = 60 }
    watch(&dashboard, stage)
    io.println("showing the {dashboard.shown.name}")?
    // The dashboard is not used again, so both rooms may change now.
    hall.name = "great hall"
    stage.seats = 80
    io.println("renamed the {hall.name}; the stage now seats {stage.seats}")?
    .Ok(0)
}
```

```
showing the hall, selected the studio
showing the stage
renamed the great hall; the stage now seats 80
```

Without `borrow`, as in `show`, the dashboard takes over a view the caller
already holds, and inherits whatever that view points at. `selected` itself is
not observed, so the caller can point it at another room, as
`selected = borrow studio` does. The hall it pointed *into* is what has to stay
put. Rename the hall while the dashboard still shows it:

```linea
    selected = borrow studio
    // Renaming the hall is refused, because the dashboard shows it.
    hall.name = "great hall"
    io.println("showing the {dashboard.shown.name}, selected the {selected.name}")?
```

<!-- guide: unchecked the error an edit of the program above produces -->
```
error[O-Borrow]: this operation invalidates a place that a later observation still needs
  --> dashboard_rename.lin:37:5
   |
37 |     hall.name = "great hall"
   |     ^^^^^^^^^ keep this place available until the last use of its observation
38 |     io.println("showing the {dashboard.shown.name}, selected the {selected.name}")?
   |                              -------------------- the observation is still used here
```

With `borrow`, as in `watch`, the dashboard observes the caller's own variable,
so `stage` is the one that freezes:

```linea
    watch(&dashboard, stage)
    // Changing the stage is refused, because the dashboard watches `stage` itself.
    stage.seats = 80
    io.println("showing the {dashboard.shown.name}")?
```

<!-- guide: unchecked the error an edit of the program above produces -->
```
error[O-Borrow]: this operation invalidates a place that a later observation still needs
  --> dashboard_stage.lin:41:5
   |
41 |     stage.seats = 80
   |     ^^^^^^^^^^^ keep this place available until the last use of its observation
42 |     io.println("showing the {dashboard.shown.name}")?
   |                              -------------------- the observation is still used here
```

Both refusals are `[O-Borrow]`, on the assignment rather than on the call: the
call was allowed, and it is the later change that the dashboard cannot
survive. Once the dashboard's last use has passed, both changes are fine,
which is why the full program ends by renaming the hall and adding seats to
the stage.

So reach for the plain form when you are passing views along — a `Str` into a
`Vec[Str]` inherits the text's owner, which is `remember` above — and for
`borrow` when the destination is meant to watch a caller's variable itself.

## What happens if you forget one

Three different things, and the difference tells you what the clauses are for.

**Forget `borrows`** and the function does not compile. Observing a caller's
value is never inferred, not even when there is only one parameter it could
mean. Take the clause off `label`:

```linea
fn label(station: Station) -> Str {
    station.name.view()
}
```

<!-- guide: unchecked the error an edit of the program above produces -->
```
error[O-Escapes]: this boundary carries an observation from an owner its signature does not permit
  --> station_noclause.lin:12:5
   |
12 |     station.name.view()
   |     ^^^^^^^^^^^^^^^^^^^ escape observations only from the signature's declared sources
```

The body is fine; what it hands back is a view of the station, and the
signature does not admit that.

**Forget `retains`** and the same thing happens where the function stores the
view. Delete the `where retains(seen: field)` line from `remember`:

<!-- guide: unchecked the error an edit of the program above produces -->
```
error[O-Escapes]: this boundary carries an observation from an owner its signature does not permit
 --> remember_noclause.lin:7:5
  |
7 |     &seen.push(field).settled()
  |     ^^^^^^^^^^^^^^^^^ escape observations only from the signature's declared sources
```

**Forget `carries`** and it compiles, because with one possible source Linea
infers it. Take the clause off `first_field` and the program still prints
`year 2026`.

With more than one source, it refuses to guess and you get the
`[T-BorrowContract]` from earlier in this chapter, unless one of the sources is
a type that has declared itself a carrier of its values' dependencies, which
settles the choice (see "A type can say where its values point" below). With none — a `Str` built
from a literal, whose bytes are in the program rather than in any owner — there
is nothing to carry and nothing to declare.

An inferred clause is not a weaker clause. It is part of the signature, and
callers are held to it exactly as if you had typed it. Nothing below mentions
a clause anywhere, and the compiler still refuses:

```linea
import std.io

// No clause: with one possible source, Linea infers `carries(line)`.
fn shortened(line: Str) -> Option[Str] {
    line.slice(0, 4)
}

fn main() -> Result[UInt8, io.IoError] {
    let name = "Harbour".to_owned() else |_| {
        return .Ok(1)
    }
    match shortened(name.view()) {
        Some(head) => {
            // Releasing the name frees the text that `head` points into.
            name.release()
            io.println("{head.length()}")?
        },
        None => name.release(),
    }
    .Ok(0)
}
```

```
error[O-Borrow]: this operation invalidates a place that a later observation still needs
  --> shortened.lin:15:13
   |
15 |             name.release()
   |             ^^^^ keep this place available until the last use of its observation
16 |             io.println("{head.length()}")?
   |                          ---- the observation is still used here
```

Inference only ever moves in the safe direction. It can add a dependency the
result might not really have — pinning something a moment longer than needed —
but it never concludes that a result is independent. That conclusion has to be
written by hand, as `carries()`, precisely because it is the one that lets a
caller reuse its storage.

The line between them is what the clause costs the *caller*. `borrows` and
`retains` create a new obligation — something of the caller's has to stay put
— so Linea will not take that on without the signature saying so, where anyone
calling the function can read it. `carries` imposes nothing new: whatever that
view pointed at was already pinned before the call. So it can be inferred, and
you write it when you want to be explicit, when you are targeting one part of
the result, or when Linea says the choice is ambiguous.

## A trait writes the clause once

A trait's signature can carry a clause, and every implementation adopts it.
The implementation writes no clause of its own:

```linea
import std.io

trait Labelled {
    fn label(self: Self) -> Str where borrows(self)
}

@derive(Release)
struct Station {
    name: String,
    samples: UInt64,
}

// No clause here: the implementation adopts `borrows(self)` from the trait.
impl Labelled for Station {
    fn label(self: Self) -> Str {
        self.name.view()
    }
}

fn main() -> Result[UInt8, io.IoError] {
    let name = "Harbour".to_owned() else |_| {
        return .Ok(1)
    }
    defer let station = Station { name, samples = 2 }
    io.println("{station.label()} has {station.samples} samples")?
    .Ok(0)
}
```

```
Harbour has 2 samples
```

`Labelled.label` promises `borrows(self)`, so `Station`'s `label` is checked
against that promise, and every caller of `station.label()` is held to it:
releasing the station before the label's last use is the same `[O-Borrow]` as
before. The clause lives in one place, the trait, however many types implement
it. This is how `std.http`'s `Handler` trait and the `Writer` trait state their
contracts once for every implementation.

When the trait's signature promises less than an implementation needs, the
error names the trait's contract. Drop the clause from the trait, so it infers
`carries(self)`:

<!-- guide: unchecked the error an edit of the program above produces -->
```
error[O-Escapes]: this boundary carries an observation from an owner its signature does not permit
  --> labelled_trait_noclause.lin:17:9
   |
5  |     fn label(self: Self) -> Str
   |        ----- this implementation adopts `Labelled.label`'s `where carries(self)`
17 |         self.name.view()
   |         ^^^^^^^^^^^^^^^^ escape observations only from the signature's declared sources
```

An implementation may still write a clause, as long as it promises no more
than the trait's; callers read the trait's either way.

## A type can say where its values point

Some types exist to be the thing other values hang off. A web server's request
holds the text of the request, and almost everything a handler builds — the
name it read from a header, the page it answers with — points into it. Writing
`where carries(request)` on every one of those handlers says the same thing
each time.

A type can say it once. Mark it with `@carrier`:

```linea
import std.io

@carrier
struct Session {
    user: Str,
}

fn account_for(session: Session, role: Str) -> Str {
    if role.length() > 0 {
        copy(session.user)
    } else {
        "guest"
    }
}

fn main() -> UInt8 {
    let session = Session { user = "ada" }
    let _printed = io.println(account_for(session, "admin"))
    0
}
```

```
ada
```

`account_for` has two parameters that could be where its result points, and
without the mark Linea would refuse to guess, as in the `[T-BorrowContract]`
earlier in this chapter. Because `Session` is a carrier, it breaks the tie: `account_for` means
exactly what `where carries(session)` would mean. A callable type has the same
contract wherever it is written, so a function of this shape can stand where
`fn(session: Session, role: Str) -> Str where carries(session)` is asked for.

The carrier only settles a choice among several sources. It applies to a
signature that writes no clause, only when exactly one parameter is a carrier,
and never when there is a single source anyway or when the result is a
`borrow` of another parameter's type, since that names where it comes from. It
counts a parameter of any convention (`read`, `inout` or `sink`) and any
instance of a generic carrier, so `Request[P]` is a carrier for every `P`.

**The type supplies the common default; the function supplies the exceptional
provenance.** When a function's result comes from somewhere else, it says so
with a clause, and a written clause always wins:

```linea
import std.io

@carrier
struct Session {
    user: Str,
}

fn choose(session: Session, fallback: Str) -> Str where carries(fallback) {
    if session.user.length() > 0 {
        copy(fallback)
    } else {
        copy(fallback)
    }
}

fn main() -> UInt8 {
    let session = Session { user = "ada" }
    let _printed = io.println(choose(session, "guest"))
    0
}
```

```
guest
```

The default never hides where a value really comes from. Take the clause off
`choose` and the function is held to `carries(session)`, which the body does not
keep:

```linea
@carrier
struct Session {
    user: Str,
}

fn choose(session: Session, fallback: Str) -> Str {
    if session.user.length() > 0 {
        copy(fallback)
    } else {
        copy(fallback)
    }
}

fn main() -> UInt8 {
    let session = Session { user = "ada" }
    let _chosen = choose(session, "guest")
    0
}
```

```
error[O-Escapes]: this boundary carries an observation from an owner its signature does not permit
  --> main.lin:10:9
   |
10 |         copy(fallback)
   |         ^^^^^^^^^^^^^^ escape observations only from the signature's declared sources
   |
   = help: `session` is a carrier and this signature writes no clause, so its contract is `where carries(session)`
   = help: the value comes from `fallback`; write `where carries(fallback)` to say so
```

The report names the carrier that supplied the contract and the clause that says
what the body does. Nothing is worked out again from the body: the signature
means the same thing for a caller that cannot see it.

A function with two carriers has no default, because there is nobody to choose.
Linea asks you to:

```linea
@carrier
struct Session {
    user: Str,
}

@carrier
struct Visit {
    page: Str,
}

fn describe(session: Session, visit: Visit) -> Str {
    if visit.page.length() > 0 {
        copy(session.user)
    } else {
        copy(session.user)
    }
}

fn main() -> UInt8 {
    let session = Session { user = "ada" }
    let visit = Visit { page = "/" }
    let _described = describe(session, visit)
    0
}
```

```
error[T-BorrowContract]: the result has more than one eligible observation source, and several parameters are carriers
  --> main.lin:11:4
   |
11 | fn describe(session: Session, visit: Visit) -> Str {
   |    ^^^^^^^^ `session` and `visit` are carriers, so none is the default source; add `where carries(session)` or `where carries(visit)`, or list several sources in one clause
```

Only a struct or an enum can be a carrier. `http.Request` is one, which is why
the handlers in [Networking](09-networking.md) take a request and an extractor
and write no clause.

If you know Rust, this is close to lifetime elision. Rust fills in an omitted
lifetime from a rule about the parameters (a single input lifetime, or `&self`);
Linea fills in an omitted contract from a mark on the type, and the mark is
written once where the type is declared, not guessed from each signature.

## Saying that only part of the result points at it

Look again at `first_field`:

```linea
fn first_field(line: Str) -> Option[Str] where carries(.Some: line)
```

The `.Some:` prefix narrows the promise to one part of the result. A `.None`
points at nothing, so there is no reason to pin anything when the answer comes
back empty. The same trick separates success from failure:

```linea
where borrows(.Ok: self), carries(.Err.Input.reason: self.reader)
```

The success is a view into `self`; the error is not. A caller handling the
error path is free to touch `self` again straight away.

## Closures look too

A closure that captures with `[name]` holds a view of that value, exactly as a
`borrow` would, so everything in this chapter applies to it: the captured value
must stay as it is while the closure is still going to be called. [Calling
things](02-calling-things.md#why-captures-are-written-out) showed the
`[O-Borrow]` that guards it. A closure that captures with `sink` owns what it
captured and points at nothing of yours. [Memory](07-memory.md#keeping-a-closure-memclosure)
shows how a closure kept for later carries these views with it.

## A closure that lends a variable

`[inout name]` lends one of your variables to a closure to change ([Calling
things](02-calling-things.md#a-closure-that-changes-a-value-of-yours)). The
lend lasts as long as the closure, or anything holding the closure, is still
going to be used. A lazy `filter` holds its predicate, so a predicate lent a
counter keeps the counter until the chain is walked:

```linea
import std.io

fn main() -> Result[UInt8, io.IoError] {
    let arrivals = [UInt64(1200), 3500, 6400, 5000, 900]
    let limit = 5000
    var inspected = 0
    // The filter counts every parcel it looks at in `inspected`, which the
    // closure is lent until the chain's last use.
    let accepted = arrivals
        .as_slice()
        .filter(inout [limit, inout inspected] |parcel| {
            inspected += 1
            *parcel <= limit
        })
    let shipped = accepted.fold(0, |sink grams, sink parcel| grams + *parcel)
    io.println("{shipped} grams shipped; {inspected} parcels inspected")?
    .Ok(0)
}
```

```
10600 grams shipped; 5 parcels inspected
```

`fold` walks the chain and is its last use, so `inspected` is `main`'s again
on the next line. Before that, it belongs to the closure: reading it, changing
it or lending it again is `[O-Borrow]`. Ask for the count before the chain is
walked:

An operation that walks at once, such as `fold`, `for_each`, `any` or `find`,
takes such a closure too, and the lend ends when the call returns:

```linea
var inspected = UInt64(0)
let heavy = arrivals.any(inout [limit, inout inspected] |sink parcel| {
    inspected += 1
    *parcel > limit
})
```

```linea
    io.println("{inspected} parcels inspected so far")?
    let shipped = accepted.fold(0, |sink grams, sink parcel| grams + *parcel)
```

<!-- guide: unchecked the error an edit of the program above produces -->
```
error[O-Borrow]: this operation uses a place lent `inout` to a value that is still used
  --> inspected_early.lin:15:18
   |
11 |         .filter(inout [limit, inout inspected] |parcel| {
   |                                     --------- lent `inout` here
15 |     io.println("{inspected} parcels inspected so far")?
   |                  ^^^^^^^^^ this uses the place while it is lent
16 |     let shipped = accepted.fold(0, |sink grams, sink parcel| grams + *parcel)
   |                   -------- a value holding the lend is still used here
   |
   = help: a place lent `inout` is reached only through what holds the lend until that value's last use; use it after that, or through the closure
```

The lend cannot leave the function that made it, either: a value holding it
cannot be returned, and [Memory](07-memory.md#a-kept-closure-is-settled-like-its-allocators-memory)
shows the error when a function tries to keep such a closure for its caller.

What the chain hands out holds only a read of the count, because nothing in
it can change the count. So a vector of weights collected from the filter
leaves `inspected` readable while the vector is in use, and refuses only a
change to `inspected` until the vector's last use:

```linea
import std.io

fn main() -> Result[UInt8, io.IoError] {
    let arrivals = [UInt64(1200), 3500, 6400, 5000, 900]
    let limit = 5000
    var inspected = 0
    // `kept` holds views of the accepted weights, taken through the filter.
    let { values: kept, iterator: _ } = arrivals
        .as_slice()
        .filter(inout [limit, inout inspected] |parcel| {
            inspected += 1
            *parcel <= limit
        })
        .collect()
        .settled() else |_| {
        return .Ok(1)
    }
    defer kept.release()
    io.println("{kept.length()} parcels kept; {inspected} parcels inspected")?
    // Resetting the count is refused while `kept` is still going to be used.
    inspected = 0
    io.println("{kept.length()} parcels to ship")?
    .Ok(0)
}
```

```
error[O-Borrow]: this operation invalidates a place that a later observation still needs
  --> kept_weights.lin:21:5
   |
21 |     inspected = 0
   |     ^^^^^^^^^ keep this place available until the last use of its observation
22 |     io.println("{kept.length()} parcels to ship")?
   |                  ---- the observation is still used here
```

The first `println` reads `inspected` while `kept` is alive, and that is fine.
Move `inspected = 0` below the last use of `kept` and the program compiles.

## If you know Rust

Linea relates a result to an argument by naming the parameter:

```linea
fn label(station: Station) -> Str where borrows(station)
```

Rust says the same thing with a lifetime variable:

```rust
fn label<'a>(station: &'a Station) -> &'a str
```

This is borrow checking without lifetime annotations. There are no variables to
name, quantify or thread through a struct — a clause names a parameter and its
fields, and that is the whole vocabulary. Rust's elision rules, which let you
leave `'a` out when there is only one candidate, match Linea's inference: leave
the clause out and it is filled in, unless more than one parameter could be the
answer.

The one distinction Rust does not have to make is `borrows` against `carries`.
In Rust, `&'a str` carries its lifetime in its type. In Linea, `Str` is
an ordinary value that happens to point elsewhere, so a signature has two
different things to say about it — *my result points at the value you gave me*,
and *my result points wherever your value pointed* — and those are the two
words. Where Rust writes a struct holding `&'a T` and threads `'a` through every
`impl`, Linea writes `retains(dest: source)` on the one function that does the
storing.

Errors line up too: `[O-Borrow]` is *cannot borrow while borrowed* and
*does not live long enough*; `[O-Escapes]` is the one about returning a
reference to a local.

## The three errors you will see

| Error | What it is telling you | What usually fixes it |
| --- | --- | --- |
| `O-Borrow` | Something was released, moved or changed while a view of it was still going to be used | Move the release or the change below the view's last use, which the error's second label points at |
| `O-Escapes` | A view is leaving the function, but the signature does not allow it to point where it points | Add the clause naming the real source — or return an owned value instead |
| `T-BorrowContract` | The clause itself does not work: a name that is not a parameter, a destination that is not `inout`, or a source Linea will not guess | Name the source explicitly |

`O-Escapes` most often means you returned a view of something the function
itself owns. No clause can save that — the value is freed when the function
ends, so the caller would get a view of nothing. Return something owned
instead, with `to_owned(allocator)` on text, or take the storage as a parameter
so the caller owns it.

## Questions to ask about any value

When you write a type or a function, a short list of questions decides most of
what you write. Each one has been answered in a chapter of this guide:

| Question | Answer | Chapter |
| --- | --- | --- |
| Who owns it? | the binding that holds it, until it is moved | [Copying, settling and sealing](04-copying-settling-and-sealing.md) |
| May I copy it? | only if the type is `@copyable`, with `copy(x)` | [Copying, settling and sealing](04-copying-settling-and-sealing.md#copyable-values-that-are-safe-to-duplicate) |
| May I drop it? | only if it is Discardable: not linear, and nothing it holds must be settled | [Copying, settling and sealing](04-copying-settling-and-sealing.md) |
| Must I consume it? | if it is linear, or holds something that is, exactly once | [Copying, settling and sealing](04-copying-settling-and-sealing.md#linear-values-you-must-not-forget) |
| Do I look, change or take? | `read`, `inout` or `sink` | [Linea in an hour](01-linea-in-an-hour.md#read-inout-and-sink) |
| Does my result point into an input? | name it with `borrows`, `carries` or `retains` | this chapter |
| Into the input, or where the input pointed? | `borrows(x)` for the input, `carries(x)` for where it pointed | this chapter |
| Who chooses the memory? | the caller, by passing an allocator | [Memory](07-memory.md) |

## What you have seen

| You want to say | Write |
| --- | --- |
| a view of a whole value | `borrow value`, of type `borrow T`; `*view` reads it |
| a copy of the value a view points at | `copy(*view)` |
| my result points into this parameter | `where borrows(param)` |
| my result points wherever this view pointed | `where carries(param)` |
| my result points at nothing of yours | `where carries()` |
| values built from this type point into it | `@carrier` on the type |
| this `inout` argument now holds what that one held | `where retains(dest: source)` |
| this `inout` argument now holds a view of that one | `where retains(dest: borrow source)` |
| only the `.Some`/`.Ok` part does | put the target first: `borrows(.Ok: param)` |
| every implementation of a trait promises the same | write the clause on the trait's signature only |
| a view that lasts for one call or one construct | `read`, the default for a parameter |
| a variable a closure may change until its last use | `inout [inout name] \|…\| …` |

Three example programs do all of this at full size: the
[log filter](../../examples/log_filter.lin) reads borrowed lines and never copies
one, the [configuration editor](../../examples/config_editor.lin) keeps parsed
views while it builds new owned text, and the
[parcel manifest](../../examples/parcel_manifest.lin) borrows a collection for a
pipeline.

Next: [Memory](07-memory.md) — where owned values get their memory, and who
decides.
