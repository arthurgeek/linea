# Text

Linea has two kinds of text, and knowing which one you hold answers most
questions about it:

| Type | What it is | Where it comes from |
| --- | --- | --- |
| `Str` | a view of UTF-8 text that something else owns | string literals, slices of other text, `String.view()` |
| `String[A]` | UTF-8 text that owns its bytes, allocated from `A` | text you build or read at run time |

This is Rust's `&str` and `String`. A `Str` is cheap to pass around and copy;
a `String` owns memory, so it is released like any other owner
([Memory](07-memory.md)). Both always hold valid UTF-8, and both are in the
prelude.

This chapter covers both kinds, then the ways to write text in source:
interpolation, format specs, raw literals and multi-line literals.

## Views and owned text

```linea
import std.io

fn main() -> Result[UInt8, io.IoError] {
    let greeting = "Olá, mundo"
    // `scalars()` walks the text one Unicode scalar at a time.
    var letters: UInt64 = 0
    for _scalar in greeting.scalars() {
        letters += 1
    }
    io.println("{greeting.length()} bytes, {letters} scalars")?
    let comma = greeting.find(",").unwrap()
    let first = greeting.slice(0, comma).unwrap()
    io.println("first word: {first}")?

    defer var owned = String.new()
    if &owned.append(first).is_err() || &owned.append("!").is_err() {
        return .Ok(1)
    }
    io.println(owned.view())?
    .Ok(0)
}
```

```
11 bytes, 10 scalars
first word: Olá
Olá!
```

`length()` counts bytes, not characters: `á` takes two. `find` and `slice`
work in byte positions too, and `slice` answers `.None` if a position falls
inside a character, so a `Str` can never hold half of one. `first` is a view
into the literal; `owned` is a `String` that copies bytes into memory from
`mem.system()`, and `owned.view()` lends them back out as a `Str`.

`scalars()` walks the text one Unicode scalar — one code point — at a time,
which is how you count them. A scalar is not always what a reader sees as one
character: an emoji with a skin tone, or a letter followed by a combining
accent, is several scalars. Walking text by user-perceived characters, called
grapheme clusters, is not available.

## Interpolation

Braces in a string literal insert a value:

```linea
import std.io

@(copyable, derive(Debug))
enum Weather {
    Sunny,
    Rain(UInt64),
}

fn main() -> Result[UInt8, io.IoError] {
    let city = "Lisbon"
    let high = 27
    let today = Weather.Rain(4)
    io.println("{city}: high of {high}, then {high - 5} tonight")?
    io.println("forecast: {today:?}, city as Debug: {city:?}")?
    io.println("braces are doubled: {{city}}")?
    io.println("tab\tquote\" backslash\\ and \u{2600}")?
    .Ok(0)
}
```

```
Lisbon: high of 27, then 22 tonight
forecast: Rain(4), city as Debug: "Lisbon"
braces are doubled: {city}
tab	quote" backslash\ and ☀
```

Any expression can go inside the braces, `{high - 5}` included. Without a
spec a value is written through its `Display` implementation, which numbers,
`Bool` and text have. `{today:?}` writes it through `Debug` instead, which a
type gets from `@derive(Debug)`, and which shows text in quotes. `{{` and `}}`
write a brace. The escapes are `\n`, `\t`, `\r`, `\0`, `\\`, `\"` and
`\u{…}` for any Unicode scalar by number.

### An interpolation is a value, not a `Str`

`"weather in {city}"` does not build a string in memory. It makes a small value
holding the text around the braces and the values inside them, and that value
knows how to write itself out. `io.println` accepts it directly. A function
that wants a `Str` does not:

```linea
import std.io

fn main() -> Result[UInt8, io.IoError] {
    let city = "Lisbon"
    var line = String.new()
    defer line.release()
    if &line.append("weather in {city}").is_err() {
        return .Ok(1)
    }
    io.println(line.view())?
    .Ok(0)
}
```

```
error[T-Mismatch]: expected `Str`, found `{interpolation Str}`
   --> notstr.lin:7:21
    |
7   |     if &line.append("weather in {city}").is_err() {
    |                     ^^^^^^^^^^^^^^^^^^^ expected `Str`, found `{interpolation Str}`
   ::: std/text/string.lin
406 |     pub fn append(inout self: Self, text: Str) -> Result[(), Oom] where carries() {
    |                                     ---- expected because of this parameter
```

Building text would need memory, and in Linea nothing allocates unless you
say where from. So you write the interpolation into something that holds text.
A `String` is a writer, and `Display.fmt(value, &writer)` writes any
displayable value into one:

```linea
import std.io

fn main() -> Result[UInt8, io.IoError] {
    let city = "Lisbon"
    defer var line = String.new()
    // An interpolation writes itself into any writer, and a String is one.
    if Display.fmt("weather in {city}", &line).is_err() {
        return .Ok(1)
    }
    io.println(line.view())?
    .Ok(0)
}
```

```
weather in Lisbon
```

When you just want an owned `String` of the result, `fmt.render_owned` does
both steps:

```linea
import std.fmt
import std.io

fn main() -> Result[UInt8, io.IoError] {
    let city = "Lisbon"
    let high = 27
    defer let summary = fmt.render_owned("{city} reaches {high} degrees") else |_| {
        return .Ok(1)
    }
    io.println("{summary.length()} bytes: {summary.view()}")?
    .Ok(0)
}
```

```
25 bytes: Lisbon reaches 27 degrees
```

Because an interpolation implements `Display`, a function of your own can
take one. Ask for `D: Display`, and the caller may pass a number, text, or
a whole interpolation:

```linea
import std.io

// `D: Display` accepts anything `{…}` can write: a number, text, or a whole
// interpolation.
fn announce[D: Display](message: D) -> Result[(), io.IoError] {
    io.println("*** {message} ***")
}

fn main() -> Result[UInt8, io.IoError] {
    let city = "Lisbon"
    announce(27)?
    announce(city)?
    announce("sunny in {city}")?
    .Ok(0)
}
```

```
*** 27 ***
*** Lisbon ***
*** sunny in Lisbon ***
```

`io.println` is written the same way, which is why it accepts both `"text"`
and `"{value}"`.

### An interpolation looks at what it writes

An interpolation looks at a variable where it is, as a view does
([Borrowing](06-borrowing.md)); it does not take or copy it. So any value that
implements `Display` or `Debug` can be written, including one that must be
settled:

```linea
import std.io

// `Forecast` owns its city's name, so it must be released and cannot be copied.
@derive(Debug, Release)
struct Forecast {
    city: String,
    high: Int64,
}

fn main() -> Result[UInt8, io.IoError] {
    let city = "Lisbon".to_owned() else |_| {
        return .Ok(1)
    }
    defer let forecast = Forecast { city, high = 27 }
    // The interpolation looks at `forecast` where it is; nothing is copied.
    io.println("today: {forecast:?}")?
    io.println("{forecast.city.view()} reaches {forecast.high} degrees")?
    .Ok(0)
}
```

```
today: Forecast { city: "Lisbon", high: 27 }
Lisbon reaches 27 degrees
```

`forecast` owns memory and cannot be copied, and the interpolation still
writes it: it only looks. Like any view, the interpolation must be used before
`forecast` is released or changed; here that is guaranteed, because it is
written straight to `io.println`.

A value computed inside the braces, such as `{warmer(high)}`, has no variable
to look at, so the interpolation keeps the computed value itself. That is fine
for a number or a `Str`. It is not for a value that must be settled, because an
interpolation cannot release anything. Write a function's owned `String`
straight into an interpolation:

```linea
import std.fmt
import std.io

// `title` builds owned text, which its caller must release.
fn title(city: Str) -> String {
    fmt.render_owned("Weather in {city}").unwrap()
}

fn main() -> Result[UInt8, io.IoError] {
    io.println("== {title("Lisbon")} ==")?
    .Ok(0)
}
```

```
error[O-Leak]: this linear `String[mem.SystemAllocator]` is never settled
  --> interp_owned_bad.lin:10:21
   |
10 |     io.println("== {title("Lisbon")} ==")?
   |                     ^^^^^^^^^^^^^^^ nothing can take what this yields
   |
   = help: bind it with `let`, or give it to something that takes it
```

The help says what to do: bind the value with `let`, release it when you are
done, and let the interpolation look at the variable:

```linea
import std.fmt
import std.io
import std.mem

// `title` builds owned text, which its caller must release.
fn title(city: Str) -> Result[String, mem.Oom] {
    fmt.render_owned("Weather in {city}")
}

fn main() -> Result[UInt8, io.IoError] {
    defer let heading = title("Lisbon") else |_| {
        return .Ok(1)
    }
    io.println("== {heading.view()} ==")?
    .Ok(0)
}
```

```
== Weather in Lisbon ==
```

### A temporary lasts until the end of its statement

Some operations look at their arguments rather than taking them, and keep
looking afterwards. A log field is one. `std.log` writes log lines:
`log.to_stderr(minimum: .Info)` makes a logger to standard
error, `logger.info(message, fields)` writes a line, and `log.field("port",
port)` builds a field for it ([Networking](09-networking.md#logging) covers
logging). The field holds a view of `port` until the line is logged. When the
argument is a computed value rather than a variable, such as `port + 1`, there
is nothing for the view to point at once the statement is over. Linea keeps such a **temporary** until
the end of the statement it is written in, and no longer:

```linea
import std.log

fn main() -> UInt8 {
    let logger = log.to_stderr(minimum: .Info)
    let port: UInt16 = 8080
    // A field borrows its value; `port + 1` lives only until this statement ends.
    let fields = log.field("port", port + 1)
    logger.info("listening", fields)
    0
}
```

```
error[O-Temporary]: a value borrowing a temporary is used after the temporary's statement
 --> log_temp.lin:7:36
  |
7 |     let fields = log.field("port", port + 1)
  |                                    ^^^^^^^^ this temporary ends with its statement
8 |     logger.info("listening", fields)
  |                              ------ and a value borrowing it is used here
  |
  = help: bind the value with `let` first, and borrow the binding
```

Write it in one statement, `logger.info("listening", log.field("port", port + 1))`,
and the temporary lives exactly as long as it is needed. To keep the fields for
later, bind the value first, `let next = port + 1`, and pass `next`: the field
then looks at a variable, which lives as long as the block. This is the same
rule Rust uses for temporaries in a statement.

## Format specs: laying a value out

A colon after the value lays it out: a width, an alignment, a fill, zero
padding, a sign, or a number of decimal places:

```linea
import std.io

@copyable
struct Line {
    item: Str,
    quantity: UInt64,
    price: Float64,
}

fn main() -> Result[UInt8, io.IoError] {
    let lines: [Line; 3] = [
        .{ item = "coffee", quantity = 2, price = 2.5 },
        .{ item = "croissant", quantity = 1, price = 1.75 },
        .{ item = "jam", quantity = 12, price = 0.4 },
    ]
    io.println("{"item":<10}{"qty":>4}{"price":>8}")?
    for line in lines {
        io.println("{line.item:<10}{line.quantity:>4}{line.price:>8.2}")?
    }
    io.println("{"":-^22}")?
    let day = 7
    let month = 3
    let change = 3
    io.println("date {day:02}/{month:02}, stock change {change:+}, {"thanks":*^12}")?
    .Ok(0)
}
```

```
item       qty   price
coffee       2    2.50
croissant    1    1.75
jam         12    0.40
----------------------
date 07/03, stock change +3, ***thanks***
```

A spec is written `[[fill]align][+][0][width][.precision][?]`, every part
optional:

| Spec | Meaning | Example |
| --- | --- | --- |
| `:10` | at least 10 columns; numbers go right, everything else left | `{count:4}` |
| `:<10`, `:>10`, `:^10` | left, right or centre in 10 columns | `{item:<10}` |
| `:*^12` | centre, padding with `*` | `{"thanks":*^12}` |
| `:02` | pad a number with zeros to 2 digits | `{day:02}` → `07` |
| `:+` | write `+` before a number that is not negative | `{change:+}` → `+3` |
| `:.2` | two digits after a `Float64`'s point | `{price:.2}` → `2.50` |
| `:?` | write through `Debug`; combines with the rest, as in `:>12?` | `{today:?}` |

Width counts Unicode scalars, so `"café"` takes four columns. A value wider
than its width is written whole. Parts that make no sense for the value are
refused rather than ignored:

```linea
import std.io

fn main() -> Result[UInt8, io.IoError] {
    let item = "croissant"
    let quantity = 12
    io.println("{item:.3} x {quantity:.2}")?
    .Ok(0)
}
```

```
error[T-Format]: `Str` is not a Float64, so its format spec cannot ask for a precision
 --> spec_bad.lin:6:18
  |
6 |     io.println("{item:.3} x {quantity:.2}")?
  |                  ^^^^ a precision counts the digits after a Float64's point
error[T-Format]: `Int64` is not a Float64, so its format spec cannot ask for a precision
 --> spec_bad.lin:6:30
  |
6 |     io.println("{item:.3} x {quantity:.2}")?
  |                              ^^^^^^^^ a precision counts the digits after a Float64's point
```

Rust would truncate the text to three characters; Linea asks you to say that
with `slice`.

The spec's numbers are written in the literal. A width chosen while the
program runs goes through a `fmt.Spec` value instead: `fmt.Spec.padded(width)`
pads to `width` columns, its other fields choose the alignment, fill, sign and
precision, and `fmt.write_display(value, spec, &writer)` writes a value laid
out that way. Here the longest item sets the column's width:

```linea
import std.fmt
import std.io

fn main() -> Result[UInt8, io.IoError] {
    let items = ["coffee", "croissant", "jam"]
    // The longest name sets the column's width, so it is known only at run time.
    var width = 0
    for read item in items {
        if item.length() > width {
            width = item.length()
        }
    }
    // `spec` is `{…:<width}`, with the width chosen while the program runs.
    let spec = fmt.Spec { align = .Some(.Left), ..fmt.Spec.padded(width) }
    for read item in items {
        defer var cell = String.new()
        if fmt.write_display(item, spec, &cell).is_err() {
            return .Ok(1)
        }
        io.println("{cell.view()}|")?
    }
    .Ok(0)
}
```

```
coffee   |
croissant|
jam      |
```

## Reading text as a value

`parse` goes the other way: `"8080".parse[UInt16]()` reads text as a number
and answers a `Result` whose error, a `text.ParseError`, says which byte was
wrong. Every integer type and `Float64` can be read this way, and
[Errors](03-errors.md) uses `parse` throughout. A type of your own joins them
by implementing the `text.Parse` trait:

```linea
import std.io
import std.text

@(copyable, derive(Debug))
struct Time {
    hours: UInt8,
    minutes: UInt8,
}

// With `Parse`, `parse[Time]()` reads a `Time` the way it reads a number.
// The `ParseError` says which byte is wrong.
impl text.Parse for Time {
    fn parse(text: Str) -> Result[Time, text.ParseError] where carries() {
        let colon = text.find(":") else {
            return .Err(.Syntax(text.length()))
        }
        let hours = text.slice(0, colon).unwrap().parse[UInt8]()?
        let minutes = text.slice(colon + 1, text.length()).unwrap().parse[UInt8]()?
        if hours > 23 {
            return .Err(.Syntax(0))
        }
        if minutes > 59 {
            return .Err(.Syntax(colon + 1))
        }
        .Ok(.{ hours, minutes })
    }
}

fn main() -> Result[UInt8, io.IoError] {
    let alarms = ["07:30", "7h30", "25:00"]
    for alarm in alarms {
        match alarm.parse[Time]() {
            Ok(time) => io.println("{alarm}: {time:?}")?,
            Err(error) => io.println("{alarm}: {error:?}")?,
        }
    }
    .Ok(0)
}
```

```
07:30: Time { hours: 7, minutes: 30 }
7h30: Syntax(4)
25:00: Syntax(0)
```

`Parse.parse` takes the text and answers the value or a `text.ParseError`.
Inside it, `?` passes up the errors of the numbers it reads, which already
point at the right byte. `where carries()` promises that a `Time` points into
nothing: it holds two numbers, not a view of the text. Rust's `FromStr` and
`str::parse` work the same way.

An implementation writes a trait's operation with the parameter names the
trait gives it, as `From`'s `from` takes `source` in
[Errors](03-errors.md#-converts-errors-with-from). `Parse` declares
`parse(text: Str)`, so the parameter here is `text` too. Rename it to
`written` throughout and the implementation is refused:

<!-- guide: unchecked the error an edit of the program above produces -->
```
error[T-Impl]: `Parse` declares `parse`'s parameter `text`, and this declares it `written`
  --> time_renamed.lin:13:8
   |
13 |     fn parse(written: Str) -> Result[Time, text.ParseError] where carries() {
   |        ^^^^^ name it what the signature names it
```

So one name does two jobs in `parse`. In a type, such as `text.ParseError` in
the signature, `text` names the `std.text` module. As a value, inside the
body, `text` is the parameter, which shadows the module there: `text.find(":")`
searches the text being parsed.

## Raw literals: text exactly as written

Routes, JSON and Windows paths are full of braces, quotes and backslashes. A
raw literal, `r"…"`, holds its text exactly: no escapes, no interpolation.

```linea
import std.io

fn main() -> Result[UInt8, io.IoError] {
    let route = r"GET /forecast/{city}"
    let folder = r"C:\weather\today"
    let json = r#"{"city":"Lisbon","high":27}"#
    io.println(route)?
    io.println(folder)?
    io.println(json)?
    io.println("{json.length()} bytes")?
    .Ok(0)
}
```

```
GET /forecast/{city}
C:\weather\today
{"city":"Lisbon","high":27}
27 bytes
```

Which form to use depends on the quotes in the text:

- `r"…"` for text without a `"`: a route, a path, a pattern.
- `r#"…"#` for text that contains `"`, such as JSON. It ends at the first `"#`.
- `r##"…"##`, and so on up to eight hashes, for text that itself contains
  `"#`.

The braces in `r"GET /forecast/{city}"` are text, which is what an HTTP route
pattern needs: the router, not the compiler, fills in `{city}`. Leave the `r`
off and the compiler interpolates a local `city` if there is one, so the two
lines below print different things:

```linea
import std.io

fn main() -> Result[UInt8, io.IoError] {
    let city = "Lisbon"
    io.println(r"GET /forecast/{city}")?
    io.println("GET /forecast/{city}")?
    .Ok(0)
}
```

```
GET /forecast/{city}
GET /forecast/Lisbon
```

Rust's raw strings work the same way.

## Multi-line text

Text of several lines is written as a run of lines that each start with `\\`:

```linea
import std.io

// Every line starts with `\\`; the lines are joined with line breaks.
let usage =
    \\usage: forecast CITY [DAYS]
    \\  CITY  the city to forecast, such as "Lisbon"
    \\  DAYS  how many days ahead, 1 to 7

// Braces in a `\\` line are text, so the part that names someone is written apart.
let advice =
    \\Rain is expected tomorrow.
    \\Take an umbrella, and "stay dry".

fn main() -> Result[UInt8, io.IoError] {
    io.println(usage)?
    let name = "Ada"
    defer var letter = String.new()
    // `Display.fmt` writes the greeting, then the fixed text, into one String.
    if Display.fmt("Dear {name},\n{advice}", &letter).is_err() {
        return .Ok(1)
    }
    io.println(letter.view())?
    .Ok(0)
}
```

```
usage: forecast CITY [DAYS]
  CITY  the city to forecast, such as "Lisbon"
  DAYS  how many days ahead, 1 to 7
Dear Ada,
Rain is expected tomorrow.
Take an umbrella, and "stay dry".
```

Each `\\` line holds the rest of its line exactly, like a raw literal: quotes,
backslashes and braces are text. The indentation before `\\` is not part of
the text, so the literal can sit indented in your code. The lines are joined
with line breaks, and there is none after the last one; end with an empty `\\`
line if you want one. This is Zig's multi-line string syntax.

Because braces are text in a `\\` line, a multi-line literal has no
interpolation: `\\Dear {name},` prints `{name}` as it is. When part of the text
changes, write the fixed part as a `\\` constant and the changing part with an
ordinary literal, and let `Display.fmt` write both into one `String`, as the
letter above does. `{advice}` interpolates the whole constant.

A multi-line literal is an ordinary `Str`, and it can be a module constant, as
`usage` and `advice` are. The [form letters example](../../examples/form_letters.lin)
fills a `\\` template from a JSON list of orders, and the
[TCP echo example](../../examples/tcp_echo.lin) keeps its usage text this way.

## Escaping text for HTML

A page that shows text a visitor typed must not let that text become markup. A
name such as `<script>` would otherwise run in every browser that opens the
page. `html.escaped(text)` replaces the five characters that matter, `&`, `<`,
`>`, `"` and `'`, with entities. It returns a small value that borrows the text,
allocates nothing, and writes the escaped form when something displays it, so it
sits inside an interpolation like any other value:

```linea
import std.html
import std.io

fn main() -> Result[UInt8, io.IoError] {
    let name = "Ada <ada@example.com>"
    let message = "I <3 \"Linea\" & it's fast"
    io.println("<li><b>{html.escaped(name)}</b>: {html.escaped(message)}</li>")?
    io.println("<a title=\"{html.escaped(message)}\">link</a>")?
    .Ok(0)
}
```

```
<li><b>Ada &lt;ada@example.com&gt;</b>: I &lt;3 &quot;Linea&quot; &amp; it&#39;s fast</li>
<a title="I &lt;3 &quot;Linea&quot; &amp; it&#39;s fast">link</a>
```

The same five characters make text safe as an element's content and inside a
quoted attribute whose value is plain text, such as `title`, `alt` or `value`,
in either kind of quote, so there is one function for both. Text
that already holds an entity is escaped again, `&amp;` becoming `&amp;amp;`,
because escaping cannot tell an entity from text that happens to look like one.
Escape each piece of untrusted text once, where it enters the markup, and write
the markup around it yourself.

To write into a `String` or any other `Writer` without an interpolation,
`html.escape(&writer, text)` appends the escaped text:

```linea
import std.html
import std.io

fn main() -> Result[UInt8, io.IoError] {
    let names = ["Ada", "<script>", "Tom & Jerry"]
    defer var page = String.new()
    if &page.append("<ul>").is_err() {
        return .Ok(1)
    }
    for name in names {
        if &page.append("<li>").is_err() || html.escape(&page, name).is_err() || &page.append("</li>").is_err() {
            return .Ok(1)
        }
    }
    if &page.append("</ul>").is_err() {
        return .Ok(1)
    }
    io.println(page.view())?
    .Ok(0)
}
```

```
<ul><li>Ada</li><li>&lt;script&gt;</li><li>Tom &amp; Jerry</li></ul>
```

`escaped` calls `escape`, so the two always agree. Neither makes text safe in
an attribute whose value is a URL (`href`, `src`, `action`), an event handler
(`onclick` and the other `on…` attributes) or a style (`style`):
`javascript:alert(1)` holds none of the five characters, and a browser decodes
the entities in `onclick="..."` before it runs the script. Nor is either enough
in an unquoted attribute or inside a `<script>` or `<style>` element. Keep
untrusted text out of those places. An HTTP handler answers a page with
`http.text` and `set_header("Content-Type", "text/html; charset=utf-8")`
([Networking](09-networking.md#handlers-return-responses)). The [welcome-back
server](../../examples/welcome_back.lin) escapes a name taken from the address.

## What you have seen

| You want | Write |
| --- | --- |
| a view of text | `Str`; slice with `line.slice(from, to)` |
| text you own and can grow | `String.new_in(allocator)`, then `&s.append(…)` |
| to count Unicode scalars (code points) | `for _scalar in text.scalars()` |
| a value inside text | `"{value}"`, or `"{value:?}"` for `Debug` |
| an interpolation in a `String` | `Display.fmt("…{value}…", &string)` |
| an interpolation as a new `String` | `fmt.render_owned("…")`, or `fmt.render_owned_in(allocator, "…")` |
| a function that takes any displayable value | `fn f[D: Display](value: D)` |
| a column, padding or decimals | `{value:>8}`, `{day:02}`, `{price:.2}` |
| a layout chosen at run time | `fmt.write_display(value, spec, &writer)` with a `fmt.Spec` |
| a view of a computed value past its statement | bind the value with `let` first; a temporary lasts to the end of its statement |
| a number or your own type from text | `"80".parse[UInt16]()`, `impl text.Parse for T` |
| braces or backslashes as text | `r"…"`, or `r#"…"#` when the text has a `"` |
| several lines | a run of `\\` lines |
| untrusted text in HTML | `"<p>{html.escaped(text)}</p>"`, or `html.escape(&writer, text)` |

Next: [Networking](09-networking.md) — TCP connections and HTTP servers.
