# Testing

[Linea in an hour](01-linea-in-an-hour.md#tests) showed the shape of a test:
a `test fn` beside the code, assertions followed by `?`, and `linea test` to run
them. This chapter covers what real tests need: helpers that build what several
tests share, tests that expect the program to stop, checking that every
allocation can fail safely, and testing an HTTP server without a network.

## Assertions

A `test fn` takes no arguments, and its body runs like any function's. Each
assertion answers a `Result`, and `?` ends the test at the first one that
fails:

| Assertion | Passes when |
| --- | --- |
| `testing.assert(condition, message)` | the `Bool` is `true` |
| `testing.assert_eq(actual, expected, message)` | the two values are equal; both are printed when they are not |
| `testing.assert_ok_eq(result, expected, message)` | the result is `.Ok` with that value |
| `testing.assert_err(result, message)` | the result is an `.Err` of any kind |

`assert_eq` needs the values' type to implement `Equatable` and `Debug`, which
`@derive(Equatable, Debug)` gives your own types; it compares whole values, enum
payloads included. For a shape check, write
`testing.assert(match read value { … }, message)`. A test's return type may be
left out; written in full, it is `-> Result[(), testing.Failure]`.

Here the three kinds of check test a function that reads the port out of an
address. Save it as `ports.lin` and run `linea test ports.lin`:

```linea
import std.io
import std.testing
import std.text

// Read the port after the colon in an address such as "localhost:8080".
fn port_of(address: Str) -> Result[UInt16, text.ParseError] {
    let colon = address.find(":") else {
        return .Err(.Syntax(address.length()))
    }
    address.slice(colon + 1, address.length()).unwrap().parse[UInt16]()
}

test fn the_port_follows_the_colon() {
    testing.assert_ok_eq(port_of("localhost:8080"), 8080, "the port of localhost:8080")?
}

test fn an_address_without_a_port_is_refused() {
    testing.assert_err(port_of("localhost"), "an address with no colon")?
}

// `match read` checks the error's shape: a `Syntax` error, at whatever byte.
test fn a_letter_in_the_port_is_a_syntax_error() {
    let refused = match port_of("localhost:80x0") {
        Ok(_) => return testing.assert(false, "a letter in the port was accepted"),
        Err(error) => error,
    }
    testing.assert(match read refused {
        Syntax(_) => true,
        _ => false,
    }, "a letter in the port is not a syntax error")?
}

fn main() -> Result[UInt8, io.IoError] {
    let port = port_of("localhost:8080").unwrap_or(80)
    io.println("connecting on port {port}")?
    .Ok(0)
}
```

```
ok    a_letter_in_the_port_is_a_syntax_error
ok    an_address_without_a_port_is_refused
ok    the_port_follows_the_colon

3 passed, 0 failed
```

The report lists the tests by name, in alphabetical order, not in the order
the file declares them. The third test takes the error out with a `match`
first, because a pattern names one level ([Errors](03-errors.md#when-to-keep-match)):
`match read refused` can then look at the error's variant.

## Helpers that tests share

Tests often need the same data: a sample order, a request, a configured
server. Build it once, in an ordinary function the tests call. Save this as
`receipt.lin`:

```linea
import std.io
import std.testing

struct Line {
    item: Str,
    cents: UInt64,
    quantity: UInt64,
}

fn total(lines: [Line; 3]) -> UInt64 {
    var sum = 0
    for read line in lines {
        sum += line.cents * line.quantity
    }
    sum
}

// The tests share one order, so it is built in one place. Only tests call
// this function, and it is not part of the program `linea build` makes.
fn sample_order() -> [Line; 3] {
    [
        .{ item = "coffee", cents = 250, quantity = 2 },
        .{ item = "croissant", cents = 175, quantity = 1 },
        .{ item = "jam", cents = 40, quantity = 12 },
    ]
}

test fn the_total_counts_every_line() {
    testing.assert_eq(total(sample_order()), 1155, "the sample order's total")?
}

test fn a_free_line_adds_nothing() {
    var order = sample_order()
    order[1].cents = 0
    testing.assert_eq(total(order), 980, "the order without the croissant")?
}

fn main() -> Result[UInt8, io.IoError] {
    let order: [Line; 3] = [
        .{ item = "tea", cents = 220, quantity = 1 },
        .{ item = "scone", cents = 300, quantity = 2 },
        .{ item = "butter", cents = 60, quantity = 1 },
    ]
    io.println("Total: {total(order)} cents")?
    .Ok(0)
}
```

```
ok    a_free_line_adds_nothing
ok    the_total_counts_every_line

2 passed, 0 failed
```

`sample_order` is an ordinary function, and two things about it are worth
knowing.

It does not trip the rule that an unused declaration is an error, because the
tests use it. Remove both tests, and it is reported like any other unused
function:

<!-- guide: unchecked the error an edit of the program above produces -->
```
error[M-Unused]: `testing` is never used
 --> receipt_notests.lin:2:12
  |
2 | import std.testing
  |            ^^^^^^^ remove the import
error[N-Unused]: `sample_order` is never used
  --> receipt_notests.lin:20:4
   |
20 | fn sample_order() -> [Line; 3] {
   |    ^^^^^^^^^^^^ call it, or name it with a leading `_`
```

And it is not part of the program. Every build checks the tests and their
helpers, so a helper that no longer compiles stops `linea build` too, but only
what `main` reaches is compiled into the program. Build it and list its
functions:

<!-- guide: unchecked a shell session, not the output of one program -->
```
$ linea build receipt.lin -O 0 -o receipt
$ nm receipt | grep -E "total|sample_order|testing|main"
0000000100003498 t _lin.main
000000010000363c t _lin.total
000000010000a2f0 T _main
```

`total` is there because `main` calls it; `sample_order`, the tests and
`std.testing` are not. (`-O 0` turns off optimisation, so that `total` is not
folded into `main` and you can see it.) So there is no `#[cfg(test)]` to write,
as there would be in Rust: a function only tests call is left out of the
program on its own, and a `use` or an `import` only tests need costs the
program nothing.

## Tests that expect the program to stop

Some mistakes are not errors to handle but bugs, and Linea stops the program
at them: an overflow, an index out of range, a `panic`. Writing `trap` after
`test` marks a test that passes only when its body stops the program:

```linea
import std.io
import std.testing

// A row holds 20 seats. Asking for a seat past the end is a mistake in the
// program, so it stops the program rather than answering a wrong seat.
fn seat_label(row: UInt8, seat: UInt8) -> UInt64 {
    if seat == 0 || seat > 20 {
        panic("a row has seats 1 to 20")
    }
    UInt64(row) * 100 + UInt64(seat)
}

test fn the_label_joins_row_and_seat() {
    testing.assert_eq(seat_label(3, 14), 314, "row 3, seat 14")?
}

// `test trap fn` marks a test that passes only when its body stops the program.
test trap fn seat_twenty_one_stops_the_program() {
    let _label = seat_label(3, 21)
}

fn main() -> Result[UInt8, io.IoError] {
    io.println("Your seat is {seat_label(12, 7)}.")?
    .Ok(0)
}
```

```
ok    seat_twenty_one_stops_the_program
ok    the_label_joins_row_and_seat

2 passed, 0 failed
```

Each test runs in its own process, so one that stops takes no other test with
it. A `test trap fn` that finishes normally fails; ask for seat 20 instead of 21:

<!-- guide: unchecked the output of an edited or partial program -->
```
FAIL  seat_twenty_one_stops_the_program
        expected the test to trap
ok    the_label_joins_row_and_seat

1 passed, 1 failed
```

## Every allocation can fail

A function that allocates can fail at each allocation, and each failure takes
a different path through it: the first `append` failing leaves nothing built,
the third leaves most of a line. The compiler already checks that every path
settles what it acquired. What it cannot check is that the function *handles*
each failure — that it passes the refusal up rather than, say, calling
`unwrap()` on it. `testing.each_allocation_failure` tries every one. Save this
as `banner.lin`:

```linea
import std.io
import std.mem
import std.testing

// The caller passes the allocator, so the caller decides where the banner lives.
fn banner[A: Allocator](allocator: A, title: Str) -> Result[String[A], mem.Oom] where carries(.Ok: allocator) {
    var line = String.new_in(allocator)
    // Release the line if a `?` leaves early; returning it skips this.
    defer line.release()
    &line.append("== ")?
    &line.append(title)?
    &line.append(" ==")?
    .Ok(line)
}

test fn a_banner_frames_its_title() {
    defer let heading = banner(mem.system(), "Daily report").unwrap()
    testing.assert_eq(heading.view(), "== Daily report ==", "the banner changed")?
}

// `each_allocation_failure` runs the body once to count the allocations it
// asks for, then once more for each of them with that one refused. Every run
// must end cleanly: with the refusal passed up, or with success.
test fn every_allocation_the_banner_asks_for_can_fail() {
    let attempts = testing.each_allocation_failure(
        mem.system(),
        |allocator| -> Result[(), mem.Oom] {
            let heading = banner(allocator, "Daily report")?
            heading.release()
            .Ok(())
        },
        testing.oom_is_a_refusal,
    )?
    testing.assert_eq(attempts, 3, "the banner asked for a different number of allocations")?
}

fn main() -> Result[UInt8, io.IoError] {
    defer let heading = banner(mem.system(), "Daily report") else |_| {
        return .Ok(1)
    }
    io.println(heading.view())?
    .Ok(0)
}
```

```
ok    a_banner_frames_its_title
ok    every_allocation_the_banner_asks_for_can_fail

2 passed, 0 failed
```

`each_allocation_failure` takes three arguments:

- the allocator every run really allocates from, here `mem.system()`. The
  caller chooses it, as for every function that allocates;
- the body, a lambda ([Calling
  things](02-calling-things.md#closures-functions-that-capture)) that takes
  the allocator to use and answers a `Result`. It is handed a
  `testing.RefusingAllocator`, which passes each request on to the first
  argument and refuses the one the run is testing;
- a function that says which errors count as a refusal. This body fails only
  with `mem.Oom`, so every error it returns is one, and
  `testing.oom_is_a_refusal` says so.

It runs the body once to count the allocations it asks for, then once more for
each of them, with that one refused. The run with nothing refused must
succeed; every other run must pass the refusal up or succeed without that
allocation. It answers how many allocations it tried, so the test can check
that too: `banner` allocates three times, so the body runs four times. `banner`
needed no change to be tested this way: it takes its allocator as an argument
([Memory](07-memory.md)).

A body that makes assertions of its own answers `Result[(), testing.Failure]`.
It reports a refused allocation with `testing.refused(message)`, and passes
`testing.Failure.is_refusal` as the third argument, so that a failed assertion
still fails the test. Add this test to `banner.lin`:

<!-- guide: unchecked the program is a partial listing or an edit of an earlier one -->
```linea
// Every run that builds the banner must build it right, whichever allocation
// was refused before it.
test fn every_banner_that_is_built_reads_right() {
    let _attempts = testing.each_allocation_failure(
        mem.system(),
        |allocator| -> Result[(), testing.Failure] {
            let heading = banner(allocator, "Daily report") else |_| {
                return .Err(testing.refused("the banner was refused"))
            }
            let reads_right = heading.view() == "== Daily report =="
            heading.release()
            testing.assert(reads_right, "the banner changed")
        },
        testing.Failure.is_refusal,
    )?
}
```

```
ok    a_banner_frames_its_title
ok    every_allocation_the_banner_asks_for_can_fail
ok    every_banner_that_is_built_reads_right

3 passed, 0 failed
```

The heading is released before the assertion, because a failed assertion
returns from the lambda, and the heading must not be left behind on that path.

Break `banner` by writing `&line.append(title).unwrap()` in place of
`&line.append(title)?`, and the run that refuses the second allocation stops
the program:

<!-- guide: unchecked the output of an edited or partial program -->
```
ok    a_banner_frames_its_title
FAIL  every_allocation_the_banner_asks_for_can_fail
        linea: panic: called Result.unwrap on Err at std/result/result.lin:394:23

1 passed, 1 failed
```

The location is the line inside the standard library's `unwrap` that stopped
the program; the `unwrap` to look for is the one in `banner`.

`each_allocation_failure` is built on `mem.AllocationLog`, which you can use
directly to refuse one chosen allocation. `mem.AllocationLog.open(backing, n)`
makes a log whose `allocator()` passes requests on to `backing` and refuses the
`n`th; `attempts()` counts the requests it saw, and `all_disposed()` checks
that everything it handed out was given back. The log keeps its records in
memory from `backing` too, so `open` answers a `Result`. Add this test to
`banner.lin`:

<!-- guide: unchecked the program is a partial listing or an edit of an earlier one -->
```linea
// `AllocationLog.open(mem.system(), 2)` refuses the second allocation its
// allocator is asked for. The test checks that `banner` passes the refusal up,
// and that the first allocation was given back on the way out.
test fn a_refused_second_allocation_leaves_nothing_behind() {
    defer let log = mem.AllocationLog.open(mem.system(), 2).unwrap()
    let refused = match banner(log.allocator(), "Daily report") {
        Ok(heading) => {
            heading.release()
            false
        },
        Err(_) => true,
    }
    testing.assert(refused, "the banner was built without its second allocation")?
    testing.assert_eq(log.attempts(), 2, "the banner went on after the refusal")?
    testing.assert(log.all_disposed(), "the first allocation was not given back")?
}
```

```
ok    a_banner_frames_its_title
ok    a_refused_second_allocation_leaves_nothing_behind
ok    every_allocation_the_banner_asks_for_can_fail

3 passed, 0 failed
```

The log is linear, so it is released like any other owner, and the result of
`banner` is matched rather than tested with `is_err()`, because on success it
holds a `String` that must be released.

## Testing a server

A router is a handler, so a test sends it a request. `http.new_request` builds a
request in an arena you provide, exactly as `serve` would, and the test hands
it to the router with a state of its own, which reads the extractors a
handler's parameters name and calls it. These tests are for the station
server of [Networking](09-networking.md#reading-inputs-sharing-state-and-logging);
add them to the end of `stations.lin`, with `import std.testing`,
`use http.Handler` and `use mem.Owner` at the top:

<!-- guide: unchecked the program is a partial listing or an edit of an earlier one -->
```linea
// The tests hand the handlers a state whose logger writes only errors, so the
// lines they log stay out of the test report.
fn quiet() -> App {
    .{ logger = log.to_stderr(minimum: .Error), readings = 0 }
}

// Build a request in an arena, as `serve` would, and send it through the routes.
test fn a_reading_is_recorded_and_counted() {
    defer var router: http.Router[App] = http.Router.new()
    routes(&router, "Weather stations report here.\n").unwrap()
    defer let arena = mem.Arena.open(mem.system(), size: 65536)
    var sent = http.new_request(arena.handle(), "POST", "/readings", body: r#"{"celsius":21,"sky":"clear"}"#, content_type: "application/json").unwrap()
    &sent.add_header("Authorization", "Bearer harbour").unwrap()
    var app = quiet()
    let response = &router.serve_http(&app, sent.request()).unwrap()
    testing.assert_eq(Str.from_bytes(response.body().unwrap()).unwrap(), r#"{"station":"harbour","sky":"clear","count":1}"#, "the answer changed")?
    testing.assert_eq(app.readings, 1, "the reading was not counted")?
}

// A request that names no station is refused before anything is counted.
test fn a_reading_without_a_station_is_refused() {
    defer var router: http.Router[App] = http.Router.new()
    routes(&router, "Weather stations report here.\n").unwrap()
    defer let arena = mem.Arena.open(mem.system(), size: 65536)
    let sent = http.new_request(arena.handle(), "POST", "/readings", body: r#"{"celsius":21,"sky":"clear"}"#, content_type: "application/json").unwrap()
    var app = quiet()
    let refused = match &router.serve_http(&app, sent.request()) {
        Ok(_) => return testing.assert(false, "a reading without a station was accepted"),
        Err(error) => error,
    }
    testing.assert_eq(refused.status(), http.Status.Unauthorized, "the status changed")?
    testing.assert_eq(app.readings, 0, "a refused reading was counted")?
}

// `recorded_body` runs a streamed body into the request's arena, so a test
// reads what a client would receive.
test fn the_outlook_streams_one_line_a_day() {
    defer var router: http.Router[App] = http.Router.new()
    routes(&router, "Weather stations report here.\n").unwrap()
    defer let arena = mem.Arena.open(mem.system(), size: 65536)
    let sent = http.new_request(arena.handle(), "GET", "/outlook?days=2", body: "").unwrap()
    var app = quiet()
    let body = &router.serve_http(&app, sent.request()).unwrap().recorded_body().unwrap()
    testing.assert_eq(Str.from_bytes(body.as_slice()).unwrap(), "day 1: sunny\nday 2: sunny\n", "the outlook changed")?
}

// A route that is a closure is reached the same way.
test fn the_root_answers_with_the_greeting() {
    defer var router: http.Router[App] = http.Router.new()
    routes(&router, "Weather stations report here.\n").unwrap()
    defer let arena = mem.Arena.open(mem.system(), size: 65536)
    let sent = http.new_request(arena.handle(), "GET", "/", body: "").unwrap()
    var app = quiet()
    let response = &router.serve_http(&app, sent.request()).unwrap()
    testing.assert_eq(Str.from_bytes(response.body().unwrap()).unwrap(), "Weather stations report here.\n", "the greeting changed")?
}
```

```
ok    a_reading_is_recorded_and_counted
ok    a_reading_without_a_station_is_refused
ok    the_outlook_streams_one_line_a_day
ok    the_root_answers_with_the_greeting

4 passed, 0 failed
```

A few things to notice:

- `quiet()` builds the state the tests share, with a logger that writes only
  errors, so the lines the handlers log do not clutter the test report.
- `&sent.add_header(name, value)` adds a header to a built request, and
  `content_type:` sets its `Content-Type`.
- `&router.serve_http(&app, request)` runs the router as `serve` does: it reads
  the extractors `record` names and calls it, and the test then reads
  `app.readings` to see what it changed.
- `response.recorded_body()` runs a streamed body into the arena, so a test can
  read what a client would receive.
- Every test goes through the router, so a handler's extractors, its path
  values and its refusals are exercised as `serve` exercises them. `use
  http.Handler` brings `serve_http` into scope.

No socket is opened, so these tests run anywhere, quickly. The [JSON echo
server](../../examples/http-json-echo/main.lin) and the [countdown
server](../../examples/countdown-server/main.lin) test every handler this way.

## Running tests

`linea test <path>` takes a file or a project directory; given a directory, it
runs the tests of every module beneath it. The report lists each test with
`ok` or `FAIL`, what a failing assertion said, and a count, and the command
exits with status 1 when any test failed, so a script or a CI job can rely on
it.

## What you have seen

- `testing.assert` and `testing.assert_eq` check conditions and whole values,
  and `testing.assert_ok_eq` and `testing.assert_err` check a `Result`; `?`
  ends a test at the first failure.
- A helper that only tests call is an ordinary function: it counts as used,
  and it is left out of the program.
- `test trap fn` marks a test that must stop the program.
- `testing.each_allocation_failure(allocator, body, is_refusal)` refuses each
  allocation in turn and checks that every one is handled.
- A handler is tested by calling it with a request from `http.new_request`,
  or through the router with `&router.serve_http`.

That is the end of the guide. [Errors the guide shows](errors.md) indexes
every error code the chapters show. The [language
definition](../linea-semantics.md) holds every rule the compiler enforces,
under the name its errors print, and the [examples](../../examples/) are
complete programs to read next.
