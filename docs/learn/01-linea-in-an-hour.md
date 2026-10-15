# Linea in an hour

This chapter walks through the parts of Linea you use in every program: values,
bindings, functions, collections, structs and enums, `match`, modules and
tests. Each section is a small program you can run. By the end you will be able
to read the [example programs](../../examples/) and write your own.

Read the chapters of this guide in order; each one builds on the ones before
it. The guide teaches; for the exact rules, the [language
definition](../linea-semantics.md) states each one under the name the compiler
prints, so `error[T-Mismatch]` is a name you can search for there.

If you have written Rust, most of this will look familiar, and the chapter
points out where Linea differs. If you have not, nothing here assumes it. If
you know another systems language, such as C++ or Zig, skim `let` and `var`,
`for` and `Vec`, and slow down at `sink`, `inout` and linear values: those are
where Linea differs most.

This is a tour, so a few features appear before their chapter explains them:
`Result` and `?` turn up in the first programs, for example. Each one points
to where it is explained, and you can read on without it.

> **The 15-minute path.** Short on time? Read these six sections in order,
> the first example of each and the text beside it, then come back for the
> rest:
>
> 1. [Your first program](#your-first-program): `hello.lin` and `main`.
> 2. [Values and their types](#values-and-their-types): `io.println` and the
>    `{…}` that puts a value into text.
> 3. [`let` and `var`](#let-and-var): a binding that stays, and one that
>    changes.
> 4. [Functions](#functions): parameters, a result, and named arguments.
> 5. [Structs and enums](#structs-and-enums): a struct with named fields.
> 6. [The commands](#the-commands): `linea run` and the rest.

## Two ideas

Two ideas shape the whole language, and every chapter comes back to them.

**Values, not implicit aliases.** A Linea variable holds its value, never a
hidden pointer to a value someone else can change behind your back. Views of
someone else's data do exist, such as `Str` and slices, but they are written in
the types and checked: while a view is in use, nothing may change what it
points at. When a function should change something of yours, it says so with
`inout`, and you say so at the call with `&`. When a function should keep
something of yours, it says so with `sink`, and you no longer have it
afterwards. This is called *mutable value semantics*, and it is the model Swift
uses for its `inout` parameters. You get the convenience of changing things in
place without any of the aliasing that makes pointers hard to follow.

**Values consumed exactly once.** Some values stand for something that has to
end properly: a payment must be committed or refunded, an open network
connection must be closed, memory from the heap must be given back. Linea lets
a type say *a value of me must be consumed exactly once*: handed to something
that takes it, one time, on every path through the program. Never forgotten, and
never used up twice. The compiler checks every path to make sure. Consuming
such a value is also called *settling* it. Types like that are called **linear
types**, and they give the language its name.

Most values are ordinary: you copy them, pass them and forget them freely.
Only a type that asks for it is linear, and the compiler checks those.
Linear is one of the ownership policies a type can choose, beside affine (the
default: used at most once) and copyable; [Copying, settling and
sealing](04-copying-settling-and-sealing.md) names them all.

The rest of this chapter shows both ideas in small doses. [Copying, settling
and sealing](04-copying-settling-and-sealing.md) and
[Borrowing](06-borrowing.md) cover them in full.

## What Linea promises

Linea makes three promises, and says what each one does not cover.

**Every operation has a defined result.** An operation either produces a value
or is a diagnosed failure, and the optimisation level never changes which.
Integer overflow, an invalid index and an out-of-range direct numeric conversion
trap; the optional conversion returns absence instead. Floating-point operations
follow IEEE 754. A failure the caller can handle is a value, such as a
`Result`. Checking proves the language's static guarantees. It does not prove
that your logic is right, that a loop ends, that memory is available, that I/O
succeeds, or that a runtime check never fires. `linea check` validates a
program without running the native backend, and a program it accepts is not
rejected later for a source mistake.

**Resource obligations are checked, and cleanup is written by you.** A linear
value must be consumed exactly once on every path. What consuming means is the
type's choice: close a file, commit or roll back a transaction, hand the value
back. The compiler checks that you did it and never invents the policy. Write
cleanup next to the acquisition with `defer`; it also runs on an early return
and on `?`. A value that points into storage it does not own says so in the
function's signature with `borrows`, `carries` or `retains`; there are no
lifetime variables, and an ambiguous source is refused rather than guessed. The
rules are in [ownership](../linea-semantics.md#5-ownership), and chapters
[Copying, settling and sealing](04-copying-settling-and-sealing.md) and
[Borrowing](06-borrowing.md) teach them.

**Costs are visible.** `copy` marks duplication, `inout` and `&` mark an argument
a call may change, and `sink` marks a transfer of ownership. Which allocator a
container uses, and whether allocation can fail, appear where they matter.
Linea does not hide meaningful work to shorten a call, and does not make you
repeat what the surrounding code already settles.

## Your first program

Save this as `hello.lin`:

```linea
import std.io

fn main() -> Result[UInt8, io.IoError] {
    // `?` means stop here if printing failed. Errors teaches `Result`.
    io.println("Hello, world!")?
    .Ok(0)
}
```

Run it with the `linea` command:

```sh
linea run hello.lin
```

```
Hello, world!
```

Every program starts at `main`. This `main` returns a `Result`: either `.Ok`
with the exit status the shell sees, where `0` means success, or an
`io.IoError` if printing failed. `io.println` can fail — standard output might
be a closed pipe — and the `?` after it says *if this failed, stop here and
return the error*. [Errors](03-errors.md) covers `Result` and `?` properly.

`io.eprintln` writes a line to standard error instead, where a program says
what went wrong. It takes no `?`: it returns `()`, the empty value that
[`read`, `inout` and `sink`](#read-inout-and-sink) introduces, rather than a
`Result`, because when writing an error message fails, the program has
nowhere left to report that failure.

`import std.io` loads the standard library's `io` module, and `io.println`
names a function inside it. The names almost every program needs are there
without an import. This set is called the **prelude**: types such as `Option`,
`Result`, `Str`, `String` and `Vec`, and traits such as `Display`, `Debug`,
`Release`, `From` and `Default`. Everything else comes from a module you
import. A module may declare its own type under a prelude name, and its own
declaration wins inside that module.

To check a program without running it, use `linea check hello.lin`. To start a
project with its own directory, a test and a manifest, use
`linea init hello`. It creates `hello/linea.json`, which names the source
directory `src`, and `hello/src/main.lin`, a program with a `main`, a function
and a test. `linea run hello` runs the program and `linea test hello` runs the
test. `linea init --library arithmetic` starts a library, which has no `main`.

## Values and their types

```linea
import std.io

fn main() -> Result[UInt8, io.IoError] {
    let apples = 12
    let price_cents: UInt64 = 45
    let weight_kg = 1.5
    let organic = true
    let fruit = "apple"
    io.println("{apples} {fruit}s weigh {weight_kg} kg and cost {apples * price_cents} cents.")?
    io.println("Organic: {organic}")?
    .Ok(0)
}
```

```
12 apples weigh 1.5 kg and cost 540 cents.
Organic: true
```

The built-in types are the ones you would expect:

| Type | Holds |
| --- | --- |
| `Int8` … `Int64`, `UInt8` … `UInt64` | signed and unsigned integers of 8, 16, 32 or 64 bits |
| `Float64` | a 64-bit IEEE 754 floating-point number |
| `Bool` | `true` or `false` |
| `Str` | a view of UTF-8 text, such as a string literal |

You rarely write a type on a local. `weight_kg` is a `Float64` because `1.5`
is one, and `fruit` is a `Str`. Braces inside a string insert a value:
`"{apples} {fruit}s"`. [Text](08-text.md) covers interpolation and layout.

An integer literal takes the type its uses need. `apples` is multiplied by
`price_cents`, a `UInt64`, so `apples` is a `UInt64` too. A literal with no
such use is an `Int64`. The compiler also checks that the literal fits the type
it ends up with:

```linea
import std.io

fn main() -> Result[UInt8, io.IoError] {
    let apples = 12
    let price_cents: UInt64 = 45
    let crates = -2
    let total = apples * price_cents + crates
    io.println("{total}")?
    .Ok(0)
}
```

```
error[T-Literal]: `UInt64` cannot hold -2
 --> default_int.lin:6:18
  |
6 |     let crates = -2
  |                  ^^ value is out of range for its type
7 |     let total = apples * price_cents + crates
  |                                        ------ settled to `UInt64` here
```

The error shows both halves: where the literal is, and the use that made it
unsigned.

Values of different types never mix silently. Multiplying a `UInt8` by a
`UInt64` is an error, and you convert one side by writing the type as a
function:

```linea
fn main() -> UInt8 {
    let boxes: UInt8 = 3
    let per_box: UInt64 = 24
    let eggs = boxes * per_box
    UInt8(eggs / 10)
}
```

```
error[T-Operands]: expected `UInt8`, found `UInt64`
 --> boxes.lin:4:24
  |
4 |     let eggs = boxes * per_box
  |                ----- expected because of this operand
  |                        ^^^^^^^ expected `UInt8`, found `UInt64`
```

Write `UInt64(boxes) * per_box` and the program compiles.

### Arithmetic is checked

Integer arithmetic never wraps around silently. When the compiler can see an
overflow, the program does not compile:

```linea
fn main() -> UInt8 {
    let seats: UInt8 = 200
    let doubled = seats * 2
    doubled
}
```

```
error[T-Overflow]: this operation overflows `UInt8`
 --> seats.lin:3:25
  |
3 |     let doubled = seats * 2
  |                         ^ the result is not representable
```

When it cannot see it, because the number arrives while the program runs, the
program stops at the overflow instead of carrying on with a wrong number:

```linea
import std.env

fn main() -> UInt8 {
    // `env.args()` is the command line; `count()` is how many words it holds,
    // the program's own name included.
    let seats = UInt8(200 + env.args().count())
    seats * 2
}
```

```
linea: integer overflow at seats_runtime.lin:7:11
```

Dividing by zero stops the program the same way. No operation in Linea has
undefined behaviour: each one gives a defined result or a diagnosed error, in
every build mode. Rust panics on overflow only in debug builds; Linea does it
in all of them.

## `let` and `var`

`let` makes a binding you cannot reassign:

```linea
fn main() -> UInt8 {
    let visitors = 0
    visitors = visitors + 1
    visitors
}
```

```
error[N-Immutable]: `visitors` is declared with `let`
 --> counter.lin:3:5
  |
2 |     let visitors = 0
  |         -------- declared with `let` here
3 |     visitors = visitors + 1
  |     ^^^^^^^^ this binding cannot be assigned
```

Use `var` for a binding that changes. `+=`, `-=`, `*=` and the rest update it
in place:

```linea
fn main() -> UInt8 {
    var visitors = 0
    visitors += 1
    visitors
}
```

This program exits with status 1. `let` is Rust's `let`, and `var` is Rust's
`let mut`.

A `let` written outside any function is a **module constant**. Every function
in the file can read it:

```linea
import std.io

// A `let` outside any function is a module constant, usable from every function.
let vat_percent: UInt64 = 20

fn with_vat(cents: UInt64) -> UInt64 {
    cents + cents * vat_percent / 100
}

fn main() -> Result[UInt8, io.IoError] {
    io.println("A 1000-cent lamp costs {with_vat(1000)} cents with VAT.")?
    .Ok(0)
}
```

```
A 1000-cent lamp costs 1200 cents with VAT.
```

## Functions

```linea
import std.io

fn area(width: UInt64, height: UInt64) -> UInt64 {
    width * height
}

// `tile` has a default, so a caller may leave it out.
fn tiles_needed(floor: UInt64, tile: UInt64 = 4) -> UInt64 {
    if floor % tile == 0 {
        return floor / tile
    }
    floor / tile + 1
}

fn main() -> Result[UInt8, io.IoError] {
    let kitchen = area(3, 5)
    io.println("The kitchen floor is {kitchen} square metres.")?
    io.println("It takes {tiles_needed(kitchen)} large tiles")?
    io.println("or {tiles_needed(kitchen, tile: 1)} small ones.")?
    .Ok(0)
}
```

```
The kitchen floor is 15 square metres.
It takes 4 large tiles
or 15 small ones.
```

A function's parameters always have written types, and so does its result
when it has one. The last expression in its body is its result, so `area` needs no `return`; `return`
is for leaving early, as `tiles_needed` does when the floor divides evenly.

`main` ends the same way: its last line, `.Ok(0)`, is its result, the exit
status the shell sees.

A caller can name an argument, as in `tiles_needed(kitchen, tile: 1)`.
Positional arguments come first; named ones follow in any order. A parameter
with a default, like `tile: UInt64 = 4`, may be left out.

### A name's case says what it names

A name's first letter says what kind of thing it names. Types, traits, enum
variants and type parameters start with a capital letter: `UInt64`, `Result`,
`Ok`. Functions, fields, parameters, module constants, modules and every
local start with a lowercase letter: `area`, `tiles_needed`, `kitchen`. The
compiler holds you to it, and suggests the name respelled:

```linea
fn Area(width: UInt64, height: UInt64) -> UInt64 {
    width * height
}

fn main() -> UInt8 {
    UInt8(Area(3, 5))
}
```

```
error[N-Case]: functions start with a lowercase letter
 --> area.lin:1:4
  |
1 | fn Area(width: UInt64, height: UInt64) -> UInt64 {
  |    ^^^^ rename it `area`
```

A leading `_`, which marks a name you mean to leave unused, does not count:
`_total` is a lowercase name. Rust has the same conventions as warnings; in
Linea they are part of the language, so a capitalised name is never a variable
or a function.

### Where a statement ends

A line break ends a statement, so Linea needs no `;`; write one only to put two
statements on one line. A line break does not end a statement in two cases:

- when the line stops where no statement can end: after an operator such as
  `+` or `-`, an `=`, a `(`, a `[` or a `,`. That is how a long call or array
  spreads over several lines, one argument or element per line;
- when the next line opens with `.` and a lowercase name. No statement starts
  that way, so the line continues the expression above it, and a long
  calculation can put each step on a line of its own:

```linea
import std.io

fn main() -> Result[UInt8, io.IoError] {
    let side = 2.5
    // A line that opens with `.` and a lowercase name continues the line above.
    let area = side
        .pow(2.0)
    io.println("A square with side {side} m covers {area} m².")?
    .Ok(0)
}
```

```
A square with side 2.5 m covers 6.25 m².
```

`.pow(2.0)` raises `side` to the power 2. A line that opens with `.` and a
capital letter, such as `.Ok(0)` or `.None`, or with `.{`, names a variant or
builds a struct instead, and begins a statement of its own. That is why `main`
can end with `.Ok(0)` right after a statement.

A line that begins with `-` or `(` could also have continued the line above,
but it does not: the statement above has already ended. The compiler adds a
note when it sees one. Here a subtraction was split before its `-`:

```linea
import std.io

fn main() -> Result[UInt8, io.IoError] {
    let price = 1200
    let discount = 150
    let total = price
        - discount
    io.println("You pay {total} cents.")?
    .Ok(0)
}
```

```
note[S-Continuation]: the next line begins with `-`, which could have continued the expression above
 --> checkout.lin:7:9
  |
7 |         - discount
  |         ^ end the previous line with it if that was meant
error[T-Discard]: this expression produces an `Int64` that is discarded
 --> checkout.lin:7:9
  |
7 |         - discount
  |         ^^^^^^^^^^ bind it with `let _ =` to discard it deliberately
```

The first line ended with `price`, where a statement can end, so `total` is
just `price`, and `- discount` stood alone as a value nobody uses, which is an
error. Keep the subtraction on one line, or end the first line with the `-`, as
the note says: `let total = price -` cannot end there, so the next line carries
it on.

### `read`, `inout` and `sink`

A parameter is only *read* by default: the function looks at the value, and the
caller keeps it unchanged. So a function cannot change a read parameter, even
its own copy of a number:

```linea
// A read parameter cannot be changed: `service_charge` may only look at `bill`.
fn service_charge(bill: UInt64) -> UInt64 {
    bill += bill / 10
    bill
}

fn main() -> UInt8 {
    UInt8(service_charge(100) - 100)
}
```

```
error[N-Immutable]: `bill` is a read-only parameter
 --> service_charge.lin:3:5
  |
2 | fn service_charge(bill: UInt64) -> UInt64 {
  |                   ---- read-only parameter declared here
3 |     bill += bill / 10
  |     ^^^^ this binding cannot be assigned
```

Replace the body with `bill + bill / 10` and it compiles; the program exits
with status 10, the charge on a 100-cent bill. `read` is the name of this
default. You never write it on a parameter, because every parameter already
has it. Write `fn service_charge(read bill: UInt64)` in the fixed program:

<!-- guide: unchecked the error an edit of the program above produces -->
```
error[S-Entry]: `read` is redundant on a parameter
 --> service_read.lin:2:19
  |
2 | fn service_charge(read bill: UInt64) -> UInt64 {
  |                   ^^^^ omit `read`; parameters are read by default
```

You will still meet the word. Error messages say a parameter was `declared
read`, a function type prints it, as in `fn(read UInt64) -> UInt64`, and you
write it in `for read` and `match read` below, where the form would otherwise
take its value.

Two words change the default, and they are the first of the two ideas at work.

`inout` lets the function change the caller's value. The caller marks the
argument with `&`, so the change is visible where it happens:

```linea
import std.io

// `inout` lets `add_tip` change the caller's bill. The caller writes `&` to
// show that the bill may change.
fn add_tip(inout bill: UInt64, percent: UInt64) {
    bill += bill * percent / 100
}

fn main() -> Result[UInt8, io.IoError] {
    var dinner = 4000
    let before = dinner
    add_tip(&dinner, 15)
    io.println("before {before}, after {dinner}")?
    .Ok(0)
}
```

```
before 4000, after 4600
```

`before` kept its own copy of the number, so changing `dinner` did not change
it. Two variables never share one value.

`add_tip` has nothing to give back, so it writes no `->` and no result type.
Such a function returns `()`, the type with one value and nothing in it.
Rust lets you write that result out as `-> ()`; Linea refuses it, so a
function returning nothing has exactly one spelling:

```linea
fn add_tip(inout bill: UInt64, percent: UInt64) -> () {
    bill += bill * percent / 100
}

fn main() -> UInt8 {
    var dinner = 4000
    add_tip(&dinner, 15)
    0
}
```

```
error[S-UnitResult]: a function that returns nothing writes no result type
 --> tip.lin:1:49
  |
1 | fn add_tip(inout bill: UInt64, percent: UInt64) -> () {
  |                                                 ^^^^^ a function writing no result returns `()`
  |
  = help: remove `-> ()`
```

The value of `()` is written the same way, `()`, so the type and the value
look alike, as they do in Rust. A function that gives nothing back but can
fail answers `Result[(), E]`, and its success is `.Ok(())`:

```linea
import std.io

// `print_receipt` gives nothing back, but printing can fail, so it answers
// `Result[(), io.IoError]` and succeeds with `.Ok(())`.
fn print_receipt(item: Str, cents: UInt64) -> Result[(), io.IoError] {
    io.println("{item}: {cents} cents")?
    io.println("Thank you.")?
    .Ok(())
}

fn main() -> Result[UInt8, io.IoError] {
    print_receipt("tea", 250)?
    .Ok(0)
}
```

```
tea: 250 cents
Thank you.
```

A block's value is its last expression. An empty block, `{}`, computes
nothing, so its value is `()` as well. That is why a `match` arm with nothing
to do can be written `=> {}`.

`sink` makes the function take the value, and the caller cannot use it
afterwards. A number is copied whenever it is passed, so `sink` shows its
effect on a value that is not a plain number, like this parcel:

```linea
import std.io

// A `struct` groups named values. "Structs and enums" below covers them.
struct Parcel {
    weight_grams: UInt64,
}

// `sink` takes the parcel: once it is posted, the caller no longer has it.
fn post(sink parcel: Parcel) -> UInt64 {
    parcel.weight_grams / 100 * 3
}

fn main() -> Result[UInt8, io.IoError] {
    let gift = Parcel { weight_grams = 1200 }
    let stamps = post(gift)
    io.println("posting the gift took {stamps} stamps")?
    .Ok(0)
}
```

```
posting the gift took 36 stamps
```

Try to post the same gift twice, with `let _again = post(gift)` after the
`println`, and the compiler points at both calls:

<!-- guide: unchecked the error an edit of the program above produces -->
```
error[O-Move]: `gift` has already been moved
  --> twice.lin:17:23
   |
15 |     let stamps = post(gift)
   |                       ---- it was taken here
17 |     let _again = post(gift)
   |                       ^^^^ it was already taken, and a value is taken once
```

A value has one owner at a time. `sink` hands it over, so there is never a
second copy of the parcel that could be posted again. Rust calls this a
*move*; in Linea the parameter says so, and the call site does not change.

The three conventions, read from the caller's side:

| Parameter | At the call | What it means |
| --- | --- | --- |
| read (the default) | `f(x)` | I keep it; the function only looks |
| `inout` | `f(&x)` | I lend it for the call; the function may change it |
| `sink` | `f(x)` | I give it away; the function takes ownership, and `x` is gone |

`sink` is written on the parameter, never at the call: the function takes
ownership, and a number is copied instead. [Calling
things](02-calling-things.md#-marks-a-receiver-the-call-will-change) shows the
same table for dot calls.

## Deciding and repeating

```linea
import std.io

fn main() -> Result[UInt8, io.IoError] {
    let temperatures = [18, 21, 25, 19, 30]
    var warm_days = 0
    // `for read` walks the array and leaves it whole, so it can be counted below.
    for read reading in temperatures {
        // An `if` is an expression, so it can give `feel` its value.
        let feel = if reading >= 25 { "hot" } else if reading >= 20 { "warm" } else { "cool" }
        io.println("{reading} degrees: {feel}")?
        if reading >= 20 {
            warm_days += 1
        }
    }
    io.println("{warm_days} of {temperatures.length()} days were at least warm.")?

    var countdown = 3
    while countdown > 0 {
        io.println("{countdown}...")?
        countdown -= 1
    }

    // `1..=3` includes 3; `1..3` would stop at 2.
    for day in 1..=3 {
        io.println("day {day}")?
    }
    .Ok(0)
}
```

```
18 degrees: cool
21 degrees: warm
25 degrees: hot
19 degrees: cool
30 degrees: hot
3 of 5 days were at least warm.
3...
2...
1...
day 1
day 2
day 3
```

`for` walks anything that can be walked, such as an array, a range or a slice;
[Iterating](05-iterating.md#what-a-for-can-walk-sequences-and-iterators) says
what makes a type walkable. `while` repeats while a condition holds.
Conditions need no parentheses, and the braces are required.

### `for` and `for read`

A plain `for x in xs` takes `xs`, the way a `sink` parameter takes its
argument: the loop owns the array from then on and hands you its elements one
by one. `for read x in xs` walks the array where it is and leaves it whole, so
you can still use it after the loop. That is why the program above can ask for
`temperatures.length()` at the end. Take the `read` away and the count is
refused, because the loop has already taken the array:

<!-- guide: unchecked the error an edit of the program above produces -->
```
error[O-Move]: `temperatures` has already been moved
  --> weather.lin:15:33
   |
7  |     for reading in temperatures {
   |                    ------------ it was taken here
15 |     io.println("{warm_days} of {temperatures.length()} days were at least warm.")?
   |                                 ^^^^^^^^^^^^ it was already taken, and a value is taken once
```

A range such as `1..=3` exists only for its loop, so a plain `for` is the right
one there. Use `for read` whenever the collection is still needed afterwards.
[Iterating](05-iterating.md#four-ways-to-walk) adds `for inout`, which lets the
body change each element, and [Borrowing](06-borrowing.md#reading-a-value-takes-nothing)
explains what `read` means everywhere else it appears.

### `loop`, `break` and `continue`

`loop` repeats until a `break` leaves it. `continue` ends the current pass and
starts the next one:

```linea
import std.io

fn main() -> Result[UInt8, io.IoError] {
    // A hiker carries 5 litres of water and drinks 2 a day.
    var litres = 5
    var days = 0
    // `loop` repeats until a `break` leaves it.
    loop {
        if litres < 2 {
            break
        }
        litres -= 2
        days += 1
    }
    io.println("The water lasts {days} days, with {litres} litre left over.")?

    let temperatures = [18, 21, 25, 19, 30]
    for read reading in temperatures {
        // `continue` skips the rest of this pass, so cooler days print nothing.
        if reading < 25 {
            continue
        }
        io.println("{reading} degrees: a day for the beach")?
    }
    .Ok(0)
}
```

```
The water lasts 2 days, with 1 litre left over.
25 degrees: a day for the beach
30 degrees: a day for the beach
```

`break` and `continue` work the same way in `for` and `while` loops.

## Arrays, views and collections

`[18, 21, 25, 19, 30]` is an **array**: a fixed number of values of one type,
stored in place. Its type, `[Int64; 5]`, holds the element type and the length.
Write `_` for the length and the compiler counts it:

```linea
import std.io

// The length is part of an array's type. `_` asks the compiler to count it.
let week: [Str; _] = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

fn main() -> Result[UInt8, io.IoError] {
    let highs: [Int64; 7] = [18, 21, 25, 19, 30, 27, 22]
    io.println("{week.length()} days, starting on {week[0]}")?
    // `as_slice()` lends the array out as a `Slice`, a view of its elements.
    // `subspan(5, 2)` answers the last two days, or nothing if they are not
    // there, and `unwrap()` takes the answer out, stopping the program if
    // there is none.
    let weekend = highs.as_slice().subspan(5, 2).unwrap()
    var warmest = weekend[0]
    for high in weekend {
        if *high > warmest {
            warmest = *high
        }
    }
    io.println("The weekend peaks at {warmest} degrees.")?
    .Ok(0)
}
```

```
7 days, starting on Mon
The weekend peaks at 27 degrees.
```

Every index is checked. One computed while the program runs stops the program
instead of reading past the end, with `linea: index out of bounds at …`. One
the compiler can see is out of range does not compile at all. Add
`io.println("Sunday: {highs[7]}")?` after the weekend line:

<!-- guide: unchecked the error an edit of the program above produces -->
```
error[T-Index]: no element sits here, and the length is part of the type
  --> week_index.lin:14:32
   |
14 |     io.println("Sunday: {highs[7]}")?
   |                                ^ the length is 7, so the last index is 6
```

### Views: `Str` and `Slice`

`weekend` is a `mem.Slice[Int64]`, the `Slice` type of the `std.mem` module; a
signature that takes one writes `mem.Slice[Int64]` after `import std.mem`. It
does not hold any numbers of its own. It is a
**view**: it points at two of the elements `highs` owns. A view is cheap to
make and to pass around, and it works only while the thing it points into is
still there. Walking a slice with `for` hands you each element as a view too,
and `*high` reads the number it points at.

`Str` is the same idea for text. A string literal is a `Str` pointing at text
stored in the program, and slicing text gives another `Str` pointing into the
same bytes. Linea checks that no view outlives what it points into;
[Borrowing](06-borrowing.md) shows how.

### `Vec`: a list that grows

An array's length is fixed when you write it. A `Vec` grows while the program
runs, so it needs memory from somewhere, and Linea makes you say where. For now,
read `Vec[Str]` as a growable list of `Str` that takes its memory from the heap.
A `Vec` names its allocator as a second type argument, and leaving it out
means the heap: `Vec[Str]` is `Vec[Str, mem.SystemAllocator]`, which is how
the compiler spells it in a message:

```linea
import std.io

fn main() -> Result[UInt8, io.IoError] {
    // `Vec.new()` takes its memory from the heap. A `Vec` that allocates from
    // it must be released, and `defer` releases it when `main` ends, however
    // it ends.
    var basket: Vec[Str] = Vec.new()
    defer basket.release()
    let wanted = ["bread", "milk", "eggs"]
    for item in wanted {
        // `push` fails when memory runs out, so its result is checked.
        if &basket.push(item).is_err() {
            return .Ok(1)
        }
    }
    io.println("{basket.length()} items, first {basket[0]}")?
    for read item in basket {
        io.println("- {item}")?
    }
    .Ok(0)
}
```

```
3 items, first bread
- bread
- milk
- eggs
```

A few things are new here:

- `Vec.new()` makes an empty vector that takes its memory from the system
  allocator, the operating system's heap. A `Vec[T, A]` names the allocator
  type `A` it takes memory from, and `Vec.new_in(allocator)` makes an empty one
  in an allocator the caller chooses. [Memory](07-memory.md) explains why the
  caller always chooses. An empty vector has no element to infer the type
  from, which is why `basket` has an annotation.
- `&basket.push(item)` adds an item. The `&` in front says the call changes
  `basket`, just as `&dinner` did for `add_tip`. `push` can fail when memory
  runs out, so it returns a `Result` you must look at.
- This `Vec` takes its memory from the heap, which must be given back, so the
  vector must be settled: it is a value that must be consumed exactly once —
  the second idea — and `basket.release()` consumes it. Leave the release out
  and the program does not compile. It is the storage that makes the vector
  owe something; a `Vec` is not linear by nature, and [Memory](07-memory.md)
  shows memory that owes nothing. Settling is not freeing memory: committing a
  payment, returning a loan and closing a socket settle a value too.
- `defer basket.release()` schedules the release for when the block ends, on
  every way out of it: the normal end, the early `return .Ok(1)`, and every
  `?`. It is written once, right beside the value it cleans up.
- `for read item in basket` walks the vector and leaves it whole, as `for read`
  does for an array.

Delete the `defer` line and the compiler lists every way out of `main` that
would leave the basket's memory held:

<!-- guide: unchecked the error an edit of the program above produces -->
```
error[O-Leak]: `basket` (a linear `Vec[Str, mem.SystemAllocator]`) is still owned when this path leaves
  --> basket.lin:12:13
   |
7  |     var basket: Vec[Str, mem.SystemAllocator] = Vec.new()
   |         ------ acquired here
12 |             return .Ok(1)
   |             ^^^^^^ still owned here
15 |     io.println("{basket.length()} items, first {basket[0]}")?
   |                                                             - also still owned here
17 |         io.println("- {item}")?
   |                               - also still owned here
20 | }
   | - also still owned where the block ends
   |
   = help: settle it first with `basket.release()`, or declare it `defer var basket = …` so every path releases it
```

The two `?` marks count as ways out, because a failed print returns from
`main` early. Writing `basket.release()` before each of the four exits would
work too; one `defer` says the same thing once. The help offers a shorter
spelling still: `defer var basket: Vec[Str, mem.SystemAllocator] = Vec.new()`
declares the vector and schedules its release in one statement.
[Copying, settling and sealing](04-copying-settling-and-sealing.md) covers
`defer let` and `defer var`.

`String` is the growable, owned counterpart of `Str`, in the same way. Both
`Vec` and `String` are in the prelude.

### `Map`: values by key

A `collections.Map` finds a value by its key, like Rust's `HashMap` or a Python
dictionary:

```linea
import std.collections
import std.io

fn main() -> Result[UInt8, io.IoError] {
    let votes = ["tea", "coffee", "tea", "juice", "tea"]
    // `merge` keeps each drink as a key, so the loop takes the array to hand
    // the drinks over; that is why the count is read before the loop.
    let ballots = votes.length()
    var counts: collections.Map[Str, UInt64] = collections.Map.new()
    defer counts.release()
    for drink in votes {
        // `merge` inserts a new drink with 1, or adds 1 to the count stored.
        if &counts.merge(drink, 1, |sink stored, sink added| stored + added).is_err() {
            return .Ok(1)
        }
    }
    let tea = *counts.get("tea").unwrap()
    io.println("tea has {tea} of {ballots} votes")?
    .Ok(0)
}
```

```
tea has 3 of 5 votes
```

`|sink stored, sink added| stored + added` is a small unnamed function, a
**lambda**, that `merge` calls when the key is already there. [Calling
things](02-calling-things.md#closures-functions-that-capture) covers lambdas and
closures. `counts.get("tea")` answers a view of the stored count, or nothing
if the key is missing, and `*` reads the number out of the view. A map also
has `insert`, which hands back the entry a key held before; `remove`; `update`,
which changes a stored value in place; `length()`; and `entries()`, which walks
every key and value.

## Structs and enums

A struct groups named fields. An enum is a value that is one of several
variants, and a variant can carry a value of its own:

```linea
import std.io

struct Room {
    name: Str,
    width: UInt64,
    length: UInt64,
}

enum Floor {
    Carpet,
    Tiles(UInt64),
    Wood(Bool),
}

fn area(room: Room) -> UInt64 {
    room.width * room.length
}

fn describe(floor: Floor) -> Str {
    // `match read` picks an arm without taking `floor`; "`match`" below says why.
    match read floor {
        Carpet => "carpet",
        Tiles(size) => if size >= 60 { "large tiles" } else { "small tiles" },
        Wood(varnished) => if varnished { "varnished wood" } else { "bare wood" },
    }
}

fn main() -> Result[UInt8, io.IoError] {
    let hall = Room { name = "hall", width = 2, length = 6 }
    let floor = Floor.Wood(true)
    io.println("The {hall.name} is {area(hall)} square metres of {describe(floor)}.")?
    // The annotation names the enum, so `.Tiles` needs no `Floor` in front.
    let bathroom: Floor = .Tiles(30)
    io.println("The bathroom has {describe(bathroom)}.")?
    .Ok(0)
}
```

```
The hall is 12 square metres of varnished wood.
The bathroom has small tiles.
```

You build a struct by naming its type and giving every field with `=`:
`Room { name = "hall", width = 2, length = 6 }`. Where the type is already
known — from an annotation, a parameter or a return type — you can leave its
name out and write `.{ name = "hall", width = 2, length = 6 }`. A field whose
value is a local of the same name can be written once: `Room { name, width,
length }`.

A variant is named through its enum, `Floor.Wood(true)`, or with a leading dot
where the enum is known, `.Tiles(30)`.

### Defaults and struct update

A struct that derives `Default` has a value to start from, with each field at
its own type's starting value. `..` fills in every field you do not write from
another value of the same type:

```linea
import std.io

// `@derive(Default)` gives every field its type's starting value: 0, false,
// and empty text.
@derive(Default, Debug)
struct Order {
    shots: UInt64,
    oat_milk: Bool,
    name: Str,
}

fn main() -> Result[UInt8, io.IoError] {
    let plain = Order.default()
    // `..` takes every field not written here from another value.
    let flat_white = Order { shots = 2, name = "Ada", ..Order.default() }
    let oat = Order { oat_milk = true, ..flat_white }
    io.println("plain: {plain:?}")?
    io.println("oat:   {oat:?}")?
    .Ok(0)
}
```

```
plain: Order { shots: 0, oat_milk: false, name: "" }
oat:   Order { shots: 2, oat_milk: true, name: "Ada" }
```

`@derive(...)` asks the compiler to write the obvious implementation for you
([Calling things](02-calling-things.md#derive-implementations-the-compiler-writes)
lists what it can write); `Debug` is what lets `{plain:?}` print every field.
`oat` keeps the two shots
and the name from `flat_white` and changes only the milk. The base after `..`
is taken, so `flat_white` is used up by building `oat`. This is Rust's struct
update syntax, `..Default::default()` included.

### Tuples

A **tuple** groups two to eight values by position, with no names:
`(lo, hi)`. Its type is written the same way, `(Int64, Int64)`.

```linea
import std.io

// The cheapest and dearest price of a basket: two numbers whose meaning is
// clear from the function's name, so the function needs no struct for them.
fn bounds(prices: [Int64; 3]) -> (Int64, Int64) {
    var lo = prices[0]
    var hi = prices[0]
    for read price in prices {
        if price < lo {
            lo = price
        }
        if price > hi {
            hi = price
        }
    }
    (lo, hi)
}

fn main() -> Result[UInt8, io.IoError] {
    let prices = [1200, 850, 300]
    // `let (lo, hi)` takes the pair apart into two bindings.
    let (lo, hi) = bounds(prices)
    io.println("Prices run from {lo} to {hi} cents.")?
    // A pair is also one value; `._0` and `._1` name its components.
    let range = bounds(prices)
    io.println("The dearest price is {range._1} cents.")?
    .Ok(0)
}
```

```
Prices run from 300 to 1200 cents.
The dearest price is 1200 cents.
```

`let (lo, hi) = bounds(prices)` takes the pair apart into two bindings, one for
each component. A tuple that stays whole is one value, and `range._0`,
`range._1` name its components by position, counting from zero.
[Iterating](05-iterating.md#pairs-from-enumerate-and-zip) takes pairs apart in
a `for`, and [Calling things](02-calling-things.md#a-closure-that-takes-a-pair-apart)
in a lambda's parameters.

Use a tuple for a positional relationship that is obvious from where it
appears: the lowest and highest price, or an item and its position. Use a
struct when the components are concepts of your domain that deserve names, such
as a `Room` with a `width` and a `length`. If the reader would ask which
number is which, write the struct.
Taking a tuple apart with a pattern does not dispose of its components: each
binding receives one.

Parentheses with one thing in them only group, `(x)` is just `x` as in
arithmetic, and `()` with nothing in it is the unit value from before. A tuple
has at least two components and at most eight; a longer row is a struct
waiting to be named:

```linea
fn main() -> UInt8 {
    let _row = (1, 2, 3, 4, 5, 6, 7, 8, 9)
    0
}
```

```
error[S-Tuple]: a tuple has two to eight components
 --> wide_tuple.lin:2:16
  |
2 |     let _row = (1, 2, 3, 4, 5, 6, 7, 8, 9)
  |                ^ give a struct names past eight parts
```

### `match`

`match` picks the arm whose pattern fits the value, and binds what the variant
carries: in `Tiles(size) => …`, `size` is the number inside. Every variant must
be covered. Leave one out and the program does not compile:

```linea
enum Floor {
    Carpet,
    Tiles(UInt64),
    Wood,
}

fn price(floor: Floor) -> UInt64 {
    match read floor {
        Carpet => 20,
        Tiles(count) => count * 2,
    }
}

fn main() -> UInt8 {
    UInt8(price(.Carpet))
}
```

```
error[T-Cover]: this `match` does not cover `Wood`
 --> nonexhaustive.lin:8:5
  |
8 |     match read floor {
  |     ^^^^^^^^^^^^^^^^^^ add the missing arms, or a `_`
```

That is why adding a variant to an enum is safe: every `match` that needs to
handle it tells you so.

`match read` looks at the value without taking it apart
([Borrowing](06-borrowing.md#reading-a-value-takes-nothing) is about reading
without taking). A plain `match` takes the value apart and hands its pieces to
the arm, which is what you want when you own the value and are done with it.
`describe` only reads its `floor`, so it cannot take it apart. Write `match floor` there and:

<!-- guide: unchecked the error an edit of the program above produces -->
```
error[O-Move]: `floor` is lent, and this takes it
  --> matchtake.lin:21:11
   |
21 |     match floor {
   |           ^^^^^ `copy` it, or declare the parameter `sink` to take it
```

This is the first ownership error most people meet, and it reads the way it
sounds: `describe` was lent the floor, and a plain `match` would keep it.

### Operations with `impl`

A type's braces hold its data and nothing else. Functions that belong to a type
go in an `impl` block, and are called on a value with a dot:

```linea
import std.io

struct Room {
    name: Str,
    width: UInt64,
    length: UInt64,
}

impl Room {
    // `Self` names the type the `impl` is for, here `Room`.
    fn area(self: Self) -> UInt64 {
        self.width * self.length
    }
}

fn main() -> Result[UInt8, io.IoError] {
    let hall = Room { name = "hall", width = 2, length = 6 }
    io.println("The {hall.name} is {hall.area()} square metres.")?
    .Ok(0)
}
```

```
The hall is 12 square metres.
```

The first parameter, `self`, is the value before the dot. [Calling
things](02-calling-things.md) covers operations, traits and how a dot call
finds what it runs.

### Checkpoint

You can now read a program that declares structs and enums, defines functions
and operations on them, branches with `if` and `match`, loops with `for` and
`while`, and keeps its data in arrays, `Vec`s and `Map`s. That covers most of
what the [example programs](../../examples/) are made of. The rest of this
chapter adds the part of Linea that is new, values that must be consumed
exactly once, and then modules, tests and the commands. If you are reading in a
hurry, skip ahead to [The commands](#the-commands) and come back.

## Values consumed exactly once

Here is the second idea in its simplest form. A café takes a payment for each
order, and each payment must end in exactly one of two ways: committed to the
till, or refunded. A payment that silently disappears is lost money, and one
committed twice is a bug. `@linear` says so:

```linea
import std.io

// A payment must be consumed exactly once: committed to the till, or refunded.
@linear
struct Payment {
    cents: UInt64,
}

impl Payment {
    // `sink self` takes the payment, and the pattern takes it apart.
    fn commit(sink self: Self, inout till: UInt64) {
        let Payment { cents } = self
        till += cents
    }

    fn refund(sink self: Self) -> UInt64 {
        let Payment { cents } = self
        cents
    }
}

fn main() -> Result[UInt8, io.IoError] {
    var till = 0
    let coffee = Payment { cents = 250 }
    let cake = Payment { cents = 320 }
    let cake_in_stock = false
    coffee.commit(&till)
    // The cake is sold out, so its payment goes back.
    let refunded = if cake_in_stock {
        cake.commit(&till)
        0
    } else {
        cake.refund()
    }
    io.println("{till} cents in the till, {refunded} refunded")?
    .Ok(0)
}
```

```
250 cents in the till, 320 refunded
```

`commit` and `refund` both take the payment with `sink self`, so calling
either one consumes it. Inside them, `let Payment { cents } = self` is a
**pattern**: it takes the payment apart and binds its one field to `cents`,
which consumes it too. A pattern names fields with `:` where building a struct
uses `=`: `cents: c` binds the field to `c`, `cents: _` drops it, and a bare
`cents` binds it to a variable of the same name.

Forget one payment, and the program does not compile. Take a tea's payment,
print it, and do nothing else with it:

<!-- guide: unchecked the error an edit of the program above produces -->
```
error[O-Leak]: `tea` (a linear `Payment`) is still owned when this path leaves
  --> till_forgot.lin:37:64
   |
26 |     let tea = Payment { cents = 180 }
   |         --- acquired here
37 |     io.println("{till} cents in the till, {refunded} refunded")?
   |                                                                ^ still owned here
39 | }
   | - also still owned where the block ends
   |
   = help: settle it first with `tea.commit(…)` or `tea.refund()`, or take it apart with `let Payment { cents: _ } = tea`
```

The help lists every way to consume a payment. Consume one twice, with
`let _back = coffee.refund()` after the coffee is committed, and the program
does not compile either:

<!-- guide: unchecked the error an edit of the program above produces -->
```
error[O-Move]: `coffee` has already been moved
  --> till_twice.lin:28:17
   |
27 |     coffee.commit(&till)
   |     ------ it was taken here
28 |     let _back = coffee.refund()
   |                 ^^^^^^ it was already taken, and a value is taken once
```

Zero times is `[O-Leak]`, and twice is `[O-Move]`: exactly once is what is
left. The `Vec` and `Map` above are the same kind of value. Their memory must
be given back, and `release()` is the operation that consumes them. A type may
offer one ending, like `release()`, or several that each decide something,
like `commit` and `refund`. [Copying, settling and
sealing](04-copying-settling-and-sealing.md#linear-values-you-must-not-forget)
covers linear types in full.

## Modules

A module is a directory. Every `.lin` file in it shares one namespace, so the
files can use each other's declarations without importing anything. A project
that grows a module looks like this:

<!-- guide: unchecked a directory tree, not program output -->
```
garden/
    main.lin
    plants/
        plant.lin
        herbs.lin
```

`plants/plant.lin`:

```linea
pub struct Plant {
    name: Str,
    days_to_harvest: UInt64,
}

impl Plant {
    // `sink` takes the name, because the new plant keeps it.
    pub fn sow(sink name: Str, days_to_harvest: UInt64) -> Plant {
        Plant { name, days_to_harvest }
    }
}
```

`plants/herbs.lin`:

```linea
// Every file in `plants/` shares one namespace, so `Plant` needs no import here.
pub fn herb(sink name: Str) -> Plant {
    Plant.sow(name, days_to_harvest: 30)
}
```

`main.lin`:

```linea
import plants
import std.io

use plants.Plant

fn main() -> Result[UInt8, io.IoError] {
    let tomato = Plant.sow("tomato", days_to_harvest: 60)
    let basil = plants.herb("basil")
    io.println("{tomato.name} is ready in {tomato.days_to_harvest} days.")?
    io.println("{basil.name} is ready in {basil.days_to_harvest} days.")?
    .Ok(0)
}
```

Run the directory with `linea run garden`:

```
tomato is ready in 60 days.
basil is ready in 30 days.
```

`import plants` loads the module, relative to the project's source directory,
and `plants.herb` names something inside it. `use plants.Plant` brings one name
into scope so you can write `Plant` instead of `plants.Plant`.

Declarations are private to their module unless marked `pub`. Take `pub` off
`herb` and `main` can no longer call it:

<!-- guide: unchecked the error an edit of the program above produces -->
```
error[M-Vis]: `herb` is private to `plants`
 --> garden_private/main.lin:8:24
  |
8 |     let basil = plants.herb("basil")
  |                        ^^^^ declare it `pub` in its own module, or do not name it here
```

`internal` is a third visibility beside private and `pub`, and the `@opaque`
attribute seals a type's representation. [Copying, settling and
sealing](04-copying-settling-and-sealing.md#opaque-replaces-pub) lists all four
choices and what each allows.

Linea's rule about unused code applies across modules too: a declaration
nobody uses is an error, not a warning. A name starting with `_` says you meant
to leave it unused, as `_tiles` does in the next section.

### Using a library project

A module belongs to one program. Code that several programs share goes in a
**library project**: a directory whose `linea.json` says it is a library and
gives it the name programs import it by. Here a gardening almanac sits beside
the program that uses it:

<!-- guide: unchecked a directory tree, not program output -->
```
almanac/
    linea.json
    almanac.lin
planner/
    linea.json
    main.lin
```

`almanac/linea.json`:

```json
{ "kind": "library", "name": "almanac" }
```

`almanac/almanac.lin`:

```linea
// `frost_free_day` is public, so a program that depends on the library can
// call it.
pub fn frost_free_day() -> UInt64 {
    days_after_spring(40)
}

// `days_after_spring` is internal: every module of `almanac` may call it, and
// a program that depends on the library may not.
internal fn days_after_spring(days: UInt64) -> UInt64 {
    80 + days
}
```

The program names the library under `dependencies` in its own manifest, with
the directory that holds it, relative to the manifest:

`planner/linea.json`:

```json
{ "dependencies": { "almanac": { "path": "../almanac" } } }
```

`planner/main.lin`:

```linea
import almanac
import std.io

fn main() -> Result[UInt8, io.IoError] {
    io.println("Plant out after day {almanac.frost_free_day()}.")?
    .Ok(0)
}
```

Run the program with `linea run planner`:

```
Plant out after day 120.
```

`import almanac` starts with the library's name, so it reaches the library
rather than a directory of `planner`. The library is a separate root, so its
`internal` declarations stay inside it. Call `almanac.days_after_spring(10)`
from `main` and the compiler refuses it:

<!-- guide: unchecked the error an edit of the program above produces -->
```
error[M-Vis]: `days_after_spring` is internal to another root
 --> planner/main.lin:5:46
  |
5 |     io.println("Plant out after day {almanac.days_after_spring(10)}.")?
  |                                              ^^^^^^^^^^^^^^^^^ only modules in the same root may name it
```

A library that calls C functions through `extern` says `"extern": true` in its
own manifest. A program that uses it, even through another library, names it
under `dependencies` with `"extern": true` too, agreeing to trust signatures
the compiler cannot check.

A library may also offer functions to C with `export`, and that is the
library's own business: an `export` reaches C only from the project being
built, so a program that depends on the library gets no C symbol from it and
calls the function like any other public one.

`metric/linea.json`:

```json
{ "kind": "library", "name": "metric" }
```

`metric/metric.lin`:

```linea
// `to_centimetres` is exported to C when `metric` itself is built. A Linea
// program that depends on `metric` calls it as an ordinary public function.
pub export fn to_centimetres(inches: Int32) -> Int32 {
    inches * 254 / 100
}
```

`beds/linea.json`:

```json
{ "dependencies": { "metric": { "path": "../metric" } } }
```

`beds/main.lin`:

```linea
import metric
import std.io

fn main() -> Result[UInt8, io.IoError] {
    io.println("A 48-inch bed is {metric.to_centimetres(48)} cm long.")?
    .Ok(0)
}
```

Run the program with `linea run beds`:

```
A 48-inch bed is 121 cm long.
```

To publish `to_centimetres` as a C symbol, build `metric` on its own, or
write an `export` in the program itself.

If you know Rust: the entry is a path dependency, `almanac = { path =
"../almanac" }` in `Cargo.toml`, and `internal` is `pub(crate)`.

## Tests

Tests live beside the code they test. A `test fn` takes no arguments, and each
assertion is followed by `?`, which ends the test at the first failure:

```linea
import std.io
import std.testing

fn tiles_needed(floor: UInt64, tile: UInt64) -> UInt64 {
    if floor % tile == 0 {
        return floor / tile
    }
    floor / tile + 1
}

test fn a_floor_that_divides_evenly_needs_no_extra_tile() {
    testing.assert_eq(tiles_needed(16, 4), 4, "16 square metres of 4-metre tiles")?
}

test fn a_partial_tile_counts_as_a_whole_one() {
    testing.assert_eq(tiles_needed(15, 4), 4, "15 square metres of 4-metre tiles")?
}

// `test trap fn` marks a test that passes only if the program stops, here by
// dividing by zero.
test trap fn a_tile_of_no_size_stops_the_program() {
    let _tiles = tiles_needed(15, 0)
}

fn main() -> Result[UInt8, io.IoError] {
    io.println("A 15 square metre floor takes {tiles_needed(15, 4)} tiles.")?
    .Ok(0)
}
```

```sh
linea test tiles.lin
```

```
ok    a_floor_that_divides_evenly_needs_no_extra_tile
ok    a_partial_tile_counts_as_a_whole_one
ok    a_tile_of_no_size_stops_the_program

3 passed, 0 failed
```

Break `tiles_needed` by dropping the `+ 1`, and the runner shows both values
and your message:

<!-- guide: unchecked the output of an edited or partial program -->
```
ok    a_floor_that_divides_evenly_needs_no_extra_tile
FAIL  a_partial_tile_counts_as_a_whole_one
        expected 4, got 3
        error: 15 square metres of 4-metre tiles
ok    a_tile_of_no_size_stops_the_program

2 passed, 1 failed
```

`testing.assert_eq` compares whole values and prints both when they differ;
`testing.assert` checks a `Bool`. Each test runs in its own process, so one
that stops the program does not take the others with it. Tests are left out
of what `linea build` and `linea run` produce, but they are still checked:
a test that does not compile stops the build. [Testing](10-testing.md) covers
helpers, allocation failures and testing a server.

## The commands

| Command | What it does |
| --- | --- |
| `linea run <path>` | compile and run a program; arguments for the program follow `--` |
| `linea check <path>` | report errors without producing a binary |
| `linea test <path>` | run the tests |
| `linea build <path> -o <output>` | build an executable or a library object |
| `linea fmt <path>` | format source files in place |
| `linea init <directory>` | start a project; `--library` starts a library |

A `<path>` is a single `.lin` file or a project directory. `linea lsp` serves
editors; `linea fmt --check <path>` reports the files the formatter would
change without writing them; `linea build --keep` retains the intermediate
files; and `linea emit-mlir <path>` prints the generated MLIR.

## What you have seen

- Variables hold values, never references to someone else's; `inout` and `&`
  change a caller's value in the open, and `sink` takes it.
- A linear value must be consumed exactly once, and the compiler checks every
  path: never is `[O-Leak]`, twice is `[O-Move]`.
- `let` binds, `var` binds something that changes, and types are inferred from
  the values you write. A `let` outside a function is a module constant.
- A function ends with its result; `return` leaves early. A line break ends a
  statement, unless the line stops after an operator, `(`, `[` or `,`, or the
  next line opens with `.` and a lowercase name.
- A capital first letter names a type, a trait, a variant or a type
  parameter; every other name starts with a lowercase letter.
- Arithmetic and indexing are checked, and nothing has undefined behaviour.
- `()` is the type with nothing in it, and `()` is also its one value; an
  empty block `{}` has that value too.
- `for x in xs` takes `xs`, and `for read x in xs` leaves it usable; `loop`
  repeats until `break`, and `continue` starts the next pass.
- Arrays have a fixed length; `Vec` and `Map` grow from an allocator you choose,
  and `defer` releases them.
- `Str` and `Slice` are views into something else's storage.
- Structs hold fields, enums hold one of several variants, and `match` must
  cover every variant. `@derive(Default)` and `..base` build a struct from
  another.
- A tuple `(a, b)` groups two to eight values by position, and
  `let (a, b) = pair` takes it apart; use a struct when the parts deserve
  names.
- A module is a directory; `pub` makes a declaration visible outside it.
- `test fn` sits beside the code, and `linea test` runs it.

You can safely ignore for now: allocators other than `mem.system()`, the
`borrows`, `carries` and `retains` clauses that some signatures carry, and the
`Release` and `Settle` traits behind `release()`. Each has its chapter, and
nothing before it needs them.

Next: [Calling things](02-calling-things.md) — methods, traits, `@derive`,
functions as values and closures.
