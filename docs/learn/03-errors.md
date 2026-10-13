# Errors

Linea has no exceptions. A function that can fail says so in its result type,
and the caller decides what to do about it. This chapter works mostly around
one small program — reading alarm times such as `07:30` — and uses it to show
the tools:
`Option` and `Result`, `match`, `?`, converting one error into another with
`From` and `map_err`, `let … else`, conversions that can fail, newtypes that
carry a range check, and failures that hand a value back.

## `Option`: a value that may be missing

`Option[T]` is either `.Some(value)` or `.None`. Searching text is a typical
source of one: `find` answers the position of what it found, or `.None`.

```linea
import std.io

// `find` answers `.Some(position)` of the first colon, or `.None` when there is none.
fn hours_of(time: Str) -> Option[Str] {
    match time.find(":") {
        Some(colon) => time.slice(0, colon),
        None => .None,
    }
}

fn main() -> Result[UInt8, io.IoError] {
    let times = ["07:30", "noon"]
    for time in times {
        match hours_of(time) {
            Some(hours) => io.println("{time}: hour {hours}")?,
            None => io.println("{time}: no colon")?,
        }
    }
    .Ok(0)
}
```

```
07:30: hour 07
noon: no colon
```

`time.slice(0, colon)` returns an `Option[Str]` too, because the positions
might not fall on character boundaries. Here the `Some` arm hands that option
straight back.

You cannot use an `Option[Str]` as a `Str`. The type makes you say what
happens when the value is missing, and `match` makes you cover both cases.
There is no null in Linea.

If you know Rust, you already know most of this chapter: `Option`, `Result`,
`?` and `From` work the way they do there, and `let … else` is Rust's
`let … else` with a binder for the error.

## `?`: pass the failure up

Most of the time, when a step fails, the function should fail too. `?` says
exactly that. After an `Option`, it returns `.None` from the function if the
value is missing, and otherwise hands you what was inside:

```linea
import std.io

fn hours_of(time: Str) -> Option[Str] {
    // `?` returns `.None` from `hours_of` when `find` finds no colon.
    let colon = time.find(":")?
    time.slice(0, colon)
}

fn main() -> Result[UInt8, io.IoError] {
    let times = ["07:30", "noon"]
    for time in times {
        match hours_of(time) {
            Some(hours) => io.println("{time}: hour {hours}")?,
            None => io.println("{time}: no colon")?,
        }
    }
    .Ok(0)
}
```

```
07:30: hour 07
noon: no colon
```

The output is the same. You have been using `?` since the first chapter:
`io.println(…)?` passes a failed write up out of `main`.

## `Result`: a failure that says why

`Option` can only say *missing*. When the caller needs to know what went
wrong, return `Result[T, E]`: `.Ok(value)` on success, `.Err(error)` on
failure. The error is usually an enum of your own:

```linea
import std.io
import std.text

@(copyable, derive(Debug))
enum TimeError {
    NoColon,
    Number(text.ParseError),
    OutOfRange,
}

fn minutes(time: Str) -> Result[UInt64, TimeError] {
    let colon = match time.find(":") {
        Some(colon) => colon,
        None => return .Err(.NoColon),
    }
    // `parse[UInt64]()` reads the text as a `UInt64`, or fails with a `text.ParseError`.
    let hours = match time.slice(0, colon).unwrap().parse[UInt64]() {
        Ok(hours) => hours,
        Err(error) => return .Err(.Number(error)),
    }
    let rest = time.slice(colon + 1, time.length()).unwrap()
    let mins = match rest.parse[UInt64]() {
        Ok(mins) => mins,
        Err(error) => return .Err(.Number(error)),
    }
    if hours > 23 || mins > 59 {
        return .Err(.OutOfRange)
    }
    .Ok(hours * 60 + mins)
}

fn main() -> Result[UInt8, io.IoError] {
    let times = ["07:30", "noon", "25:00", "07:3x"]
    for time in times {
        match minutes(time) {
            Ok(count) => io.println("{time} is {count} minutes after midnight")?,
            Err(error) => io.println("{time}: {error:?}")?,
        }
    }
    .Ok(0)
}
```

```
07:30 is 450 minutes after midnight
noon: NoColon
25:00: OutOfRange
07:3x: Number(Syntax(1))
```

`parse[UInt64]()` reads text as a number. The `[UInt64]` names the type
to read ([Calling things](02-calling-things.md#naming-a-type-argument)); every
number type can be read this way. It fails with a `text.ParseError`, which
says where the digits went wrong: `Syntax(1)` means the byte at offset 1 of
`"3x"`. `@(copyable, derive(Debug))` writes two attributes in one group, and
means the same as `@copyable` on one line and `@derive(Debug)` on the next.
`derive(Debug)` lets `{error:?}` print the error with its payload, and
[Copying, settling and sealing](04-copying-settling-and-sealing.md) explains
the `copyable`.

`unwrap()` takes the value out of an `Option` or `Result` and stops the
program if there is none. It is right only where failure is impossible, as
here: a colon that `find` located is always a character boundary, so these
slices always succeed. Anywhere else, use `?`, a `match`, or `unwrap_or`,
which supplies a fallback:

```linea
import std.io

fn main() -> Result[UInt8, io.IoError] {
    let port = "8080".parse[UInt16]().unwrap()
    let fallback = "eighty".parse[UInt16]().unwrap_or(80)
    io.println("port {port}, fallback {fallback}")?
    let broken = "eighty".parse[UInt16]().unwrap()
    io.println("never printed: {broken}")?
    .Ok(0)
}
```

```
port 8080, fallback 80
linea: panic: called Result.unwrap on Err at std/result/result.lin:394:23
```

The location in the message is the line inside the standard library's
`unwrap` that stopped the program, not your call, so look for the `unwrap` in
your own code that was handed an `Err`.

Those three `match`es in `minutes` each do the same thing — return early on
failure — and they bury the three lines that matter. The next sections remove
them.

## `?` converts errors with `From`

`?` after a `Result` returns the error if there is one. When the error's type
is not the function's own error type, `?` converts it, through an
implementation of the `From` trait:

```linea
import std.io
import std.text

@(copyable, derive(Debug))
enum TimeError {
    NoColon,
    Number(text.ParseError),
    OutOfRange,
}

// With this, `?` turns a `text.ParseError` into a `TimeError` on its way out.
impl From[text.ParseError] for TimeError {
    fn from(sink source: text.ParseError) -> TimeError {
        .Number(source)
    }
}

fn minutes(time: Str) -> Result[UInt64, TimeError] {
    let colon = match time.find(":") {
        Some(colon) => colon,
        None => return .Err(.NoColon),
    }
    let hours = time.slice(0, colon).unwrap().parse[UInt64]()?
    let mins = time.slice(colon + 1, time.length()).unwrap().parse[UInt64]()?
    if hours > 23 || mins > 59 {
        return .Err(.OutOfRange)
    }
    .Ok(hours * 60 + mins)
}

fn main() -> Result[UInt8, io.IoError] {
    let times = ["07:30", "noon", "25:00", "07:3x"]
    for time in times {
        match minutes(time) {
            Ok(count) => io.println("{time} is {count} minutes after midnight")?,
            Err(error) => io.println("{time}: {error:?}")?,
        }
    }
    .Ok(0)
}
```

```
07:30 is 450 minutes after midnight
noon: NoColon
25:00: OutOfRange
07:3x: Number(Syntax(1))
```

The output is unchanged. Each `?` on a `parse` now returns
`.Err(.Number(error))` by calling `From.from`. `From` is in the prelude, so it
needs no import. Remove the `impl` and the compiler tells you which conversion
is missing:

<!-- guide: unchecked the error an edit of the program above produces -->
```
error[T-TryAnswer]: this `?` may fail with `text.ParseError`, and no `From[text.ParseError] for TimeError` implementation converts it to the function's error type
  --> from_missing.lin:16:17
   |
16 |     let hours = time.slice(0, colon).unwrap().parse[UInt64]()?
   |                 ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ `?` converts a different error through `From`: implement it, or convert the error before `?`
error[T-TryAnswer]: this `?` may fail with `text.ParseError`, and no `From[text.ParseError] for TimeError` implementation converts it to the function's error type
  --> from_missing.lin:17:16
   |
17 |     let mins = time.slice(colon + 1, time.length()).unwrap().parse[UInt64]()?
   |                ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ `?` converts a different error through `From`: implement it, or convert the error before `?`
```

This is Rust's `?` and `From` exactly. The conversion is written once, beside
the error type, and every `?` in the program uses it. The
[electricity bill example](../../examples/electricity_bill.lin) wraps the
errors of `std.json` and `std.text` into its own `BillError` this way. The
implementation's parameter has to be called `source`, as it is in the `From`
trait; a different name is refused with `[T-Impl]` and a note to use the
trait's.

Implementing `From` also gives you `Into` for free, in the other direction:
with the implementation above, `let wrapped: TimeError = error.into()` turns a
`text.ParseError` into a `TimeError`, and the annotation says which type to
convert into. `TimeError.from(error)` does the same with the destination
named. As in Rust, you implement `From` and never `Into`.

### A conversion that only wraps: `@derive(From[...])`

The `impl` above does nothing but put the source in the variant that holds
it. Ask for exactly that with a derive entry that names the source:

```linea
import std.io
import std.text

// `From[text.ParseError]` writes `impl From[text.ParseError] for TimeError`,
// wrapping the source in `Number`: the one variant whose only field is a
// `text.ParseError`.
@(copyable, derive(Debug, From[text.ParseError]))
enum TimeError {
    NoColon,
    Number(text.ParseError),
    OutOfRange,
}

fn minutes(time: Str) -> Result[UInt64, TimeError] {
    let colon = match time.find(":") {
        Some(colon) => colon,
        None => return .Err(.NoColon),
    }
    let hours = time.slice(0, colon).unwrap().parse[UInt64]()?
    let mins = time.slice(colon + 1, time.length()).unwrap().parse[UInt64]()?
    if hours > 23 || mins > 59 {
        return .Err(.OutOfRange)
    }
    .Ok(hours * 60 + mins)
}

fn main() -> Result[UInt8, io.IoError] {
    let times = ["07:30", "noon", "25:00", "07:3x"]
    for time in times {
        match minutes(time) {
            Ok(count) => io.println("{time} is {count} minutes after midnight")?,
            Err(error) => io.println("{time}: {error:?}")?,
        }
    }
    .Ok(0)
}
```

```
07:30 is 450 minutes after midnight
noon: NoColon
25:00: OutOfRange
07:3x: Number(Syntax(1))
```

The output is the same as with the written `impl`, because the derive writes
that `impl` for you. This is what `derive_more`'s `#[derive(From)]` and
`thiserror`'s `#[from]` do in Rust, except that Linea asks for the conversion by
the source's type on the enum, not by marking the variant. Write one entry per
source: `@derive(From[text.ParseError], From[io.IoError])` converts both. Each
entry is a request. Converting every variant that holds one field would give
`TimeError` a `From[Str]` the moment it gained a `Key(Str)` variant, and then a
`?` on any `Str` error anywhere would convert into it without a word.

The derive refuses a source it cannot place. A source that two variants hold
has no single variant to wrap it in. Reading the hours and the minutes both
fail with a `text.ParseError`, so `From[text.ParseError]` cannot tell `Hours`
from `Minutes`:

```linea
import std.text

@(copyable, derive(Debug, From[text.ParseError]))
enum TimeError {
    NoColon,
    Hours(text.ParseError),
    Minutes(text.ParseError),
}

fn main() -> UInt8 {
    0
}
```

```
error[T-Derive]: `TimeError` has two variants wrapping `text.ParseError`
 --> two_parts.lin:3:27
  |
3 | @(copyable, derive(Debug, From[text.ParseError]))
  |                           ^^^^^^^^^^^^^^^^^^^^^ the conversion would wrap the source in either variant
6 |     Hours(text.ParseError),
  |     ----- this variant holds the source's type
7 |     Minutes(text.ParseError),
  |     ------- this variant holds the source's type
  |
  = help: write the conversion by hand, or give each variant its own type
```

[Converting at one call with `map_err`](#converting-at-one-call-with-map_err-and-reporting-from-main)
is the way to wrap those two. A source no variant holds is refused too, and
the error lists the variants and their fields. Replace `text.ParseError` in
the derive entry above with `io.IoError` and the enum `TimeError` above:

<!-- guide: unchecked the error an edit of the first program above produces -->
```
error[T-Derive]: no variant of `TimeError` wraps exactly `io.IoError`
 --> no_variant.lin:4:27
  |
4 | @(copyable, derive(Debug, From[io.IoError]))
  |                           ^^^^^^^^^^^^^^^^ no variant wraps this source
  |
  = help: a variant wraps a source when its only field has the source's type; `TimeError` has `NoColon`, `Number(text.ParseError)`
```

A derive only wraps. A conversion that does more stays an `impl`: choosing what
to keep of the source (the [electricity bill
example](../../examples/electricity_bill.lin) releases a decode error's path
and keeps its reason) or answering with a variant that carries nothing.

`?` does not turn an `Option` into a `Result`. A missing value carries no
error to convert, so the compiler refuses it and you say what the error is:

```linea
enum TimeError {
    NoColon,
}

fn colon_of(time: Str) -> Result[UInt64, TimeError] {
    let colon = time.find(":")?
    .Ok(colon)
}

fn main() -> UInt8 {
    match colon_of("07:30") {
        Ok(colon) => UInt8(colon),
        Err(_) => 1,
    }
}
```

```
error[T-TryAnswer]: this `?` may return `Option[UInt64]`, and the function answers with `Result[UInt64, TimeError]`
 --> option_in_result.lin:6:17
  |
6 |     let colon = time.find(":")?
  |                 ^^^^^^^^^^^^^^^ `?` returns from the function it is written in
```

That is what the remaining `match` in `minutes` does, and `let … else` says it
in fewer words.

## `let … else`: bind the value, or handle the failure right there

`let pattern = value else { … }` binds what an `Option` or `Result` holds on
success. On failure it runs the block:

```linea
import std.io
import std.text

@(copyable, derive(Debug, From[text.ParseError]))
enum TimeError {
    NoColon,
    Number(text.ParseError),
    OutOfRange,
}

fn minutes(time: Str) -> Result[UInt64, TimeError] {
    // `else` runs when `find` answers `.None`, and must leave the function.
    let colon = time.find(":") else {
        return .Err(.NoColon)
    }
    let hours = time.slice(0, colon).unwrap().parse[UInt64]()?
    let mins = time.slice(colon + 1, time.length()).unwrap().parse[UInt64]()?
    if hours > 23 || mins > 59 {
        return .Err(.OutOfRange)
    }
    .Ok(hours * 60 + mins)
}

// A time that does not parse counts as midnight: the block's value is bound instead.
fn minutes_or_midnight(time: Str) -> UInt64 {
    let count = minutes(time) else |_| {
        0
    }
    count
}

fn main() -> Result[UInt8, io.IoError] {
    let times = ["07:30", "noon", "25:00", "07:3x"]
    for time in times {
        let count = minutes(time) else |error| {
            io.println("{time}: {error:?}")?
            continue
        }
        io.println("{time} is {count} minutes after midnight")?
    }
    io.println("An alarm set for noon rings {minutes_or_midnight("noon")} minutes after midnight.")?
    .Ok(0)
}
```

```
07:30 is 450 minutes after midnight
noon: NoColon
25:00: OutOfRange
07:3x: Number(Syntax(1))
An alarm set for noon rings 0 minutes after midnight.
```

`minutes` now reads top to bottom: each line either produces the next value or
leaves. The `else` block has two choices:

- **Leave**: `return`, `break` or `continue`, as `minutes` and the loop in
  `main` do. The binding is never made.
- **Supply the value** instead, as `minutes_or_midnight` does with `0`. The
  block's value is bound in place of the missing one.

A failed `Result` carries its error into the block: `else |error|` names it,
and `else |_|` says you do not need it. A failed `Option` carries nothing, so
its `else` takes no binder. The compiler holds you to both:

```linea
fn hours(time: Str) -> UInt64 {
    let count = time.parse[UInt64]() else {
        return 0
    }
    count
}

fn main() -> UInt8 {
    UInt8(hours("7"))
}
```

```
error[T-LetElse]: a failed `Result[UInt64, text.ParseError]` carries an error, and this `else` binds none
 --> letelse_bad2.lin:2:38
  |
2 |     let count = time.parse[UInt64]() else {
  |                                      ^^^^ name it with `else |error|`, or discard it with `else |_|`
```

And a block that neither leaves nor yields the right type is refused:

```linea
fn first_colon(time: Str) -> UInt64 {
    let colon = time.find(":") else {
        "none"
    }
    colon
}

fn main() -> UInt8 {
    UInt8(first_colon("07:30"))
}
```

```
error[T-Mismatch]: expected a block that leaves or yields `UInt64`, found `Str`
 --> letelse_bad3.lin:3:9
  |
2 |     let colon = time.find(":") else {
  |                                ---- an `else` block leaves, or yields what a success carries
3 |         "none"
  |         ^^^^^^ expected a block that leaves or yields `UInt64`, found `Str`
```

Rust's `let … else` must always leave; Linea's may also supply a value, as
Zig's `catch |e| value` does. And where Rust would need
`let Ok(x) = f() else { … }` plus a separate `match` to see the error, the
binder hands it to you directly.

### Handling a failure and keeping nothing

Some steps only check something: on success they answer `()`, which has
nothing to carry. Write `let _` to keep nothing, and `else |error|` to handle
the failure, so the result is never silently dropped:

```linea
import std.io

// A check that answers `()` on success, so there is nothing to bind.
fn check_alarm(time: Str) -> Result[(), Str] {
    let colon = time.find(":") else {
        return .Err("write the time as HH:MM")
    }
    let hours = time.slice(0, colon).unwrap().parse[UInt64]() else |_| {
        return .Err("the hours are not a number")
    }
    if hours > 23 {
        return .Err("the hours run from 0 to 23")
    }
    .Ok(())
}

fn main() -> Result[UInt8, io.IoError] {
    let alarms = ["07:30", "noon", "25:00"]
    for alarm in alarms {
        // `let _` keeps nothing from a success that carries no value, and
        // `else |error|` handles the failure.
        let _ = check_alarm(alarm) else |error| {
            io.println("{alarm}: {error}")?
            continue
        }
        io.println("{alarm} is a valid alarm")?
    }
    .Ok(0)
}
```

```
07:30 is a valid alarm
noon: write the time as HH:MM
25:00: the hours run from 0 to 23
```

`continue` leaves the `else` block, so the loop moves on to the next alarm.
Call `check_alarm(alarm)` on a line of its own instead, and the compiler
refuses to let the result vanish:

<!-- guide: unchecked the error an edit of the program above produces -->
```
error[T-Discard]: this expression produces a `Result[(), Str]` that is discarded
  --> check_discarded.lin:22:9
   |
22 |         check_alarm(alarm)
   |         ^^^^^^^^^^^^^^^^^^ match it, hand it on with `?`, or return it
```

## Converting at one call with `map_err`, and reporting from `main`

`From` converts every error of one type the same way. Sometimes two calls fail
with the same type and need different wrapping. Reading the hours and reading
the minutes both fail with a `text.ParseError`, but the user deserves to know
which part was wrong. `map_err` converts the error of one call, before its
`?`.

This version is also a real command: it reads the time from its arguments, and
its `main` reports a failure the way command-line programs usually do, with a
message on standard error, written with `io.eprintln`, and a nonzero exit
status:

<!-- guide: unchecked the program needs command-line arguments and the output is three runs -->
```linea
import std.env
import std.io
import std.text

@(copyable, derive(Debug))
enum TimeError {
    NoColon,
    Hours(text.ParseError),
    Minutes(text.ParseError),
    OutOfRange,
}

// `Display` is what `{error}` writes. Each arm writes one message into `w`.
impl Display for TimeError {
    fn fmt[W: Writer](self: Self, inout w: W) -> Result[(), W.Error] {
        match read self {
            NoColon => &w.write_str("write the time as HH:MM"),
            Hours(_) => &w.write_str("the hours are not a number"),
            Minutes(_) => &w.write_str("the minutes are not a number"),
            OutOfRange => &w.write_str("there is no such time of day"),
        }
    }
}

fn minutes(time: Str) -> Result[UInt64, TimeError] {
    let colon = time.find(":") else {
        return .Err(.NoColon)
    }
    // Both parts fail with a `text.ParseError`, so one `From` could not tell
    // them apart. `map_err` wraps each error in the variant for its own part.
    let hours = time.slice(0, colon).unwrap().parse[UInt64]().map_err(.Hours)?
    let mins = time.slice(colon + 1, time.length()).unwrap().parse[UInt64]().map_err(.Minutes)?
    if hours > 23 || mins > 59 {
        return .Err(.OutOfRange)
    }
    .Ok(hours * 60 + mins)
}

fn main() -> UInt8 {
    let time = env.args().at(1) else {
        io.eprintln("usage: alarm HH:MM")
        return 64
    }
    let count = minutes(time) else |error| {
        io.eprintln("alarm: {time}: {error}")
        return 1
    }
    if io.println("The alarm rings {count} minutes after midnight.").is_err() {
        return 1
    }
    0
}
```

```
$ linea run alarm.lin -- 07:30
The alarm rings 450 minutes after midnight.
$ linea run alarm.lin -- 07:3x
alarm: 07:3x: the minutes are not a number
$ linea run alarm.lin -- noon
alarm: noon: write the time as HH:MM
```

A few things to notice:

- `.map_err(.Hours)` passes the error to the variant `.Hours`, which carries
  exactly a `text.ParseError`. The enum comes from the function's error type,
  so `.Hours` needs no `TimeError` in front. A variant is a function, which is
  why `map_err` takes it: `map_err` is one of the operations that hand a value
  to a function, like the `map`, `and_then` and `unwrap_or_else` of [Calling
  things](02-calling-things.md#handing-a-function-to-option-and-result).
- `impl Display for TimeError` is what `{error}` in the message writes. A
  `Display` implementation writes into any writer `w`; `&w.write_str(…)` writes
  text and returns whether the writer accepted it. `W.Error` is the error type
  of whichever writer is passed: a writer to a socket fails differently from
  one into a `String`. [Text](08-text.md) says more about writers.
- `main` returns a plain `UInt8`. Each failure is handled where it happens:
  `let … else |error|` prints what went wrong and returns an exit status —
  here 64, the conventional status for a usage mistake, and 1 for a time that
  does not read.
- `env.args().at(1)` is the first argument after the program's name, or
  `.None` when there is none.

### Which `main` to write

Choose between the two shapes of `main` by who decides the exit status, and
handle each failure in the style that shape suits:

- A `main` that answers `Result[UInt8, io.IoError]` suits a short program
  whose only failures are printing ones. Write `?` there, as in any helper
  function: it passes the failure up, and the program prints the error and
  exits with a failure status.
- A `main` that answers `UInt8` suits a command that chooses its exit
  statuses, as `alarm` does. Handle each setup failure — a missing argument, a
  file that will not open, a port already taken — with `let … else |error|`,
  printing the error and returning a status:

  ```linea
  let port = written.parse[UInt16]() else |error| {
      io.eprintln("cannot read the port {written}: {error}")
      return 64
  }
  ```

  The message and the status sit beside the step that failed, and the rest of
  `main` reads straight down.
- Write `match` only where both outcomes carry on, as the next section shows.

## When to keep `match`

`?` and `let … else` are for the common shape: success carries on, failure
leaves or falls back. Keep `match` when both outcomes carry on and do
different work, or when different errors need different handling:

```linea
import std.io
import std.text

@(copyable, derive(Debug, From[text.ParseError]))
enum TimeError {
    NoColon,
    Number(text.ParseError),
    OutOfRange,
}

fn minutes(time: Str) -> Result[UInt64, TimeError] {
    let colon = time.find(":") else {
        return .Err(.NoColon)
    }
    let hours = time.slice(0, colon).unwrap().parse[UInt64]()?
    let mins = time.slice(colon + 1, time.length()).unwrap().parse[UInt64]()?
    if hours > 23 || mins > 59 {
        return .Err(.OutOfRange)
    }
    .Ok(hours * 60 + mins)
}

fn main() -> Result[UInt8, io.IoError] {
    let times = ["07:30", "noon", "25:00", "07:3x"]
    var alarms: UInt64 = 0
    for time in times {
        match minutes(time) {
            Ok(count) => {
                alarms += 1
                io.println("Alarm {alarms} rings at minute {count}.")?
            },
            Err(error) => match error {
                NoColon => io.println("{time}: write the time as HH:MM.")?,
                Number(_) => io.println("{time}: the hours and minutes must be numbers.")?,
                OutOfRange => io.println("{time}: there is no such time of day.")?,
            },
        }
    }
    io.println("Alarms set: {alarms}.")?
    .Ok(0)
}
```

```
Alarm 1 rings at minute 450.
noon: write the time as HH:MM.
25:00: there is no such time of day.
07:3x: the hours and minutes must be numbers.
Alarms set: 1.
```

A pattern in a `match` arm names one level: `Err(error)` binds the error, and
a second `match` looks inside it. Because the inner `match` must cover every
`TimeError` variant, adding a variant later makes this program stop compiling
until the new case has a message.

## Conversions that can fail

`From` is for conversions that always work. When a value may not fit, implement
`TryFrom` instead. It answers an `Option`: the converted value, or `.None`,
where Rust's `TryFrom` answers a `Result` with an error type of its own. As
`From` gives you `Into`, `TryFrom` gives you `TryInto`:

```linea
import std.io

// An `Hour` is a number from 0 to 23.
@(copyable, derive(Debug))
struct Hour {
    value: UInt8,
}

// `TryFrom` converts when the value fits, and answers `.None` when it does not.
impl TryFrom[UInt64] for Hour {
    fn try_from(x: UInt64) -> Option[Hour] {
        if x > 23 { .None } else { .Some(.{ value = UInt8(x) }) }
    }
}

fn main() -> Result[UInt8, io.IoError] {
    let readings: [UInt64; _] = [7, 42]
    for reading in readings {
        // `try_into` comes free with `TryFrom`; the annotation picks `Hour`.
        let hour: Option[Hour] = reading.try_into()
        io.println("{reading}: {hour:?}")?
    }
    // Numbers convert the same way: 300 does not fit in a `UInt8`.
    let small: Option[UInt8] = UInt64(300).try_into()
    io.println("300 as a UInt8: {small:?}")?
    .Ok(0)
}
```

```
7: Some(Hour { value: 7 })
42: None
300 as a UInt8: None
```

Compare the conversion written as a function call, `UInt8(300)`: it stops the
program, because it promises the value fits. `try_into` is the one that asks.
When the caller needs to know *why* a value was refused, return a `Result`
with an error of your own instead, as `minutes` does.

## Newtypes: a check the type carries

`TryFrom` checks a value each time it converts one. A newtype can carry the
check in its type instead, so a value that exists has already passed it.

### A new type, not a nickname

A distance and a duration are both numbers. Mixing them up is still a bug.
`type Meters = UInt64` creates a **new type** with a `UInt64` inside — not
another name for `UInt64`:

```linea
import std.io

@copyable
type Meters = UInt64

@copyable
type Seconds = UInt64

fn pace(distance: Meters, time: Seconds) -> UInt64 {
    let read Meters(m) = distance
    let read Seconds(s) = time
    s * 1000 / m
}

fn main() -> Result[UInt8, io.IoError] {
    let run = Meters(5000)
    let took = Seconds(1500)
    io.println("{pace(run, took)} seconds per kilometre")?
    .Ok(0)
}
```

```
300 seconds per kilometre
```

You build one explicitly, `Meters(5000)`, and take the number back out with a
pattern. `pace` only looks at `distance` — it has no `sink` — so the pattern
is written `let read Meters(m) = distance`. `read` looks inside without taking
the value apart. Leave `read` out and the pattern tries to take a value the
function was only lent:

```linea
let Meters(m) = distance
```

<!-- guide: unchecked the error an edit of the program above produces -->
```
error[O-Move]: `distance` is lent, and this takes it
  --> pace_lent.lin:10:21
   |
10 |     let Meters(m) = distance
   |                     ^^^^^^^^ `copy` it, or declare the parameter `sink` to take it
```

`read` is the fix here: the function wants the number, not the `Meters`.

Pass the arguments the wrong way round and the compiler catches that too:

```linea
io.println("{pace(took, run)} seconds per kilometre")?
```

<!-- guide: unchecked the error an edit of the program above produces -->
```
error[T-Mismatch]: expected `Meters`, found `Seconds`
  --> pace_mixed.lin:18:23
   |
9  | fn pace(distance: Meters, time: Seconds) -> UInt64 {
   |         -------- expected because of this parameter
18 |     io.println("{pace(took, run)} seconds per kilometre")?
   |                       ^^^^ expected `Meters`, found `Seconds`
```

A second, matching error follows for `run`.

`[T-Mismatch]` is the general "wrong type here" error. A plain `UInt64` is
refused the same way. Go's `type Meters uint64` and Rust's
`struct Meters(u64)` work like this too.

A nickname is what `alias` makes ([Calling
things](02-calling-things.md#a-name-for-a-long-type-alias)): another name for
the same type. It documents what a number means and nothing more, so the same
mix-up compiles and prints a wrong answer:

```linea
import std.io

// An alias is only a second name: `Meters` and `Seconds` are both `UInt64`.
alias Meters = UInt64
alias Seconds = UInt64

fn pace(distance: Meters, time: Seconds) -> UInt64 {
    time * 1000 / distance
}

fn main() -> Result[UInt8, io.IoError] {
    let run: Meters = 5000
    let took: Seconds = 1500
    // The arguments are the wrong way round, and nothing stops them.
    io.println("{pace(took, run)} seconds per kilometre")?
    .Ok(0)
}
```

```
3333 seconds per kilometre
```

Use `alias` to shorten a long type, and `type` when two values must not mix.

`@copyable` lets a newtype be copied like the plain data it is; [Copying,
settling and sealing](04-copying-settling-and-sealing.md) explains when a type
should say so.

### Limiting the values

A percentage is a number from 0 to 100. Say so, and the type rejects anything
else:

```linea
import std.io

@copyable
type Percent = UInt8 where it in 0..=100

fn discounted(price_cents: UInt64, discount: Percent) -> UInt64 {
    let read Percent(rate) = discount
    price_cents - price_cents * UInt64(rate) / 100
}

fn main() -> Result[UInt8, io.IoError] {
    let price = 5000
    io.println("Members pay {discounted(price, Percent(15))} cents.")?

    // Offers typed in by a user arrive at run time, so they are checked then.
    let offers: [UInt8; _] = [30, 130]
    for offered in offers {
        match Percent?(offered) {
            Some(discount) => io.println("{offered}% off: {discounted(price, discount)} cents.")?,
            None => io.println("{offered}% is not a percentage.")?,
        }
    }
    .Ok(0)
}
```

```
Members pay 4250 cents.
30% off: 3500 cents.
130% is not a percentage.
```

`it` stands for the value being checked. When you write a number directly,
the check happens before the program ever runs:

```linea
io.println("Members pay {discounted(price, Percent(150))} cents.")?
```

<!-- guide: unchecked the error an edit of the program above produces -->
```
error[T-Refine]: 150 is not in 0..=100 for Percent
  --> percent_150.lin:13:48
   |
13 |     io.println("Members pay {discounted(price, Percent(150))} cents.")?
   |                                                ^^^^^^^^^^^^ this value is outside the type's range
```

When the number arrives while the program runs — from a user, a file, a
request — the compiler cannot know it is in range. Write `Percent(offered)`
inside the loop instead of `Percent?(offered)`, and it says so:

<!-- guide: unchecked the error an edit of the program above produces -->
```
error[T-Refine]: `offered` is not known to be in 0..=100
  --> discounts_unchecked.lin:18:15
   |
18 |         match Percent(offered) {
   |               ^^^^^^^^^^^^^^^^ make it fallible: `Percent?(offered)`
```

`Percent?(offered)` is the answer: it returns `Some(percent)` when the number
fits and `None` when it does not, and `match` makes you handle both.
`[T-Refine]` is the error for a value that may not fit its type's range.

Once you hold a `Percent`, every function that takes one knows it is between 0
and 100. You checked once, at the edge of your program, and the type carries
the proof everywhere else. Rust would need a constructor function to enforce
the same range.

### A checked value as a default argument

Because `Percent(10)` is checked before the program runs, a copyable ranged
type can be a parameter default:

```linea
import std.io

@copyable
type Percent = UInt8 where it in 0..=100

fn price_after(price_cents: UInt64, discount: Percent = Percent(10)) -> UInt64 {
    let read Percent(rate) = discount
    price_cents - price_cents * UInt64(rate) / 100
}

fn main() -> Result[UInt8, io.IoError] {
    io.println("Usual price: {price_after(5000)} cents.")?
    io.println("Sale price: {price_after(5000, discount: Percent(25))} cents.")?
    .Ok(0)
}
```

```
Usual price: 4500 cents.
Sale price: 3750 cents.
```

A default built from a type's parts — `Percent(10)`, or a struct literal such
as `.{ grams = 3 }` — needs that type to be copyable. The default is written
once, but every call that leaves the argument out gets its own value built
from those parts, so the parts have to be something that can be handed out
again and again. Drop `@copyable` from `Percent` and the default is refused,
with the fix in the help line:

<!-- guide: unchecked the error an edit of the program above produces -->
```
error[T-Default]: a default is built again at every call that omits it, so `Percent` must be copyable
 --> sale_price_affine.lin:5:57
  |
5 | fn price_after(price_cents: UInt64, discount: Percent = Percent(10)) -> UInt64 {
  |                                                         ^^^^^^^^^^^ built from the parts of `Percent`, which is not copyable
  |
  = help: mark `Percent` `@copyable`
```

An enum variant that carries nothing is different: it has no parts to build,
so it can be a default even when the enum is not copyable:

```linea
import std.io

enum Size {
    Small,
    Large,
}

fn postage_cents(size: Size = .Small) -> UInt64 {
    match read size {
        Small => 85,
        Large => 190,
    }
}

fn main() -> Result[UInt8, io.IoError] {
    io.println("A letter costs {postage_cents()} cents; a parcel costs {postage_cents(.Large)}.")?
    .Ok(0)
}
```

```
A letter costs 85 cents; a parcel costs 190.
```

## Failures that hand a value back

Some operations take a value and can still fail. Inserting into a map takes
the key and the value; pushing onto a `Vec` takes the item. When memory runs
out, what they took is not lost: the failure hands it back, beside the reason.
Here a small hotel keeps its bookings in a map from a room number to the
nights booked:

```linea
import std.collections
import std.io
import std.mem

// Book a room for some nights. A refused `insert` hands the room and the
// nights back inside a `collections.InsertFailure`; `settled()` drops them and
// keeps the reason, a `mem.Oom`, which `?` returns.
fn book(
    inout bookings: collections.Map[UInt64, UInt64],
    room: UInt64,
    nights: UInt64,
) -> Result[(), mem.Oom] {
    // Booking a room again replaces its entry and hands back the earlier one,
    // which `book` drops.
    let _earlier = &bookings.insert(room, nights).settled()?
    .Ok(())
}

fn main() -> Result[UInt8, io.IoError] {
    var bookings: collections.Map[UInt64, UInt64] = collections.Map.new()
    defer bookings.release()
    if book(&bookings, 101, 2).is_err() || book(&bookings, 102, 5).is_err() || book(&bookings, 101, 3).is_err() {
        return .Ok(1)
    }
    io.println("{bookings.length()} rooms booked; room 101 for {*bookings.get(101).unwrap()} nights.")?
    .Ok(0)
}
```

```
2 rooms booked; room 101 for 3 nights.
```

`insert` answers `.Ok` with the entry the key held before, if it held one:
booking room 101 a second time hands back its first booking, which `book`
drops. When memory runs out, `insert` answers a `collections.InsertFailure`
holding the room and the nights it could not keep, and the reason, a
`mem.Oom`. `book` promises only a `mem.Oom`, so it cannot return the failure
whole. `settled()` drops the room and the nights and keeps the reason.
`Vec.push` and `collect` work the same way.

`?` never gives up a value for you. Without `settled()`, the failure holds an
owned value and `mem.Oom` has no conversion from it, so the program is refused:

<!-- guide: unchecked the error an edit of the program above produces -->
```
error[T-TryAnswer]: this `?` may fail with `collections.InsertFailure[UInt64, UInt64]`, and no `From[collections.InsertFailure[UInt64, UInt64]] for mem.Oom` implementation converts it to the function's error type
  --> bookings_unsettled.lin:15:20
   |
15 |     let _earlier = &bookings.insert(room, nights)?
   |                    ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ `?` converts a different error through `From`: implement it, or convert the error before `?`
   |
   = help: call `.settled()` before `?`: it releases what `collections.InsertFailure[UInt64, UInt64]` hands back and keeps its reason, `mem.Oom`
```

`?` converts what an error says, its reason. What a failure holds is not for
`?` to throw away: a value can own memory, or a file, and its `release` may
write to disk or close a connection. Writing `settled()` is how the source says
that this value is being dropped here, and the line shows it. When the caller
might want the value back, for example to retry an insertion after freeing some
room, `match` the failure and take it apart instead.

### Settling by hand

`settled()` also works when the function answers an error of its own. The hotel
now also refuses rooms below 100, so it answers its own error, which wraps a
`mem.Oom` for the memory case:

```linea
import std.collections
import std.io
import std.mem

// A booking fails when memory runs out or when the room does not exist.
@derive(Debug, From[mem.Oom])
enum BookingError {
    Memory(mem.Oom),
    NoSuchRoom,
}

// Rooms are numbered from 100. `settled()` drops the room and the nights of a
// refused `insert` and keeps the `mem.Oom`, which the derived `From` wraps in
// `BookingError.Memory`.
fn book(
    inout bookings: collections.Map[UInt64, UInt64],
    room: UInt64,
    nights: UInt64,
) -> Result[(), BookingError] {
    if room < 100 {
        return .Err(.NoSuchRoom)
    }
    let _earlier = &bookings.insert(room, nights).settled()?
    .Ok(())
}

fn main() -> Result[UInt8, io.IoError] {
    var bookings: collections.Map[UInt64, UInt64] = collections.Map.new()
    defer bookings.release()
    match book(&bookings, 7, 2) {
        Ok(_) => io.println("room 7 booked")?,
        Err(error) => io.println("could not book room 7: {error:?}")?,
    }
    match book(&bookings, 101, 2) {
        Ok(_) => io.println("room 101 booked for 2 nights")?,
        Err(error) => io.println("could not book room 101: {error:?}")?,
    }
    .Ok(0)
}
```

```
could not book room 7: NoSuchRoom
room 101 booked for 2 nights
```

Without `settled()`, `?` has no conversion from the whole failure to
`BookingError`:

<!-- guide: unchecked the error an edit of the program above produces -->
```
error[T-TryAnswer]: this `?` may fail with `collections.InsertFailure[UInt64, UInt64]`, and no `From[collections.InsertFailure[UInt64, UInt64]] for BookingError` implementation converts it to the function's error type
  --> bookings_unsettled.lin:23:20
   |
23 |     let _earlier = &bookings.insert(room, nights)?
   |                    ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ `?` converts a different error through `From`: implement it, or convert the error before `?`
   |
   = help: call `.settled()` before `?`: it releases what `collections.InsertFailure[UInt64, UInt64]` hands back and keeps its reason, `mem.Oom`
```

The same line is refused for the same reason, and the help names the fix.
Writing `settled()` says that you have decided to drop what the failure holds.
Every failure that holds an owned value implements two traits, and they answer
different questions:

- **`Release`** consumes the whole failure and returns nothing. Use it when you
  are done with the failure, reason included: `Err(failure) =>
  failure.release()` in a `match` arm.
- **`Settle`** consumes the owned part and returns the reason. `result.settled()`
  does that inside a `Result`, turning a `Result[T, collections.InsertFailure[K, V]]`
  into a `Result[T, mem.Oom]`, so the code can go on with the reason: pass it
  up with `?`, print it, or convert it with `map_err`.

Settling can also do more than free memory. A buffered reader takes a
connection when it opens, and a failed open hands the connection back.
Settling that failure closes the connection, which is I/O the program should
see in its own text, which is why `?` never does it for you. The
[visitor counter](../../examples/visitor_counter.lin) writes `settled()`
there and says what it closes.

### A buffer handed back

A room number and a count of nights need no releasing, so settling them
gives up nothing. A buffer from the heap does. Here each sensor's readings arrive in a
`Vec` of their own, and the program keeps the buffers in another `Vec`:

```linea
import std.io
import std.mem

// Keep a buffer of readings in `buffers`. A refused `push` hands the buffer
// back inside a `mem.PushFailure`; `settled()` releases it and keeps the
// reason, a `mem.Oom`.
fn keep(
    inout buffers: Vec[Vec[Int64]],
    sink buffer: Vec[Int64],
) -> Result[(), mem.Oom] {
    &buffers.push(buffer).settled()
}

fn main() -> Result[UInt8, io.IoError] {
    var buffers: Vec[Vec[Int64]] = Vec.new()
    // Releasing the outer vector releases every buffer still in it.
    defer buffers.release()
    // Each sensor sent this many readings of 21 degrees.
    let sent: [UInt64; _] = [2, 3, 1]
    for count in sent {
        // `Vec.filled` makes a buffer holding `count` copies of one reading.
        let buffer = Vec.filled(mem.system(), count, value: 21) else |_| {
            return .Ok(1)
        }
        if keep(&buffers, buffer).is_err() {
            return .Ok(1)
        }
    }
    var readings = 0
    for read buffer in buffers {
        readings += buffer.length()
    }
    io.println("{buffers.length()} buffers, {readings} readings")?
    .Ok(0)
}
```

```
3 buffers, 6 readings
```

When the outer vector cannot grow, `push` hands the buffer back inside a
`mem.PushFailure`, and the buffer still owns memory from the heap. `keep`
returns the result of `push` as it is, with no `?` to convert it, so
`settled()` releases the buffer and keeps the `mem.Oom`. No path leaves a
buffer unreleased.

### Reading a file as text

Reading a file and turning its bytes into text are two operations that can each
fail, and each failure hands back the bytes. `fs.read_text` does both and owns
the bytes in between. It answers the text, or a `fs.ReadTextError` that says
whether reading or decoding failed and holds nothing that needs releasing:

```linea
import std.fs
import std.io

fn main() -> Result[UInt8, io.IoError] {
    // `/dev/null` is an empty file, which is valid UTF-8 of no bytes.
    let empty = fs.Path.from_str("/dev/null").unwrap()
    defer let text = fs.read_text(empty, max_bytes: 1024) else |error| {
        io.println("could not read the empty file: {error}")?
        return .Ok(1)
    }
    io.println("read {text.length()} bytes")?
    // `read_text` answers a `fs.ReadTextError` that owns no bytes, so the
    // failure needs no settling.
    let missing = fs.Path.from_str("/no/such/file.txt").unwrap()
    defer let other = fs.read_text(missing, max_bytes: 1024) else |error| {
        io.println("could not read the missing file: {error}")?
        return .Ok(0)
    }
    .Ok(2)
}
```

```
read 0 bytes
could not read the missing file: file read failed: file operation failed after 0 bytes: Open failed (NotFound) after 0 bytes; errno 2
```

`read_text` uses the system allocator; `fs.read_text_in(allocator, path,
max_bytes)` takes one, as `new_in` does.

`fs.read_file` and `String.from_bytes` remain for a program that wants the
bytes, or that wants them back when decoding fails. `io.read_text` and
`io.read_text_in` do the same for any reader, such as standard input.

## What you have seen

| You want | Write |
| --- | --- |
| a value that may be missing | `Option[T]`: `.Some(value)` or `.None` |
| a failure that says why | `Result[T, E]`: `.Ok(value)` or `.Err(error)` |
| to pass a failure up | `value?` |
| `?` to wrap another module's error in yours | `@derive(From[TheirError])` on your enum, or `impl From[TheirError] for YourError` |
| to wrap the error of one call | `call().map_err(.Variant)?` |
| to convert with a known destination | `let x: Target = value.into()` |
| a conversion that may not fit | `impl TryFrom[Source] for Target`, then `value.try_into()` |
| a number with a unit | `type Meters = UInt64`, then `Meters(5)` |
| another name for the same type | `alias Pricing = fn(cents: UInt64) -> UInt64` |
| a number with limits | `type Percent = UInt8 where it in 0..=100` |
| to check input against those limits | `Percent?(value)`, which answers an `Option` |
| a checked value as a parameter default | a `@copyable` type: `discount: Percent = Percent(10)` |
| to bind a value, or leave on failure | `let x = value else { return … }` |
| to bind a value, or fall back | `else { fallback }` for an `Option`, `else \|_\| { fallback }` for a `Result` |
| to see the error in the `else` | `else \|error\| { … }` |
| a `main` whose only failures are printing ones | `-> Result[UInt8, io.IoError]`, with `?` |
| a `main` that chooses its exit statuses | `-> UInt8`, with `let x = f() else \|error\| { … }` printing with `io.eprintln` and returning a status |
| to drop what a failure hands back and keep its reason | `result.settled()`, then `?` or `match` |
| a file's text | `fs.read_text(path, max_bytes)`, or `fs.read_text_in(allocator, path, max_bytes)` |
| both outcomes to carry on | `match` |
| a value you know is there | `.unwrap()`, which stops the program if it is not |

The [server settings example](../../examples/server_settings.lin) loads a
configuration file with `let … else` at every step.

Next: [Copying, settling and sealing](04-copying-settling-and-sealing.md) —
what your types promise about copies, cleanup and privacy.
