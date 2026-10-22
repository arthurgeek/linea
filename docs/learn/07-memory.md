# Memory

Most values in Linea live where you declare them and need no thought: numbers,
structs of numbers, arrays, `Str` views of literals. Memory becomes a question
when the size is only known while the program runs — text you build, a list
that grows, a request that arrives over the network. This chapter answers who
provides that memory, who gives it back, and how.

The short answer: **the caller always chooses.** Every call that allocates
either passes the allocator or calls a form that uses the system allocator. A
constructor or function that allocates comes in two forms: the one whose name
ends in `_in` takes the allocator as its first argument (after the value a
method is called on), and the one without the suffix uses the system allocator.
Whichever is called, the value it builds keeps that allocator to give the
memory back.

## An allocator is an argument

Here is a function that builds a line of text. It does not decide where the
text lives; its caller does:

```linea
import std.io
import std.mem

// The caller passes the allocator, so the caller decides where the banner lives.
fn banner_in[A: Allocator](allocator: A, title: Str) -> Result[String[A], mem.Oom] where carries(.Ok: allocator) {
    var line = String.new_in(allocator)
    // Release the line if a `?` leaves early; returning it skips this.
    defer line.release()
    &line.append("== ")?
    &line.append(title)?
    &line.append(" ==")?
    .Ok(line)
}

fn main() -> Result[UInt8, io.IoError] {
    let heading = banner_in(mem.system(), "Daily report") else |_| {
        io.eprintln("out of memory")
        return .Ok(1)
    }
    defer heading.release()
    io.println(heading.view())?
    .Ok(0)
}
```

```
== Daily report ==
```

Four things to notice:

- `banner_in` takes the allocator first, and its name ends in `_in` to say so.
  It is generic over `A: Allocator`, so it works with any allocator,
  and `String.new_in(allocator)` makes an empty string that will allocate from
  it. `Allocator` and `String` are in the prelude. `where carries(.Ok:
  allocator)` says the string depends on the allocator you passed
  ([Borrowing](06-borrowing.md) explains the clause).
- `mem.system()` is the system allocator: the operating system's heap, like
  C's `malloc`. `main` chooses it.
- Allocation can fail. `append` returns `Result[(), mem.Oom]`, and `?` passes
  an out-of-memory error up. No allocation in Linea aborts the program on its
  own.
- `defer line.release()` inside `banner_in` frees the half-built line if a `?`
  leaves early. On the path that returns the line, the line is handed to the
  caller instead, so the `defer` does not run there
  ([Copying, settling and sealing](04-copying-settling-and-sealing.md#a-defer-and-a-move)
  explains why). This is the usual shape of a function that builds something:
  schedule the cleanup first, and return the value when it is done.

If you know Zig, this is Zig's rule. If you know Rust, it is as if every `Vec`
and `String` took its allocator as a parameter, and `Vec::new()` were a short
way of passing the global one.

## Memory from the system is given back by hand

A `String` that allocates from `mem.system()` owns heap memory, so it must be
settled, exactly like the linear values of [Copying, settling and
sealing](04-copying-settling-and-sealing.md#linear-values-you-must-not-forget).
`main` does that with `defer heading.release()`. Take it out:

<!-- guide: unchecked the error an edit of the program above produces -->
```
error[O-Leak]: `heading` (a linear `String[mem.SystemAllocator]`) is still owned when this path leaves
  --> banner_leak.lin:20:31
   |
16 |     let heading = banner_in(mem.system(), "Daily report") else |_| {
   |         ------- acquired here
20 |     io.println(heading.view())?
   |                               ^ still owned here
22 | }
   | - also still owned where the block ends
   |
   = help: settle it first with `heading.release()`
```

A memory leak is a compile error. There is no garbage collector, and
`release()` runs when you call it or `defer` it, never on its own ([Copying,
settling and
sealing](04-copying-settling-and-sealing.md#release-the-ending-you-do-not-have-to-think-about));
the compiler checks that every path does one or the other.

## The allocator is part of the type

A `String` remembers the allocator its memory came from, and the type says
which: `String[A]` is a string whose memory comes from `A`. Leaving the
allocator out means the system allocator, so `String` is
`String[mem.SystemAllocator]`, and `Vec[Str]` is `Vec[Str, mem.SystemAllocator]`.
A program that takes all its memory from `mem.system()` never writes the
allocator in a type:

```linea
import std.io

// `String` and `Vec[Str]` take their memory from the system allocator, so the
// fields name no allocator.
@derive(Release)
struct Report {
    title: String,
    lines: Vec[Str],
}

fn main() -> Result[UInt8, io.IoError] {
    var report = Report {
        title = "Daily report".to_owned().unwrap(),
        lines = Vec.new(),
    }
    defer report.release()
    if &report.lines.push("opened").is_err() {
        return .Ok(1)
    }
    io.println("{report.title.view()}: {report.lines.length()} line")?
    .Ok(0)
}
```

```
Daily report: 1 line
```

The short form is the same type as the long one, so a `Vec[Str]` passes where
a `Vec[Str, mem.SystemAllocator]` is expected. It is not the same type as a
vector in an arena: `Vec[Str, mem.Handle]` names the handle of an arena over
the system allocator ([below](#arenas-allocate-many-things-give-them-back-at-once)),
and the compiler prints the allocator it filled in when the two meet.

A function that is generic over an allocator is another matter. `banner_in` above
takes `A: Allocator` to work with any allocator, and a result written
`String` would quietly be a system string whatever `A` is. So a declaration that
declares an allocator parameter must write the allocator of every type that
has one, either the parameter or the system allocator spelled out:

<!-- guide: unchecked the error an edit of the program above produces -->
```
error[T-DefaultedAllocator]: `String` leaves its allocator `A` to a default, and this declaration is generic over an allocator itself
  --> banner_default.lin:5:84
   |
 5 | fn banner_in[A: Allocator](allocator: A, title: Str) -> Result[String, mem.Oom] where carries(.Ok: allocator) {
   |                                                                ^^^^^^ write the allocator: `A`, or `mem.SystemAllocator` where the system allocator is meant
```

Write `String[A]` to return the string from the allocator the caller chose, or
`String[mem.SystemAllocator]` for a string that always comes from the heap.

## Arenas: allocate many things, give them back at once

Releasing every string one by one is right for values that live on their own.
It is tedious for many small values that all die together — the lines of a
report, the pieces of a parsed request. For those, use an **arena**: one block
of memory, handed out piece by piece and taken back in one go.

```linea
import std.io
import std.mem

use mem.Lender

// The caller passes the allocator, so the caller decides where the banner lives.
fn banner_in[A: Allocator](allocator: A, title: Str) -> Result[String[A], mem.Oom] where carries(.Ok: allocator) {
    var line = String.new_in(allocator)
    // Release the line if a `?` leaves early; returning it skips this.
    defer line.release()
    &line.append("== ")?
    &line.append(title)?
    &line.append(" ==")?
    .Ok(line)
}

fn main() -> Result[UInt8, io.IoError] {
    // The arena takes 4096 bytes from the system, and everything below comes out of them.
    let arena = mem.Arena.open(mem.system(), size: 4096)
    // Releasing the arena gives all 4096 bytes back at once, however `main` ends.
    defer arena.release()
    let titles = ["Morning", "Afternoon", "Evening"]
    for title in titles {
        // Nothing here is released by hand: the arena takes it all back at once.
        let heading = banner_in(arena.handle(), title) else |_| {
            io.eprintln("the arena is full")
            return .Ok(1)
        }
        io.println(heading.view())?
    }
    .Ok(0)
}
```

```
== Morning ==
== Afternoon ==
== Evening ==
```

`mem.Arena.open(mem.system(), size: 4096)` takes 4096 bytes from the system
allocator. `arena.handle()` answers a `mem.Handle`, an allocator that hands out
pieces of those bytes, so `banner_in(arena.handle(), title)` builds its string
inside the arena.

`handle` is the one operation of the `Lender` trait, which is why the program
has `use mem.Lender`. A **lender** holds memory and lends out allocators that
take from it without owning any of it. An arena is one. `mem.SystemAllocator`
is another, whose handle is the system allocator itself, since the system's
memory belongs to no value in your program. "Lender" names what a value does
with bytes. It is not a third kind of ownership: who must give a value
back is a separate question, answered in [Who owns it, and what it points
into](#who-owns-it-and-what-it-points-into).

`open` answers an arena rather than a `Result`, although taking 4096 bytes can
fail. When it does, the arena holds nothing, and every allocation from it
fails with `mem.Oom`, so the failure reaches you at the first allocation,
through the same `else` that handles a full arena. Ask for more than any
system has, `size: 1000000000000000000`, and the program prints what it
prints for a full arena, and exits with status 1:

<!-- guide: unchecked the output of an edited or partial program -->
```
the arena is full
```

Notice what is missing: nobody releases `heading`. A string whose memory comes
from an arena does not have to be settled, because the arena gives all of it
back at once. The arena itself is the one thing that must be released, and
`defer arena.release()`, written right after it is opened, does that on every
way out of `main`: the normal end, the `return .Ok(1)` when the arena is full,
and every `?`. `banner_in` did not change at all — the same function builds system
strings for one caller and arena strings for another.

An arena has a fixed size. When it runs out, allocating from it fails like any
other allocation: change `size: 4096` to `size: 32` and the program prints
`the arena is full` and exits with status 1.

### `new`, `open` and the `_in` form

A constructor or function that allocates has two forms. The plain name uses
the system allocator, and the name ending in `_in` takes the allocator as its
first argument. The constructor's own name says what it does:

- `T.new()` builds an empty value and cannot fail; `T.new_in(allocator)` builds
  the same value in the allocator you pass, such as an arena's handle.
- `T.open(...)` can fail or acquires something that must be given back, as a
  buffered reader, a file, a logger or a kept closure does;
  `T.open_in(allocator, ...)` does the same with the allocator you pass.

An allocator built on top of another one is the exception: `mem.Arena.open`
takes the allocator its block comes from, because that is what the arena is
made of, so it has no `_in` form.

This program builds one vector with `new` and one with `new_in`:

```linea
import std.io
import std.mem

use mem.Lender

fn main() -> Result[UInt8, io.IoError] {
    // `Vec.new()` takes its memory from the system, so `defer var` releases it.
    defer var ages: Vec[UInt64] = Vec.new()
    if &ages.push(41).is_err() {
        return .Ok(1)
    }

    // `mem.Arena.open` acquires the block of memory the arena hands out.
    let arena = mem.Arena.open(mem.system(), size: 256)
    defer arena.release()
    // `Vec.new_in` builds in the arena, which takes the vector's memory back
    // with its own, so this vector needs no release.
    var names: Vec[Str, mem.Handle] = Vec.new_in(arena.handle())
    if &names.push("Ada").is_err() {
        return .Ok(1)
    }
    io.println("{names.length()} name, {ages.length()} age")?
    .Ok(0)
}
```

```
1 name, 1 age
```

`Vec`, `String`, `collections.Map` and `http.Router` each have the pair; only
`new_in` lets you choose the allocator, and the type records the choice.

### A function's `_in` form takes the allocator

Functions that allocate follow the same rule as constructors. A method's
allocator comes first after the value it is called on:
`"Lisbon".to_owned()` copies text into the system allocator, and
`"Lisbon".to_owned_in(arena.handle())` copies it into an arena. `fmt.render_owned` and `fmt.render_owned_in`, `json.parse` and
`json.parse_in`, and `Vec.filled` and `Vec.filled_in` are pairs in the same
way:

```linea
import std.fmt
import std.io
import std.mem

use mem.Lender

fn main() -> Result[UInt8, io.IoError] {
    // `to_owned` copies the text into memory from the system allocator.
    defer let city = "Lisbon".to_owned() else |_| {
        return .Ok(1)
    }
    let arena = mem.Arena.open(mem.system(), size: 256)
    defer arena.release()
    // `render_owned_in` takes the arena's handle first, so the line lives in
    // the arena and goes back with it.
    let line = fmt.render_owned_in(arena.handle(), "{city.view()} reaches 27 degrees") else |_| {
        return .Ok(1)
    }
    io.println(line.view())?
    .Ok(0)
}
```

```
Lisbon reaches 27 degrees
```

The plain form takes no allocator at all, so passing one is an error rather
than a second way to say the same thing:

```linea
import std.io
import std.mem

fn main() -> Result[UInt8, io.IoError] {
    defer let city = "Lisbon".to_owned(mem.system()) else |_| {
        return .Ok(1)
    }
    io.println(city.view())?
    .Ok(0)
}
```

```
error[T-Arity]: expected 0 argument(s), found 1
  --> main.lin:5:22
   |
5  |     defer let city = "Lisbon".to_owned(mem.system()) else |_| {
   |                      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ the wrong number of arguments
  ::: std/text/str.lin
34 |     pub fn to_owned(self: Self) -> Result[String[mem.SystemAllocator], mem.Oom] where carries() {
   |            -------- declared here
   |
   = help: `to_owned` uses the system allocator; use `to_owned_in(allocator, …)` to choose the allocator
```

Write `"Lisbon".to_owned()` for the system allocator, and
`"Lisbon".to_owned_in(allocator)` when the allocator is one you were given. A
function of your own that allocates follows the same rule, as `banner_in`
does: take the allocator first in the `_in` form, and where callers want the
system allocator, add a plain form that passes `mem.system()` to it.

### An arena outlives everything built in it

Every string built from `arena.handle()` points into the arena, so the compiler
holds the arena in place while any of them is still used. The programs in
this section keep `banner_in` and the imports from the arena program in
[Arenas](#arenas-allocate-many-things-give-them-back-at-once), and change only
`main`. Release the arena too early:

<!-- guide: unchecked the program is a partial listing or an edit of an earlier one -->
```linea
fn main() -> Result[UInt8, io.IoError] {
    let arena = mem.Arena.open(mem.system(), size: 4096)
    let heading = banner_in(arena.handle(), "Morning") else |_| {
        arena.release()
        return .Ok(1)
    }
    arena.release()
    io.println(heading.view())?
    .Ok(0)
}
```

```
error[O-Borrow]: this operation invalidates a place that a later observation still needs
  --> arena_early.lin:23:5
   |
23 |     arena.release()
   |     ^^^^^ keep this place available until the last use of its observation
24 |     io.println(heading.view())?
   |                ------- the observation is still used here
```

This is the same `[O-Borrow]` as a view outliving its `String`: the arena is
the owner, and `heading` still points into it. With `defer arena.release()`
this cannot happen, because the release runs after the last line of `main`.

### Who owns it, and what it points into

Two questions are worth keeping apart. **Ownership** asks who must give a value
back: whose job it is to release it, or to hand it to something that settles
it. **Provenance** asks what the value points into: what must stay in place
for as long as the value is used. `[O-Leak]` answers the first
question, and the clauses of [Borrowing](06-borrowing.md) and `[O-Borrow]`
answer the second. Arenas are where the two come apart:

| Value | Who must give it back | What it points into |
| --- | --- | --- |
| a `String` from `mem.system()` | you, with `release()` | nothing of yours |
| a `String` from an arena | nobody: the arena takes it back | the arena |
| `arena.handle()` | nobody: a handle owns nothing | the arena |
| an arena from `mem.system()` | you, with `release()` | nothing of yours |
| an arena opened from another arena's handle | nobody | the other arena |

An arena points into whatever it took its bytes from: nothing of yours when
that is `mem.system()`, and the other arena when it is another arena's handle.

A string in an arena is yours, but it owes nothing, so you may simply stop
using it. It still points into the arena, and that is what the `[O-Borrow]`
above refused. A handle is the same kind of value: it is `@copyable`, since a
copy is only a second way to reach the same arena, and it holds a borrow of
the arena, so no handle can outlive the arena it came from.

### An arena inside an arena

A handle is an allocator like any other, so an arena can take its bytes from
another arena. Here a report keeps its title in one arena for the whole run,
and builds each section's heading in a small scratch arena carved out of the
first, rewinding the scratch arena between sections:

```linea
import std.io
import std.mem

use mem.Lender

// The caller passes the allocator, so the caller decides where the banner lives.
fn banner_in[A: Allocator](allocator: A, title: Str) -> Result[String[A], mem.Oom] where carries(.Ok: allocator) {
    var line = String.new_in(allocator)
    // Release the line if a `?` leaves early; returning it skips this.
    defer line.release()
    &line.append("== ")?
    &line.append(title)?
    &line.append(" ==")?
    .Ok(line)
}

fn main() -> Result[UInt8, io.IoError] {
    let report = mem.Arena.open(mem.system(), size: 4096)
    defer report.release()
    let title = banner_in(report.handle(), "Daily report") else |_| {
        return .Ok(1)
    }
    // The scratch arena's 256 bytes come out of the report's arena, which
    // takes them back with everything else, so nothing releases `scratch`.
    var scratch = mem.Arena.open(report.handle(), size: 256)
    for section in ["Morning", "Evening"] {
        &scratch.rewind()
        let heading = banner_in(scratch.handle(), section) else |_| {
            return .Ok(1)
        }
        io.println(heading.view())?
    }
    io.println(title.view())?
    .Ok(0)
}
```

```
== Morning ==
== Evening ==
== Daily report ==
```

`scratch` owes nothing, like any value built in the report's arena, and it
points into the report's arena, so it may not outlive it. `rewind`, which the
next section covers, empties `scratch` without touching `title`.

### Rewinding: one arena, used again and again

A loop that builds something new on each pass can reuse the same bytes.
`rewind` takes back everything the arena handed out, so the next pass starts
from an empty arena:

<!-- guide: unchecked the program is a partial listing or an edit of an earlier one -->
```linea
fn main() -> Result[UInt8, io.IoError] {
    defer var arena = mem.Arena.open(mem.system(), size: 64)
    let titles = ["Morning", "Afternoon", "Evening", "Night"]
    for title in titles {
        // Each pass reuses the same 64 bytes: `rewind` takes back what the last pass used.
        &arena.rewind()
        let heading = banner_in(arena.handle(), title) else |_| {
            io.eprintln("the arena is full")
            return .Ok(1)
        }
        io.println(heading.view())?
    }
    .Ok(0)
}
```

```
== Morning ==
== Afternoon ==
== Evening ==
== Night ==
```

Sixty-four bytes are enough for any one heading, but not for four at once:
remove the `&arena.rewind()` and the program prints `== Morning ==` and then
`the arena is full`. `rewind` takes the arena `inout`, so it is marked with
`&`, and the arena is declared with `var` rather than the `let` of the arenas
above, which are never changed. It only zeroes the bytes that were used, so
its cost is what the pass used rather than the arena's size.

Rewinding throws away everything built so far, so nothing built before it may
still be in use. Keep one heading from before the loop and print it afterwards:

<!-- guide: unchecked the program is a partial listing or an edit of an earlier one -->
```linea
fn main() -> Result[UInt8, io.IoError] {
    var arena = mem.Arena.open(mem.system(), size: 64)
    defer arena.release()
    let first = banner_in(arena.handle(), "Dawn") else |_| {
        return .Ok(1)
    }
    let titles = ["Morning", "Afternoon", "Evening", "Night"]
    for title in titles {
        // Each pass reuses the same 64 bytes: `rewind` takes back what the last pass used.
        &arena.rewind()
        let heading = banner_in(arena.handle(), title) else |_| {
            io.eprintln("the arena is full")
            return .Ok(1)
        }
        io.println(heading.view())?
    }
    io.println(first.view())?
    .Ok(0)
}
```

```
error[O-Borrow]: this operation invalidates a place that a later observation still needs
  --> arena_kept.lin:26:9
   |
26 |         &arena.rewind()
   |         ^^^^^^^^^^^^^^^ keep this place available until the last use of its observation
33 |     io.println(first.view())?
   |                ----- the observation is still used here
```

`first` lives in the arena, and the rewind would erase it before its last use.

## Keeping a closure: `mem.Closure`

[Calling things](02-calling-things.md#closures-functions-that-capture) showed
that every lambda has a type of its own, so a `Vec` cannot hold two closures
that captured different things. `mem.Closure[S, A]` solves that. It moves any
function or closure callable as `S` into memory from an allocator `A`, and
answers a value of one type, whatever was captured. It is Rust's
`Box<dyn Fn(…)>`, with the allocator named:

```linea
import std.io
import std.mem

// A pricing rule takes a total in cents and answers the new total.
alias Pricing = fn(cents: UInt64) -> UInt64

// The checkout's rules: closures kept in a vector, both from the heap.
alias Rules = Vec[mem.Closure[Pricing]]

// Add the checkout's rules, in the order they apply. Each `mem.Closure.open`
// moves a closure into memory from the heap and answers a value of one type,
// whatever the closure captured, so one vector holds them all.
fn add_rules(inout rules: Rules, percent: UInt64, fee: UInt64) -> Result[(), mem.Oom] {
    &rules.push(mem.Closure.open([sink percent] |cents: UInt64| cents - cents * percent / 100)?).settled()?
    &rules.push(mem.Closure.open([sink fee] |cents: UInt64| cents + fee)?).settled()?
    .Ok(())
}

fn main() -> Result[UInt8, io.IoError] {
    var rules: Rules = Vec.new()
    // Releasing the vector releases every closure in it.
    defer rules.release()
    if add_rules(&rules, percent: 10, fee: 499).is_err() {
        return .Ok(1)
    }
    var total = 6000
    // Calling a kept closure runs its rule.
    for read rule in rules {
        total = rule(total)
    }
    io.println("A 6000-cent cart costs {total} cents.")?
    .Ok(0)
}
```

```
A 6000-cent cart costs 5899 cents.
```

The 10% discount takes 6000 cents to 5400, and shipping adds 499. `Pricing`
names the rule's signature once and `Rules` names the vector's type once
([Calling things](02-calling-things.md#a-name-for-a-long-type-alias)), and
`mem.Closure.open` keeps each closure in memory from the system allocator, as
`Vec.new()` does for the vector. `open` can fail when memory runs out, so it answers a `Result`, and a refused `push` hands the closure back,
which `settled()` releases
([Errors](03-errors.md#failures-that-hand-a-value-back)). The [pricing rules
example](../../examples/pricing_rules.lin) builds a checkout this way.

### A kept closure is settled like its allocator's memory

A `mem.Closure` follows the same rule as a `Vec`: whether it must be released
depends on where its memory came from.

```linea
import std.io
import std.mem

use mem.Lender

fn main() -> Result[UInt8, io.IoError] {
    let fee = 499
    // Kept in memory from the heap, the closure must be released.
    let shipping = mem.Closure.open([sink fee] |cents: UInt64| cents + fee) else |_| {
        return .Ok(1)
    }
    defer shipping.release()

    let arena = mem.Arena.open(mem.system(), size: 4096)
    defer arena.release()
    let percent = 10
    // Kept in an arena, the closure goes when the arena does: nothing releases it.
    let discount = mem.Closure.open_in(arena.handle(), [sink percent] |cents: UInt64| cents - cents * percent / 100) else |_| {
        return .Ok(1)
    }
    io.println("6000 cents become {shipping(discount(6000))}.")?
    .Ok(0)
}
```

```
6000 cents become 5899.
```

- **From the heap**, `mem.system()`, a closure owns memory that must be given
  back, so it must be released, and the release also settles what it captured.
  Remove `defer shipping.release()`:

<!-- guide: unchecked the error an edit of the program above produces -->
  ```
  error[O-Leak]: `shipping` (a linear `mem.Closure[fn(read UInt64) -> UInt64, mem.SystemAllocator]`) is still owned when this path leaves
    --> kept_leak.lin:18:9
     |
  9  |     let shipping = mem.Closure.open([sink fee] |cents: UInt64| cents + fee) else |_| {
     |         -------- acquired here
  18 |         return .Ok(1)
     |         ^^^^^^ still owned here
  20 |     io.println("6000 cents become {shipping(discount(6000))}.")?
     |                                                                - also still owned here
  22 | }
     | - also still owned where the block ends
     |
     = help: settle it first with `shipping.release()`
  ```

- **From an arena**, a closure goes when the arena goes, and nothing releases
  it. That is only safe when nothing it captured needs releasing either:
  dropping the arena would skip that release. So an arena refuses a closure
  that owns, say, a `Vec` from the heap:

<!-- guide: unchecked the error an edit of the program above produces -->
  ```
  error[T-Bound]: this closure captures `guests`, a `Vec[Str, mem.SystemAllocator]` that must be released, and a closure kept in memory from `mem.Handle[mem.SystemAllocator]` may be dropped without releasing it
    --> kept_arena_vec.lin:14:29
     |
  14 |     let count = mem.Closure.open_in(arena.handle(), [sink guests] || -> UInt64 { guests.length() }) else |_| {
     |                             ^^^^^^^ capture `guests` by `read`, or keep the closure with `mem.Closure.open(closure)`, whose memory is released
  ```

  The help names both ways out: look at the vector instead of owning it, or
  keep the closure somewhere that is released.

A closure kept with a `[name]` capture still looks at that value where it is,
so `open` carries the view along. The kept closure pins what it looks at
exactly as the lambda did:

```linea
import std.io
import std.mem

fn main() -> Result[UInt8, io.IoError] {
    var guests: Vec[Str] = Vec.new()
    if &guests.push("Ada").is_err() {
        guests.release()
        return .Ok(1)
    }
    // `[seen = guests]` looks at `guests` where it is, under the name `seen`.
    let count = mem.Closure.open([seen = guests] || -> UInt64 { seen.length() }) else |_| {
        guests.release()
        return .Ok(1)
    }
    // Releasing the guests frees what the kept closure still looks at.
    guests.release()
    let printed = io.println("{count()} guests")
    count.release()
    printed?
    .Ok(0)
}
```

```
error[O-Borrow]: this operation invalidates a place that a later observation still needs
  --> kept_view.lin:16:5
   |
16 |     guests.release()
   |     ^^^^^^ keep this place available until the last use of its observation
17 |     let printed = io.println("{count()} guests")
   |                                ----- the observation is still used here
```

`open` is declared `where carries(.Ok: callback)`: the kept closure points
wherever the lambda pointed. `open_in` adds `allocator` to the clause, so a
closure kept in an arena also points into the arena
([Borrowing](06-borrowing.md) explains `carries`). Move `guests.release()`
after `count.release()` and the program prints `1 guests`.

A closure that changes a variable it was lent, `[inout name]`, is called
`inout`, so its signature is written `inout fn(…)`. It can be kept only inside
the function that lent the variable: the lend belongs to that function, and a
kept closure outlives it. A function that builds such a closure for its caller
is refused:

```linea
import std.io
import std.mem

// Build a check that counts every parcel it weighs in the caller's `seen`.
fn counting_check(inout seen: UInt64) -> Result[mem.Closure[inout fn(grams: UInt64) -> Bool], mem.Oom] {
    mem.Closure.open(inout [inout seen] |grams: UInt64| {
        seen += 1
        grams <= 5000
    })
}

fn main() -> Result[UInt8, io.IoError] {
    var seen = 0
    var check = counting_check(&seen) else |_| {
        return .Ok(1)
    }
    let light = &check(1200)
    check.release()
    io.println("light: {light}, weighed: {seen}")?
    .Ok(0)
}
```

```
error[O-Escapes]: a value holding a place lent `inout` cannot leave the function that lends it
 --> counting_check.lin:6:5
  |
6 |     mem.Closure.open(inout [inout seen] |grams: UInt64| {
  |     ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ this value holds the lend
  |                                   ---- lent `inout` here
  |
  = help: finish with the value inside this function, or give the closure its own state with a `sink` capture
```

The help names both ways out: use the closure inside the function that lends
the variable, or give the closure a counter of its own, `[sink seen = 0]`, as
the ticket counter in [Calling
things](02-calling-things.md#a-closure-that-changes-what-it-owns) does.

## One arena per HTTP request

A web server is the classic case for arenas. Everything a request needs — its
text, its headers, the response built for it — lives exactly as long as the
request, and a server answers requests forever. `std.http` serves every request
from one arena:

1. `http.serve` carves one arena of `limits.request_arena_bytes` (48 MiB by
   default) from the allocator you give it.
2. It reads each request into that arena and hands the handler a
   `Request`.
3. The handler builds its response with `request.allocator()`, a handle to
   the same arena.
4. Once the response is written, `serve` rewinds the arena for the next
   request.

The rewinding loop above has exactly this shape. The loop is `serve`: it
rewinds the arena at the start of each pass, which is step 4 for the pass
before. `banner_in(arena.handle(), title)` is the handler: it builds its answer in
the arena and releases nothing. And the `[O-Borrow]` that refused to keep
`first` across a rewind is what stops a handler keeping a request's text, or a
response, past the request it belongs to.

So a handler releases nothing, and a server that runs for a year uses the same
six megabytes throughout. [Networking](09-networking.md#every-request-lives-in-an-arena)
drives these steps with a real handler once handlers have been introduced.

## Choosing an allocator

| Situation | Use |
| --- | --- |
| a value with a life of its own: a configuration, a cache, a table that grows | `mem.system()`, and `release()` or `defer … .release()` |
| many values that die together: one request, one line of input, one pass of a loop | a `mem.Arena`, released once, or rewound between passes |
| a library function that allocates | take `A: Allocator` as a parameter and let the caller choose; name it `x_in`, and add `x` whose signature writes `mem.SystemAllocator` ([below](#a-library-lets-its-caller-choose-the-allocator)) |
| a closure kept for later | `mem.Closure.open(closure)`, or `mem.Closure.open_in(allocator, closure)`, settled like that allocator's memory |
| a test that must check every allocation failure is handled | `mem.AllocationLog`, which refuses a chosen allocation; [Testing](10-testing.md#every-allocation-can-fail) shows it |

Collections follow the same rules. `Vec[T, A]` is a growable list that
allocates from `A`; `collections.Map` is a hash map that does too. Their
`new_in` takes an allocator and `new` uses the system allocator; neither
allocates until the first insertion. The
[histogram example](../../examples/histogram.lin) and
[prime sieve](../../examples/prime_sieve.lin) use vectors from the system
allocator.

## A library lets its caller choose the allocator

A program decides where its own memory comes from, so it may leave the
allocator out and take the system allocator. A library is written for programs
it has never met, and one of them may keep everything in an arena. So a
library's public signatures say which allocator they work with, every time.

Here is a small library that adds an exclamation mark to a word. `shout_in`
builds the result in whatever allocator the caller passes, and `shout` is the
convenience form over the system allocator, whose signature writes that out:

`shout/linea.json`:

```json
{ "kind": "library", "name": "shout" }
```

`shout/shout.lin`:

```linea
import std.fmt
import std.mem

// `shout_in` builds the shouted word in the allocator its caller passes, so a
// caller with an arena keeps the word in the arena.
pub fn shout_in[A: Allocator](allocator: A, word: Str) -> Result[String[A], mem.Oom] where carries(.Ok: allocator) {
    fmt.render_owned_in(allocator, "{word}!")
}

// `shout` builds it from the system allocator, and its result type says so.
pub fn shout(word: Str) -> Result[String[mem.SystemAllocator], mem.Oom] where carries() {
    shout_in(mem.system(), word)
}
```

A program that depends on the library chooses per call:

`greeter/linea.json`:

```json
{ "dependencies": { "shout": { "path": "../shout" } } }
```

`greeter/main.lin`:

```linea
import shout
import std.io
import std.mem

use mem.Lender

fn main() -> Result[UInt8, io.IoError] {
    let arena = mem.Arena.open(mem.system(), size: 256)
    defer arena.release()
    // This word lives in the arena and goes back with it.
    let kept = shout.shout_in(arena.handle(), "hello") else |_| {
        return .Ok(1)
    }
    // This one comes from the system allocator, so the program releases it.
    defer let loud = shout.shout("world") else |_| {
        return .Ok(1)
    }
    io.println("{kept.view()} {loud.view()}")?
    .Ok(0)
}
```

```sh
linea run greeter
```

```
hello! world!
```

Write a result as `Result[String, mem.Oom]` instead, and the library no longer
compiles, because `String` there means the system allocator without saying so:

`loud/linea.json`:

```json
{ "kind": "library", "name": "loud" }
```

`loud/loud.lin`:

```linea
import std.fmt
import std.mem
import std.testing

// `shout` writes `String` for its result, which leaves the allocator out.
pub fn shout(word: Str) -> Result[String, mem.Oom] where carries() {
    fmt.render_owned_in(mem.system(), "{word}!")
}

test fn a_word_is_shouted() {
    defer let loud = shout("hi") else |_| {
        return .Err(testing.refused("the word fits"))
    }
    testing.assert_eq(loud.view(), "hi!", "the word is shouted")?
}
```

```sh
linea check loud
```

```
error[T-DefaultedAllocator]: Public library signature uses the default allocator for `String`.
 --> loud/loud.lin:6:35
  |
6 | pub fn shout(word: Str) -> Result[String, mem.Oom] where carries() {
  |                                   ^^^^^^ Specify `mem.SystemAllocator` to make this restriction intentional, or make the allocator a generic parameter to preserve allocator polymorphism.
```

The rule covers what a program using the library can see: a public function's
parameters and result, the types inside them such as `Option[Vec[Str]]`, a
public struct's fields, a public alias, and the head of an `impl` whose
functions are public. Function bodies and private helpers keep the short form,
since no caller sees them. A public function also cannot give its allocator a
default, as in `[A: Allocator = mem.SystemAllocator]`: a caller leaving it out
would take the system allocator without writing it, so the library writes the
pair instead.

If you know Rust: a crate whose API names `Vec<T>` has quietly chosen the
global allocator for its users, because `Vec<T, A = Global>` fills it in. Linea
lets a program do that and asks a library to say it.

## What you have seen

- A constructor or function that allocates has two forms: `x(...)` uses the
  system allocator and `x_in(allocator, ...)` takes the allocator the caller
  chooses, as `new` and `new_in` do.
- A library's public signatures state their allocator: a parameter
  `A: Allocator`, or `mem.SystemAllocator` written out.
- Allocation can fail, and says so with a `Result`.
- Memory from `mem.system()` is released by hand; `defer` schedules the release
  on every way out, and a path that returns the value skips it.
- An arena hands out pieces of one block and takes them all back at once, when
  it is released or rewound; nothing built in it may be used afterwards.
- `mem.Closure` keeps any closure behind one type, settled like the memory it
  lives in.
- An HTTP server serves each request from one arena and rewinds it, so
  handlers release nothing.

Next: [Text](08-text.md) — owned and borrowed text, interpolation and
layout.
