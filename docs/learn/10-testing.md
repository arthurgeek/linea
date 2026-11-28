# Testing

[Linea in an hour](01-linea-in-an-hour.md#tests) showed the shape of a test:
a `test "…"` beside the code, assertions followed by `?`, and `linea test` to run
them. This chapter covers what real tests need: helpers that build what several
tests share, tests that expect the program to stop, checking that every
allocation can fail safely, and testing an HTTP server without a network.

## Assertions

A test is `test` followed by a string that says what it checks, and a body
that runs like any function's. Each assertion answers a `Result`, and `?` ends
the test at the first one that fails:

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
left out; written in full, it is `-> Result[(), testing.Failure]`. That is the
one place a missing result means something other than `()`: an ordinary
function that writes none returns `()`.

Here the three kinds of check test a function that reads the port out of an
address. Save it as `ports.lin` and run `linea test ports.lin`:

```linea
import std.io
import std.testing
import std.text

// Read the port after the colon in an address such as "localhost:8080".
fn port_of(address: Str) -> Result[UInt16, text.ParseError] {
    let (_, port) = address.split_once(":") else {
        return .Err(.Syntax(address.length()))
    }
    port.parse[UInt16]()
}

test "the port follows the colon" {
    testing.assert_ok_eq(port_of("localhost:8080"), 8080, "the port of localhost:8080")?
}

test "an address without a port is refused" {
    testing.assert_err(port_of("localhost"), "an address with no colon")?
}

// The `match` checks the error's shape: a `Syntax` error, at whatever byte.
test "a letter in the port is a syntax error" {
    testing.assert(match port_of("localhost:80x0") {
        Err(Syntax(_)) => true,
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
ok    a letter in the port is a syntax error
ok    an address without a port is refused
ok    the port follows the colon

3 passed, 0 failed
```

The report lists the tests by name, in alphabetical order, not in the order
the file declares them. A name is any sentence that says what the test checks,
written once: two tests of one module may not share it, an empty name is
refused, a name neither begins nor ends with a space, and the name holds no
`{…}` interpolation, since it is fixed where the test is written. The third
test checks the error's variant with a pattern inside a pattern,
`Err(Syntax(_))`, which matches only an `Err` carrying a `Syntax` error
([Errors](03-errors.md#when-to-keep-match)).

## Tests inside an implementation

A test can sit at the top level of a module, beside the functions it tests,
and it can also sit directly inside an inherent `impl Type { … }` block beside
the methods:

```linea
import std.io
import std.testing

struct Counter {
    value: UInt64,
}

impl Counter {
    pub fn new() -> Counter {
        Counter { value = 0 }
    }

    test "a new counter starts at zero" {
        let counter = Counter.new()
        testing.assert_eq(counter.value, 0, "initial value")?
    }

    pub fn bump(inout self: Self) {
        self.value += 1
    }

    test "bump increments the counter" {
        var counter = Counter.new()
        &counter.bump()
        testing.assert_eq(counter.value, 1, "value after one bump")?
    }
}

fn main() -> Result[UInt8, io.IoError] {
    var counter = Counter.new()
    &counter.bump()
    io.println("count: {counter.value}")?
    .Ok(0)
}
```

```
ok    a new counter starts at zero
ok    bump increments the counter

2 passed, 0 failed
```

This keeps each method and its unit tests together without having to close and
reopen the `impl` block around them. The braces only decide where the test is
written: it is a member of nothing, and it is named and checked exactly as if it
sat at the top level of the module. `linea test` reports it by its own name,
and two tests of one name in two `impl` blocks of one module are a duplicate.

The same holds for the names an `impl` gives its members. A test is not
instantiated, so `Self` and the implementation's type parameters name nothing
inside it, and the test names the type it tests:

```linea
import std.testing

struct Meter {
    reading: UInt32,
}

impl Meter {
    pub fn new() -> Meter {
        Meter { reading = 1 }
    }

    test "a new meter reads one" {
        let meter = Self.new()
        testing.assert_eq(meter.reading, 1, "a new meter reads one")?
    }
}

fn main() -> UInt8 {
    if Meter.new().reading == 1 {
        0
    } else {
        1
    }
}
```

```
error[S-Test]: `Self` names no type in a test
  --> meter.lin:13:21
   |
13 |         let meter = Self.new()
   |                     ^^^^ a test inside an `impl` is resolved at module scope; write `Meter`
```

Writing `Meter.new()` fixes it. In a generic `impl[T] Boxed[T]`, a test names
the instance it checks: `let boxed: Boxed[UInt8] = Boxed.new(3)` writes the
whole type in the annotation and only `Boxed` before the call, whose argument
settles `T`. Because trait implementations supply only what a trait declares, tests
sit in inherent implementations and in trait declarations, not in trait
implementations (`impl Trait for Type`) or templates.

## Tests inside a trait

A trait can give an operation a body, and every type that implements the trait
then runs that body. The test for such an operation sits inside the trait,
right after the operation:

```linea
import std.io
import std.testing

trait Doubling {
    fn value(self: Self) -> UInt32

    fn doubled(self: Self) -> UInt32 {
        self.value() * 2
    }

    test "doubled is twice the value" {
        let meter = Meter { reading = 4 }
        testing.assert_eq(meter.doubled(), 8, "twice four is eight")?
    }
}

struct Meter {
    reading: UInt32,
}

impl Doubling for Meter {
    fn value(self: Self) -> UInt32 {
        self.reading
    }
}

fn main() -> Result[UInt8, io.IoError] {
    let meter = Meter { reading = 21 }
    io.println("doubled: {meter.doubled()}")?
    .Ok(0)
}
```

```
ok    doubled is twice the value

1 passed, 0 failed
```

The test is not part of the trait. `impl Doubling for Meter` supplies `value`
and nothing else, nothing reaches the test through `Doubling`, and a module
that imports `Doubling` gets no test with it. As inside an `impl`, the
test is named and checked as if it sat at the top level of the module.

A trait's body is written for whatever type implements it, but a test runs
once, for no type in particular. So `Self`, the trait's own type parameters and
its associated types name nothing inside a test, and the test names a type that
implements the trait, as `Meter` above. Writing `Self` is refused:

<!-- guide: edit 12 let meter = Meter { reading = 4 } -->
```linea
        let meter: Self = Meter { reading = 4 }
```

```
error[S-Test]: `Self` names no type in a test
  --> main.lin:12:20
   |
12 |         let meter: Self = Meter { reading = 4 }
   |                    ^^^^ a test inside a trait is resolved at module scope; write the type it tests
```

Rust keeps a trait's tests outside the trait, in a `#[cfg(test)]` module; here
they sit beside the provided operation they check.

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
    lines.as_slice().map(|sink line| line.cents * line.quantity).sum()
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

test "the total counts every line" {
    testing.assert_eq(total(sample_order()), 1155, "the sample order's total")?
}

test "a free line adds nothing" {
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
ok    a free line adds nothing
ok    the total counts every line

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

test "the label joins row and seat" {
    testing.assert_eq(seat_label(3, 14), 314, "row 3, seat 14")?
}

// `test trap` marks a test that passes only when its body stops the program.
test trap "seat twenty one stops the program" {
    let _label = seat_label(3, 21)
}

fn main() -> Result[UInt8, io.IoError] {
    io.println("Your seat is {seat_label(12, 7)}.")?
    .Ok(0)
}
```

```
ok    seat twenty one stops the program
ok    the label joins row and seat

2 passed, 0 failed
```

Each test runs in its own process, so one that stops takes no other test with
it. A `test trap` that finishes normally fails; ask for seat 20 instead of 21:

<!-- guide: unchecked the output of an edited or partial program -->
```
FAIL  seat twenty one stops the program
        expected the test to trap
ok    the label joins row and seat

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
fn banner_in[A: Allocator](allocator: A, title: Str) -> Result[String[A], mem.Oom] where carries(.Ok: allocator) {
    var line = String.new_in(allocator)
    // Release the line if a `?` leaves early; returning it skips this.
    defer line.release()
    &line.append("== ")?
    &line.append(title)?
    &line.append(" ==")?
    .Ok(line)
}

// `testing.allocated` answers the banner, or fails the test with the message
// when the allocation is refused.
test "a banner frames its title" {
    defer let heading = testing.allocated(banner_in(mem.system(), "Daily report"), "the banner was refused")?
    testing.assert_eq(heading.view(), "== Daily report ==", "the banner changed")?
}

// `each_allocation_failure` runs the body once to count the allocations it
// asks for, then once more for each of them with that one refused. Every run
// must end cleanly: with the refusal passed up, or with success.
test "every allocation the banner asks for can fail" {
    let attempts = testing.each_allocation_failure(
        mem.system(),
        |allocator| -> Result[(), mem.Oom] {
            let heading = banner_in(allocator, "Daily report")?
            heading.release()
            .Ok(())
        },
        testing.oom_is_a_refusal,
    )?
    testing.assert_eq(attempts, 3, "the banner asked for a different number of allocations")?
}

fn main() -> Result[UInt8, io.IoError] {
    defer let heading = banner_in(mem.system(), "Daily report") else |refusal| {
        return .Ok(refusal.report("the banner"))
    }
    io.println(heading.view())?
    .Ok(0)
}
```

```
ok    a banner frames its title
ok    every allocation the banner asks for can fail

2 passed, 0 failed
```

The first test needs its banner, and `testing.allocated(result, message)`
says so. It takes the `Result[T, mem.Oom]` an allocating call answers and
answers `Result[T, testing.Failure]`: the value when the allocation was
granted, or a failure carrying the message when it was refused, which `?`
hands on so the test fails and names what it could not build. It accepts only
`mem.Oom` as the error, so it never passes off another kind of failure, such
as a file that would not open, as a refused allocation. Writing `.unwrap()`
there instead would stop the whole test program at the first refusal, before
the other tests run.

`each_allocation_failure` takes three arguments:

- the allocator every run really allocates from, here `mem.system()`. The
  caller chooses it, as for every function that allocates;
- the body, a lambda ([Calling
  things](02-calling-things.md#closures-functions-that-capture)) that takes
  the allocator to use and answers a `Result`. It is handed a
  `testing.TestHandle`, which passes each request on to the first
  argument and refuses the one the run is testing;
- a function that says which errors count as a refusal. This body fails only
  with `mem.Oom`, so every error it returns is one, and
  `testing.oom_is_a_refusal` says so.

It runs the body once to count the allocations it asks for, then once more for
each of them, with that one refused. The run with nothing refused must
succeed; every other run must pass the refusal up or succeed without that
allocation. It answers how many allocations it tried, so the test can check
that too: `banner_in` allocates three times, so the body runs four times. `banner_in`
needed no change to be tested this way: it takes its allocator as an argument
([Memory](07-memory.md)).

A body that makes assertions of its own answers `Result[(), testing.Failure]`.
It hands each allocation on with `testing.allocated`, and passes
`testing.Failure.is_refusal` as the third argument. The failure `allocated`
makes for a refused allocation is a refusal, so the walk accepts it, while a
failed assertion is not, so it still fails the test. Add this test to
`banner.lin`:

<!-- guide: unchecked the program is a partial listing or an edit of an earlier one -->
```linea
// Every run that builds the banner must build it right, whichever allocation
// was refused before it.
test "every banner that is built reads right" {
    let _attempts = testing.each_allocation_failure(
        mem.system(),
        |allocator| -> Result[(), testing.Failure] {
            let heading = testing.allocated(banner_in(allocator, "Daily report"), "the banner was refused")?
            let reads_right = heading.view() == "== Daily report =="
            heading.release()
            testing.assert(reads_right, "the banner changed")
        },
        testing.Failure.is_refusal,
    )?
}
```

```
ok    a banner frames its title
ok    every allocation the banner asks for can fail
ok    every banner that is built reads right

3 passed, 0 failed
```

The heading is released before the assertion, because a failed assertion
returns from the lambda, and the heading must not be left behind on that path.

Break `banner_in` by writing `&line.append(title).unwrap()` in place of
`&line.append(title)?`, and the run that refuses the second allocation stops
the program:

<!-- guide: unchecked the output of an edited or partial program -->
```
ok    a banner frames its title
FAIL  every allocation the banner asks for can fail
        linea: panic: called Result.unwrap on Err at banner.lin:11:25

1 passed, 1 failed
```

The location is the `unwrap` in `banner_in`, line 11 of `banner.lin`.

`each_allocation_failure` is built on `testing.TestAllocator`, which you can use
directly to refuse one chosen allocation. `testing.TestAllocator.open(backing)`
makes a test allocator whose `handle()` passes requests on to `backing` and
counts them, and `open(backing, fail_at: .Some(n))` also refuses the `n`th;
`attempts()` counts the requests it saw, and `outstanding()` counts what it
handed out and was not given back. It keeps its counts in memory from
`backing` too, so `open` answers a `Result`. Add this test to `banner.lin`:

<!-- guide: unchecked the program is a partial listing or an edit of an earlier one -->
```linea
// `fail_at: .Some(2)` refuses the second allocation the handle is asked for.
// The test checks that `banner_in` passes the refusal up, and that the first
// allocation was given back on the way out.
test "a refused second allocation leaves nothing behind" {
    defer let log = testing.TestAllocator.open(mem.system(), fail_at: .Some(2)).unwrap()
    let refused = match banner_in(log.handle(), "Daily report") {
        Ok(heading) => {
            heading.release()
            false
        },
        Err(_) => true,
    }
    testing.assert(refused, "the banner was built without its second allocation")?
    testing.assert_eq(log.attempts(), 2, "the banner went on after the refusal")?
    testing.assert_eq(log.outstanding(), 0, "the first allocation was not given back")?
}
```

```
ok    a banner frames its title
ok    a refused second allocation leaves nothing behind
ok    every allocation the banner asks for can fail

3 passed, 0 failed
```

The test allocator is linear, so it is released like any other owner. It
records what happened and leaves the judging to the compiler: a buffer from
`mem.system()` must be given back, and a test that returns while one is still
live is refused before it runs, while a buffer from an arena may be dropped,
because the arena takes it back. A test that wants everything given back says
so, as this one does with `outstanding()`. It counts however many allocations
a test makes.
The result of `banner_in` is matched rather than tested with `is_err()`,
because on success it holds a `String` that must be released.

### Allocations from more than one task

A `testing.TestAllocator`'s handle counts through a plain read of the test
allocator, so two tasks allocating through it at once would race on its
counts. Linea refuses that: the test allocator is `@unshareable`, and so is its
handle. Code that hands its allocator to other tasks, such as `http.serve_in`,
asks for an allocator that is `Shareable`, and `testing.SharedTestAllocator`
gives you one. It keeps its counts in an owning task of its own, which every
task reaches one call at a time, so its handle is `Shareable` whenever the
allocator under it is.

It opens with the same `fail_at:`, answers `attempts()`, `acquired()`,
`outstanding()` and `all_disposed()` like the other, and refuses on request:
`fail_at(.Some(n))` refuses the `n`th attempt,
`fail_from(.Some(n))` every attempt from the `n`th on, `fail_size_at(size, n)`
the `n`th acquisition of exactly `size` bytes made after the call, and
`fail_size_from(size, n)` every such acquisition from the `n`th on.

Each task a server runs takes a 4 KiB buffer from its parent allocator before it
accepts anything, to answer 503 with when it runs out of memory later. This
test refuses every one of those buffers to a server with four tasks, and checks
that serving stops with `Memory` and gives back everything it took. Save it as
`refused_server.lin`:

```linea
import std.http
import std.mem
import std.net
import std.testing

// A router whose tables and answers come from the test allocator's handle.
alias Routes = http.Router[(), testing.SharedTestHandle[mem.SystemAllocator]]

fn hello[P: mem.Allocator](inout _: (), request: http.Request[P], inout _incoming: http.RequestBody[P]) -> Result[http.Response[P], http.Error[P]] where carries(request), borrows(_incoming), retains(_incoming: _incoming) {
    http.text(request, "hello")
}

test "a server refused its buffers stops and gives everything back" {
    defer let log = testing.SharedTestAllocator.open(mem.system()).unwrap()
    log.fail_size_from(4096, 1)
    let parent = log.handle()
    // Each serving task calls `made` to build its own router. The closure
    // keeps its own copy of the allocator, which every task may read at once.
    let made = [sink routes = copy(parent)] || -> Routes where carries(routes) {
        var router = http.Router.new_in(routes)
        &router.route_raw("GET /", hello).unwrap()
        router
    }
    let listener = net.listen(net.loopback(0)).unwrap()
    let served = http.serve_in(parent, listener, made, policy: .Threads(4))
    testing.assert_eq(served, .Err(.Memory(.Exhausted)), "serving went on without its buffers")?
    testing.assert(log.all_disposed(), "serving kept memory it took")?
}
```

```
ok    a server refused its buffers stops and gives everything back

1 passed, 0 failed
```

Opening a shared test allocator starts its task, so `open` answers a
`Result`, which fails with `task.PrepareError` when the task cannot be started.
Give it a backing allocator that cannot be shared, such as an arena's handle,
and it still works, but its handle is not `Shareable`, and `http.serve_in`
refuses it.

## Testing a server

A router is a handler, so a test sends it a request, as `serve` does, without
opening a socket. `serve` reads each request into an arena of its own, the
handler builds its response there, and the arena is rewound once the response
is written. `http.TestExchange` is that arena for a test:
`http.TestExchange.open()` opens it under the limits `serve` uses unless it is
given others with `limits:`, and `exchange.request(method, target, body:,
content_type:)` builds the request a client would send in it. The body is sent
with its `Content-Length`, a body longer than the limits allow is refused with
413 before any handler sees it, as `serve` refuses it, and the handler reads
the body through its `http.RequestBody`, as it reads one from a connection. `&sent.send_to(&router,
&state)` hands the request to the router:

`greeting.lin`:

```linea
import std.http
import std.testing

// Answer `hello, NAME` for the name the query holds, and refuse a request
// that names nobody.
fn greet(inout _: (), request: http.Request, inout _body: http.RequestBody) -> Result[http.Response, http.Error] where carries(request), borrows(_body), retains(_body: _body) {
    let name = request.query() else {
        return .Err(http.error(request, .BadRequest, "say who to greet"))
    }
    http.text(request, "hello, {name}")
}

// Count the bytes of the text a client posted.
fn measure(inout _: (), request: http.Request, inout body: http.RequestBody) -> Result[http.Response, http.Error] where carries(request), borrows(body), retains(body: body) {
    let text = &body.text(request)?
    http.text(request, "{text.length()} bytes")
}

fn routes() -> http.Router[()] {
    var router: http.Router[()] = http.Router.new()
    &router.route_raw("GET /greet", greet).unwrap()
    &router.route_raw("POST /measure", measure).unwrap()
    router
}

test "a greeting names the visitor" {
    defer var router = routes()
    defer let exchange = http.TestExchange.open()
    defer var sent = exchange.request("GET", "/greet?Ada").unwrap()
    var nothing = ()
    let response = &sent.send_to(&router, &nothing).unwrap()
    testing.assert_ok_eq(response.text(), "hello, Ada", "the greeting changed")?
}

test "a greeting for nobody is refused" {
    defer var router = routes()
    defer let exchange = http.TestExchange.open()
    defer var sent = exchange.request("GET", "/greet").unwrap()
    var nothing = ()
    let refused = match &sent.send_to(&router, &nothing) {
        Ok(_) => return testing.assert(false, "a greeting for nobody was answered"),
        Err(error) => error,
    }
    testing.assert_eq(refused.status(), http.Status.BadRequest, "the status changed")?
    testing.assert_eq(refused.message(), Option.Some("say who to greet"), "the message changed")?
}

// The exchange holds the request to its limits as `serve` does, so a body
// past `max_body_bytes` is refused with 413 before any handler runs.
test "a body past the limit is refused" {
    defer var router = routes()
    defer let exchange = http.TestExchange.open(limits: http.Limits { max_body_bytes = 4, ..http.Limits.default() })
    defer var fits = exchange.request("POST", "/measure", body: "tea").unwrap()
    var nothing = ()
    let measured = &fits.send_to(&router, &nothing).unwrap()
    testing.assert_ok_eq(measured.text(), "3 bytes", "the body changed")?
    let refused = match exchange.request("POST", "/measure", body: "coffee") {
        Ok(long) => {
            long.release()
            return testing.assert(false, "a body past the limit was sent")
        },
        Err(error) => error,
    }
    testing.assert_eq(refused, http.RequestError.Status(.ContentTooLarge), "the refusal changed")?
}
```

```sh
linea test greeting.lin
```

```
ok    a body past the limit is refused
ok    a greeting for nobody is refused
ok    a greeting names the visitor

3 passed, 0 failed
```

The request and the response live in the exchange's arena, and the response
may view the request and its body, so the test reads the response while all
three live. Each is released by `defer`, last bound first: the request, then
the exchange. A test that reads the response after the exchange is released
does not compile, as a handler that keeps a request past its response does
not.

These tests are for the station server of
[Networking](09-networking.md#reading-inputs-sharing-state-and-logging); add
them to the end of `stations.lin`, with `import std.testing` at the top:

<!-- guide: unchecked the program is a partial listing or an edit of an earlier one -->
```linea
// The tests own an `App` of their own, and hand the handlers a context with a
// client of it and a logger that writes only errors, so the lines the
// handlers log stay out of the test report.
fn quiet(owner: task.Owner[App]) -> Ctx where borrows(owner) {
    .{ app = owner.client(), logger = log.to_stderr(minimum: .Error) }
}

// Build a request in an arena, as `serve` would, and send it through the routes.
test "a reading is recorded and counted" {
    defer var router: http.Router[Ctx] = http.Router.new()
    routes(&router, "Weather stations report here.\n").unwrap()
    defer let owner = task.own(App { readings = 0 }).unwrap()
    defer var ctx = quiet(owner)
    defer let exchange = http.TestExchange.open()
    defer var sent = exchange.request("POST", "/readings", body: r#"{"celsius":21,"sky":"clear"}"#, content_type: "application/json").unwrap()
    &sent.add_header("Authorization", "Bearer harbour").unwrap()
    let response = &sent.send_to(&router, &ctx).unwrap()
    testing.assert_ok_eq(response.text(), r#"{"station":"harbour","sky":"clear","count":1}"#, "the answer changed")?
    let readings = ctx.app.call(|inout app: App| app.readings)
    testing.assert_eq(readings, 1, "the reading was not counted")?
}

// A request that names no station is refused before anything is counted.
test "a reading without a station is refused" {
    defer var router: http.Router[Ctx] = http.Router.new()
    routes(&router, "Weather stations report here.\n").unwrap()
    defer let owner = task.own(App { readings = 0 }).unwrap()
    defer var ctx = quiet(owner)
    defer let exchange = http.TestExchange.open()
    defer var sent = exchange.request("POST", "/readings", body: r#"{"celsius":21,"sky":"clear"}"#, content_type: "application/json").unwrap()
    let refused = match &sent.send_to(&router, &ctx) {
        Ok(_) => return testing.assert(false, "a reading without a station was accepted"),
        Err(error) => error,
    }
    testing.assert_eq(refused.status(), http.Status.Unauthorized, "the status changed")?
    let readings = ctx.app.call(|inout app: App| app.readings)
    testing.assert_eq(readings, 0, "a refused reading was counted")?
}

// `recorded_body` runs a streamed body into the request's arena, so a test
// reads what a client would receive.
test "the outlook streams one line a day" {
    defer var router: http.Router[Ctx] = http.Router.new()
    routes(&router, "Weather stations report here.\n").unwrap()
    defer let owner = task.own(App { readings = 0 }).unwrap()
    defer var ctx = quiet(owner)
    defer let exchange = http.TestExchange.open()
    defer var sent = exchange.request("GET", "/outlook?days=2").unwrap()
    let body = &sent.send_to(&router, &ctx).unwrap().recorded_body().unwrap()
    testing.assert_eq(Str.from_bytes(body.as_slice()).unwrap(), "day 1: sunny\nday 2: sunny\n", "the outlook changed")?
}

// A route that is a closure is reached the same way.
test "the root answers with the greeting" {
    defer var router: http.Router[Ctx] = http.Router.new()
    routes(&router, "Weather stations report here.\n").unwrap()
    defer let owner = task.own(App { readings = 0 }).unwrap()
    defer var ctx = quiet(owner)
    defer let exchange = http.TestExchange.open()
    defer var sent = exchange.request("GET", "/").unwrap()
    let response = &sent.send_to(&router, &ctx).unwrap()
    testing.assert_ok_eq(response.text(), "Weather stations report here.\n", "the greeting changed")?
}
```

```
ok    a reading is recorded and counted
ok    a reading without a station is refused
ok    the outlook streams one line a day
ok    the root answers with the greeting

4 passed, 0 failed
```

A few things to notice:

- Each test owns an `App` of its own with `task.own`, and `quiet(owner)`
  builds the `Ctx` the routes take: a client of that owner, and a logger that
  writes only errors, so the lines the handlers log do not clutter the test
  report. Both are `defer`red, so the context is released before the owner
  closes.
- `&sent.add_header(name, value)` adds a header to a built request, and
  `content_type:` sets its `Content-Type`.
- `&sent.send_to(&router, &ctx)` runs the router as `serve` does: it reads
  the extractors `record` names and calls it, and the test then asks the
  owning task for `readings` with `ctx.app.call` to see what it changed.
- `response.text()` reads a held body as text, and answers an error instead
  for a streamed body or for bytes that are not UTF-8; `testing.assert_ok_eq`
  compares it with the text a client should see.
- `response.recorded_body()` runs a streamed body into the arena, so a test can
  read what a client would receive.
- Every test goes through the router, so a handler's extractors, its path
  values and its refusals are exercised as `serve` exercises them.

No socket is opened, so these tests run anywhere, quickly. The [JSON echo
server](../../examples/http-json-echo/main.lin) and the [countdown
server](../../examples/countdown-server/main.lin) test every handler this way.

## Repeating task schedules in a simulation

`io.Simulation` provides a virtual clock and network, and tasks started inside
`&sim.run(...)` inherit its simulated Io. They are fibers on one carrier,
with scheduling choices drawn from the seed. Their session sends, receives,
joins and wait sets compose with virtual timers and sockets, so a test can
exercise several tasks without depending on kernel thread timing. Join every
child during a run before closing the simulation. Pending children can remain
between runs on the same operating-system thread. The
[networking chapter](09-networking.md#testing-a-timeout-without-waiting) shows
opening a simulation and configuring its network; use another seed to explore
another repeatable execution. Real sockets cannot be used inside a run, and
simulated sockets cannot be used outside their simulation.

## Running tests

`linea test <path>` takes a file or a project directory; given a directory, it
runs the tests of every module beneath it. The report lists each test with
`ok`, `FAIL` or `SKIP`, the failure or skip reason, and separate counts. The command
exits with status 1 when any test failed, so a script or a CI job can rely on
it.

`--filter TEXT` runs only the tests whose names hold `TEXT`. A test below the
root is named after its module's directory too, as `geometry.a square has four
sides`, so a filter can pick out one module or one test. Against `ports.lin`
from the start of this chapter, `linea test --filter refused ports.lin` runs
the one test whose name holds `refused`, `an address without a port is
refused`, and reports `1 passed, 0 failed`. Quote a filter that holds spaces,
as any shell argument: `--filter "the port"`. A filter that matches no test
says so, and the command succeeds.

A filter is matched against the name as the report spells it, and the report
writes a `.` inside a test's name as `\.`, so that it is not read as the dot
before a module's directory. Save this as `rounding.lin`:

```linea
import std.testing

// Round a count of tenths to the nearest whole number, halves up.
fn rounded(tenths: UInt32) -> UInt32 {
    (tenths + 5) / 10
}

test "1.5 rounds up to 2" {
    testing.assert_eq(rounded(15), 2, "fifteen tenths round to two")?
}

test "1.4 rounds down to 1" {
    testing.assert_eq(rounded(14), 1, "fourteen tenths round to one")?
}
```

```
ok    1\.4 rounds down to 1
ok    1\.5 rounds up to 2

2 passed, 0 failed
```

`linea test --filter '1\.5' rounding.lin` runs the second test alone, while
`--filter '1.5'` matches no name and says so.

## Unavailable prerequisites

A test that needs unavailable hardware returns `.Err(testing.skip(reason))`.
It uses the ordinary `testing.Failure` result, so deferred cleanup still runs:

```linea
import std.testing

test "requires an unavailable capability" {
    return .Err(testing.skip("GPU device unavailable"))
}
```

```text
SKIP  requires an unavailable capability
        GPU device unavailable

0 passed, 0 failed, 1 skipped
```

A skip never counts as a pass. Ordinary `linea test` succeeds when every selected
test passed or skipped. `linea test --deny-skips <path>` exits with status 1
when any selected test skips; use it for hardware qualification. Filtering
happens before execution, so a skipped test outside the filter does not affect
that command. A test expecting a trap cannot pass or skip by returning.

`testing.Failure.is_skip()` distinguishes this outcome from assertions and
allocation refusals. Custom `Display` error types keep their ordinary failure
meaning, even when their displayed text says `Unavailable`. Only skip a known
missing prerequisite; allocation, submission and computation errors fail tests.

## What you have seen

- `testing.assert` and `testing.assert_eq` check conditions and whole values,
  and `testing.assert_ok_eq` and `testing.assert_err` check a `Result`; `?`
  ends a test at the first failure.
- A helper that only tests call is an ordinary function: it counts as used,
  and it is left out of the program.
- A test is named by a string, `test "what it checks" { … }`, and sits beside
  what it tests: at the top level of a module, inside
  an inherent `impl`, or inside a trait, beside the operation it tests.
- `test trap` marks a test that must stop the program.
- `linea test --filter TEXT` runs only the tests whose names hold `TEXT`.
- `testing.each_allocation_failure(allocator, body, is_refusal)` refuses each
  allocation in turn and checks that every one is handled.
- `testing.TestAllocator.open(backing, fail_at: .Some(n))` counts what its
  `handle()` hands out and refuses the `n`th request; `outstanding()` says
  what was not given back.
- `testing.SharedTestAllocator` counts and refuses allocations made from many
  tasks at once, so a server under test can be refused the memory it asks for.
- `http.TestExchange.open()` holds the arena `serve` gives one request,
  `exchange.request(…)` builds a request in it under the same limits, and
  `&sent.send_to(&router, &state)` hands it to a handler as `serve` does.

That is the end of the guide. [Errors the guide shows](errors.md) indexes
every error code the chapters show. The [language
definition](../linea-semantics.md) holds every rule the compiler enforces,
under the name its errors print, and the [examples](../../examples/) are
complete programs to read next.
