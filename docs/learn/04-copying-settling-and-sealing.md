# Copying, settling and sealing: what your types promise

When you declare a type in Linea, you decide more than its fields. You decide
what the rest of the program may do with a value of that type. Can it be
duplicated? Can it be forgotten? Can code in another module build one, or look
inside it?

This chapter teaches you to answer those questions for your own types. Each
section starts with a problem you will actually meet, shows a small program,
shows what the compiler says about it, and then explains the idea. By the end
you will be able to look at a type — a status code, an email address, a
ticket, a bank transfer, a network connection — and know what it needs.

You have already met the default in the first chapters: `sink` takes a value,
and a `match` on a value you were only lent is refused. You have also met
values that must be consumed exactly once: a `Vec` from the heap must be
released, and a `@linear` payment must be committed or refunded. This chapter explains that default, and the
attributes and visibility that change it. They show up as soon as a value
should be shared freely (a status code), when only your module should be able
to make a value (a checked email address), or when forgetting a value would be
a bug (an open connection).

## Three questions every type answers

Every type answers three questions:

1. **May I copy it?** Can you end up with two independent values where you
   had one?
2. **May I drop it?** Can you simply stop using it and let it go away?
3. **Must I settle it?** Does something have to happen to it before it goes
   away — a ticket redeemed, a transfer committed, a connection closed?

Linea gives you three answers to choose from, the affine, copyable and linear
policies:

| Policy | Copy it? | Drop it? | Must settle it? | Good for |
| --- | --- | --- | --- | --- |
| affine (the default) | no | yes | no | most records: a parcel, a form, a parsed line |
| `@copyable` | yes, with `copy(...)` | yes | no | small plain data: a point, a status code, an address |
| `@linear` | no | no | yes: consumed exactly once | obligations: a ticket, a transfer, an open socket |

A type whose values may be dropped is called **Discardable**: an affine or a
copyable type is, as long as nothing it holds must be settled, and a linear
type never is. Error messages use the word, as `filter` does in
[Iterating](05-iterating.md#filter-drops-what-it-rejects-filter_map-hands-it-to-you).

The policy is the one answer you choose for a type. Discardable and Copyable
are what follow from it and from what the type holds: they are not traits you
write an `impl` for, they are bounds a generic function can ask for. Traits
such as `Release`, `Iterator` and `Display` are separate. They are ordinary
traits that any type may implement, whatever its policy, and none of them
changes the policy: a linear type can implement `Display`, and implementing
`Release` does not make a type linear.

A fourth question is about who may build a value and look inside it, not about
ownership. The `@opaque` attribute answers it: code outside the type's module
can hold and pass a value but not build one, read its fields or take it apart.

You write attributes on the line before the type. Write them one per line, or
group them with `@(...)`:

```linea
// One attribute per line, or several grouped in `@(...)`: these mean the same.
@linear
@derive(Debug)
struct Ticket {
    seat: UInt8,
}

@(linear, derive(Debug))
struct Pass {
    seat: UInt8,
}
```

That is the whole list: `opaque`, `linear`, `copyable` and `derive(...)`, all
on types. A test that must stop the program is written `test trap fn`, as
[Linea in an hour](01-linea-in-an-hour.md#tests) showed. You cannot invent your
own:

```linea
@sealed
struct Ticket {
    seat: UInt8,
}
```

<!-- guide: first 1 diagnostic -->
```
error[S-Entry]: attribute names are closed
 --> policies_closed.lin:1:2
  |
1 | @sealed
  |  ^^^^^^ use `opaque`, `linear`, `copyable`, `carrier`, or `derive(...)`
```

The `@` is required. Writing `linear struct Ticket` or `opaque struct Ticket`
is refused with `type policies are declaration attributes` and a note to write
`@` before the policy.

A type cannot be both copyable and linear. "You must settle this exactly once"
and "you may make as many of these as you like" cannot both be true:

```linea
@(linear, copyable)
struct Ticket {
    seat: UInt8,
}
```

<!-- guide: first 1 diagnostic -->
```
error[S-Entry]: linear and copyable are exclusive
 --> policies_exclusive.lin:1:1
  |
1 | @(linear, copyable)
  | ^ choose one ownership policy
```

`[S-Entry]` is the code for a declaration written in a shape the language does
not accept. The rest of this chapter takes each policy in turn.

## Affine: the default

Start with a type that has no attributes at all. Here is a parcel, and a
function that ships it:

```linea
import std.io

struct Parcel {
    label: Str,
    grams: UInt64,
}

fn ship(sink parcel: Parcel) -> Result[(), io.IoError] {
    io.println("Shipped {parcel.label}, {parcel.grams} g.")
}

fn main() -> Result[UInt8, io.IoError] {
    let parcel = Parcel { label = "books", grams = 1200 }
    ship(parcel)?
    ship(parcel)?
    .Ok(0)
}
```

Shipping the same parcel twice is a bug, and the compiler says so:

```
error[O-Move]: `parcel` has already been moved
  --> parcels.lin:15:10
   |
14 |     ship(parcel)?
   |          ------ it was taken here
15 |     ship(parcel)?
   |          ^^^^^^ it was already taken, and a value is taken once
```

`sink` means *this function takes the value*. After the first call the parcel
belongs to `ship`, and your `main` no longer has it. `[O-Move]` is the error
for using a value after it was given away.

That is what **affine** means: a value is used up at most once. If you have
written Rust, this is Rust's default move semantics, and `[O-Move]` is
*use of moved value*.

The other half of affine is that you may also use a value **zero** times.
Nothing forces you to ship every parcel. Keep `Parcel` and `ship`, and add
`weigh` and a new `main`:

<!-- guide: unchecked the program is a partial listing or an edit of an earlier one -->
```linea
// Looking at a parcel does not take it.
fn weigh(parcel: Parcel) -> UInt64 {
    parcel.grams
}

fn main() -> Result[UInt8, io.IoError] {
    let limit = 1000
    let books = Parcel { label = "books", grams = 1200 }
    let tape = Parcel { label = "tape", grams = 50 }
    io.println("Books weigh {weigh(books)} g.")?
    if weigh(tape) < limit {
        ship(tape)?
    }
    // `books` is never shipped. It is simply dropped at the end of `main`.
    .Ok(0)
}
```

```
Books weigh 1200 g.
Shipped tape, 50 g.
```

`weigh` has no `sink`, so it only reads the parcel. You can read a value as
often as you like. The tape is shipped on one path and dropped on the other,
and the books are never shipped at all. All of that is fine for an affine type.

### Where a value sits decides whether it moves

You never write a "move" keyword. Whether a value is taken depends on **where
you put it**. A `sink` argument takes it. So does storing it in a `let`, in a
field, or in a return. And an `if` or `match` passes that position on to its
arms: a value in an arm sits wherever the whole `if` sits.

```linea
struct Parcel {
    label: Str,
    grams: UInt64,
}

fn main() -> UInt8 {
    let books = Parcel { label = "books", grams = 1200 }
    let tape = Parcel { label = "tape", grams = 50 }
    let express = true
    let first = if express { books } else { tape }
    UInt8(first.grams / 100 + books.grams / 100)
}
```

```
error[O-Move]: `books` has already been moved
  --> express.lin:11:31
   |
10 |     let first = if express { books } else { tape }
   |                              ----- it was taken here
11 |     UInt8(first.grams / 100 + books.grams / 100)
   |                               ^^^^^^^^^^^ it was already taken, and a value is taken once
```

The `if` is stored in `first`, so `books` inside it is stored too. Write
`if express { books.grams } else { tape.grams }` instead and nothing moves:
numbers are copied when you read them, as the next section explains.

**What you can do now:** leave most of your types as they are. Pass them with
`sink` when a function should keep them, and without it when a function only
needs to look.

## `copyable`: values that are safe to duplicate

Some values are just data. A point on a map, a status code, a network address.
Having two of them hurts nobody. Mark such a type `@copyable`:

```linea
import std.io

@copyable
struct Point {
    x: Int64,
    y: Int64,
}

fn moved(sink point: Point, dx: Int64) -> Point {
    Point { x = point.x + dx, y = point.y }
}

fn main() -> Result[UInt8, io.IoError] {
    let start = Point { x = 2, y = 3 }
    let right = moved(copy(start), 10)
    let left = moved(copy(start), -10)
    io.println("start ({start.x}, {start.y}), right ({right.x}, {right.y}), left ({left.x}, {left.y})")?
    .Ok(0)
}
```

```
start (2, 3), right (12, 3), left (-8, 3)
```

Notice the `copy(start)`. Copyable does not make copies happen behind your
back. It *permits* you to write `copy(...)`, and every copy in the program is
one you can see. Leave `copy` out and the first call takes `start` exactly as
it would take an affine value. Take away `@copyable` and the `copy` itself is
refused:

<!-- guide: unchecked the error an edit of the program above produces -->
```
error[O-Copy]: `Point` does not permit copying
  --> points_affine.lin:14:23
   |
14 |     let right = moved(copy(start), 10)
   |                       ^^^^^^^^^^^ move the value, or declare a copyable representation
error[O-Copy]: `Point` does not permit copying
  --> points_affine.lin:15:22
   |
15 |     let left = moved(copy(start), -10)
   |                      ^^^^^^^^^^^ move the value, or declare a copyable representation
```

`[O-Copy]` means you asked to duplicate a value whose type does not allow it.

### Numbers and truth values copy themselves

Built-in numbers and `Bool` are the exception. They are copied every time you
read them, with no `copy` needed. That is why `weigh(parcel)` above could
return `parcel.grams` without taking anything. Writing `copy` on one is
refused, because it would do nothing:

```linea
fn main() -> UInt8 {
    let count: UInt8 = 3
    let again = copy(count)
    count + again
}
```

```
error[O-ScalarCopy]: `UInt8` already produces a scalar snapshot when read
 --> counter.lin:3:17
  |
3 |     let again = copy(count)
  |                 ^^^^^^^^^^^ remove `copy` and read the value directly
```

A copyable enum whose variants carry nothing behaves the same way. A traffic
light is as plain as a number:

```linea
import std.io

@copyable
enum Light {
    Red,
    Green,
}

struct Crossing {
    north: Light,
    east: Light,
}

fn main() -> Result[UInt8, io.IoError] {
    let go = Light.Green
    // `go` is copied into both fields without `copy`.
    let crossing = Crossing { north = go, east = go }
    match read crossing.east {
        Red => io.println("East waits.")?,
        Green => io.println("East goes.")?,
    }
    .Ok(0)
}
```

```
East goes.
```

`match read` leaves `crossing` whole, as [Linea in an
hour](01-linea-in-an-hour.md#match) showed.

### Copyable types from the standard library

`http.Status` is a copyable enum. Most of its variants are plain names
(`.Ok`, `.NotFound`), and one, `Other(Code)`, carries any other three-digit
code. Because a variant carries data, you write `copy` to keep a second one:

```linea
import std.http
import std.io

struct Reply {
    status: http.Status,
    body: Str,
}

fn lookup(path: Str) -> Reply {
    if path == "/" {
        Reply { status = .Ok, body = "welcome" }
    } else {
        Reply { status = .NotFound, body = "no such page" }
    }
}

fn main() -> Result[UInt8, io.IoError] {
    let paths = ["/", "/missing"]
    var last = http.Status.Ok
    for path in paths {
        let reply = lookup(path)
        io.println("{path}: {reply.status.code()} {reply.status.reason()} ({reply.body})")?
        last = copy(reply.status)
    }
    io.println("last status: {last.code()}")?
    .Ok(0)
}
```

```
/: 200 OK (welcome)
/missing: 404 Not Found (no such page)
last status: 404
```

Bind a status, `let missing = http.Status.NotFound`, store it in two replies
without `copy`, and you get the familiar `[O-Move]`: `missing` has already
been moved.

`net.Address` is copyable too: an IPv4 address and a port, with `port` as a
public field. You can hand the same address to a log line, a `listen` call and
an error message without worrying about who owns it.

### A copyable type can only hold copyable things

Copying a value copies every field. So if a field cannot be copied, neither can
the type holding it:

```linea
struct Parcel {
    label: Str,
    grams: UInt64,
}

@copyable
struct Delivery {
    parcel: Parcel,
    day: UInt8,
}

fn main() -> UInt8 {
    let delivery = Delivery { parcel = Parcel { label = "books", grams = 1200 }, day = 3 }
    delivery.day
}
```

```
error[O-Universe]: a copyable declaration owns `Parcel`, which cannot be copied
 --> delivery.lin:8:5
  |
8 |     parcel: Parcel,
  |     ^^^^^^ remove `copyable`, or hold a copyable part
```

`[O-Universe]` names the field that stands in the way. In practice this means a
copyable type owns nothing that needs cleaning up: no heap memory, no open
file, no socket. Views are fine — a `Str` field is copyable, because copying a
view copies the pointer, not the text it points at. On a generic type,
`@copyable` holds wherever the fields allow it, as a derive does ([Calling
things](02-calling-things.md#derive-on-a-generic-type)): a `Labelled[Int64]` is
copyable, and a `Labelled[Parcel]` is not.

`@copyable` is not Rust's `Copy`. Rust copies a `Copy` value silently on every
use; Linea only *permits* `copy(value)`, and every copy is written where it
happens. `copy(value)` is closer to `.clone()`, restricted to types that hold
nothing that needs cleaning up.

**What you can do now:** mark small plain-data types `@copyable`, and write
`copy(value)` at the places you want a second one.

## Phantom types: a tag that is never stored

Sometimes two things share a shape but must never be confused: a customer ID
and an invoice ID are both numbers. A **phantom** type parameter tags a type
without storing anything:

```linea
import std.io

struct Customer {}

struct Invoice {}

// `Of` is never stored. It only makes an `Id[Customer]` and an
// `Id[Invoice]` two different types.
@copyable
struct Id[phantom Of] {
    number: UInt64,
}

fn send_reminder(customer: Id[Customer], invoice: Id[Invoice]) -> Result[(), io.IoError] {
    io.println("Reminding customer {customer.number} about invoice {invoice.number}.")
}

fn main() -> Result[UInt8, io.IoError] {
    let customer: Id[Customer] = .{ number = 42 }
    let invoice: Id[Invoice] = .{ number = 1007 }
    send_reminder(customer, invoice)?
    .Ok(0)
}
```

```
Reminding customer 42 about invoice 1007.
```

Swap the arguments and you get `expected Id[Customer], found Id[Invoice]`.
One generic `Id` type serves every kind of record, and the tag keeps them
apart. You must write `phantom`. Declare `struct Id[Of]` without it, and the
compiler reports the parameter as unused, since no field mentions it:

<!-- guide: unchecked the error an edit of the program above produces -->
```
error[N-Unused]: `Of` is never used
  --> ids_unused.lin:10:11
   |
10 | struct Id[Of] {
   |           ^^ name it in this declaration, declare it `phantom`, or remove it
```

`[N-Unused]` is the error for something declared and never used. Here,
`phantom` is how you say the parameter is meant to go unstored.

**What you can do now:** tag a shared shape with a `phantom` parameter when
two uses of it must never mix.

## `@opaque`: only the module can make one

A range ([Errors](03-errors.md#limiting-the-values)) checks a number, but many checks do not fit in a `where`. An email
address must have an `@` with something on each side; a username must not
contain spaces. For those, write the check as a function, and make that
function the only way to get a value of the type. `@opaque` does that: outside
the module that declares the type, nobody can build one or look inside it.

Here is a newsletter in two parts: a `mail` module that declares the email
address, and a `main.lin` that uses it. A module is a directory, so the layout
is:

<!-- guide: unchecked a directory tree, not program output -->
```
newsletter/
    main.lin
    mail/
        email.lin
```

`newsletter/mail/email.lin`:

```linea
// Outside `mail`, `Email.of` is the only way to make an `Email`, so every
// `Email` in the program has passed its check.
@opaque
type Email = Str

impl Email {
    // Answer an `Email` when `text` has an `@` with something on both sides.
    pub fn of(text: Str) -> Option[Email] {
        let at = text.find("@")?
        if at == 0 || at + 1 == text.length() { .None } else { .Some(Email(copy(text))) }
    }

    // Lend the address back as text.
    pub fn address(self: Self) -> Str where carries(self) {
        let read Email(text) = self
        copy(text)
    }
}
```

`newsletter/main.lin`:

```linea
import mail
import std.io

use mail.Email

// `subscribe` takes an `Email`, so it never has to check an address itself.
fn subscribe(email: Email) -> Result[(), io.IoError] {
    io.println("Subscribed {email.address()}.")
}

fn main() -> Result[UInt8, io.IoError] {
    let typed = ["ada@example.com", "not an address", "@example.com"]
    for text in typed {
        match Email.of(text) {
            Some(email) => subscribe(email)?,
            None => io.println("{text} is not an email address.")?,
        }
    }
    .Ok(0)
}
```

Run it with `linea run newsletter`:

```
Subscribed ada@example.com.
not an address is not an email address.
@example.com is not an email address.
```

Inside `mail`, `Email` is an ordinary newtype
([Errors](03-errors.md#newtypes-a-check-the-type-carries)):
`Email(copy(text))` builds one and `let read Email(text) = self` looks inside. `copy(text)` copies the view,
not the text, so the email points at the same bytes the caller's `Str` did,
which is what `where carries(self)` on `address` says ([Borrowing](06-borrowing.md)
explains the clause).

Outside `mail`, both are closed. Add `subscribe(Email("root"))?` to `main`, and
the compiler refuses to build an address that skipped the check:

<!-- guide: unchecked the error an edit of the program above produces -->
```
error[M-Opaque]: `Email` is opaque outside `mail`
  --> newsletter/main.lin:19:15
   |
19 |     subscribe(Email("root"))?
   |               ^^^^^^^^^^^^^ only its own module can build one
```

Reach inside instead, with `let read Email(_text) = email` as the first line
of `subscribe`:

<!-- guide: unchecked the error an edit of the program above produces -->
```
error[M-Opaque]: `Email` is opaque outside `mail`
 --> newsletter/main.lin:8:14
  |
8 |     let read Email(_text) = email
  |              ^^^^^^^^^^^^ only its own module can take one apart
```

`[M-Opaque]` means *this type's insides belong to its own module*. So every
`Email` anywhere in the program came through `Email.of`, and a function that
takes an `Email`, like `subscribe`, can rely on the check without repeating
it. This is sometimes called *parse, don't validate*: check once at the edge,
and let the type carry the proof. `@opaque` works on structs and enums too:
`@opaque struct Account { … }` hides its fields, and an opaque enum hides its
variants.

### `@opaque` replaces `pub`

`@opaque` already makes the type's name available to other modules, just as
`pub` does, so it does not combine with `pub` or `internal`:

<!-- guide: unchecked the error an edit of the program above produces -->
```
error[S-Entry]: opaque does not combine with another visibility
 --> newsletter/mail/email.lin:3:1
  |
3 | @opaque
  | ^ remove `pub` or `internal`
```

Think of a type's reach as one choice among four:

- private (the default): only its own module can use the type;
- `internal`: the rest of your program or library can use it, like Rust's
  `pub(crate)`;
- `pub`: everyone can use it, read its fields and build values of it;
- `@opaque`: everyone can use the type — hold, pass and return its values, and
  call its `pub` operations — but its insides are sealed, and nobody outside
  its module can build (forge) a value or take one apart.

**What you can do now:** make a type `@opaque` when a value must pass a check
before it exists, and give its module the one function that checks. The email
address in the [discounts example](../../examples/discounts/) works this way.

## `linear`: values you must not forget

Now the opposite problem. You sell a concert ticket. It must end in exactly one
of two ways: redeemed at the door, or refunded. A ticket that silently
disappears is a bug — someone paid for it. A linear value is **consumed
exactly once**, like the café payment of [Linea in an
hour](01-linea-in-an-hour.md#values-consumed-exactly-once): the compiler
refuses a path that consumes it zero times with `[O-Leak]`, and a second use
with `[O-Move]`.

`[O-Leak]` means a linear value reached the end of its scope without being
consumed. Consuming a linear value is also called *settling* it: you give it
to something that takes it — a function with a `sink` parameter — or take it
apart with a pattern, as the help line spells out. The ending has no special
name in the language: `commit`, `refund`, `release` and `finish` are ordinary
functions that take their value with `sink`, and each consumes it. Settling is
consuming, and which consuming function a type offers is its own decision.

The compiler checks every path, not just the one you had in mind:

```linea
import std.io

@linear
struct Ticket {
    seat: Str,
}

fn redeem(sink ticket: Ticket) -> Result[(), io.IoError] {
    let Ticket { seat } = ticket
    io.println("Welcome! Your seat is {seat}.")
}

fn main() -> Result[UInt8, io.IoError] {
    let ticket = Ticket { seat = "14C" }
    let doors_open = false
    if doors_open {
        redeem(ticket)?
    }
    .Ok(0)
}
```

```
error[O-Merge]: the paths here disagree about `ticket`
  --> ticket_doors.lin:16:5
   |
16 |     if doors_open {
   |     ^^^^^^^^^^^^^^^ consume it on the other path too, or on neither
```

`[O-Merge]` means one branch settled the value and another did not. When the
doors stay shut, what happens to the ticket? Say so with a second ending,
`refund`, and an `else` that calls it, and the program compiles:

<!-- guide: edit end -->
```linea
fn refund(sink ticket: Ticket) -> Result[(), io.IoError] {
    let Ticket { seat } = ticket
    io.println("Seat {seat} refunded.")
}
```

<!-- guide: edit after 17 redeem(ticket)? -->
```linea
    } else {
        refund(ticket)?
```

```
Seat 14C refunded.
```

`redeem` and `refund` settle the ticket by taking it apart:
`let Ticket { seat } = ticket` consumes the ticket and hands you its seat.

A `?` is a path too, and the easiest one to miss. Keep `Ticket` and `redeem`
and write this `main`:

<!-- guide: unchecked the program is a partial listing or an edit of an earlier one -->
```linea
fn main() -> Result[UInt8, io.IoError] {
    let ticket = Ticket { seat = "14C" }
    io.println("Checking in.")?
    redeem(ticket)?
    .Ok(0)
}
```

```
error[O-Leak]: `ticket` (a linear `Ticket`) is still owned when this path leaves
  --> check_in.lin:15:31
   |
14 |     let ticket = Ticket { seat = "14C" }
   |         ------ acquired here
15 |     io.println("Checking in.")?
   |                               ^ still owned here
   |
   = help: take it apart with `let Ticket { seat: _ } = ticket`, or give it to something that takes it
```

Every line reads correctly. But if printing `Checking in.` fails, the first `?`
leaves `main` with the ticket still in hand. The error points at that `?`: it
is the way out on which the ticket is still owned.

The usual fix is to settle first and check for errors afterwards: keep the
`Result` in a `let`, settle your linear values, then apply `?`:

<!-- guide: unchecked the program is a partial listing or an edit of an earlier one -->
```linea
fn main() -> Result[UInt8, io.IoError] {
    let ticket = Ticket { seat = "14C" }
    // Keep the result, settle the ticket, then check the result.
    let checked_in = io.println("Checking in.")
    redeem(ticket)?
    checked_in?
    .Ok(0)
}
```

```
Checking in.
Welcome! Your seat is 14C.
```

Now no path leaves `main` before the ticket is redeemed. If printing failed,
`checked_in?` still reports it — just after the ticket is settled. The
box-office program later on this page works the same way.

### Linear does not choose the ending for you

The compiler does not decide what "settled" means. Your API does. A bank
transfer is the classic case: money that has left one account either arrives
in the other, or goes back.

```linea
import std.io

struct Account {
    owner: Str,
    cents: UInt64,
}

// A Transfer holds money that has left one account and not yet reached another.
@linear
struct Transfer {
    cents: UInt64,
}

// `inout` lets `begin` change the caller's account; the caller marks it with `&`.
fn begin(inout from: Account, cents: UInt64) -> Option[Transfer] {
    if cents > from.cents {
        return .None
    }
    from.cents -= cents
    .Some(Transfer { cents = cents })
}

// The money arrives in the recipient's account.
fn commit(sink transfer: Transfer, inout to: Account) {
    let Transfer { cents } = transfer
    to.cents += cents
}

// The money goes back to the sender's account.
fn rollback(sink transfer: Transfer, inout from: Account) {
    let Transfer { cents } = transfer
    from.cents += cents
}

fn pay(inout from: Account, inout to: Account, cents: UInt64, approved: Bool) {
    match begin(&from, cents) {
        Some(transfer) => if approved {
            commit(transfer, &to)
        } else {
            rollback(transfer, &from)
        },
        None => {},
    }
}

fn main() -> Result[UInt8, io.IoError] {
    var alice = Account { owner = "Alice", cents = 5000 }
    var landlord = Account { owner = "Landlord", cents = 0 }
    pay(&alice, &landlord, 3000, approved: true)
    pay(&alice, &landlord, 1500, approved: false)
    io.println("{alice.owner}: {alice.cents} cents, {landlord.owner}: {landlord.cents} cents.")?
    .Ok(0)
}
```

```
Alice: 2000 cents, Landlord: 3000 cents.
```

`begin` takes the money out of the sender's account and hands you a
`Transfer`. From that moment the compiler holds you to finishing it: `commit`
puts the money in the recipient's account, and `rollback` puts it back in the
sender's. Alice's first payment is approved, so the landlord receives 3000
cents. Her second is not, so its 1500 cents return to her.

Forget the `rollback` branch and the money would leave Alice's account without
reaching anyone. That program does not compile:

<!-- guide: edit 37-42 Some(transfer) => if approved { … None => {}, -->
```linea
        Some(transfer) => if approved {
            commit(transfer, &to)
        },
        None => {},
```

```
error[N-Unused]: `rollback` is never used
  --> transfer_forgot.lin:30:4
   |
30 | fn rollback(sink transfer: Transfer, inout from: Account) {
   |    ^^^^^^^^ call it, or name it with a leading `_`
error[O-Merge]: the paths here disagree about `transfer`
  --> transfer_forgot.lin:37:27
   |
37 |         Some(transfer) => if approved {
   |                           ^^^^^^^^^^^^^ consume it on the other path too, or on neither
```

The first error is a hint of its own: a function that ends a transfer and is
never called is usually the path you forgot.

The [payment batch example](../../examples/payment_batch.lin) does this for a
whole vector of payments.

### Linear spreads to whatever holds it

Put a ticket inside an order, and the order becomes something you must settle
too. You do not write `@linear` on the order; it follows from the field:

```linea
import std.io

@linear
struct Ticket {
    seat: Str,
}

// No attribute here, yet an Order is linear: it holds a Ticket.
struct Order {
    ticket: Ticket,
    paid_cents: UInt64,
}

fn main() -> UInt8 {
    let order = Order { ticket = Ticket { seat = "14C" }, paid_cents = 4500 }
    io.eprintln("Paid {order.paid_cents} cents.")
    0
}
```

```
error[O-Leak]: `order` (a linear `Order`) is still owned when this path leaves
  --> order.lin:15:9
   |
15 |     let order = Order { ticket = Ticket { seat = "14C" }, paid_cents = 4500 }
   |         ^^^^^ never settled on the path that reaches the end of this block
18 | }
   | - the block ends here
   |
   = help: give it to something that takes it
```

The same holds for `Option[Ticket]`, a `Vec` of tickets, or any other wrapper.
A `String` or a `Vec` that allocates from `mem.system()` owns heap memory, so a
struct holding one must be settled too. The next section shows one.

### `Release`: the ending you do not have to think about

Some linear values have one obvious way to end. For those, implement the
`Release` trait, or derive it. A type has an obvious ending when one
**context-free** ending is right for every value: it makes sense without
knowing why the value is being let go. A ticket that is never used is simply
released. A transfer is not like that. Releasing one has to mean commit or
rollback, and which one depends on what the caller is doing, so there is no
single `release` it could have. The central sentence is this: linear means a
value is consumed exactly once, and `Release` is one context-free ending, not a
property of being linear. A linear type may have no `Release`, and a type that
is not linear may have one, as the `Note` below does.

Deriving `Release` gives the type a `release` that settles each field in
turn. It is a claim you opt into: you are saying that releasing every field is
a correct ending for this type, and the compiler does not guess it for you:

```linea
import std.io

@(linear, derive(Release))
struct Ticket {
    seat: Str,
}

fn redeem(sink ticket: Ticket) -> Result[(), io.IoError] {
    let Ticket { seat } = ticket
    io.println("Welcome! Your seat is {seat}.")
}

fn board(sink ticket: Ticket, doors_open: Bool) -> Result[(), io.IoError] {
    if !doors_open {
        // Nobody boards, so the ticket is released without being redeemed.
        ticket.release()
        return io.println("Doors are closed.")
    }
    redeem(ticket)
}

fn main() -> Result[UInt8, io.IoError] {
    board(Ticket { seat = "14C" }, doors_open: true)?
    board(Ticket { seat = "14D" }, doors_open: false)?
    .Ok(0)
}
```

```
Welcome! Your seat is 14C.
Doors are closed.
```

`Release` is in the prelude, so neither deriving it nor calling `release()`
needs an import. It never runs by itself. There is no destructor that fires
at the end of a scope, the way Rust runs `Drop`; the compiler checks that a
linear value was settled, and never settles it for you. You call `release()`,
or you schedule it with `defer`,
which runs it on every way out of the block — including a `?`. Here a note owns
its title text, so the note must be settled, and `defer` settles it however
`main` ends:

```linea
import std.io

// A String owns memory, so a Note must be settled. Deriving Release gives it
// a `release` that releases each field in turn.
@derive(Release)
struct Note {
    title: String,
    pinned: Bool,
}

fn main() -> Result[UInt8, io.IoError] {
    let title = "Buy milk".to_owned() else |_| {
        return .Ok(1)
    }
    let note = Note { title, pinned = true }
    defer note.release()
    io.println("{note.title.view()} (pinned: {note.pinned})")?
    .Ok(0)
}
```

```
Buy milk (pinned: true)
```

`"Buy milk".to_owned()` copies the text into memory from the heap,
and can fail when there is none. `note.title.view()` lends the `String` back
out as a `Str`, which is what the interpolation writes. `Note` has no `@linear`. It must be settled
because its `String` must be.

### `defer` belongs to its block

A `defer` belongs to the block it is written in, not to the whole function. It
runs when that block ends. Inside a loop body, that is once per pass:

```linea
import std.io

fn main() -> Result[UInt8, io.IoError] {
    for table in 1..=2 {
        // This defer runs when this pass through the loop body ends.
        defer io.eprintln("Table {table} cleared.")
        io.println("Serving table {table}.")?
    }
    io.println("Kitchen closed.")?
    .Ok(0)
}
```

```
Serving table 1.
Table 1 cleared.
Serving table 2.
Table 2 cleared.
Kitchen closed.
```

That is the order a terminal shows. The `cleared` lines go to standard error
and the rest to standard output, two separate streams, so a pipe or a file
that collects both may interleave them differently.

So a resource opened inside a loop is settled before the next pass begins,
not held until the function returns. When several `defer`s are waiting, they
run in the reverse of the order they were written: the last thing set up is
the first thing cleaned up.

If you know Go, this is the difference to watch: Go's `defer` runs when the
function returns, and Linea's when the enclosing *block* ends.

### A `defer` and a move

A `defer` that settles a value, such as `defer note.release()`, runs only on
the ways out where the value is still there. If something took the value on
the way — a function with a `sink` parameter, or a `return` of the value — the
value is no longer yours to release, and that `defer` is skipped on that path:

```linea
import std.io

@derive(Release)
struct Note {
    title: String,
    pinned: Bool,
}

// `archive` takes the note, prints it, and releases it.
fn archive(sink note: Note) -> Result[(), io.IoError] {
    let printed = io.println("Archived {note.title.view()}.")
    note.release()
    printed
}

fn tidy(sink note: Note) -> Result[(), io.IoError] {
    // This defer runs on every way out of `tidy` where `note` is still here.
    defer note.release()
    if note.pinned {
        return io.println("Kept {note.title.view()}.")
    }
    // On this path `archive` takes the note, so the defer does not run.
    archive(note)
}

fn main() -> Result[UInt8, io.IoError] {
    let milk = "Buy milk".to_owned() else |_| {
        return .Ok(1)
    }
    let bread = "Buy bread".to_owned() else |_| {
        milk.release()
        return .Ok(1)
    }
    let kept = tidy(Note { title = milk, pinned = true })
    let archived = tidy(Note { title = bread, pinned = false })
    kept?
    archived?
    .Ok(0)
}
```

```
Kept Buy milk.
Archived Buy bread.
```

This is what makes `defer` safe to write early. You schedule the release right
beside the value, and it covers every early exit, including every `?`, while
the path that hands the value on — to `archive` here, or back to a caller —
simply skips it. [Memory](07-memory.md) uses the same pattern to build a value
and return it.

If every path takes the value, the `defer` can never run, and that is a
mistake worth hearing about. Replace `tidy` with this version, which archives
every note:

<!-- guide: edit fn tidy -->
```linea
fn tidy(sink note: Note) -> Result[(), io.IoError] {
    defer note.release()
    archive(note)
}
```

```
error[O-DeferDead]: what this schedules never runs: the value is gone on every path out
  --> archive_always.lin:17:11
   |
17 |     defer note.release()
   |           ^^^^^^^^^^^^^^ delete the `defer`, or move what takes the value after it
```

### A `defer` covers exits, not joins

Release is not the only ending a `defer` can schedule. A transfer that is
committed or rolled back schedules `rollback` right beside the value, and a
`?` before the commit leaves the function through that rollback:

```linea
import std.io

// A transfer ends in one of two ways, and neither is the default.
@linear
struct Transfer {
    cents: UInt64,
}

impl Transfer {
    fn commit(sink self: Self) -> UInt64 {
        let Transfer { cents } = self
        cents
    }

    fn rollback(sink self: Self) {
        let Transfer { cents: _ } = self
    }
}

fn check(cents: UInt64, limit: UInt64) -> Result[(), Str] {
    if cents > limit {
        return .Err("over the limit")
    }
    .Ok(())
}

// If the check fails, `?` leaves `send` and the deferred rollback runs. If it
// passes, `commit` takes the transfer and the rollback is skipped.
fn send(cents: UInt64, limit: UInt64) -> Result[UInt64, Str] {
    let transfer = Transfer { cents }
    defer transfer.rollback()
    check(cents, limit)?
    .Ok(transfer.commit())
}

fn main() -> Result[UInt8, io.IoError] {
    match send(300, 500) {
        Ok(sent) => io.println("sent {sent} cents")?,
        Err(why) => io.println("refused: {why}")?,
    }
    match send(900, 500) {
        Ok(sent) => io.println("sent {sent} cents")?,
        Err(why) => io.println("refused: {why}")?,
    }
    .Ok(0)
}
```

```
sent 300 cents
refused: over the limit
```

`send` schedules `rollback` as soon as the transfer exists. When `check` fails,
`?` leaves `send` and the rollback runs. When it passes, `commit` takes the
transfer, so on that path the `defer` is skipped, exactly as with `archive`
above. The ending is chosen where the value is made, and every early exit
inherits it.

A `defer` runs on the ways out of a block, and an `if` that rejoins is not one.
Suppose `send` committed in one arm of an `if` and left the other arm to the
`defer`:

```linea
import std.io

// A transfer ends in one of two ways, and neither is the default.
@linear
struct Transfer {
    cents: UInt64,
}

impl Transfer {
    fn commit(sink self: Self) -> UInt64 {
        let Transfer { cents } = self
        cents
    }

    fn rollback(sink self: Self) {
        let Transfer { cents: _ } = self
    }
}

fn send(cents: UInt64, limit: UInt64) -> UInt64 {
    let transfer = Transfer { cents }
    defer transfer.rollback()
    if cents <= limit {
        transfer.commit()
    } else {
        0
    }
}

fn main() -> Result[UInt8, io.IoError] {
    io.println("sent {send(300, 500)} cents")?
    io.println("sent {send(900, 500)} cents")?
    .Ok(0)
}
```

```
error[O-Merge]: the paths here disagree about `transfer`
  --> transfer_if.lin:23:5
   |
23 |     if cents <= limit {
   |     ^^^^^^^^^^^^^^^^^^^ consume it on the other path too, or on neither
```

The two arms meet again after the `if`, and on one of them `transfer` is gone
while on the other it is not. A `defer` does not reconcile that, because it
runs when the block ends and not where the paths meet, so the compiler asks
the arms to agree. There are two ways to make them agree. The `?` form above
leaves the function before the commit when the check fails. Or the committing
arm can leave the function itself:

<!-- guide: edit fn send -->
```linea
fn send(cents: UInt64, limit: UInt64) -> UInt64 {
    let transfer = Transfer { cents }
    defer transfer.rollback()
    if cents <= limit {
        return transfer.commit()
    }
    0
}
```

```
sent 300 cents
sent 0 cents
```

After `return transfer.commit()` nothing remains to disagree about, and the
`defer` rolls the transfer back on the path that falls through to `0`.

### `defer let`: bind a value and schedule its release

A `defer value.release()` written straight under the line that binds `value`
is so common that it has a shorter spelling. `defer let` binds the name and
schedules the release in one statement:

```linea
import std.io

fn main() -> Result[UInt8, io.IoError] {
    defer let milk = "Buy milk".to_owned() else |_| {
        return .Ok(1)
    }
    io.println("Noted {milk.view()}.")?
    .Ok(0)
}
```

```
Noted Buy milk.
```

`defer let milk = ...` means `let milk = ...` followed by `defer
milk.release()` for a type that implements `Release`, and everything above
still holds. The release runs on every
way out of the block, once per pass through a loop body, and not at all on a
path where `milk` was given away. If every path gives it away the release can
never run, and `[O-DeferDead]` says to write `let`, since a value that is meant
to move was never meant to be released here. The `else` block runs before the
name is bound, so it releases nothing of `milk`. `defer var` binds a place you
may assign again and releases whatever it holds when the block ends.

Write `defer let` when the value is never reassigned and never changed through
`&name`, which is most of the time. Write `defer var` when the body changes it
before it is released or returned, such as pushing into a `Vec` or appending to
a `String`. The compiler refuses `&name` on a `defer let`, but it does not
flag a `defer var` that nothing changes, so choosing `let` is up to you:

```linea
import std.io

fn main() -> Result[UInt8, io.IoError] {
    // Nothing changes `title` after it is built, so `defer let`.
    defer let title = "Weekly plan".to_owned() else |_| {
        return .Ok(1)
    }
    // The loop appends to `tasks`, so `defer var`.
    defer var tasks: Vec[UInt64] = Vec.new()
    for number in 1..4 {
        if &tasks.push(number * 10).is_err() {
            return .Ok(1)
        }
    }
    io.println("{title.view()}: {tasks.length()} tasks")?
    .Ok(0)
}
```

```
Weekly plan: 3 tasks
```

The compiler still never chooses an ending for you. `defer let` schedules
`release()`, so it needs a type that implements `Release`. The transfer above
has no such default, because committing and rolling back are both honest
endings, and `defer let` refuses it:

<!-- guide: unchecked the error an edit of the program above produces -->
```
error[T-DeferLet]: `Transfer` implements no `Release`, so it has no single ending `defer let` may choose
  --> transfer_defer_let.lin:29:5
   |
29 |     defer let transfer = Transfer { cents = 300 }
   |     ^^^^^^^^^^^^^^^^^^ write `let`, then `defer` the operation that ends it on every path
```

Write `let` and the `defer transfer.rollback()` you chose, as `send` does. A
pattern cannot be written after `defer`, since it takes a value apart into
several bindings and there is no one release to schedule.

### Choosing not to have a default

`Release` is a convenience, and a type does not have to have it. A transfer
should not quietly roll back because you forgot to commit it; the compiler
should stop you. So a type that needs a *choice* — commit or rollback, redeem
or refund — leaves `Release` out, and the compiler makes every caller choose.
Other endings are just as ordinary: a `Vec` offers `finish`
([Iterating](05-iterating.md#why-finish-ends-a-lent-walk)), which completes a
collection whose elements were all handed over and hands a nonempty one back.
That ending belongs to those containers, and the language does not ask every
type to have one. The verbs differ in what they promise,
and a type offers the ones its contract allows:

| Verb | What it promises | Offered by |
| --- | --- | --- |
| `release()` | Disposal that cannot fail and answers nothing; `defer value.release()` schedules it. A type that needs a choice leaves it out. | every type that implements `Release` |
| `close()` | Disposal that can fail, so it answers a `Result` saying what went wrong. A type's `release()` closes too and drops that answer, so call `close()` when a failed close matters. | `fs.File`, `net.Listener`, `net.Connection` |
| `reset()` | A close the peer sees as a reset, discarding what was never sent. | `net.Connection` |
| `finish()` | Completes a protocol or a producer, and is not a synonym for cleanup. A `Vec` answers `Ok` only when nothing is left, which is how a collection of linear elements is completed, and otherwise hands itself back. A buffered writer flushes every pending byte and hands back the writer. A body is complete when it is finished. | `Vec`, drains, `io.BufferedWriter`, `hash.Hasher` |
| `abort()`, `abandon()` | Gives up buffered data on purpose and hands back the underlying resource: `abort` drops a writer's pending bytes, `abandon` a reader's buffered input. Neither can fail. | `io.BufferedWriter`, `io.BufferedReader` |
| `settle()`, `settled()` | Releases the owned value a failure handed back and keeps the reason, so `?` can go on with it ([Errors](03-errors.md#failures-that-hand-a-value-back)). | results that carry an owned value |

`release()` and `close()` differ in what they let you ignore: `release()`
promises there is nothing to report, and `close()` reports what could go wrong.
`finish()` is a different kind of verb: it says the value's work is done, and
the answer says whether it was. To dispose of a value, use `release()` or
`close()`. This program ends one vector with `release()` and the other with
`finish()`:

```linea
import std.io

fn main() -> Result[UInt8, io.IoError] {
    // `release()` cannot fail and answers nothing, so `defer` can schedule it
    // where the vector is made.
    var scores: Vec[UInt64] = Vec.new()
    defer scores.release()
    let _first = &scores.push(90).settled()
    io.println("best score {scores[0]}")?

    // `finish()` completes the vector: it answers `Ok` only when nothing is
    // left, and an `Err` hands the vector back to be settled.
    var queue: Vec[UInt64] = Vec.new()
    let _queued = &queue.push(7).settled()
    match queue.finish() {
        Ok(_) => io.println("the queue was empty")?,
        Err(left) => {
            let held = left[0]
            left.release()
            io.println("the queue still held {held}")?
        },
    }
    .Ok(0)
}
```

```
best score 90
the queue still held 7
```

`defer scores.release()` runs on every way out of `main`, because ending a
vector this way needs no decision. The queue still holds a number, so `finish()`
answers `Err` and hands the vector back, and the `Err` arm settles it. Leave the
`left.release()` line out and the compiler refuses the arm:

<!-- guide: unchecked the error an edit of the program above produces -->
```
error[O-Leak]: `left` (a linear `Vec[UInt64, mem.SystemAllocator]`) is still owned when this path leaves
  --> queue_leak.lin:20:54
   |
18 |         Err(left) => {
   |             ---- acquired here
20 |             io.println("the queue still held {held}")?
   |                                                      ^ still owned here
21 |         },
   |         - also still owned where the block ends
   |
   = help: settle it first with `left.release()`, or write `defer left.release()` where it is bound so every path releases it
```

A pattern's binder such as `left` has no `let` to write `defer` in front of,
so the help offers the release scheduled at the top of the arm instead.

A network socket is the textbook linear value from the standard library.
`net.Listener` and `net.Connection` are both linear, so a listener you forget
to close is an `[O-Leak]` like a forgotten ticket;
[Networking](09-networking.md#a-socket-must-be-closed) shows that error and
the two ways a listener ends.

Rust has no linear types: `std::mem::forget` is safe there, and `#[must_use]`
is only a warning. Linea's `@linear` makes "you forgot to commit" a compile
error, and lets a type offer several endings without either being the default.

**What you can do now:** mark a type `@linear` when dropping it silently would
be a bug. Give it the functions that end it — as many as your domain has — and
derive or implement `Release` only if one of them is a sensible default.

## `@opaque` and `@linear` together

A linear ticket still has a weakness. Make `Ticket` `pub` so that other
modules can use it, and anyone can write `Ticket { seat = "1A" }` and print
themselves a free front-row seat. Anyone can also write
`let Ticket { seat } = ticket` to "settle" a ticket without redeeming or
refunding it. `@linear` stops you forgetting a value; it does not stop you
forging one or taking it apart. `@opaque` closes both doors.

Here is a box office: a `box_office` module that declares the ticket, and a
`main.lin` that uses it. The layout is:

<!-- guide: unchecked a directory tree, not program output -->
```
box-office/
    main.lin
    box_office/
        tickets.lin
```

Run it with `linea run box-office`.

`box-office/box_office/tickets.lin`:

```linea
import std.io

// Outside `box_office`, a Ticket can only come from `sell` and only end
// through `redeem` or `refund`.
@(opaque, linear)
struct Ticket {
    seat: Str,
    cents: UInt64,
}

impl Ticket {
    pub fn sell(sink seat: Str) -> Ticket {
        Ticket { seat = seat, cents = 4500 }
    }

    pub fn seat_label(self: Self) -> Str where carries(self.seat) {
        copy(self.seat)
    }

    pub fn redeem(sink self: Self) -> Result[(), io.IoError] {
        let Ticket { seat, cents: _ } = self
        io.println("Welcome! Your seat is {seat}.")
    }

    pub fn refund(sink self: Self) -> UInt64 {
        let Ticket { seat: _, cents } = self
        cents
    }
}
```

`box-office/main.lin`:

```linea
import box_office
import std.io

use box_office.Ticket

fn main() -> Result[UInt8, io.IoError] {
    let mine = Ticket.sell("14C")
    let yours = Ticket.sell("14D")
    let seat = mine.seat_label()
    let greeted = mine.redeem()
    let back = yours.refund()
    greeted?
    io.println("Seat {seat} is taken; refunded {back} cents for the other.")?
    .Ok(0)
}
```

```
Welcome! Your seat is 14C.
Seat 14C is taken; refunded 4500 cents for the other.
```

Notice the order in `main`: both tickets are settled before the first `?`, so
an early return cannot leave one behind.

Inside `box_office`, `Ticket` is an ordinary struct. Outside it, every way into
the fields is closed, each with `[M-Opaque]`. Each attempt below is one edit
to `main.lin`. Building a ticket, on a line after `let back = yours.refund()`:

<!-- guide: edit box-office/main.lin after 11 let back = yours.refund() -->
```linea
    let _forged = Ticket { seat = "1A", cents = 0 }
```

```
error[M-Opaque]: `Ticket` is opaque outside `box_office`
  --> box-office/main.lin:12:19
   |
12 |     let _forged = Ticket { seat = "1A", cents = 0 }
   |                   ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ only its own module can build one
```

Leaving the type name out does not help:

<!-- guide: edit box-office/main.lin after 11 let back = yours.refund() -->
```linea
    let _forged: Ticket = .{ seat = "1A", cents = 0 }
```

```
error[M-Opaque]: `Ticket` is opaque outside `box_office`
  --> box-office/main.lin:12:27
   |
12 |     let _forged: Ticket = .{ seat = "1A", cents = 0 }
   |                           ^^^^^^^^^^^^^^^^^^^^^^^^^^^ only its own module can build one
```

Reading a field, on a line before `let back = yours.refund()`:

<!-- guide: edit box-office/main.lin after 10 let greeted = mine.redeem() -->
```linea
    let _price = yours.cents
```

```
error[M-Opaque]: `Ticket` is opaque outside `box_office`
  --> box-office/main.lin:11:18
   |
11 |     let _price = yours.cents
   |                  ^^^^^^^^^^^ only its own module can read its parts
```

### Only the module's functions can end it

With `@opaque` and `@linear` together, a ticket outside `box_office` ends
through `redeem` or `refund`, and nothing else. Every other route is closed:

- **Dropping it** is `[O-Leak]`, as for any linear value.
- **Taking it apart** is `[M-Opaque]`, in a `let` or in a `match`, even one
  whose only arm is `_`. Write `let Ticket { seat: _, cents: back } = yours`
  in place of `let back = yours.refund()`:

<!-- guide: unchecked the error an edit of the program above produces -->
  ```
  error[M-Opaque]: `Ticket` is opaque outside `box_office`
    --> box-office/main.lin:11:9
     |
  11 |     let Ticket { seat: _, cents: back } = yours
     |         ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ only its own module can take one apart
  ```

- **Releasing it** only works if the module implemented `Release`. `Ticket`
  does not, so `Release.release(yours)`, on a line before
  `let back = yours.refund()`, is refused:

<!-- guide: unchecked the error an edit of the program above produces -->
  ```
  error[T-Bound]: `Release` requires `Self` to implement it, and `Ticket` does not
    --> box-office/main.lin:11:21
     |
  11 |     Release.release(yours)
     |                     ^^^^^ implement it for that type in `box_office`, or reach the operation on one that does
  ```

  `[T-Bound]` means a type is missing a trait that the operation needs.

`net.Listener` and `net.Connection` are opaque and linear for the same reason.
You cannot build a connection out of a number that happens to be a file
descriptor, and you cannot lose one without closing it. The
[accounts example](../../examples/accounts/) seals a linear account the same
way.

If you know Rust, `@opaque struct Ticket` is a `pub struct Ticket` whose fields
are private, and `@opaque type Email = Str` is `pub struct Email(String)` with a
private field. Linea goes further in three ways: the seal works on enums too,
where Rust's variants are always public; outside the module you cannot even
`match` the value, not even with a lone `_` arm; and with `@linear`, code
outside the module cannot drop the value, which Rust always allows.

### Contracts may name sealed fields, but only at home

Look again at `seat_label`:

<!-- guide: excerpt docs/learn/04-copying-settling-and-sealing.md -->
```linea
pub fn seat_label(self: Self) -> Str where carries(self.seat) {
    copy(self.seat)
}
```

The clause `carries(self.seat)` tells callers *the text you get back comes
from wherever the seat's text came from — not from the ticket itself*. That is
why `main` could redeem the ticket and still print `seat` afterwards.
([Borrowing](06-borrowing.md) explains `carries` in full.)

That clause names a sealed field, and the module that declares the type is
allowed to do that. It tells callers what the result depends on without
letting them touch the field. It also means that renaming `seat` changes what
`seat_label` promises, so treat such a rename as a change to your public
interface.

Any other module is not allowed to name the field, even in a clause. Add
this function to `main.lin`:

<!-- guide: edit box-office/main.lin after 4 use box_office.Ticket -->
```linea
fn seat_of(ticket: Ticket) -> Str where carries(ticket.seat) {
    ticket.seat_label()
}
```

and call it in place of `let seat = mine.seat_label()`:

<!-- guide: edit box-office/main.lin 9 let seat = mine.seat_label() -->
```linea
    let seat = seat_of(mine)
```

```
error[M-Opaque]: `Ticket` is opaque outside `box_office`
 --> box-office/main.lin:5:56
  |
5 | fn seat_of(ticket: Ticket) -> Str where carries(ticket.seat) {
  |                                                        ^^^^ only its own module's contracts can name its parts
```

### An operation can share a sealed field's name

A dot call with parentheses always looks for an operation and never reads a
field ([Calling things](02-calling-things.md#a-dot-call-never-reaches-a-field)).
So `box_office` can name its operation `seat` instead of `seat_label`, and
`let seat = mine.seat()` in `main` reaches it even though the field `seat` is
sealed. Leave out the parentheses and you are reading the sealed field again:

<!-- guide: unchecked the error an edit of the program above produces -->
```
error[M-Opaque]: `Ticket` is opaque outside `box_office`
 --> box-office/main.lin:9:16
  |
9 |     let seat = mine.seat
  |                ^^^^^^^^^ only its own module can read its parts
```

**What you can do now:** pair `@opaque` with `@linear` when the module should
be the only place that can both create a value and end it.

## What you have seen

| You want | Write |
| --- | --- |
| an ordinary record that moves and may be dropped | nothing; affine is the default |
| to allow copies | `@copyable`, then `copy(value)` |
| a type tag that stores nothing | `struct Id[phantom Of] { ... }` |
| a value only your module can make | `@opaque type Email = Str` or `@opaque struct Account { … }`, with a `pub fn` that checks |
| a value that must end in one of your functions | `@linear` |
| a default way to end it | `@(linear, derive(Release))` or `impl Release for T` |
| a value only your module can create and end | `@(opaque, linear)` on a struct |
| to settle on every exit from a block | `defer value.release()`, or `defer let value = ...` to bind and settle at once |

These are the errors the chapter's rules produce:

| Error | What it is telling you | What usually fixes it |
| --- | --- | --- |
| `O-Move` | You used a value after giving it away | Give it away last, pass it without `sink`, or `copy` it if the type is copyable |
| `O-Copy` | You wrote `copy` on a type that does not allow it | Move the value instead, or mark the type `@copyable` |
| `O-ScalarCopy` | You wrote `copy` on a number or `Bool` | Delete the `copy`; reading it already copies |
| `O-Universe` | A copyable type has a field that cannot be copied | Remove `@copyable`, or make the field copyable |
| `O-Leak` | A value that must be settled was not | Pass it to a function that settles it, or `release()` it if its type implements `Release` |
| `O-Merge` | One path settled a value and another did not | Settle it on every path, or on none |
| `O-DeferDead` | A `defer` settles a value that every path gives away first | Delete the `defer` |
| `T-DeferLet` | `defer let` over a type with no `Release`, which has no single ending to schedule | Write `let`, then `defer` the operation that ends it |
| `M-Opaque` | You reached inside an opaque type from outside its module | Use the functions the module provides |
| `T-Bound` | A type lacks a trait the operation needs, such as `Release` | Implement or derive the trait, or use another operation |
| `N-Unused` | A type parameter that no field uses | Declare it `phantom`, or remove it |
| `S-Entry` | An attribute or a visibility is written in a shape the language does not accept | Use `@`, pick one of `copyable` and `linear`, drop `pub` or `internal` beside `@opaque` |

The examples put these types to work. The [accounts
example](../../examples/accounts/) seals a linear account behind a module; the
[payment batch](../../examples/payment_batch.lin) commits or rolls back each
linear payment; the [discounts example](../../examples/discounts/) uses a
ranged `Percent` and an opaque email address; the [TCP echo
server](../../examples/tcp_echo.lin) settles every connection it accepts.

Next: [Iterating](05-iterating.md) — `for`, chains of `map`, `filter` and
`fold`, and emptying a collection of values that must be consumed.
