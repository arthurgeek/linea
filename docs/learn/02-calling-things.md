# Calling things

A Linea program calls functions in two ways: `describe(hall)` and
`hall.needs_heat()`. This chapter explains what each form can reach, how a
call says it will change its receiver, how traits give many types one
operation, what to do when a type's own operation and a trait's share a name,
and how `@derive` writes a trait's implementation for you. It ends with
functions as values, closures, which capture values from where they are
written, including closures that take a pair apart, and the functions you
hand to an `Option` or a `Result`.

## Free functions and operations

A function declared at the top of a file is a **free function**. A function
declared inside an `impl` block belongs to a type, and this guide calls it an
**operation** of that type (other languages say *method*):

```linea
import std.io

struct Thermostat {
    target: Int64,
    current: Int64,
}

impl Thermostat {
    fn needs_heat(self: Self) -> Bool {
        self.current < self.target
    }

    // `inout self` lets this operation change the thermostat it is called on.
    fn warm_up(inout self: Self, degrees: Int64) -> () {
        self.current += degrees
    }
}

fn describe(thermostat: Thermostat) -> Str {
    if thermostat.needs_heat() { "heating" } else { "idle" }
}

fn main() -> Result[UInt8, io.IoError] {
    var hall = Thermostat { target = 21, current = 17 }
    io.println("The hall is {describe(hall)}.")?
    &hall.warm_up(5)
    io.println("The hall is {describe(hall)} at {hall.current} degrees.")?
    .Ok(0)
}
```

```
The hall is heating.
The hall is idle at 22 degrees.
```

`thermostat.needs_heat()` is a **dot call**. The value before the dot, the
*receiver*, becomes the operation's first parameter, `self`, and `Self` is the
type the `impl` is for. The same call can be spelled out with the type's name,
and the two forms mean exactly the same thing:

```linea
Thermostat.needs_heat(hall)      // This is the same call as hall.needs_heat().
Thermostat.warm_up(&hall, 5)     // This is the same call as &hall.warm_up(5).
```

The dot form is shorter and is what you will usually write. The spelled-out
form is useful when you want to say *whose* operation you mean, which comes up
with traits below.

### A dot call reaches operations, not free functions

`describe` is a free function, so it is called as `describe(hall)`. A dot call
only looks for operations of the receiver's type, and writing
`hall.describe()` is refused, with the call you meant:

<!-- guide: unchecked the error an edit of the program above produces -->
```
error[T-UnknownOperation]: `describe` is a function, not an operation of `Thermostat`
  --> free_dot.lin:25:30
   |
25 |     io.println("The hall is {hall.describe()}.")?
   |                              ^^^^^^^^^^^^^ call it as `describe(hall)`
```

Rust draws the same line: a free `fn describe(t: &Thermostat)` is never
callable as `t.describe()`. Some languages let any function be called with a
dot on its first argument; Linea keeps the dot for what the type itself
offers, so you can tell from a call where to look for its definition. If a
function belongs with the type, move it into the `impl`.

## `&` marks a receiver the call will change

`warm_up` takes `inout self`: it changes the thermostat. When you call it, you
write `&` in front of the call, `&hall.warm_up(5)`, so anyone reading the line
can see that `hall` may be different afterwards. This is the same `&` a caller
writes before an `inout` argument, `Thermostat.warm_up(&hall, 5)`, moved to the
front of the dot call.

Each parameter convention looks like this at the call, for a free function
`op` and for an operation `op` of `x`'s type:

| Convention | Free function | Operation | Afterwards |
| --- | --- | --- | --- |
| read (the default) | `op(x)` | `x.op()` | `x` is unchanged |
| `inout` | `op(&x)` | `&x.op()` | `x` may have changed |
| `sink` | `op(x)` | `x.op()` | `x` is gone; a number is copied instead |

Read and sink look alike at the call, because the parameter, not the call,
decides whether a value moves ([Copying, settling and
sealing](04-copying-settling-and-sealing.md#where-a-value-sits-decides-whether-it-moves)).

Leave the `&` off `&hall.warm_up(5)` and the compiler asks for it:

<!-- guide: unchecked the error an edit of the program above produces -->
```
error[S-Mutation]: this receiver is mutated, so the call is marked `&`
  --> no_amp.lin:26:5
   |
14 |     fn warm_up(inout self: Self, degrees: Int64) -> () {
   |                      ---- declared `inout`
26 |     hall.warm_up(5)
   |     ^^^^ write `&hall.warm_up(...)`
```

Write it where nothing changes, and the compiler asks you to remove it:

```linea
import std.io

struct Thermostat {
    target: Int64,
    current: Int64,
}

impl Thermostat {
    fn needs_heat(self: Self) -> Bool {
        self.current < self.target
    }
}

fn main() -> Result[UInt8, io.IoError] {
    var hall = Thermostat { target = 21, current = 17 }
    if &hall.needs_heat() {
        io.println("heating")?
    }
    .Ok(0)
}
```

```
error[S-Mutation]: this receiver is not mutated, so the call takes no `&`
  --> amp_read.lin:16:9
   |
9  |     fn needs_heat(self: Self) -> Bool {
   |                   ---- declared `read`
16 |     if &hall.needs_heat() {
   |         ^^^^ remove the `&` before it
```

So `&` always means *this may change*, and its absence always means *this
will not*. It is written in three places: before an argument, before a dot
call on an `inout` receiver, and at the head of a loop over an iterator,
`for x in &it` ([Iterating](05-iterating.md)). All three mark a possible
mutation. `&` is not an address and does not make a reference; Linea has no
reference values. In Rust the same information hides in the method's
signature, `fn warm_up(&mut self)`, and the call site `hall.warm_up(5)` looks
like any other.

The receiver has to be something that can change: a `var`, or a field or
element of one. Calling `&hall.warm_up(5)` on a `let hall` is refused because
`hall` cannot be assigned:

<!-- guide: unchecked the error an edit of the program above produces -->
```
error[N-Immutable]: `hall` is declared with `let`
  --> let_recv.lin:26:6
   |
24 |     let hall = Thermostat { target = 21, current = 17 }
   |         ---- declared with `let` here
26 |     &hall.warm_up(5)
   |      ^^^^ this binding cannot be assigned
```

The marker also reaches through fields and indexes: `&house.hall.warm_up(5)`
changes the `hall` field of `house`, and `&rooms[0].warm_up(5)` changes the
first element of `rooms`. When the receiver is the result of a call, bind it to
a `var` first and call the operation on that.

## Traits: one operation, many types

A **trait** names operations that several types can each provide. Here a café
prices coffee and cake differently, and one function bills either:

```linea
import std.io

trait Priced {
    fn cents(self: Self) -> UInt64
}

struct Coffee {
    shots: UInt64,
}

struct Cake {
    slices: UInt64,
}

impl Priced for Coffee {
    fn cents(self: Self) -> UInt64 {
        250 + self.shots * 60
    }
}

impl Priced for Cake {
    fn cents(self: Self) -> UInt64 {
        self.slices * 320
    }
}

// `T: Priced` accepts any type that implements `Priced`.
fn bill[T: Priced](item: T, quantity: UInt64) -> UInt64 {
    item.cents() * quantity
}

fn main() -> Result[UInt8, io.IoError] {
    let latte = Coffee { shots = 2 }
    let cake = Cake { slices = 1 }
    io.println("Two lattes: {bill(latte, 2)} cents.")?
    io.println("One slice: {bill(cake, 1)} cents.")?
    // Both spell out the same call: through the trait, or through the type.
    io.println("Written out: {Priced.cents(latte)} and {Coffee.cents(latte)} cents.")?
    .Ok(0)
}
```

```
Two lattes: 740 cents.
One slice: 320 cents.
Written out: 370 and 370 cents.
```

`Self` in the trait stands for whichever type implements it. `bill[T: Priced]`
is a generic function: `T` is a type parameter, and the **bound** `Priced`
says `bill` may call `Priced`'s operations on a `T`. Each call is compiled for
the type it is given, as in Rust. `Priced.cents(latte)` spells the call out
through the trait, and `Coffee.cents(latte)` through the type, which reaches
the operations of every trait in scope that `Coffee` implements, just as
Rust's `Coffee::cents(latte)` does.

Traits are Rust's traits, with the same `impl Trait for Type` shape.

### A trait must be in scope for a dot call

When a trait is declared in another module, a dot call reaches its operations
only once the trait is in scope. Here `menu` declares `Priced` and implements
it for `Coffee`, and `shop/main.lin` forgets to bring it in.

`shop/menu/menu.lin`:

```linea
pub trait Priced {
    fn cents(self: Self) -> UInt64
}

pub struct Coffee {
    shots: UInt64,
}

impl Priced for Coffee {
    fn cents(self: Self) -> UInt64 {
        250 + self.shots * 60
    }
}
```

`shop/main.lin`:

```linea
import menu
import std.io

fn main() -> Result[UInt8, io.IoError] {
    let latte = menu.Coffee { shots = 2 }
    io.println("A latte costs {latte.cents()} cents.")?
    .Ok(0)
}
```

```
error[T-UnknownOperation]: `cents` is declared by `Priced`, which is not in scope here
 --> shop/main.lin:6:32
  |
6 |     io.println("A latte costs {latte.cents()} cents.")?
  |                                ^^^^^^^^^^^ write `use menu.Priced`: an operation is reached through the trait that declares it
```

Add `use menu.Priced` and it compiles. Rust has the same rule: a trait
method needs `use the_trait` before `x.method()` finds it. The traits in the
prelude, such as `Display` and `Release`, are always in scope.

A bound brings its trait's operations into reach by itself. Inside a generic
function that asks for `T: menu.Priced`, `item.cents()` works without any
`use`, because the bound already says which trait `cents` comes from:

<!-- guide: unchecked the program imports a module this block does not show -->
```linea
import menu
import std.io

// The bound `T: menu.Priced` brings `cents` into reach inside `bill`.
fn bill[T: menu.Priced](item: T, quantity: UInt64) -> UInt64 {
    item.cents() * quantity
}

fn main() -> Result[UInt8, io.IoError] {
    let latte = menu.Coffee { shots = 2 }
    io.println("Two lattes cost {bill(latte, 2)} cents.")?
    .Ok(0)
}
```

```
Two lattes cost 740 cents.
```

### When the type and a trait both have the operation

A type can have an operation of its own with the same name as one of a
trait's. Then a dot call runs the type's own:

```linea
import std.io

trait Priced {
    fn cents(self: Self) -> UInt64
}

struct Coffee {
    shots: UInt64,
}

impl Coffee {
    // This operation prices the extra shots alone.
    fn cents(self: Self) -> UInt64 {
        self.shots * 60
    }
}

impl Priced for Coffee {
    fn cents(self: Self) -> UInt64 {
        250 + self.shots * 60
    }
}

fn main() -> Result[UInt8, io.IoError] {
    let latte = Coffee { shots = 2 }
    io.println("latte.cents() is {latte.cents()}")?
    io.println("Priced.cents(latte) is {Priced.cents(latte)}")?
    .Ok(0)
}
```

The compiler builds the program with a warning, and the program then runs:

```
warning[N-Shadowed]: `Coffee` declares `cents` itself, so a postfix call in this module reaches that one rather than this; a call elsewhere reaches this one
  --> shadow.lin:19:8
   |
19 |     fn cents(self: Self) -> UInt64 {
   |        ^^^^^ reach it as `Priced.cents(self)`
latte.cents() is 120
Priced.cents(latte) is 370
```

The type's own operation is part of the type: you get it without importing
anything. A trait's arrives through a `use` or a bound. If the trait's won,
adding a `use` or a bound somewhere could silently change what an existing
`latte.cents()` runs. So the type's own always wins, and the trait's is reached
spelled out, `Priced.cents(latte)`. The `[N-Shadowed]` warning tells you when
you have written an implementation whose operation a dot call will not reach.
It does not stop the build.

The type's own operation only wins where the call could use it. This `cents`
is private, so it wins only inside this module, which is what the warning's
"a call elsewhere reaches this one" says: another module that imports `Coffee`
reaches the trait's. An own operation that does not take the receiver as
`self` steps aside the same way. Inside a generic function such as
`bill[T: Priced]`, `T` has no operations of its own, so `item.cents()` is
always the trait's.

When two traits in scope both declare the operation and the type has none of
its own, the dot call is ambiguous (`[N-Ambiguous]`), and you spell out the
one you mean: `Priced.cents(latte)`.

## A dot call never reaches a field

A field and an operation can share a name, or a field can hold a function. A
dot call with parentheses always looks for an operation, and never falls back
to a field:

```linea
import std.io

// A plan's `rule` says how many cents it takes off a price.
struct Plan {
    name: Str,
    rule: fn(cents: UInt64) -> UInt64,
}

impl Plan {
    // The shop never gives more than half off, whatever a rule asks for.
    fn discount(self: Self, cents: UInt64) -> UInt64 {
        let asked = (self.rule)(cents)
        if asked > cents / 2 { cents / 2 } else { asked }
    }
}

// Students get a fifth off.
fn student(cents: UInt64) -> UInt64 {
    cents / 5
}

// Staff ask for the whole price off, and the cap holds them to half.
fn staff(cents: UInt64) -> UInt64 {
    cents
}

fn main() -> Result[UInt8, io.IoError] {
    let plans = [Plan { name = "student", rule = student }, Plan { name = "staff", rule = staff }]
    for read plan in plans {
        io.println("{plan.name}: {plan.discount(1000)} cents off")?
    }
    .Ok(0)
}
```

```
student: 200 cents off
staff: 500 cents off
```

The `rule` field holds a function, which [Functions as
values](#functions-as-values) explains. To call
the function a field holds, put parentheses around the field,
`(self.rule)(cents)`: that reads the field first, then calls what it holds.
The operation `discount` uses this to apply a cap: whatever a plan's rule asks
for, a customer never gets more than half off. That is why the staff rule, which
asks for the whole 1000 cents, gives 500.

`plan.rule(1000)` does not quietly call the field. It is refused, and the
error shows the spelling you need:

```linea
import std.io

struct Plan {
    name: Str,
    rule: fn(cents: UInt64) -> UInt64,
}

fn student(cents: UInt64) -> UInt64 {
    cents / 5
}

fn main() -> Result[UInt8, io.IoError] {
    let plan = Plan { name = "student", rule = student }
    io.println("{plan.name}: {plan.rule(1000)} cents off")?
    .Ok(0)
}
```

```
error[T-UnknownOperation]: `Plan` has no operation `rule`
  --> field_call.lin:14:31
   |
14 |     io.println("{plan.name}: {plan.rule(1000)} cents off")?
   |                               ^^^^^^^^^ `rule` is a field; to call the function it holds, write `(plan.rule)(...)`
```

This is Rust's rule as well: `x.f()` is always a method call, and `(x.f)()`
calls a closure stored in the field `f`. It matters most for types whose
fields you cannot see: an `@opaque` type can offer an operation named after one
of its hidden fields, and callers reach the operation.
[Copying, settling and sealing](04-copying-settling-and-sealing.md#an-operation-can-share-a-sealed-fields-name)
shows that case.

## `@derive`: implementations the compiler writes

Comparing two playing cards field by field, or printing one for debugging, is
code you should not have to write. `@derive(...)`, on the line before a type,
writes an `impl` of each trait it names for you, built from the type's fields:

```linea
import std.io

@derive(Equatable, Debug)
enum Suit {
    Hearts,
    Spades,
}

@derive(Equatable, Debug)
struct Card {
    rank: UInt8,
    suit: Suit,
}

fn main() -> Result[UInt8, io.IoError] {
    let drawn = Card { rank = 12, suit = .Hearts }
    let wanted = Card { rank = 12, suit = .Hearts }
    io.println("You drew {drawn:?}.")?
    if drawn == wanted {
        io.println("That is the card you wanted.")?
    }
    .Ok(0)
}
```

```
You drew Card { rank: 12, suit: Hearts }.
That is the card you wanted.
```

- `Equatable` gives you `==` and `!=`, comparing every field.
- `Debug` gives you `{value:?}` in a string, showing every field and variant.
- `Release` gives you `release()`, settling every field in turn; [Copying,
  settling and
  sealing](04-copying-settling-and-sealing.md#release-the-ending-you-do-not-have-to-think-about)
  shows the values that need it.
- `Default` gives you `Type.default()`, every field at its own default, as
  [Linea in an hour](01-linea-in-an-hour.md#defaults-and-struct-update) showed.
- `Equivalent` adds no operation: it promises that `==` is a true
  equivalence, reflexive, symmetric and transitive, which ordering and hashing
  rely on.
- `Comparable` gives `less`, and with it `<`, `<=` and `>`, comparing field by
  field; some pairs may be incomparable.
- `Ordered` promises a total order: for every pair, exactly one of `a < b`,
  `b < a` or `a == b` holds.
- `Display` derives the same way, as do `json.Encode` and `json.Decode` for
  reading and writing JSON and `http.Params` for a handler's parameters.

A trait can require another, and a derive needs the ones it requires derived
beside it. `Ordered` requires `Comparable` and `Equivalent`. `Hash` is not in the prelude: it lives in
`std.hash`, so it is written `hash.Hash` after `import std.hash`:

```linea
import std.hash
import std.io

// `Ordered` needs `Comparable` and `Equivalent` derived beside it, and `Hash`
// comes from `std.hash`, so it is written `hash.Hash`.
@derive(Equatable, Equivalent, Comparable, Ordered, hash.Hash, Debug)
struct Seat {
    row: UInt8,
    number: UInt8,
}

fn main() -> Result[UInt8, io.IoError] {
    let aisle = Seat { row = 3, number = 1 }
    let window = Seat { row = 3, number = 6 }
    io.println("{aisle:?} comes before {window:?}: {aisle < window}")?
    .Ok(0)
}
```

```
Seat { row: 3, number: 1 } comes before Seat { row: 3, number: 6 }: true
```

A derive only works when every field supports the trait. Here a reading holds
a sensor, and `Sensor` has no `==`:

```linea
struct Sensor {
    pin: UInt8,
}

@derive(Equatable)
struct Reading {
    sensor: Sensor,
    celsius: Int64,
}

fn main() -> UInt8 {
    let first = Reading { sensor = Sensor { pin = 4 }, celsius = 21 }
    let second = Reading { sensor = Sensor { pin = 4 }, celsius = 21 }
    if first == second { 0 } else { 1 }
}
```

```
error[T-Derive]: `Reading` cannot derive `Equatable` because component type `Sensor` does not implement `Equatable`
 --> derive_field.lin:5:9
  |
5 | @derive(Equatable)
  |         ^^^^^^^^^ implement `Equatable` for `Sensor`, or write this implementation by hand
7 |     sensor: Sensor,
  |     ------ this component has type `Sensor`
```

The error names the field that stands in the way, `sensor`. Derive
`Equatable` for `Sensor` too, and `Reading` compiles.

### `@derive` on a generic type

A derive on a generic type applies wherever the fields support the trait:

```linea
import std.io

@derive(Equatable, Debug)
struct Labelled[T] {
    label: Str,
    value: T,
}

fn main() -> Result[UInt8, io.IoError] {
    let before = Labelled[Int64] { label = "temperature", value = 21 }
    let after = Labelled[Int64] { label = "temperature", value = 23 }
    io.println("{before:?} -> {after:?}")?
    if before != after {
        io.println("The reading changed.")?
    }
    .Ok(0)
}
```

```
Labelled { label: "temperature", value: 21 } -> Labelled { label: "temperature", value: 23 }
The reading changed.
```

A generic struct's literal names its type argument, `Labelled[Int64] { … }`;
the fields do not settle it. Leave `[Int64]` off both literals and each is
refused:

<!-- guide: unchecked the error an edit of the program above produces -->
```
error[T-Bound]: `Labelled` takes 1 type argument(s), and was given 0
  --> labelled_infer.lin:10:18
   |
10 |     let before = Labelled { label = "temperature", value = 21 }
   |                  ^^^^^^^^ give it the arguments it declares
error[T-Bound]: `Labelled` takes 1 type argument(s), and was given 0
  --> labelled_infer.lin:11:17
   |
11 |     let after = Labelled { label = "temperature", value = 23 }
   |                 ^^^^^^^^ give it the arguments it declares
```

`Labelled[Int64]` has `==` because `Int64` has it. A `Labelled` of something
without `==` is still a valid type; it just has no `==` of its own, and the
error says why when you reach for one:

```linea
struct Sensor {
    pin: UInt8,
}

@derive(Equatable, Debug)
struct Labelled[T] {
    label: Str,
    value: T,
}

fn main() -> UInt8 {
    let first = Labelled[Sensor] { label = "kitchen", value = Sensor { pin = 4 } }
    let second = Labelled[Sensor] { label = "kitchen", value = Sensor { pin = 4 } }
    if first == second { 0 } else { 1 }
}
```

```
error[T-Bound]: `Labelled[Sensor]` does not implement `Equatable`
  --> gen_derive_bad.lin:14:14
   |
14 |     if first == second { 0 } else { 1 }
   |              ^^ implement `Equatable` for `Sensor`
   |
   = help: `Labelled[T]` implements `Equatable` when `T` implements `Equatable`, and `Sensor` does not
```

Rust's `#[derive(PartialEq)]`
instead demands `T: PartialEq` of every `T`, even one that never appears in a
field; Linea asks only of the field types.

### Arrays compare, print and hash like their elements

An array supports `==`, `Debug` and `Hash` wherever its element type does, so
a type holding one derives them like any other. Here a board is compared,
printed, and used as a map key to count how often a position comes up:

```linea
import std.collections
import std.hash
import std.io

// Each cell holds 0 when it is empty, 1 for a nought and 2 for a cross.
// `hash.Hash` lets a board be a map key, and a map releases its keys, so
// the board derives `Release` as well.
@derive(Equatable, Equivalent, hash.Hash, Release, Debug)
struct Board {
    cells: [UInt8; 9],
}

fn main() -> Result[UInt8, io.IoError] {
    let saved = Board { cells = [0, 0, 0, 0, 1, 0, 0, 0, 2] }
    let current = Board { cells = [0, 0, 0, 0, 1, 0, 0, 0, 2] }
    if saved == current {
        io.println("No moves since the last save: {current.cells:?}")?
    }
    // Count how often each position was reached, with the board as the key.
    var seen: collections.Map[Board, UInt64] = collections.Map.new()
    defer seen.release()
    let history = [saved, current]
    for position in history {
        if &seen.merge(position, 1, |sink stored, sink added| stored + added).is_err() {
            return .Ok(1)
        }
    }
    let wanted = Board { cells = [0, 0, 0, 0, 1, 0, 0, 0, 2] }
    let times = *seen.get(wanted).unwrap()
    io.println("positions seen: {seen.length()}, this one {times} times")?
    .Ok(0)
}
```

```
No moves since the last save: [0, 0, 0, 0, 1, 0, 0, 0, 2]
positions seen: 1, this one 2 times
```

Comparing two boards compares their `cells` arrays element by element,
`{current.cells:?}` prints one, and hashing a board hashes its cells, so two
equal boards land on one key. `net.Address` derives its equality this way from
its four address bytes.

### When to write it by hand

Write the implementation yourself when the field-by-field answer is wrong for
your domain. Two builds of the same release, say, are the same version:

```linea
import std.io

@derive(Debug)
struct Version {
    major: UInt64,
    minor: UInt64,
    build: Str,
}

// Two builds of the same release are the same version, so `build` is left out.
impl Equatable for Version {
    fn equals(self: Self, other: Self) -> Bool {
        self.major == other.major && self.minor == other.minor
    }
}

fn main() -> Result[UInt8, io.IoError] {
    let installed = Version { major = 2, minor = 4, build = "a1f9" }
    let offered = Version { major = 2, minor = 4, build = "c07e" }
    if installed == offered {
        io.println("{offered:?} is the release you already have.")?
    }
    .Ok(0)
}
```

```
Version { major: 2, minor: 4, build: "c07e" } is the release you already have.
```

`impl Equatable for Version` supplies `equals`, and `==` and `!=` call it.

**What you can do now:** add `@derive(Equatable, Debug)` to data you want to
compare and print, and write the implementation by hand when the field-by-field
answer is not the right one.

## Naming a type argument

A generic function usually learns its type parameters from its arguments:
`bill(latte, 2)` makes `T` a `Coffee`. When nothing does, write the type in
brackets after the function's name:

```linea
import std.io
import std.text

// `or_default` reads text as whatever type `T` the caller asks for, and gives
// that type's default when the text does not parse.
fn or_default[T: text.Parse + Default](written: Str) -> T {
    // `parse` answers a `Result`: `Ok` with the value, or `Err` with what went
    // wrong. `match` handles each; [Errors](03-errors.md) covers `Result`.
    match written.parse[T]() {
        Ok(value) => value,
        Err(_) => T.default(),
    }
}

fn main() -> Result[UInt8, io.IoError] {
    // An annotation on the result can settle `T`.
    let port: UInt16 = or_default("8080")
    // Or the call names `T` itself, in brackets after the function's name.
    let retries = or_default[UInt8]("many")
    io.println("port {port}, {retries} retries")?
    .Ok(0)
}
```

```
port 8080, 0 retries
```

`T: text.Parse + Default` asks for two bounds at once: `+` joins them, and `T`
must implement every one. `written.parse[T]()` names a type argument for an
operation the same way: `"8080".parse[UInt16]()`
reads a `UInt16`. `T.default()` calls an operation of the trait the bound
names, through the type parameter. Leave both the annotation and the brackets
out and the compiler says it cannot tell:

<!-- guide: unchecked the error an edit of the program above produces -->
```
error[T-Infer]: nothing here says what `T` is
  --> typeargs_missing.lin:19:19
   |
19 |     let retries = or_default("many")
   |                   ^^^^^^^^^^^^^^^^^^ no argument determines it, and nothing expects a type of it
```

This is Rust's turbofish, `or_default::<u8>("many")`, without the `::`.

### A type parameter with a default

A function can give a type parameter a default, written `= Type` after its
bounds, and give the parameter of that type a default value. When a call names
the argument, the argument settles the type. When it does not, nothing says
what the type is, so it takes its default and the argument takes the default
value:

```linea
import std.io

// A label that travels with a parcel.
@copyable
struct Label {
    text: Str,
}

// What `pack` returns: the packed weight, and the label the caller gave it.
struct Parcel[L] {
    grams: UInt64,
    label: L,
}

// `L` is the label type. When a call passes no `label:`, nothing else says
// what `L` is, so it takes its default, `()`, and `label` takes the default
// value `()`. `label` is `sink`, so `pack` takes it over; a `sink` parameter
// may carry a default because the default owes nothing.
fn pack[L = ()](grams: UInt64, sink label: L = ()) -> Parcel[L] {
    .{ grams = grams + 20, label }
}

fn main() -> Result[UInt8, io.IoError] {
    // No `label:`, so `L` is `()`.
    let plain = pack(300)
    // Naming `label:` makes `L` a `Label`.
    let named = pack(300, label: Label { text = "fragile" })
    io.println("{plain.grams} g plain, {named.grams} g labelled {named.label.text}")?
    .Ok(0)
}
```

```
320 g plain, 320 g labelled fragile
```

`pack(300)` leaves out `label:`, so `L` is `()` and the parcel carries no
label. `pack(300, label: Label { text = "fragile" })` settles `L` as `Label`.
A bare number meets the default the way it does for a struct: with
`fn two[T: Copyable = UInt8](a: T)`, `two(5)` is a `UInt8`, not an `Int64`.
The default value must be a constant of the type's default, so a call that
settles `L` as a `Label` and leaves `label:` out is refused as a
`T-Mismatch`: there is no label to invent. A call that writes a
function's type arguments by hand writes all of them or none: with two type
parameters, `pair[UInt8]()` is refused as `T-Bound`, since a default fills a
type a call leaves out, not one it half wrote. A defaulted `sink` parameter is
allowed because a default owes nothing; an `inout` parameter has no default,
since it needs the place the caller changes. This is how
`http.listen_and_serve(address, handler)` and
`http.listen_and_serve(address, handler, state: app)` are one function
([Networking](09-networking.md#shared-state)).

## Functions as values

`fn(coffee: Coffee) -> UInt64` is a type: a function that takes a `Coffee` and
returns a `UInt64`. A function is a value of such a type, so you can pass one
to another function, keep one in a field, or bind one to a local:

```linea
import std.io

struct Coffee {
    shots: UInt64,
}

impl Coffee {
    fn cents(self: Self) -> UInt64 {
        250 + self.shots * 60
    }

    fn add_shot(inout self: Self) -> () {
        self.shots += 1
    }
}

// Happy hour takes a quarter off.
fn happy_hour(coffee: Coffee) -> UInt64 {
    coffee.cents() * 3 / 4
}

// `price` is any function that takes a coffee and returns cents.
fn total(orders: [Coffee; 3], price: fn(coffee: Coffee) -> UInt64) -> UInt64 {
    var sum = 0
    for read order in orders {
        sum += price(order)
    }
    sum
}

fn main() -> Result[UInt8, io.IoError] {
    let orders = [Coffee { shots = 1 }, Coffee { shots = 2 }, Coffee { shots = 0 }]
    io.println("Full price: {total(orders, Coffee.cents)} cents.")?
    io.println("Happy hour: {total(orders, happy_hour)} cents.")?

    // The receiver becomes the first parameter, and keeps its `inout`.
    let strengthen = Coffee.add_shot
    var mine = Coffee { shots = 1 }
    strengthen(&mine)
    io.println("Mine has {mine.shots} shots.")?
    .Ok(0)
}
```

```
Full price: 930 cents.
Happy hour: 696 cents.
Mine has 2 shots.
```

A free function is named as a value by its name, `happy_hour`, and an
operation with its type in front, `Coffee.cents`. A trait's operation works
too: `Priced.cents` is a value wherever a `Priced` type is expected. The
receiver becomes an ordinary first parameter and keeps its convention, so
`strengthen` takes an `inout Coffee` and the call marks the
argument, `strengthen(&mine)`. A local needs no annotation: `let strengthen =
Coffee.add_shot` takes its type from the operation.

### Labels are not part of a function's type

The names in a function type are labels for reading and for named calls, not
part of the type. `total` accepts `Coffee.cents`, whose parameter is called
`self`, and `happy_hour`, whose parameter is called `coffee`, because both take
a `Coffee` and return a `UInt64`:

```linea
import std.io

fn tip(bill: UInt64, percent: UInt64) -> UInt64 {
    bill * percent / 100
}

// Inside `apply`, the function is called with the labels its type writes.
fn apply(rule: fn(amount: UInt64, rate: UInt64) -> UInt64) -> UInt64 {
    rule(amount: 2000, rate: 10)
}

fn main() -> Result[UInt8, io.IoError] {
    // A local bound to `tip` keeps `tip`'s own labels.
    let kept = tip
    io.println("tip {tip(bill: 4000, percent: 15)}, kept {kept(bill: 4000, percent: 15)}, applied {apply(tip)}")?
    .Ok(0)
}
```

```
tip 600, kept 600, applied 200
```

A named call uses the labels of whatever it calls through: `tip`'s own labels
for `tip` and for a local bound to it, and the labels of `apply`'s parameter
type inside `apply`.

### A name for a long type: `alias`

A function type written out in full is long, and a program that keeps several
rules repeats it. `alias` gives a type a second name:

```linea
import std.io

struct Coffee {
    shots: UInt64,
}

impl Coffee {
    fn cents(self: Self) -> UInt64 {
        250 + self.shots * 60
    }
}

// `Pricing` is another name for this function type, not a new type.
alias Pricing = fn(coffee: Coffee) -> UInt64

// An offer names the rule it prices a coffee by.
struct Offer {
    name: Str,
    price: Pricing,
}

// Happy hour takes a quarter off.
fn happy_hour(coffee: Coffee) -> UInt64 {
    coffee.cents() * 3 / 4
}

fn main() -> Result[UInt8, io.IoError] {
    let offers = [Offer { name = "full price", price = Coffee.cents }, Offer { name = "happy hour", price = happy_hour }]
    let latte = Coffee { shots = 2 }
    for read offer in offers {
        io.println("{offer.name}: {(offer.price)(latte)} cents")?
    }
    .Ok(0)
}
```

```
full price: 370 cents
happy hour: 277 cents
```

Wherever `Pricing` is written, it means `fn(coffee: Coffee) -> UInt64`, so
`Coffee.cents` and `happy_hour` fit it as they fit the type written out. An
alias is only a name: it has no operations of its own, and an error message
names the type it stands for. Rust writes the same thing as
`type Pricing = fn(Coffee) -> u64`. In Linea, `type` makes a *new* type
instead, which [Errors](03-errors.md#a-new-type-not-a-nickname) covers.

An alias also names a role. A program that keeps a list of things bought gives
that list a name of its own, and writes the type once:

```linea
import std.io

// `Basket` is `Vec[Str]` under the name of what it holds.
alias Basket = Vec[Str]

fn main() -> Result[UInt8, io.IoError] {
    var basket: Basket = Vec.new()
    defer basket.release()
    if &basket.push("bread").is_err() {
        return .Ok(1)
    }
    io.println("{basket.length()} item")?
    .Ok(0)
}
```

```
1 item
```

An alias may keep a parameter open. `Stack[T]` names a `Vec` used as a stack
and leaves the element type to each use, and `Stack.new()` is `Vec.new()`. The
element type comes from the annotation, as it does for `Vec.new`:

```linea
import std.io

// `Stack[T]` leaves the element type to each use.
alias Stack[T] = Vec[T]

fn main() -> Result[UInt8, io.IoError] {
    var scores: Stack[UInt64] = Stack.new()
    defer scores.release()
    var names: Stack[Str] = Stack.new()
    defer names.release()
    if &scores.push(7).is_err() {
        return .Ok(1)
    }
    if &names.push("Ada").is_err() {
        return .Ok(1)
    }
    io.println("{names.length()} name, {scores.length()} score")?
    .Ok(0)
}
```

```
1 name, 1 score
```

The alias hides nothing: `Basket` and `Stack` are the `Vec` they name, and the
`Vec.new()` that makes them is written where the storage is declared.

## Closures: functions that capture

A **lambda** is a function written where it is used, between `|` bars:
`|coffee| coffee.cents() / 2`. A lambda that uses values from around it is a
**closure**, and Linea asks you to list those values:

```linea
import std.io

struct Coffee {
    shots: UInt64,
}

impl Coffee {
    fn cents(self: Self) -> UInt64 {
        250 + self.shots * 60
    }
}

// `F: fn(coffee: Coffee) -> UInt64` accepts any function or closure that can
// be called with a coffee and returns cents.
fn total[F: fn(coffee: Coffee) -> UInt64](orders: [Coffee; 3], price: F) -> UInt64 {
    var sum = 0
    for read order in orders {
        sum += price(order)
    }
    sum
}

fn main() -> Result[UInt8, io.IoError] {
    let orders = [Coffee { shots = 1 }, Coffee { shots = 2 }, Coffee { shots = 0 }]
    // A lambda is a function written where it is used. `total` supplies the
    // type of `coffee`, so the lambda does not repeat it.
    io.println("Half price: {total(orders, |coffee| coffee.cents() / 2)} cents.")?
    let surcharge = 40
    // `[surcharge]` lets the lambda read `surcharge` from `main`.
    io.println("To take away: {total(orders, [surcharge] |coffee| coffee.cents() + surcharge)} cents.")?
    .Ok(0)
}
```

```
Half price: 465 cents.
To take away: 1050 cents.
```

`[surcharge]` is the **capture list**. Without it, the lambda cannot see
`surcharge` at all:

<!-- guide: unchecked the error an edit of the program above produces -->
```
error[O-Capture]: this name is not declared in the closure capture list
  --> uncaptured.lin:30:72
   |
30 |     io.println("To take away: {total(orders, |coffee| coffee.cents() + surcharge)} cents.")?
   |                                                                        ^^^^^^^^^ this name belongs to an enclosing body
   |
   = help: write `[surcharge]` before the parameters to read it where it is, or `[sink surcharge]` to move it into the closure
```

`total` now takes `F: fn(coffee: Coffee) -> UInt64`, a bound, rather than the
type `fn(coffee: Coffee) -> UInt64` itself. A value of a plain function type
holds only code, so a closure, which also holds what it captured, cannot become
one. Keep the earlier `total` and pass it the capturing lambda:

<!-- guide: unchecked the error an edit of the program above produces -->
```
error[O-Capture]: a capturing closure cannot become a function pointer
  --> lambdas_fnptr.lin:30:46
   |
30 |     io.println("To take away: {total(orders, [surcharge] |coffee| coffee.cents() + surcharge)} cents.")?
   |                                              ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ keep its environment with `mem.Closure.open(closure)`, or take a generic callable parameter
```

A bound accepts functions and closures alike. It is Rust's
`impl Fn(Coffee) -> u64`. A lambda that captures nothing, like the half-price
one, still fits a plain function type.

### Why captures are written out

A capture is an ownership decision, the same one every parameter makes: does
the closure look at the value where it is, take it, or take a copy? Linea asks
you to write the answer in the capture list, and then checks it like any other
ownership decision; Rust infers it from the closure's body instead. Three forms
answer those questions, and a fourth, `[inout name]`, which changes the value
where it is, comes after them.

**`[name]` looks at the value where it is.** The closure holds no copy, so the
value must stay as it is while the closure is still going to be used:

```linea
import std.io

fn main() -> Result[UInt8, io.IoError] {
    var limit = 500
    // `[limit]` reads `limit` where it is: the closure holds no copy of its own.
    let cheap = [limit] |cents: UInt64| cents < limit
    limit = 400
    io.println("450 is cheap: {cheap(450)}")?
    .Ok(0)
}
```

```
error[O-Borrow]: this operation invalidates a place that a later observation still needs
 --> capture_read_bad.lin:7:5
  |
7 |     limit = 400
  |     ^^^^^ keep this place available until the last use of its observation
8 |     io.println("450 is cheap: {cheap(450)}")?
  |                                ----- the observation is still used here
```

The error points at the change and at the later use that needs the old value.
Move `limit = 400` below the last call of `cheap` and the program compiles.
`[read limit]` is the same capture with its convention written out.
[Borrowing](06-borrowing.md) explains this rule in full: it is the one that
keeps every view valid.

**`[sink name]` moves the value into the closure.** The closure owns it from
then on, and you can no longer use it outside:

```linea
import std.io

fn main() -> Result[UInt8, io.IoError] {
    var guests: Vec[Str] = Vec.new()
    if &guests.push("Ada").is_err() || &guests.push("Alan").is_err() {
        guests.release()
        return .Ok(1)
    }
    // `[sink guests]` moves the vector into the closure, which now owns it.
    let invited = [sink guests] |name: Str| {
        for read guest in guests {
            if guest == name {
                return true
            }
        }
        false
    }
    // The closure owns memory from the heap, so it is released like the vector was.
    defer invited.release()
    io.println("Ada is invited: {invited("Ada")}")?
    io.println("Grace is invited: {invited("Grace")}")?
    .Ok(0)
}
```

```
Ada is invited: true
Grace is invited: false
```

A closure owns what it captured with `sink`, so it follows the same rules: a
closure holding a vector from the heap must be released, as the vector had to
be. Take the `defer invited.release()` away:

<!-- guide: unchecked the error an edit of the program above produces -->
```
error[O-Leak]: `invited` (a linear closure) is still owned when this path leaves
  --> capture_leak.lin:20:51
   |
11 |     let invited = [sink guests] |name: Str| {
   |         ------- acquired here
20 |     io.println("Ada is invited: {invited("Ada")}")?
   |                                                   ^ still owned here
21 |     io.println("Grace is invited: {invited("Grace")}")?
   |                                                       - also still owned here
23 | }
   | - also still owned where the block ends
   |
   = help: settle it first with `invited.release()`
```

And using `guests` after the closure took it is the familiar use-after-move,
here with `io.println("{guests.length()} guests")?` in place of the second
question:

<!-- guide: unchecked the error an edit of the program above produces -->
```
error[O-Move]: `guests` has already been moved
  --> capture_moved.lin:22:18
   |
11 |     let invited = [sink guests] |name: Str| {
   |                         ------ it was taken here
22 |     io.println("{guests.length()} guests")?
   |                  ^^^^^^ it was already taken, and a value is taken once
```

A look can take a name of its own too: `[seen = guests]` looks at `guests`
where it is, and the closure calls it `seen`. The value after `=` must be a
variable or a field, something that exists outside the closure.

**`[sink name = value]` gives the closure a value of its own.** The value can
be any expression, and `name` is what the closure calls it. The common case is
a copy, so the closure and the code around it each keep one. `copy(value)`
makes a second value of a type that allows it, and `@copyable` on a type
allows it; [Copying, settling and
sealing](04-copying-settling-and-sealing.md#copyable-values-that-are-safe-to-duplicate)
covers which types do. Here a café prints its menu prices in the currency the
till opened with, and the till changes currency during the day:

```linea
import std.io

// A currency is plain data, so `@copyable` lets the program copy it.
@copyable
struct Currency {
    symbol: Str,
    code: Str,
}

fn main() -> Result[UInt8, io.IoError] {
    var till = Currency { symbol = "€", code = "EUR" }
    // `sink menu = copy(till)` gives the closure a currency of its own, which
    // it calls `menu`. The till stays usable in `main`, and changing it later
    // leaves the menu's currency alone.
    let price_line = [sink menu = copy(till)] |item: Str, cents: UInt64| {
        io.println("{item}: {menu.symbol}{cents / 100}.{cents % 100}")
    }
    io.println("The till opens in {till.code}.")?
    price_line("tea", 250)?
    till = Currency { symbol = "£", code = "GBP" }
    price_line("scone", 375)?
    io.println("The till now takes {till.code}.")?
    .Ok(0)
}
```

```
The till opens in EUR.
tea: €2.50
scone: €3.75
The till now takes GBP.
```

Each of the other two forms fails here, for a different reason. `[sink till]`
takes the only till, so `main` can no longer read it:

<!-- guide: unchecked the error an edit of the program above produces -->
```
error[O-Move]: `till` has already been moved
  --> menu_moved.lin:18:36
   |
15 |     let price_line = [sink till] |item: Str, cents: UInt64| {
   |                            ---- it was taken here
18 |     io.println("The till opens in {till.code}.")?
   |                                    ^^^^^^^^^ it was already taken, and a value is taken once
```

`[menu = till]` looks at the till where it is, so the till cannot change while
the closure is still going to be called:

<!-- guide: unchecked the error an edit of the program above produces -->
```
error[O-Borrow]: this operation invalidates a place that a later observation still needs
  --> menu_look.lin:20:5
   |
20 |     till = Currency { symbol = "£", code = "GBP" }
   |     ^^^^ keep this place available until the last use of its observation
21 |     price_line("scone", 375)?
   |     ---------- the observation is still used here
```

A capture's form decides what the closure may outlive. A closure that looks at
a value with `[name]` must be finished with before that value changes or goes
away. A closure that owns everything it captured, through `sink`, depends on
nothing around it, so you can hand it to a function that keeps it, or keep it
in a struct.

### A closure that changes what it owns

A closure is called for reading by default: each call sees the same captures.
Write `inout` before the capture list, and each call may change what the
closure owns:

```linea
import std.io

fn main() -> Result[UInt8, io.IoError] {
    // `inout` before the capture list lets each call change what the closure
    // owns. `sink issued = 0` starts the closure's own counter at 0, and
    // `-> UInt64` gives it its type.
    var next_ticket = inout [sink issued = 0] || -> UInt64 {
        issued += 1
        issued
    }
    // A call that may change the closure is marked with `&`, like any other.
    let first = &next_ticket()
    let second = &next_ticket()
    io.println("Tickets {first} and {second} are called.")?
    .Ok(0)
}
```

```
Tickets 1 and 2 are called.
```

`||` is an empty parameter list, and `-> UInt64` gives the lambda's result type.
The counter lives inside the closure, and nothing outside can change it.

To read the counter once the closure is finished, `into_captures()` consumes
the closure and hands back a record with one field per capture, named by the
capture's alias:

```linea
import std.io

fn main() -> Result[UInt8, io.IoError] {
    var next_ticket = inout [sink issued = 0] || -> UInt64 {
        issued += 1
        issued
    }
    let _first = &next_ticket()
    let _second = &next_ticket()
    // `{ issued }` takes the record apart; `issued` is the closure's counter.
    let { issued } = next_ticket.into_captures()
    io.println("{issued} tickets issued")?
    .Ok(0)
}
```

```
2 tickets issued
```

The closure is gone after `into_captures()`, and the counter is yours again.
A server that counts connections in a closure reads its total the same way;
[Networking](09-networking.md#tcp-with-stdnet) shows it.

### A closure that changes a value of yours

`[inout name]` lends one of your variables to the closure to change, as `&name`
lends it to a function. The closure must be called `inout` too, because each
call may change what it was lent:

```linea
import std.io

fn main() -> Result[UInt8, io.IoError] {
    var total = 0
    // `[inout total]` lends `main`'s `total` to the closure, which adds each
    // parcel's weight to it.
    var weigh = inout [inout total] |grams: UInt64| {
        total += grams
    }
    &weigh(1200)
    &weigh(50)
    &weigh(800)
    io.println("{total} grams weighed")?
    .Ok(0)
}
```

```
2050 grams weighed
```

While the closure is still going to be called, `total` is lent to it, and
`main` may not use `total` by its own name. Print the running total between
two weighings:

```linea
    &weigh(1200)
    io.println("{total} grams so far")?
    &weigh(50)
```

<!-- guide: unchecked the error an edit of the program above produces -->
```
error[O-Borrow]: this operation uses a place lent `inout` to a value that is still used
  --> weigh_early.lin:11:18
   |
7  |     var weigh = inout [inout total] |grams: UInt64| {
   |                              ----- lent `inout` here
11 |     io.println("{total} grams so far")?
   |                  ^^^^^ this uses the place while it is lent
12 |     &weigh(50)
   |      ----- a value holding the lend is still used here
   |
   = help: a place lent `inout` is reached only through what holds the lend until that value's last use; use it after that, or through the closure
```

The lend ends at the closure's last call, which is why the program above could
print `total` after the third weighing. This is the rule Rust applies to a
closure that borrows a variable mutably: no one else touches the variable
until the closure is done. [Borrowing](06-borrowing.md#a-closure-that-lends-a-variable)
shows the same lend reaching through a chain of iterator operations.

### A closure that takes a pair apart

Some operations hand a closure a pair: `enumerate` pairs each item with its
position, and `zip` pairs the items of two sequences
([Iterating](05-iterating.md#pairs-from-enumerate-and-zip)). A lambda's
parameter may be a tuple pattern, `(i, x)`, which names both halves where the
closure begins, instead of a name followed by `._0` and `._1` in the body:

```linea
import std.io

fn main() -> Result[UInt8, io.IoError] {
    let scores = [10, 20, 30, 40]
    // `enumerate` pairs each score with its position. The first lambda's
    // pattern `(i, _)` looks at the pair and ignores the score; the second
    // takes the pair apart with `sink`, and `*x` reads the borrowed score.
    let weighted = scores
        .as_slice()
        .enumerate()
        .filter(|(i, _)| i % 2 == 0)
        .map(|sink (i, x)| (i + 1) * *x)
        .fold(0, |sink total, sink w| total + w)
    io.println("The weighted total is {weighted}.")?
    .Ok(0)
}
```

```
The weighted total is 100.
```

The pattern follows the convention the parameter would have had. `|(i, _)|`
is a `read` parameter, like the lambda `filter` expects, so it only looks at
the pair and `_` ignores the score. `|sink (i, x)|` takes the pair, as `map`
hands it over, and moves each half into its own name. The pattern needs a type
to take apart, which the operation supplies: a pair of position and score
here. The slice's scores stay borrowed, so `*x` reads one.

A pattern is for a lambda only. A declaration's parameter is a name, because
that name is the label a call can write:

```linea
import std.io

fn show((position, name): (UInt64, Str)) -> Result[(), io.IoError] {
    io.println("{position}. {name}")
}

fn main() -> Result[UInt8, io.IoError] {
    show((1, "ada"))?
    .Ok(0)
}
```

<!-- guide: first 1 diagnostic -->
```
error[S-Params]: a parameter is a name
 --> pair_parameter.lin:3:9
  |
3 | fn show((position, name): (UInt64, Str)) -> Result[(), io.IoError] {
  |         ^ a declaration parameter's name is the label a call writes; take the pair apart in the body
```

Names the pattern would have bound are undefined in the body, so more errors
follow this one. Take the pair as one parameter and open it with a `let`:

```linea
import std.io

// A declaration parameter is a name, because a call can write it as a label.
// The body takes the pair apart with a `let`.
fn show(sink entry: (UInt64, Str)) -> Result[(), io.IoError] {
    let (position, name) = entry
    io.println("{position}. {name}")
}

fn main() -> Result[UInt8, io.IoError] {
    show((1, "ada"))?
    .Ok(0)
}
```

```
1. ada
```

### If you know Rust

| Linea | Rust |
| --- | --- |
| `[x] \|a\| …` | a closure that borrows `x` |
| `[sink x] \|a\| …` | `move \|a\| …` |
| `[sink y = copy(x)] \|a\| …` | `let y = x.clone(); move \|a\| …` |
| a closure called for reading | `Fn` |
| `inout [ … ] \|a\| …`, called as `&f(a)` | `FnMut`, called through `&mut f` |
| `inout [inout x] \|a\| …` | an `FnMut` closure that borrows `x` mutably |
| `F: fn(a: A) -> B` | `F: Fn(A) -> B` |
| `mem.Closure[fn(a: A) -> B, Alloc]` | `Box<dyn Fn(A) -> B>`, with the allocator named |

Every lambda has a type of its own, as in Rust, so an array or a `Vec` cannot
hold two closures that captured different things. `mem.Closure` keeps any
closure behind one type, in memory from an allocator you choose; because it
involves an allocator, [Memory](07-memory.md#keeping-a-closure-memclosure)
covers it. [Networking](09-networking.md) passes closures to an HTTP router
and to a streamed response.

## Handing a function to `Option` and `Result`

A function that may have no answer returns an `Option`: `.Some(value)`, or
`.None` when there is nothing. One that can fail returns a `Result`: `.Ok(value)`,
or `.Err(error)` saying why ([Errors](03-errors.md) covers both). Both take
functions and closures as arguments, which saves a `match` when you only want
to change the value inside:

```linea
import std.io

// The menu prices the drinks it knows, and answers `.None` for any other.
fn price_of(drink: Str) -> Option[UInt64] {
    if drink == "tea" {
        .Some(250)
    } else if drink == "latte" {
        .Some(370)
    } else {
        .None
    }
}

fn main() -> Result[UInt8, io.IoError] {
    let member_discount = 10
    for drink in ["latte", "cocoa"] {
        // `map` hands the price inside a `.Some` to the lambda and wraps what it
        // returns; a `.None` passes through without calling it.
        let member_price = price_of(drink).map([member_discount] |sink cents| cents - cents * member_discount / 100)
        io.println("{drink} for members: {member_price:?}")?
    }
    // `Result.map` does the same for the value inside an `.Ok`.
    let extra_shots = "2".parse[UInt64]().map(|sink shots| shots * 60)
    io.println("extra shots: {extra_shots:?}")?
    // `and_then` runs a step that can fail itself, and passes a failure through.
    let order = price_of("tea").and_then(|sink cents| if cents <= 300 { .Some(cents + 40) } else { .None })
    io.println("tea to take away: {order:?}")?
    // `unwrap_or_else` calls the lambda only when there is no value.
    let cocoa = price_of("cocoa").unwrap_or_else(|| 300)
    io.println("cocoa: {cocoa}")?
    .Ok(0)
}
```

```
latte for members: Some(333)
cocoa for members: None
extra shots: Ok(120)
tea to take away: Some(290)
cocoa: 300
```

| Operation | On `Option` | On `Result` |
| --- | --- | --- |
| `map(f)` | `.Some(f(value))`, or `.None` | `.Ok(f(value))`, or the same `.Err` |
| `and_then(f)` | `f(value)`, itself an `Option`, or `.None` | `f(value)`, itself a `Result`, or the same `.Err` |
| `unwrap_or_else(f)` | the value, or `f()` | the value, or `f(error)` |
| `map_err(f)` | — | the same `.Ok`, or `.Err(f(error))` |

A lambda handed the value takes it with `sink`: the value moves out of the
`Option` or `Result` and into the lambda. These are Rust's `Option::map`,
`and_then` and `unwrap_or_else`. [Errors](03-errors.md#converting-at-one-call-with-map_err-and-reporting-from-main)
puts `map_err` to work, and [Iterating](05-iterating.md) hands functions to
the operations that walk a collection.

## What you have seen

- `x.op()` calls an operation of `x`'s type or of a trait in scope; a free
  function is called as `f(x)`.
- `Type.op(x)` and `Trait.op(x)` spell a call out when you need to say whose
  operation you mean; `Type.op` also reaches the traits the type implements.
- `&x.op()` marks a call that changes `x`; the compiler insists on the mark
  when the receiver is `inout` and refuses it otherwise.
- A bound such as `T: Priced` brings the trait's operations into reach.
- A type's own operation wins over a trait's of the same name, and
  `[N-Shadowed]` warns you when that hides an implementation.
- `x.f()` never calls a field; `(x.f)()` calls the function a field holds.
- `f[T](x)` and `x.op[T]()` name a type argument the call cannot work out.
- `@derive(Equatable, Debug)` and the like write a trait's implementation from
  a type's fields; write the `impl` by hand when field by field is wrong.
- A function is a value; labels in a function type are for reading and named
  calls, not part of the type. `alias Name = Type` gives a long type a second
  name.
- A closure lists its captures: `[x]` looks, `[sink x]` takes,
  `[sink y = copy(x)]` takes a copy, and `[inout x]` lends `x` for the closure
  to change. `inout` before the list lets a closure change what it owns or was
  lent.
- A lambda's parameter may be a tuple pattern, `|sink (i, x)|`, which takes a
  pair apart where the closure begins; a declaration's parameter is always a
  name.
- `map`, `and_then` and `unwrap_or_else` hand the value inside an `Option` or
  `Result` to a function.

Next: [Errors](03-errors.md) — `Result`, `Option`, `?`, `let … else`, and
newtypes that carry a range check.
