# Iterating

Most programs spend their time walking through collections: adding up an
order, finding the first free seat, refunding every payment left in a queue.
This chapter covers the ways to do that. It starts with the plain `for` loop,
which is all most walks need, then the other ways a `for` can hold what it
walks, and how a type of your own becomes something a `for` can walk. Next come
**chains** such as `prices.map(…).filter(…).fold(…)`, which say in one line
what a loop would do, and the pairs `enumerate` and `zip` hand out. The later
sections cover the less common tools: collecting into a `Vec`, callbacks that
keep their state, and collections of values that must be consumed, such as
payments, and how to empty them one by one.

## Walking with `for`

`for item in sequence` takes the items of a sequence one at a time and runs its
body for each. A range, such as `1..=3`, is a sequence, and so is an array:

```linea
import std.io

fn main() -> Result[UInt8, io.IoError] {
    // `for` takes each item of a sequence in turn. A range is a sequence.
    var total = 0
    for cents in [250, 170, 40] {
        total += cents
    }
    io.println("The order costs {total} cents.")?
    for seat in 1..=3 {
        io.println("seat {seat}")?
    }
    .Ok(0)
}
```

```
The order costs 460 cents.
seat 1
seat 2
seat 3
```

`cents` and `seat` are new names that hold one item for one pass of the body.
Everything else in this chapter is another way to say the same walk, or a way
to walk something that is not an array or a range.

## Four ways to walk

[Linea in an hour](01-linea-in-an-hour.md#for-and-for-read) showed that
`for x in xs` takes `xs` and that `for read x in xs` leaves it whole. There are
two more forms. `for inout x in xs` lends each element to the body, which may
change it in place, and `for x in &it`, near the end of this chapter, lends an
iterator to the walk. `for read` and `for inout` work on a `Vec` as they do on
an array:

```linea
import std.io

fn main() -> Result[UInt8, io.IoError] {
    defer var prices: Vec[UInt64] = Vec.new()
    for cents in [UInt64(250), 170, 40] {
        if &prices.push(cents).is_err() {
            return .Ok(1)
        }
    }
    // `for inout` lends each price to the body, which raises it by a tenth.
    for inout cents in prices {
        cents += cents / 10
    }
    // `for read` looks at each price and leaves the vector as it is.
    var total = 0
    for read cents in prices {
        total += cents
    }
    io.println("{prices.length()} prices, {total} cents in all")?
    .Ok(0)
}
```

```
3 prices, 506 cents in all
```

| Loop | What happens to `xs` | The binder `x` |
| --- | --- | --- |
| `for x in xs` | taken: the loop owns it from then on | each element, handed over |
| `for read x in xs` | lent for reading, and unchanged afterwards | each element, to look at |
| `for inout x in xs` | lent for changing; `xs` must be a `var` | each element, to change in place |
| `for x in &it` | an iterator lent to the loop, which stays yours | each item, handed over |

`for inout` is Rust's `for x in xs.iter_mut()`, and `for read` is
`for x in xs.iter()`. In Linea the loop says it, not the collection.

A `Vec` is walked with `for read` or `for inout`, but not with a plain `for`.
Taking a vector's elements out is a separate choice with operations of its
own, so a plain `for` over a vector is refused. Write `for cents in prices` in
place of `for read cents in prices` above:

<!-- guide: unchecked the error an edit of the program above produces -->
```
error[T-For]: `Vec[UInt64, mem.SystemAllocator]` implements no `Sequence`
  --> vec_for.lin:18:18
   |
18 |     for cents in prices {
   |                  ^^^^^^ a `for` walks what a `Sequence` says how to walk
   |
   = help: look at each element with `for read cents in prices`, change each in place with `for inout cents in prices`, walk a view of it with `for cents in prices.as_slice()`, or take its elements out with `prices.drain()`
```

`Sequence` is the trait of the values a plain `for` can take, which the next
section explains, and a vector does not implement it. The help line names the
four ways to walk a vector, which the list below takes in turn.

To walk a vector, pick the form that says what should happen to its elements:

- `for read x in v` or `for inout x in v` to look at them or change them, and
  keep the vector;
- `for x in v.as_slice()` to walk a view of them, as `as_slice()` does for an
  array, which is how a chain starts from a vector;
- `for x in v.drain()`, or a walk lent `&pending`, to take them out, which the
  last sections of this chapter cover.

A slice is walked with `for read` too. A function that takes a
`mem.Slice[T]` serves an array and a vector alike, and `for read` lends it
each element the view sees:

```linea
import std.io
import std.mem

// `for read` lends each amount the slice views; the amounts stay with the
// array or vector behind it.
fn wettest(rainfall: mem.Slice[UInt64]) -> UInt64 {
    var most: UInt64 = 0
    for read millimetres in rainfall {
        if millimetres > most {
            most = millimetres
        }
    }
    most
}

fn main() -> Result[UInt8, io.IoError] {
    let week = [UInt64(12), 30, 7]
    io.println("wettest day this week: {wettest(week.as_slice())} mm")?
    defer var today: Vec[UInt64] = Vec.new()
    for millimetres in [UInt64(3), 5, 1] {
        if &today.push(millimetres).is_err() {
            return .Ok(1)
        }
    }
    io.println("wettest hour today: {wettest(today.as_slice())} mm")?
    .Ok(0)
}
```

```
wettest day this week: 30 mm
wettest hour today: 5 mm
```

A slice is a view: it can be copied freely and may look at storage nothing may
write, so it lends its elements only for reading. `for inout` over a slice is
refused; change the elements through the array or vector itself.

## What a `for` can walk: sequences and iterators

A range, such as `1..=3`, and a slice, such as `highs.as_slice()`, are
**sequences**: values a plain `for` can take and walk. So are the Unicode
scalars of a text, `text.scalars()`, which [Text](08-text.md) walks. A
sequence hands the loop an **iterator**, which is the value
that actually walks: the `Iterator` trait has one operation, `next`, which
answers the next item as `.Some(item)`, or `.None` when there is nothing left.
Every iterator is also a sequence of itself, so a `for` walks an iterator
directly.

Implement `Iterator` for a type of your own, and a `for` can walk it:

```linea
import std.io

// A countdown hands out the seconds left, down to 1.
struct Countdown {
    left: UInt64,
}

// `next` answers the next second, or `.None` once the countdown is over.
impl Iterator for Countdown {
    type Item = UInt64

    fn next(inout self: Self) -> Option[UInt64] {
        if self.left == 0 {
            return .None
        }
        self.left -= 1
        .Some(self.left + 1)
    }
}

fn main() -> Result[UInt8, io.IoError] {
    let launch = Countdown { left = 3 }
    for second in launch {
        io.println("{second}...")?
    }
    io.println("liftoff")?
    .Ok(0)
}
```

```
3...
2...
1...
liftoff
```

`type Item = UInt64` names what the iterator hands out, and `next` takes the
countdown `inout`, because each call moves it on. The loop calls `next` until
it answers `.None`.

### A field whose type a trait names

`Iterator` declares a type of its own, `Item`, and each implementation says
what it is. A trait of yours can declare one the same way, and a generic
struct can use it as the type of a field:

```linea
import std.io

// A sensor takes readings of a type it names itself, `Reading`, and
// `measure` takes one.
trait Sensor {
    type Reading

    fn measure(self: Self) -> Self.Reading
}

// A thermometer reads whole degrees.
struct Thermometer {
    celsius: Int64,
}

impl Sensor for Thermometer {
    type Reading = Int64

    fn measure(self: Self) -> Int64 {
        self.celsius
    }
}

// A log entry keeps a sensor and one reading it took. The reading's type is
// whatever the sensor's `Reading` is, so a thermometer's entry holds an
// `Int64`.
struct Entry[S: Sensor] {
    sensor: S,
    reading: S.Reading,
}

fn main() -> Result[UInt8, io.IoError] {
    let hall = Thermometer { celsius = 21 }
    let entry = Entry[Thermometer] { reading = hall.measure(), sensor = hall }
    io.println("The hall read {entry.reading} degrees.")?
    .Ok(0)
}
```

```
The hall read 21 degrees.
```

`type Reading` in the trait declares the type, and `type Reading = Int64` in
the implementation settles it for thermometers. The literal writes `reading`
first because fields are evaluated in the order they are written, so
`hall.measure()` reads the hall before `sensor = hall` moves it into the entry. In `Entry`, `S.Reading` is
whatever `S`'s implementation settles it to, so an `Entry[Thermometer]` holds
an `Int64`. Rust writes the same field as `reading: S::Reading`.

The implementation has to settle the type to something that does not lead
back to itself. A hall whose reading is an optional hall reading never names
a type, and is refused:

```linea
trait Sensor {
    type Reading
}

struct Hall {}

impl Sensor for Hall {
    type Reading = Option[Hall.Reading]
}

fn main() -> UInt8 {
    0
}
```

```
error[T-Impl]: this associated type is defined through itself: `Hall.Reading` is `Option[Hall.Reading]`
 --> mirror.lin:8:20
  |
8 |     type Reading = Option[Hall.Reading]
  |                    ^^^^^^^^^^^^^^^^^^^^ define it as a type that does not read back to itself
```

An array is not a sequence. A `for` walks an array directly, element by
element, and `as_slice()` lends an array out as a slice, which is a sequence:
that is how the chains below start from one.

## Chains: `map`, `filter` and `fold`

Every sequence offers operations that walk it for you. Chained one after
another, they say what a loop would do in one line per step:

```linea
import std.io

struct Line {
    item: Str,
    cents: UInt64,
    quantity: UInt64,
}

fn main() -> Result[UInt8, io.IoError] {
    let order = [
        Line { item = "coffee", cents = 250, quantity = 2 },
        Line { item = "croissant", cents = 175, quantity = 1 },
        Line { item = "jam", cents = 40, quantity = 12 },
    ]
    // `map` turns each line into what it costs, and `fold` adds the costs up,
    // starting from 0.
    let total = order.as_slice().map(|sink line| line.cents * line.quantity).fold(0, |sink sum, sink cost| sum + cost)
    io.println("The order costs {total} cents.")?
    // `filter` keeps the lines bought more than once. Each step of the chain
    // can sit on a line of its own.
    let several = order
        .as_slice()
        .filter(|line| line.quantity > 1)
        .map(|sink line| line.quantity)
        .fold(0, |sink count, sink quantity| count + quantity)
    io.println("{several} items came in twos or more.")?
    .Ok(0)
}
```

```
The order costs 1155 cents.
14 items came in twos or more.
```

- `order.as_slice()` is a slice of the three lines. Walking a slice hands out
  each element as a view, `borrow Line`, so `line.cents` reads the field of
  the line it points at ([Borrowing](06-borrowing.md) covers views).
- `map(f)` hands each item to `f` and passes on what `f` returns. The lambda
  takes its item with `sink`, because `map` hands the item over.
- `filter(p)` passes on the items `p` accepts and drops the others. `filter`
  keeps each item to pass it on, so it only lets `p` look at it, and the
  lambda's parameter has no `sink`.
- `fold(start, f)` walks everything, carrying a running value: it starts with
  `start` and replaces it with `f(value, item)` for each item.

`map` and `filter` do no work when they are called. Each answers an adapter, a
new iterator that holds the one before it, and nothing runs until something
walks the whole chain: `fold` here, or a `for`, or `collect` below. Rust
programmers know this as lazy iterators. A chain starts from a sequence; an
array or a vector lends one with `as_slice()`, as Rust's `.iter()` does.

The second chain puts each step on a line of its own. A line that opens with
`.` and a lowercase name continues the expression on the line above ([Linea in
an hour](01-linea-in-an-hour.md#where-a-statement-ends)), so a chain reads top
to bottom, one step per line.

## Nothing runs until something walks it

An adapter does its work only when the walk asks it for an item, and only as
much as that item needs. A source that never runs out is therefore safe to
chain, as long as something in the chain stops asking. This program squares
the natural numbers, keeps the even squares, and takes five:

```linea
import std.io

// Naturals counts up from `at` and never runs out: `next` always answers Some.
struct Naturals { at: UInt64 }

impl Iterator for Naturals {
    type Item = UInt64

    fn next(inout self: Self) -> Option[UInt64] where carries() {
        let value = self.at
        self.at += 1
        .Some(value)
    }
}

fn main() -> Result[UInt8, io.IoError] {
    var squared: UInt64 = 0
    var tested: UInt64 = 0
    // Each stage counts its calls, so the totals show how much ran.
    let firsts = Naturals { at = 0 }
        .map(inout [inout squared] |sink n| {
            squared += 1
            n * n
        })
        .filter(inout [inout tested] |square| {
            tested += 1
            square % 2 == 0
        })
        .take(5)
    for square in firsts {
        io.println("took {square}")?
    }
    io.println("map ran {squared} times, filter ran {tested} times")?
    .Ok(0)
}
```

```
took 0
took 4
took 16
took 36
took 64
map ran 9 times, filter ran 9 times
```

`Naturals` never answers `.None`, yet the walk ends: `take(5)` asked `filter`
for five items and then stopped asking. To find five even squares, `filter`
pulled the squares of 0 through 8, nine items, and rejected the odd ones, 1,
9, 25 and 49. `map` ran once for each item `filter` pulled, so it ran nine
times too, and never for 9 or anything after it. Building the chain ran
nothing at all: both counters were still 0 when the `for` began.

Each stage counts its calls through an `inout` capture, because a lambda
cannot print as it goes: `io.println` answers a `Result`, which may not be
dropped ([T-Discard]), and the lambda returns a number, so `?` has no
`Result` to hand the failure to.

## Pairs from `enumerate` and `zip`

Two operations hand out pairs. `enumerate` pairs each item with its position,
counting from 0, and `zip` pairs the items of two sequences, stopping when
either one ends. A pair is a **tuple**, written `(a, b)`
([Linea in an hour](01-linea-in-an-hour.md#tuples)), and a `for` takes it apart
with a pattern, so the loop names both halves:

```linea
import std.io

fn main() -> Result[UInt8, io.IoError] {
    let order = ["coffee", "croissant", "jam"]
    let cents = [250, 175, 40]
    // `enumerate` pairs each item with its position, counting from 0.
    for (i, item) in order.as_slice().enumerate() {
        io.println("{i + 1}. {*item}")?
    }
    // `zip` pairs the items of two sequences and stops when either ends.
    for (item, price) in order.as_slice().zip(cents.as_slice()) {
        io.println("{*item} costs {*price} cents")?
    }
    .Ok(0)
}
```

```
1. coffee
2. croissant
3. jam
coffee costs 250 cents
croissant costs 175 cents
jam costs 40 cents
```

`(i, item)` names the position and the item where the loop begins, with no
`.0` or `._1` in the body. The items here come from slices, so each one is a
view of a `Str` in the array, and `*item` reads the text it points at, just as
`*cents` read a number in the chains above.

A component of the pattern can be a pattern of its own. Here each item is a
pair whose first part is itself a pair, and one pattern names all three:

```linea
import std.io

fn main() -> Result[UInt8, io.IoError] {
    let order = ["coffee", "croissant", "jam"]
    let cents = [250, 175, 40]
    // `enumerate` pairs each item with its position, and `zip` pairs that
    // pair with a price, so the pattern takes a pair inside a pair apart.
    for ((i, item), price) in order.as_slice().enumerate().zip(cents.as_slice()) {
        io.println("{i + 1}. {*item}: {*price} cents")?
    }
    .Ok(0)
}
```

```
1. coffee: 250 cents
2. croissant: 175 cents
3. jam: 40 cents
```

A slice hands out borrowed items, so a slice of pairs cannot be taken apart
the same way. The pair is something you only look at, and a pattern in a plain
`for` takes its value apart, which a view does not allow:

```linea
import std.io

fn main() -> Result[UInt8, io.IoError] {
    let spans = [(1, 4), (2, 9), (5, 6)]
    var longest = 0
    for (start, end) in spans.as_slice() {
        if end - start > longest {
            longest = end - start
        }
    }
    io.println("The longest span is {longest}.")?
    .Ok(0)
}
```

```
error[T-Mismatch]: this takes a tuple apart, and the value is a `borrow (Int64, Int64)`
 --> spans_slice.lin:6:9
  |
6 |     for (start, end) in spans.as_slice() {
  |         ^^^^^^^^^^^^ a tuple pattern takes a tuple apart
```

Walk the array with `for read`, which lends each pair and takes it apart as it
goes:

```linea
import std.io

fn main() -> Result[UInt8, io.IoError] {
    let spans = [(1, 4), (2, 9), (5, 6)]
    var longest = 0
    for read (start, end) in spans {
        if end - start > longest {
            longest = end - start
        }
    }
    io.println("The longest span is {longest}.")?
    .Ok(0)
}
```

```
The longest span is 7.
```

### `zip` draws from its first sequence first

`zip` asks the first sequence for an item before it asks the second. When the
second has already ended, the item just drawn from the first has no pair, so
`zip` drops it. A value that must be consumed cannot be dropped, so `zip`
asks for Discardable items from its first sequence, as `filter` does. Here the
payments come first and the tills second:

```linea
import std.io

// A payment must be consumed exactly once: committed or refunded.
@linear
struct Payment {
    cents: UInt64,
}

impl Payment {
    // Committing puts the money in the till.
    fn commit(sink self: Self, inout takings: UInt64) {
        let Payment { cents } = self
        takings += cents
    }
}

fn main() -> Result[UInt8, io.IoError] {
    let orders = [UInt64(250), 320, 180]
    let tills = ["north", "south", "east"]
    var takings = 0
    let payments = orders.as_slice().map(|sink cents| Payment { cents = *cents })
    for (payment, till) in payments.zip(tills.as_slice()) {
        payment.commit(&takings)
        io.println("{*till} till done, {takings} cents so far")?
    }
    io.println("took {takings} cents")?
    .Ok(0)
}
```

```
error[T-Bound]: `Self.Iter.Item` requires `Discardable`, and `Payment` does not have that capability
   --> zip_payments.lin:22:37
    |
22  |     for (payment, till) in payments.zip(tills.as_slice()) {
    |                                     ^^^ `zip` may dispose of a `Payment`, so it requires the type to be Discardable; give the value to an operation that keeps it, or settle it before. `zip` draws an item from the first sequence before asking the second, and if the second sequence ends first it disposes of that first item, so the first sequence's items must be Discardable; zip in the other order, with the sequence whose items are Discardable first, or walk both sequences by hand
   ::: std/iter/iter.lin
100 |         Self.Iter.Item: Discardable
    |         -------------- required by this `where` clause
```

The error names the way out. Put the sequence whose items may be dropped first,
and the payments second, where `zip` never drops one of them. Each pair is taken apart in
the loop, and `commit` settles each payment:

<!-- guide: edit 22-26 for (payment, till) in payments.zip(tills.as_slice()) { … io.println("took {takings} cents")? -->
```linea
    for (till, payment) in tills.as_slice().zip(payments) {
        payment.commit(&takings)
        io.println("{*till} till done, {takings} cents so far")?
    }
    io.println("took {takings} cents")?
```

```
north till done, 250 cents so far
south till done, 570 cents so far
east till done, 750 cents so far
took 750 cents
```

Only the first sequence is held to the rule: `zip` never drops what the second
sequence hands out, because it asks the second only after the first has an
item to pair it with. The other way out, which the error also names, is to
walk both sequences by hand and settle a payment yourself when the tills run
out.

### `take` and `skip`

`take(count)` ends the walk after `count` items, and it stops asking its source
at that point, so it needs no bound and accepts items that must be consumed.
That makes it the way to walk part of a sequence that never ends. `skip(count)`
passes over the first `count` items and hands out the rest. It asks for each
item it passes and drops it, so, like `zip`'s first sequence, it needs
Discardable items:

```linea
import std.io

// Tickets are numbered without end: `next` always answers another number.
struct Tickets {
    number: UInt64,
}

impl Iterator for Tickets {
    type Item = UInt64

    fn next(inout self: Self) -> Option[UInt64] {
        self.number += 1
        .Some(self.number)
    }
}

fn main() -> Result[UInt8, io.IoError] {
    // `take(3)` ends the walk after three tickets, so it never asks the
    // endless `Tickets` for a fourth.
    let first = Tickets { number = 0 }
    for ticket in first.take(3) {
        io.println("ticket {ticket}")?
    }
    // `skip(100)` passes over the first hundred tickets and hands out the
    // rest, and `take(2)` ends the walk after two of them.
    let later = Tickets { number = 0 }
    for ticket in later.skip(100).take(2) {
        io.println("ticket {ticket}")?
    }
    .Ok(0)
}
```

```
ticket 1
ticket 2
ticket 3
ticket 101
ticket 102
```

Walking a chain with `for` takes it. When the loop may stop early and you want
the sources back, walk the chain lent, `for pair in &chain`, and then call
`into_parts` (the end of this chapter covers lent walks). A `zip` answers a pair, its two sources, each as far as it
advanced:

```linea
import std.io

struct Tickets {
    number: UInt64,
}

impl Iterator for Tickets {
    type Item = UInt64

    fn next(inout self: Self) -> Option[UInt64] {
        self.number += 1
        .Some(self.number)
    }
}

fn main() -> Result[UInt8, io.IoError] {
    var pairs = (Tickets { number = 0 }).zip(Tickets { number = 100 })
    for (a, b) in &pairs {
        io.println("{a} and {b}")?
        if a == 2 {
            break
        }
    }
    // `into_parts` hands back both sources, each as far as it advanced.
    let (left, right) = pairs.into_parts()
    io.println("the first source stopped at {left.number}, the second at {right.number}")?
    .Ok(0)
}
```

```
1 and 101
2 and 102
the first source stopped at 2, the second at 102
```

`let (left, right) = pairs.into_parts()` takes the pair of sources apart in one
line. `map`, `filter_map` and `filter` offer `into_parts` too, and answer the
source and the callback.

## Asking questions: `any`, `all` and `find`

`fold` walks the chain as soon as it is called, and so do the operations
below. Each takes the chain, walks it until it has an answer, and drops what
is left:

```linea
import std.io

struct Line {
    item: Str,
    cents: UInt64,
    quantity: UInt64,
}

fn main() -> Result[UInt8, io.IoError] {
    let order = [
        Line { item = "coffee", cents = 250, quantity = 2 },
        Line { item = "croissant", cents = 175, quantity = 1 },
        Line { item = "jam", cents = 40, quantity = 12 },
    ]
    // `any` and `all` stop at the first line that settles the answer.
    let has_pastry = order.as_slice().any(|sink line| line.item == "croissant")
    let all_under_300 = order.as_slice().all(|sink line| line.cents < 300)
    io.println("pastry: {has_pastry}, all under 300 cents: {all_under_300}")?
    // `find` answers the first line the predicate accepts, or `.None`.
    match order.as_slice().find(|line| line.quantity > 10) {
        Some(line) => io.println("bulk item: {line.item}")?,
        None => io.println("no bulk item")?,
    }
    .Ok(0)
}
```

```
pastry: true, all under 300 cents: true
bulk item: jam
```

| Operation | Adapter or terminal | Answers | Lambda takes the item with `sink`? |
| --- | --- | --- | --- |
| `map(f)` | adapter | a chain of what `f` returns | yes |
| `filter(p)` | adapter | a chain of the items `p` accepts | no |
| `fold(start, f)` | terminal | `start` combined with every item by `f` | yes |
| `any(p)` | terminal | whether some item satisfies `p`, stopping at the first that does | yes |
| `all(p)` | terminal | whether every item satisfies `p`, stopping at the first that does not | yes |
| `find(p)` | terminal | the first item `p` accepts, as an `Option` | no |
| `find_map(f)` | terminal | the first `.Some` that `f` returns | yes |
| `for_each(f)` | terminal | nothing: it hands every item to `f`, as a `for` loop would | yes |
| `count()` | terminal | how many items there are, as a `UInt64` | no lambda |

An adapter answers a new chain and runs nothing until that chain is walked; a
terminal walks the chain as soon as it is called.

The rule behind the last column is one question: does the operation still need
the item after the lambda has seen it? `filter` passes the item on and `find`
hands it back to you, so they only let the lambda look at it, and the lambda's
parameter has no `sink`. Every other operation is done with the item once the
lambda has it, so it gives the item away, and the lambda takes it with `sink`.
`any` and `all` only ask a question, but they drop each item after asking, so
their lambdas still take it.

Guess wrong and the lambda does not fit the operation. Leave the `sink` off
`any`'s lambda in the program above:

<!-- guide: unchecked the error an edit of the program above produces -->
```
error[T-Call]: this lambda takes `line` as `read`, and the expected callable passes parameter 1 as `sink`
  --> any_nosink.lin:17:44
   |
17 |     let has_pastry = order.as_slice().any(|line| line.item == "croissant")
   |                                            ^^^^ write `sink line`
```

The lambda's first parameter has the wrong convention: the lambda was written
to look, and `any` hands it the item. The same error comes back for a `sink`
written on `filter`'s or `find`'s lambda.

`filter_map` and `collect`, which come later in this chapter, follow the same rule.

Each chain starts again from `order.as_slice()`, because walking a chain takes
it: once `any` has walked the slice, the slice is gone. A slice is only a
view, so making another costs nothing.

### Counting with `count`

`count()` walks a chain to its end and answers how many items it yielded. It
takes no lambda; put a `filter` in front of it to count only some items:

```linea
import std.io

fn main() -> Result[UInt8, io.IoError] {
    let temperatures = [Int64(18), 24, 31, 27, 16, 33]
    // `count` walks the whole chain and answers how many items reached it.
    let days = temperatures.as_slice().count()
    let hot = temperatures.as_slice().filter(|degrees| *degrees > 25).count()
    io.println("{hot} of {days} days were above 25 degrees.")?
    .Ok(0)
}
```

```
3 of 6 days were above 25 degrees.
```

`count` drops each item once it has counted it, and then the iterator it
walked, so it needs both to be Discardable, as `fold` does. To count the items
of an iterator that must be settled, lend it to a `for x in &it` loop, which
the last sections of this chapter cover, and count in the body.

## `filter` drops what it rejects; `filter_map` hands it to you

`filter` drops every item its predicate rejects. That is fine for numbers and
views, and for most records, but not for a value that must be consumed exactly
once ([Copying, settling and
sealing](04-copying-settling-and-sealing.md#linear-values-you-must-not-forget)).
A type whose values may be dropped is called **Discardable**, and `filter`
asks for Discardable items. Here a café turns each order into a payment, and
tries to keep only the payments below its limit:

```linea
import std.io

// A payment must be consumed exactly once: committed or refunded.
@linear
struct Payment {
    cents: UInt64,
}

impl Payment {
    // Committing puts the money in the till.
    fn commit(sink self: Self, inout takings: UInt64) {
        let Payment { cents } = self
        takings += cents
    }
}

fn main() -> Result[UInt8, io.IoError] {
    let orders = [UInt64(250), 1800, 320, 2500]
    let limit = 1000
    var takings = 0
    let accepted = orders
        .as_slice()
        .map(|sink cents| Payment { cents = *cents })
        .filter([limit] |payment| payment.cents <= limit)
    for payment in accepted {
        payment.commit(&takings)
    }
    io.println("took {takings} cents")?
    .Ok(0)
}
```

```
error[T-Bound]: `Self.Iter.Item` requires `Discardable`, and `Payment` does not have that capability
  --> payments_filter.lin:24:10
   |
24 |         .filter([limit] |payment| payment.cents <= limit)
   |          ^^^^^^ `filter` may dispose of a `Payment`, so it requires the type to be Discardable; give the value to an operation that keeps it, or settle it before
  ::: std/iter/iter.lin
82 |         Self.Iter.Item: Discardable
   |         -------------- required by this `where` clause
```

`Self.Iter.Item` is the type of the items the chain hands out, `Payment`. The
label says what `filter` would do with one: it may drop it. The line from
`std/iter/iter.lin` is the `where` clause on `filter` that asks for
Discardable items. A **capability** is
a permission a type has: Discardable says its values may be dropped, and
Copyable that they may be copied. A linear `Payment` has neither.

What should happen to a rejected payment is a decision only the program can
make. `filter_map` leaves it to you: it hands each item over, and the callback
answers `.Some(item)` to keep it, or `.None` after dealing with it. Here a
rejected payment is refunded, and the refunds are counted in `refunded`:

```linea
import std.io

// A payment must be consumed exactly once: committed or refunded.
@linear
struct Payment {
    cents: UInt64,
}

impl Payment {
    // Committing puts the money in the till.
    fn commit(sink self: Self, inout takings: UInt64) {
        let Payment { cents } = self
        takings += cents
    }

    // Refunding hands the money back, and answers how much it was.
    fn refund(sink self: Self) -> UInt64 {
        let Payment { cents } = self
        cents
    }
}

fn main() -> Result[UInt8, io.IoError] {
    let orders = [UInt64(250), 1800, 320, 2500]
    let limit = 1000
    var takings = 0
    var refunded = 0
    // A payment over the limit is refunded, and the callback answers `.None`,
    // so only the payments below the limit reach the loop.
    let accepted = orders
        .as_slice()
        .map(|sink cents| Payment { cents = *cents })
        .filter_map(inout [limit, inout refunded] |sink payment| {
            if payment.cents <= limit {
                return .Some(payment)
            }
            refunded += payment.refund()
            .None
        })
    for payment in accepted {
        payment.commit(&takings)
    }
    io.println("took {takings} cents, refunded {refunded} cents")?
    .Ok(0)
}
```

```
took 570 cents, refunded 4300 cents
```

`[limit, inout refunded]` reads `limit` and lends `refunded` to the callback to
change, and the `inout` before the list lets each call change it ([Calling
things](02-calling-things.md#a-closure-that-changes-a-value-of-yours)). Every
payment is consumed exactly once: the loop commits the ones the callback kept,
and the callback refunds the rest. `filter_map` is the general form of
`filter`, and it also changes each item on the way, as `map` does. Reach for
it whenever what `filter` would drop needs a decision.

## Collecting into a `Vec`

`collect` gathers everything a chain hands out into a new `Vec`:

```linea
import std.io

struct Line {
    item: Str,
    cents: UInt64,
    quantity: UInt64,
}

fn main() -> Result[UInt8, io.IoError] {
    let order = [
        Line { item = "coffee", cents = 250, quantity = 2 },
        Line { item = "croissant", cents = 175, quantity = 1 },
        Line { item = "jam", cents = 40, quantity = 12 },
    ]
    // `collect` gathers what the chain hands out into a new `Vec`.
    let { values: names, iterator: _ } = order
        .as_slice()
        .map(|sink line| copy(line.item))
        .collect()
        .settled() else |_| {
        return .Ok(1)
    }
    defer names.release()
    io.println("{names.length()} items, the first is {names[0]}")?
    .Ok(0)
}
```

```
3 items, the first is coffee
```

`collect` needs memory for the new vector, so it takes an allocator and can
fail ([Memory](07-memory.md) covers allocators). On success it answers a pair of
fields: `values`, the new vector, and `iterator`, the chain it walked, which
comes back because the chain may still hold something you want. The pattern
`let { values: names, iterator: _ }` takes the pair apart, a struct pattern
whose type the compiler already knows. It keeps the vector as `names` and
drops the finished chain. `settled()` turns a refused collection into its
reason, `mem.Oom`, releasing what was gathered so far
([Errors](03-errors.md#failures-that-hand-a-value-back)). `map` writes
`copy(line.item)` because `line` is only a view of the order's line, and
nothing can be moved out through a view; copying the `Str` copies a view of
the name, not its text.

## Sorting a `Vec`: `sort` and `sort_by`

`sort` puts a vector's elements in ascending order, in place. `sort_by` orders
them by a comparison you write, which answers whether `left` belongs before
`right`. An array's view and a map cannot be reordered, so collect what you
want sorted into a `Vec` first. A fixed array has no `sort` either: copy its
elements into a `Vec`, as the programs below do with `collect`, or build one
with `Vec.from_fn`:

```linea
import std.io

struct Line {
    item: Str,
    cents: UInt64,
}

fn main() -> Result[UInt8, io.IoError] {
    let order = [
        Line { item = "jam", cents = 40 },
        Line { item = "tea", cents = 175 },
        Line { item = "coffee", cents = 250 },
        Line { item = "croissant", cents = 175 },
    ]
    let { values: names, iterator: _ } = order.as_slice().map(|sink line| copy(line.item)).collect().settled() else |_| {
        return .Ok(1)
    }
    defer var sorted = names
    // `sort` puts the names in ascending order.
    &sorted.sort()
    io.println("{sorted.as_slice():?}")?
    let { values: viewed, iterator: _ } = order.as_slice().collect().settled() else |_| {
        return .Ok(1)
    }
    defer var lines = viewed
    // `sort_by` orders by a comparison you write: the dearest line first.
    &lines.sort_by(|left, right| left.cents > right.cents)
    for line in lines.as_slice() {
        io.println("{line.cents:>4} {line.item}")?
    }
    .Ok(0)
}
```

```
["coffee", "croissant", "jam", "tea"]
 250 coffee
 175 tea
 175 croissant
  40 jam
```

The tea and the croissant cost the same, so the comparison puts neither before
the other, and they keep the order they had in `order`: both sorts are
*stable*. Neither allocates, so neither can fail, and both make O(n log n)
comparisons. Like Rust's `sort` and `sort_by`, they reorder the vector itself;
unlike Rust's `sort_by`, the comparison answers a `Bool`, "does `left` come
first?", rather than an ordering.

`sort` needs an element type that is `Ordered`: one where any two values are
equal or one is less than the other. Integers, `Str`, tuples of them and types
that derive `Ordered` are. `Float64` is not, because NaN is neither less than,
greater than nor equal to any number, itself included:

```linea
import std.io

fn main() -> Result[UInt8, io.IoError] {
    let readings = [Float64(2.5), -1.0, 0.0 / 0.0, 0.5]
    let { values, iterator: _ } = readings.as_slice().map(|sink reading| *reading).collect().settled() else |_| {
        return .Ok(1)
    }
    defer var sorted = values
    &sorted.sort()
    io.println("{sorted.as_slice():?}")?
    .Ok(0)
}
```

```
error[T-Bound]: `T` requires `Ordered`, and `Float64` does not implement it
 --> sort_floats.lin:9:13
  |
9 |     &sorted.sort()
  |             ^^^^ the library declares both `Float64` and `Ordered`; wrap it in a type this program declares that implements `Ordered`
```

The library declares both `Float64` and `Ordered`, so a program cannot add
that implementation. Wrapping each float in a type of your own that implements
`Ordered` works, but it is simpler to sort floats with `sort_by` and
`Float64.total_less`, IEEE 754's total order, which puts every float somewhere:

```linea
import std.io

fn main() -> Result[UInt8, io.IoError] {
    let readings = [Float64(2.5), -1.0, 0.0 / 0.0, 0.5]
    let { values, iterator: _ } = readings.as_slice().map(|sink reading| *reading).collect().settled() else |_| {
        return .Ok(1)
    }
    defer var sorted = values
    // `Float64.total_less` names the comparison, as `Float64.abs` names a function.
    &sorted.sort_by(Float64.total_less)
    io.println("{sorted.as_slice():?}")?
    .Ok(0)
}
```

```
[-1.0, 0.5, 2.5, NaN]
```

`total_less` orders by a float's bits rather than its value: `-0.0` comes
before `0.0`, which `<` calls equal, and a NaN the program computes, like
`0.0 / 0.0`, comes after `inf`. A NaN carries a sign that only this order
sees. Negating one flips it, and `-nan` comes before `-inf`:

```linea
import std.io

fn main() -> Result[UInt8, io.IoError] {
    let nan = 0.0 / 0.0
    let readings = [Float64(0.0), nan, -nan, -0.0, 1.0 / 0.0]
    let { values, iterator: _ } = readings.as_slice().map(|sink reading| *reading).collect().settled() else |_| {
        return .Ok(1)
    }
    defer var sorted = values
    &sorted.sort_by(Float64.total_less)
    io.println("{sorted.as_slice():?}")?
    .Ok(0)
}
```

```
[NaN, -0.0, 0.0, inf, NaN]
```

Every NaN prints as `NaN`, so the first and the last look alike, but
`to_bits()` tells them apart: it returns a float's IEEE 754 bits as a
`UInt64`. This is Rust's `values.sort_by(f64::total_cmp)`, and `Float32` has
its own `total_less`.

A comparison must be consistent. It is never true for a value against itself.
It is transitive: if `a` comes before `b` and `b` before `c`, then `a` comes
before `c`. And when it puts neither of two values first, those two must sort
alike against every other value. Plain `<` on floats breaks the last rule once
NaN is among them: it puts neither 1.0 nor 2.0 before NaN, nor NaN before
either, yet 1.0 comes before 2.0. Here the sort compares each number only
with NaN, finds neither one first, and leaves all three where they were:

```linea
import std.io

fn main() -> Result[UInt8, io.IoError] {
    let readings = [Float64(2.0), 0.0 / 0.0, 1.0]
    let { values, iterator: _ } = readings.as_slice().map(|sink reading| *reading).collect().settled() else |_| {
        return .Ok(1)
    }
    defer var sorted = values
    // `<` is false both ways between NaN and each number, so the sort keeps
    // 2.0 and 1.0 on either side of NaN.
    &sorted.sort_by(|left, right| left < right)
    io.println("{sorted.as_slice():?}")?
    .Ok(0)
}
```

```
[2.0, NaN, 1.0]
```

Given an inconsistent comparison, a sort still finishes and the vector still
holds every element it held, in an order nobody promises.

## Callbacks and searches that keep their state

Some operations come with an `_inout` twin, such as `fold_inout`, which borrows
the callback instead of taking it, so that whatever the callback kept is still
yours afterwards. A closure that lends one of your variables, `[inout
count]` ([Calling things](02-calling-things.md#a-closure-that-changes-a-value-of-yours)),
usually says the same thing more simply; `fold_inout` is for a closure that owns
its state. `find_counted` is `find` for an iterator you keep: it answers a
`FindReport` holding the `found` item and how many were `inspected`, and the
iterator carries on from there.

```linea
import std.io

struct Line {
    item: Str,
    cents: UInt64,
    quantity: UInt64,
}

fn main() -> Result[UInt8, io.IoError] {
    let order = [
        Line { item = "coffee", cents = 250, quantity = 2 },
        Line { item = "croissant", cents = 175, quantity = 1 },
        Line { item = "jam", cents = 40, quantity = 12 },
    ]
    // `find_counted` searches an iterator in place and says how many lines it
    // looked at. The iterator stays yours, positioned after the last line
    // inspected, so the next search continues from there.
    var lines = order.as_slice().iterate()
    let first = &lines.find_counted(|line| line.cents > 100)
    let second = &lines.find_counted(|line| line.cents > 100)
    let third = &lines.find_counted(|line| line.cents > 100)
    io.println("first: {first.found.is_some()} after {first.inspected}")?
    io.println("second: {second.found.is_some()} after {second.inspected}")?
    io.println("third: {third.found.is_some()} after {third.inspected}")?
    // `fold_inout` borrows its callback, so what the closure counted is still
    // yours once the fold is done.
    var adding = inout [sink calls = UInt64(0)] |sink sum: UInt64, sink cost: UInt64| {
        calls += 1
        sum + cost
    }
    let total = order.as_slice().map(|sink line| line.cents * line.quantity).fold_inout(0, &adding)
    let { calls } = adding.into_captures()
    io.println("{total} cents from {calls} lines")?
    .Ok(0)
}
```

```
first: true after 1
second: true after 1
third: false after 1
1155 cents from 3 lines
```

`iterate()` is how a sequence hands a `for` its iterator; here the iterator is
kept in a variable instead. Each `find_counted` call stops at the first line over a hundred cents, and the
next call starts after it: coffee, then croissant, then jam, which is under the
limit, so the third search finds nothing after inspecting the one line left.
`adding` owns `calls`, `fold_inout` calls it once for each line, and
`into_captures()` hands the count back.

## Emptying a `Vec`: `pop` and `finish`

`pop` takes the last element out of a vector, or answers `.None` when the
vector is empty. Nothing else moves, so it costs the same however long the
vector is. A stack of plates is washed from the top:

```linea
import std.io

fn main() -> Result[UInt8, io.IoError] {
    // A stack of plates: the last one put down is the first one taken.
    var plates: Vec[Str] = Vec.new()
    defer plates.release()
    for colour in ["blue", "white", "red"] {
        if &plates.push(colour).is_err() {
            return .Ok(1)
        }
    }
    // `pop` takes the last plate, or answers `.None` when the stack is empty.
    loop {
        let plate = &plates.pop() else {
            break
        }
        io.println("washing the {plate} plate")?
    }
    io.println("{plates.length()} plates left")?
    .Ok(0)
}
```

```
washing the red plate
washing the white plate
washing the blue plate
0 plates left
```

`release()` ends a vector by releasing every element still in it, so it exists
only when the elements have a `release` of their own: a `Vec[T, A]` implements
`Release` when `T` does. A vector of payments has none, because releasing a
payment would decide nothing about it. `Vec.from_fn` below builds one payment
for each index; try to schedule the release anyway:

```linea
import std.io

@linear
struct Payment {
    cents: UInt64,
}

fn main() -> Result[UInt8, io.IoError] {
    let amounts = [UInt64(250), 400, 480]
    // `Vec.from_fn` makes room for three payments, then builds one for each
    // index, so no payment exists until there is room for all of them.
    let queue = Vec.from_fn(
        count: 3,
        initializer: [amounts] |index| Payment { cents = amounts[index] },
    ) else |_| {
        return .Ok(1)
    }
    defer queue.release()
    io.println("{queue.length()} payments are waiting")?
    .Ok(0)
}
```

```
error[T-Bound]: `release` comes from `Release`, and `Vec[Payment, mem.SystemAllocator]` does not implement it
  --> queue_release.lin:18:11
   |
18 |     defer queue.release()
   |           ^^^^^^^^^^^^^ its implementation's bounds are not met by this type's arguments
   |
   = help: `Vec[T, A]` implements `Release` when `T` implements `Release`, and `Payment` does not
```

Leave the `defer` out, and the vector is a value nobody settled:

<!-- guide: unchecked the error an edit of the program above produces -->
```
error[O-Leak]: `queue` (a linear `Vec[Payment, mem.SystemAllocator]`) is still owned when this path leaves
  --> queue_forgot.lin:20:56
   |
13 |     let queue = Vec.from_fn(
   |         ----- acquired here
20 |     io.println("{queue.length()} payments are waiting")?
   |                                                        ^ still owned here
22 | }
   | - also still owned where the block ends
   |
   = help: end it with `queue.finish()`, and settle what its `Err` hands back
```

`finish()` is the ending that decides nothing. It completes a vector that has
been emptied, answering `.Ok(())`; a vector that still holds elements comes
back whole, as `.Err(queue)`, for you to keep emptying. It is not a synonym for
cleanup: a vector of payments has no `release()` to call, and `finish()` is how
its emptying is confirmed. So a vector of payments is
emptied first, one payment at a time, and finished afterwards. Here the café
closes early and refunds every payment still waiting:

```linea
import std.io

@linear
struct Payment {
    cents: UInt64,
}

impl Payment {
    // Refunding hands the money back, and answers how much it was.
    fn refund(sink self: Self) -> UInt64 {
        let Payment { cents } = self
        cents
    }
}

fn main() -> Result[UInt8, io.IoError] {
    let amounts = [UInt64(250), 400, 480]
    var queue = Vec.from_fn(
        count: 3,
        initializer: [amounts] |index| Payment { cents = amounts[index] },
    ) else |_| {
        return .Ok(1)
    }
    // The café closes early, so every waiting payment is refunded.
    var refunded = 0
    loop {
        let payment = &queue.pop() else {
            break
        }
        refunded += payment.refund()
    }
    // The queue is empty now, so `finish` completes it and answers `.Ok`.
    match queue.finish() {
        Ok(_) => {},
        Err(_) => panic("a payment was left in the queue"),
    }
    io.println("refunded {refunded} cents")?
    .Ok(0)
}
```

```
refunded 1130 cents
```

`finish` answers a `Result`, and its `Err` holds a vector of payments that must
be consumed like any other, so the `match` handles both outcomes. The loop
emptied the queue, so an `Err` here would be a mistake in the program.
`panic(message)` stops the program with that message, and a program that has
stopped leaves nothing unsettled, which is why that arm may drop the vector
with `_`. Write `Err(_) => {}` instead, and the vector in the `Err` is refused
as `[O-Leak]`, because `_` does not settle it. `pop` takes the payments last first; the next section takes
them in the order they were queued.

## Draining, and walks that lend

`drain()` takes a vector and answers an iterator that hands its elements over
first to last. Walking a drain with a plain `for` is the obvious way to handle
a queue of payments in order:

```linea
import std.io

// A payment must be consumed exactly once: committed or refunded.
@linear
struct Payment {
    cents: UInt64,
}

impl Payment {
    // Committing puts the money in the till.
    fn commit(sink self: Self, inout takings: UInt64) {
        let Payment { cents } = self
        takings += cents
    }
}

fn main() -> Result[UInt8, io.IoError] {
    let amounts = [UInt64(250), 400, 480, 180, 90]
    let queue = Vec.from_fn(
        count: 5,
        initializer: [amounts] |index| Payment { cents = amounts[index] },
    ) else |_| {
        return .Ok(1)
    }
    var takings = 0
    for payment in queue.drain() {
        payment.commit(&takings)
    }
    io.println("took {takings} cents")?
    .Ok(0)
}
```

```
error[O-LinearWalk]: walking a `mem.Drain[Payment, mem.SystemAllocator]` abandons it where the walk ends, and it is linear
  --> queue_walk.lin:26:20
   |
26 |     for payment in queue.drain() {
   |                    ^^^^^^^^^^^^^ it still holds the `Payment` items it has not handed over, and `Payment` is linear
   |
   = help: bind it, `var pending = queue.drain()`, walk it lent with `for payment in &pending`, then settle `pending` with `finish()`
```

A plain `for` takes the drain and drops it where the walk ends. That is fine
for a drain that owes nothing, but this one owes two things: the vector's
storage, and any payment it has not handed over yet. A walk can end early,
with `break`, `return` or `?`, and then there would be payments left in a
drain that nobody holds.

The help says what to do instead. Keep the drain in a variable and **lend** it
to the walk with `for payment in &pending`. The loop calls `next` on
`pending` for each payment, and whatever the walk leaves stays in `pending`
for you to settle afterwards. Here the till has a limit: the first payment that
would take it past the limit is refunded and the walk stops, and a second walk
refunds the rest:

```linea
import std.io

// A payment must be consumed exactly once: committed or refunded.
@linear
struct Payment {
    cents: UInt64,
}

impl Payment {
    // Committing puts the money in the till.
    fn commit(sink self: Self, inout takings: UInt64) {
        let Payment { cents } = self
        takings += cents
    }

    // Refunding hands the money back, and answers how much it was.
    fn refund(sink self: Self) -> UInt64 {
        let Payment { cents } = self
        cents
    }
}

fn main() -> Result[UInt8, io.IoError] {
    let amounts = [UInt64(250), 400, 480, 180, 90]
    let queue = Vec.from_fn(
        count: 5,
        initializer: [amounts] |index| Payment { cents = amounts[index] },
    ) else |_| {
        return .Ok(1)
    }
    let till_limit = 1000
    var takings = 0
    var refunded = 0
    // `&pending` lends the drain to the walk, so the payments the walk does
    // not reach stay in `pending`.
    var pending = queue.drain()
    for payment in &pending {
        // The first payment that would take the till past its limit is
        // refunded, and the walk stops there.
        if takings + payment.cents > till_limit {
            refunded += payment.refund()
            break
        }
        payment.commit(&takings)
    }
    // Refund the payments the first walk did not reach.
    for payment in &pending {
        refunded += payment.refund()
    }
    // Every payment has been handed over, so `finish` completes the drain.
    match pending.finish() {
        Ok(_) => {},
        Err(_) => panic("a payment was left in the queue"),
    }
    io.println("took {takings} cents, refunded {refunded} cents")?
    .Ok(0)
}
```

```
took 650 cents, refunded 750 cents
```

The first walk commits 250 and 400 cents, then meets the 480-cent payment,
which would take the till to 1130, refunds it and stops. The second walk goes
on from where the first stopped and refunds the last two.

A lent walk is `for inout` for an iterator: the body cannot touch `pending` by
name while the loop runs, and `pending` is yours again when the loop ends.
Rust writes the same thing as `for payment in pending.by_ref()`.

Not every drain needs lending. A drain of numbers from an arena owes nothing,
so a plain `for` may take it ([Memory](07-memory.md) covers arenas). A drain of
numbers from `mem.system()` still owes its storage: the compiler asks for the
lent walk, and `pending.release()` settles it afterwards, whatever is left in
it, because numbers have a `release` to call.

### Why `finish()` ends a lent walk

Both loops have handed over every payment, so why `finish()`? A lent walk only
borrows `pending`. When a loop ends, the walk is over, but `pending`
is still a drain that owes its storage, and the loop cannot settle it for
you: ending a loop would have to call something that can fail, and Linea never
settles a value on your behalf. `finish()` is the operation that consumes the
drain. It succeeds, `.Ok(())`, only when every element has been handed over,
which completes the drain. If some element remains, it does not drop the drain or
panic: it hands the whole drain back as `.Err`, still holding what is left, so
you can go on settling it. That is what the `match` handles, and why a
`pending` that was never finished is an `[O-Leak]` like any other forgotten
linear value. A `Vec` has the same `finish`. It belongs to these containers,
as `release()` belongs to the types that implement `Release`; it is an
operation they offer, and not a protocol the language asks of every type.

## What you have seen

| You want | Write |
| --- | --- |
| to take the elements of an array, a range or a sequence | `for x in xs` |
| to look at each element | `for read x in xs`, on an array, a `Vec` or a slice |
| to walk a `Vec` | `for read` or `for inout`; `v.as_slice()` for a view; `v.drain()` to take its elements |
| to change each element in place | `for inout x in xs` |
| a type a `for` can walk | `impl Iterator for T`, with `type Item` and `next` |
| a field whose type a trait names | `struct Entry[S: Sensor] { reading: S.Reading }` |
| to turn each item into another | `xs.map(\|sink x\| …)` |
| to keep some items | `xs.filter(\|x\| …)`, for items that may be dropped |
| to keep some items and deal with the rest | `xs.filter_map(\|sink x\| …)`, answering `.Some` or `.None` |
| one value from all the items | `xs.fold(start, \|sink value, sink x\| …)` |
| to ask about the items | `any`, `all`, `find`, `find_map` |
| how many items there are | `xs.count()`, or `xs.filter(\|x\| …).count()` for some of them |
| the items in a new `Vec` | `xs.collect().settled()`, or `xs.collect_in(allocator).settled()` |
| a vector in ascending order | `&v.sort()`, for `Ordered` elements |
| a vector in an order you choose | `&v.sort_by(\|left, right\| …)`, true when `left` comes first |
| a search that continues, with a count of the items inspected | `&it.find_counted(\|x\| …)` on an iterator you keep |
| a fold or search whose callback keeps its state | `fold_inout`, `find_inout`, `find_counted_inout` |
| a chain across several lines | one step per line, each opening with `.` |
| each item with its position | `for (i, x) in xs.enumerate()` |
| the items of two sequences, paired | `for (a, b) in xs.zip(ys)`, with Discardable items in `xs` |
| the first few items, or all but the first few | `xs.take(n)`, `xs.skip(n)` |
| a chain over a source that never ends | an adapter runs only as the walk asks, so end it with `take(n)` |
| a vector's last element | `&v.pop()` |
| a vector's elements, first to last | `v.drain()` |
| to walk a drain of values that must be consumed | `var pending = v.drain()`, `for x in &pending`, then `pending.finish()` |

The [payment batch](../../examples/payment_batch.lin) commits or declines a
queue of payments with a lent walk, the [savings
planner](../../examples/savings_planner.lin) folds a range, the [parcel
manifest](../../examples/parcel_manifest.lin) filters and collects a shipment,
and the [upcoming leap years](../../examples/upcoming_leap_years.lin) are taken
from a walk of years that never ends.

Next: [Borrowing](06-borrowing.md) — the views that chains hand out, and the
`borrows`, `carries` and `retains` clauses that say where a view points.
