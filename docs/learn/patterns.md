# Patterns the standard library repeats

The same few shapes turn up across the standard library, and once you know
them a new module reads like an old one. Each shape below is a line or two of
code, and a link to the section that teaches it with a program you can run.

## Settling what an operation hands back

An operation that can fail either hands back what you gave it, or owns
something you must settle. Four endings cover almost every case. Turn a
refused insert or push into its reason, dropping what it handed back:

<!-- guide: excerpt docs/learn/03-errors.md -->
```linea
let _earlier = &bookings.insert(room, nights).settled()?
```

Gather a chain into a new `Vec`; `else` handles the refusal and `iterator: _`
drops the finished chain:

<!-- guide: excerpt docs/learn/05-iterating.md -->
```linea
let { values: names, iterator: _ } = order.as_slice().map(|sink line| copy(line.item)).collect().settled() else |_| {
    return .Ok(1)
}
```

Schedule the ending of a value that must be released, beside the value:

<!-- guide: excerpt docs/learn/06-borrowing.md -->
```linea
defer station.release()
```

Empty a vector or a drain, then free it; a nonempty one comes back as `Err`:

<!-- guide: excerpt docs/learn/05-iterating.md -->
```linea
match pending.finish() {
    Ok(_) => {},
    Err(_) => panic("a payment was left in the queue"),
}
```

`settled()` is taught in [Errors](03-errors.md#failures-that-hand-a-value-back),
`defer` and `release()` in [Copying, settling and
sealing](04-copying-settling-and-sealing.md#release-the-ending-you-do-not-have-to-think-about),
and `finish()` in [Iterating](05-iterating.md#emptying-a-vec-pop-and-finish)
and [Why `finish()` ends a lent walk](05-iterating.md#why-finish-ends-a-lent-walk).

## Draining a linear collection

A drain hands out items that must each be consumed. Bind it, walk it lent with
`for x in &pending`, and settle it with `finish()`. The walk may stop early,
and the items it did not reach stay in `pending` for a second walk:

<!-- guide: excerpt docs/learn/05-iterating.md -->
```linea
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
```

`for payment in queue.drain()` is refused when the items are linear
(`[O-LinearWalk]`), because the walk would abandon a drain that may still hold
items. [Draining, and walks that
lend](05-iterating.md#draining-and-walks-that-lend) teaches the idiom with a
program you can run.

## Walking two things at once

`enumerate` pairs each item with its position and `zip` pairs the items of two
sequences. A `for` takes each pair apart with a tuple pattern:

<!-- guide: excerpt docs/learn/05-iterating.md -->
```linea
for (i, item) in order.as_slice().enumerate() {
    io.println("{i + 1}. {*item}")?
}
// `zip` pairs the items of two sequences and stops when either ends.
for (item, price) in order.as_slice().zip(cents.as_slice()) {
    io.println("{*item} costs {*price} cents")?
}
```

[Iterating](05-iterating.md#pairs-from-enumerate-and-zip) shows both.

## Grouping values by position

A tuple groups two to eight values without naming a struct, and a pattern
takes it apart:

<!-- guide: excerpt docs/learn/01-linea-in-an-hour.md -->
```linea
let (lo, hi) = bounds(prices)
```

[Linea in an hour](01-linea-in-an-hour.md#tuples) introduces tuples; use a
struct when the parts deserve names.

## Serving each connection

`net.serve` is the accept loop. You write what happens to one connection, and
`serve` calls it for each one, closing the listener on every way out:

<!-- guide: excerpt docs/learn/09-networking.md -->
```linea
let ended = net.serve(listener, &handler, connections: .Some(2))
```

A handler that is a closure can keep state across connections, and
`into_captures()` hands it back ([Serving each connection with
`net.serve`](09-networking.md#serving-each-connection-with-netserve)).

## Reading one input from a request

An HTTP handler names each input as a parameter, and the router answers the
request with the refusal when an input cannot be read. The [JSON echo
server](../../examples/http-json-echo/main.lin) greets the name in its path:

<!-- guide: excerpt examples/http-json-echo/main.lin -->
```linea
// `http.Path[Str]` reads the route's only path value, `{name}`, which the
// router has percent-decoded, and `.value` is the text.
fn greet(inout app: App, name: http.Path[Str], request: http.Request) -> Result[http.Response, http.Error] {
    app.logger.info("greeting", log.field("name", name.value))
    // `http.json` encodes the greeting, escaping any quote in the name.
    http.json(request, Greeting { hello = copy(name.value) })
}
```

`http.Path`, `http.Query`, `http.Json` and `http.Form` are the extractors the
library offers, and a type of your own can implement `http.Extract`
([Networking](09-networking.md#extractors)).

## Laying out a value in text

A colon after an interpolated value lays it out: a width and an alignment, zero
padding, or decimal places.

<!-- guide: excerpt docs/learn/08-text.md -->
```linea
io.println("{line.item:<10}{line.quantity:>4}{line.price:>8.2}")?
```

[Text](08-text.md#format-specs-laying-a-value-out) lists the specs and the
errors for a spec the value cannot take.

## Keeping state and logging around a router

`http.logged` wraps a handler so every request leaves one log line, and
`http.listen_and_serve` owns the state your routes share, given as `state:`,
and lends it to the route that answers each request. The [countdown
server](../../examples/countdown-server/main.lin) does both:

<!-- guide: excerpt examples/countdown-server/main.lin -->
```linea
let server = http.logged(copy(logger), router)
let app = App { logger = copy(logger) }
```

<!-- guide: excerpt examples/countdown-server/main.lin -->
```linea
let finished = http.listen_and_serve(net.loopback(options.port), server, state: app, limits: limits) else |error| {
    logger.error("serving stopped", log.field("error", error))
    return 1
}
```

[Networking](09-networking.md#shared-state) teaches the state and
[Logging](09-networking.md#logging) the middleware.

## Building a value from another

`..` fills in every field you do not write from another value of the same
type, so a change to one field reads as one line:

<!-- guide: excerpt docs/learn/01-linea-in-an-hour.md -->
```linea
let oat = Order { oat_milk = true, ..flat_white }
```

[Linea in an hour](01-linea-in-an-hour.md#defaults-and-struct-update) shows the
update with `Default`.

## The caller chooses the memory

Anything that allocates takes an allocator as an argument, and a container
names it in its type:

<!-- guide: excerpt docs/learn/01-linea-in-an-hour.md -->
```linea
var basket: Vec[Str] = Vec.new()
```

[Memory](07-memory.md#an-allocator-is-an-argument) says why the caller always
chooses.

## Declaring command-line options and commands

`std.cli` reads process arguments against a command schema. The schema
declares each flag, option and positional once; parsing answers a matches view
of what was given, and the same schema writes the `--help` text:

```linea
import std.cli
import std.env
import std.io

fn main() -> Result[UInt8, io.IoError] {
    defer var cmd = cli.Command.new("notes", "Manage personal notes")
    &cmd.flag("loud", "--loud", "shout the summary", short: .Some("-l"))
    &cmd.option("format", "--format", "table or json", default: .Some("table"))
    &cmd.positional("title", "note title", required: false)

    // `parse_args` reads the process arguments against the schema; a usage
    // error comes back as a `cli.CliError` that prints as a sentence.
    defer let matches = cmd.parse_args(env.args()) else |error| {
        io.eprintln("notes: {error}")
        return .Ok(2)
    }
    if matches.is_help() {
        defer let help = cmd.format_help(borrow matches)
        io.print("{help}")?
        return .Ok(0)
    }
    let title = matches.positional("title") else {
        "untitled"
    }
    // `option` answers the schema's default when `--format` is not given.
    let format = matches.option("format").unwrap()
    io.println("{title} as {format}, loud: {matches.flag("loud")}")?
    .Ok(0)
}
```

```text
untitled as table, loud: false
```

Run with `--help`, the program prints the help `format_help` writes from the
schema:

<!-- guide: unchecked the output of the program above run with --help -->
```text
usage: notes [title] [options]

Manage personal notes
options:
  -l, --loud          shout the summary
  --format <value>    table or json (default: table)
```

Flags, options with defaults, optional and variadic positionals, and
subcommands keep their definitions in one place. The [notes example](../../examples/notes/)
builds a multi-command CLI with table rendering, JSON export, and config
defaults; [`bounded_echo`](../../examples/bounded_echo.lin) and
[`tcp_echo`](../../examples/tcp_echo.lin) demonstrate servers and clients with
subcommands, options, and variadic trailing arguments.
