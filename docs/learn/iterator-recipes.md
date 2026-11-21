# Iterator recipes

Each recipe below answers one question that comes up again and again when a
program walks a collection: how to add up a column, find the first match,
group by a key, or stop early with an error. Most of them quote a few lines
from a program in [`examples/`](../../examples/), so you can open the whole
program, run it, and see the lines in context. Each recipe links the section
of [Iterating](05-iterating.md) or another chapter that explains the
operations it uses; this page only shows where to reach for them.

## Add up a column

`map` picks the number out of each item and `sum` adds them up, starting from
zero. Here each cash register reports its own cents:

<!-- guide: excerpt examples/cash_register.lin -->
```linea
registers.as_slice().map(|sink register| register.cents()).sum()
```

When the items already are the numbers, `copied` turns the views a slice hands
out into the numbers themselves, and `sum` adds those:

<!-- guide: excerpt examples/temperature_readings.lin -->
```linea
let total = week.readings.as_slice().copied().sum()
```

From [`cash_register.lin`](../../examples/cash_register.lin) and
[`temperature_readings.lin`](../../examples/temperature_readings.lin).
[Numbers from a chain](05-iterating.md#numbers-from-a-chain-sum-min-max-and-product)
explains `sum` and `copied`. As with Rust's `sum`, an empty walk adds up to
zero.

## Count the items that pass a test

`filter` keeps the items its test accepts and `count` says how many there
were. The prime sieve keeps a `Bool` for each number and counts the ones still
marked prime:

<!-- guide: excerpt examples/prime_sieve.lin -->
```linea
.Ok(candidates.as_slice().filter(|candidate| *candidate).count())
```

From [`prime_sieve.lin`](../../examples/prime_sieve.lin).
[Counting with `count`](05-iterating.md#counting-with-count) explains `count`.

## The smallest and the largest

`min` and `max` answer an `Option`, since an empty walk has neither. A week of
readings is never empty, so the weather station unwraps the answer:

<!-- guide: excerpt examples/temperature_extremes.lin -->
```linea
let lowest = readings.as_slice().copied().min().unwrap()
let highest = readings.as_slice().copied().max().unwrap()
```

When the walk may be empty, `unwrap_or` names the answer for that case. The
grocery receipt measures its widest name this way, so a receipt with no
purchases has a name column zero characters wide:

<!-- guide: excerpt examples/grocery_receipt.lin -->
```linea
let widest = copy(purchases).map(|sink purchase| purchase.name.length()).max().unwrap_or(0)
```

From [`temperature_extremes.lin`](../../examples/temperature_extremes.lin) and
[`grocery_receipt.lin`](../../examples/grocery_receipt.lin), with `min` and
`max` in [Numbers from a
chain](05-iterating.md#numbers-from-a-chain-sum-min-max-and-product).

## Is any item a match?

`any` stops at the first item its test accepts and answers `true`; `all`
stops at the first it rejects and answers `false`. The allow list asks
whether any rule matches a request exactly:

<!-- guide: excerpt examples/network_allowlist.lin -->
```linea
fn permits[T: Equatable](rules: [Rule[T]; 3], request: Rule[T]) -> Bool {
    rules.as_slice().any([request] |sink rule| *rule == request)
}
```

From [`network_allowlist.lin`](../../examples/network_allowlist.lin).
[Asking questions](05-iterating.md#asking-questions-any-all-and-find) covers
`any` and `all`.

## The first item that matches

A `for` loop that leaves with `break value` answers `.Some(value)`, and
`.None` when it walks every item without breaking. As the last expression of
a function, that is the function's answer:

<!-- guide: excerpt examples/temperature_readings.lin -->
```linea
fn first_at_least(w: Week, limit: UInt64) -> Option[UInt64] {
    for read r in w {
        if r >= limit {
            break r
        }
    }
}
```

The same question as a chain is `find`, which [Asking
questions](05-iterating.md#asking-questions-any-all-and-find) shows. To learn
also how many items the search looked at, keep the iterator in a `var` and
search it with `find_counted`; the parcel inspection reports both the first
parcel over the weight limit and how many parcels it checked:

<!-- guide: excerpt examples/parcel_inspection.lin -->
```linea
var arrivals = weights.map(|sink weight| *weight)
let { found, inspected } = &arrivals.find_counted([limit] |weight| weight > limit)
```

From [`temperature_readings.lin`](../../examples/temperature_readings.lin) and
[`parcel_inspection.lin`](../../examples/parcel_inspection.lin).
[Callbacks and searches that keep their
state](05-iterating.md#callbacks-and-searches-that-keep-their-state) explains
`find_counted`.

## Where an item stands

`position` answers the index of the first item its test accepts, counting from
zero, or `.None`. The note store finds the note to remove this way, and `?`
answers `.None` for the whole call when no note has that id:

<!-- guide: excerpt examples/notes/storage.lin -->
```linea
let index = self.notes.as_slice().position([id] |sink note| note.id == id)?
&self.notes.remove(index)
```

From [`notes/storage.lin`](../../examples/notes/storage.lin).
[`position`](05-iterating.md#one-item-from-all-of-them-reduce-and-where-one-stands-position)
is in Iterating, and `?` on an `Option` in [Errors](03-errors.md#-pass-the-failure-up).

## Number the items

`enumerate` hands out each item beside its index, counting from zero, and the
pattern `(rank, team)` takes the pair apart. The tournament board adds one
to print places from 1:

<!-- guide: excerpt examples/tournament_board.lin -->
```linea
for (rank, team) in order.as_slice().enumerate() {
    println("{rank + 1}. {teams[*team]}: {board[*team]} points")?
}
```

From [`tournament_board.lin`](../../examples/tournament_board.lin).
[Pairs from `enumerate` and `zip`](05-iterating.md#pairs-from-enumerate-and-zip)
explains `enumerate`.

## Walk two sequences together

`zip` pairs the first item of one sequence with the first of the other, then
the second with the second, and stops when either runs out. The greenhouse
report pairs each day's name with that day's reading:

<!-- guide: excerpt examples/temperature_readings.lin -->
```linea
let days = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]
for (day, reading) in days.as_slice().zip(week.readings.as_slice()) {
    println("{day}: {reading} degrees")?
}
```

From [`temperature_readings.lin`](../../examples/temperature_readings.lin).
[Pairs from `enumerate` and `zip`](05-iterating.md#pairs-from-enumerate-and-zip)
explains `zip`, and [`zip` draws from its first sequence
first](05-iterating.md#zip-draws-from-its-first-sequence-first) says what
happens to the longer one.

## Pairs of neighbours

`windows(2)` hands out each item together with the next one, as a slice of
two. The trail profile subtracts each marker's elevation from the next one's
and adds up the rises:

<!-- guide: excerpt examples/trail_profile.lin -->
```linea
elevations.windows(2).map(|sink pair| pair[1] - pair[0]).filter(|change| change > 0).sum()
```

From [`trail_profile.lin`](../../examples/trail_profile.lin).
[Neighbours with `windows`](05-iterating.md#neighbours-with-windows) explains
`windows`.

## A running total

`scan` keeps a value from one item to the next and hands out what it holds
after each item. The trail profile reports the metres climbed so far at every
marker:

<!-- guide: excerpt examples/trail_profile.lin -->
```linea
let climbed_so_far = elevations.as_slice().windows(2).scan(
    Int64(0),
    |inout climbed, sink pair| {
        if pair[1] > pair[0] {
            climbed += pair[1] - pair[0]
        }
        climbed
    },
)
for (step, climbed) in climbed_so_far.enumerate() {
    println("marker {step + 2}: {climbed} m climbed")?
}
```

From [`trail_profile.lin`](../../examples/trail_profile.lin).
[Running totals with `scan`](05-iterating.md#running-totals-with-scan)
explains `scan`.

## Walk backwards

`rev` walks a slice from its last item to its first:

<!-- guide: excerpt examples/trail_profile.lin -->
```linea
for elevation in elevations.as_slice().rev() {
    println("  {*elevation} m")?
}
```

From [`trail_profile.lin`](../../examples/trail_profile.lin).
[Walking backwards with `rev`](05-iterating.md#walking-backwards-with-rev)
explains `rev`.

## The first few from a walk that never ends

A chain does no work until something walks it, so `filter` and `take` are safe
on a source that never runs out. `take(5)` stops asking for years once it has
five leap years:

<!-- guide: excerpt examples/upcoming_leap_years.lin -->
```linea
let leap_years = YearsAfter { last = 2024 }
    .filter(
        inout [inout examined] |year| {
            examined += 1
            is_leap(year)
        },
    )
    .take(5)
for year in leap_years {
    io.println("{year}")?
}
```

From [`upcoming_leap_years.lin`](../../examples/upcoming_leap_years.lin).
[Nothing runs until something walks
it](05-iterating.md#nothing-runs-until-something-walks-it) and [`take` and
`skip`](05-iterating.md#take-and-skip) explain why the walk ends.

## Keep the largest few

To keep the three best scores, gather the scores into a `Vec`, sort it with
the highest first, and walk only the first three. `sort_by` keeps equal
scores in the order they came, so the earlier of two tied teams places first:

```linea
import std.io

struct Score {
    team: Str,
    points: UInt64,
}

fn main() -> Result[UInt8, io.IoError] {
    let round = [
        Score { team = "Comets", points = 42 },
        Score { team = "Falcons", points = 77 },
        Score { team = "Otters", points = 18 },
        Score { team = "Ravens", points = 77 },
        Score { team = "Herons", points = 55 },
    ]
    // `collect` gathers a view of each score into a `Vec`, which `sort_by`
    // can reorder; the array itself stays as it is.
    let { values, iterator: _ } = round.as_slice().collect().settled() else |_| {
        return .Ok(1)
    }
    defer var ranked = values
    // The comparison says whether `left` belongs before `right`: the higher
    // score first.
    &ranked.sort_by(|left, right| left.points > right.points)
    // `take(3)` ends the walk after the first three scores.
    for (place, score) in ranked.as_slice().take(3).enumerate() {
        io.println("{place + 1}. {score.team}: {score.points}")?
    }
    .Ok(0)
}
```

```
1. Falcons: 77
2. Ravens: 77
3. Herons: 55
```

[Collecting into a `Vec`](05-iterating.md#collecting-into-a-vec) and [Sorting
a `Vec`](05-iterating.md#sorting-a-vec-sort-and-sort_by) explain `collect`
and `sort_by`. [`frequency_report.lin`](../../examples/frequency_report.lin)
ranks the entries of a map the same way.

## Keep some items, change them, and gather them into a `Vec`

`filter` keeps the parcels at or under the weight limit, `map` adds the
packaging to each weight, and `collect` gathers the results into a new vector:

<!-- guide: excerpt examples/parcel_manifest.lin -->
```linea
var inspected: UInt64 = 0
let accepted = arrivals.filter(
    inout [limit, inout inspected] |parcel| {
        inspected += 1
        *parcel <= limit
    },
)
// `collect` gathers the shipping weights into a new vector, and
// `.settled()` turns a refused allocation into its `Oom` for `?` to return.
// `iterator: _` drops the finished chain, after which `inspected` holds
// the final count.
let { values, iterator: _ } = accepted.map(shipping_weight).collect().settled()?
```

From [`parcel_manifest.lin`](../../examples/parcel_manifest.lin).
[Chains](05-iterating.md#chains-map-filter-and-fold) explains `filter` and
`map`, and [Collecting into a `Vec`](05-iterating.md#collecting-into-a-vec)
explains `collect`.

## Count by category

When the categories are known in advance, a struct with one count per
category and a `match` on each item does it. The character counter sorts
every byte of a message into one of four counts:

<!-- guide: excerpt examples/character_counts.lin -->
```linea
for byte in text.as_bytes() {
    match *byte {
        // Single-character range endpoints denote their character codes.
        "a"..="z" => counts.letters += 1,
        "A"..="Z" => counts.letters += 1,
        "0"..="9" => counts.digits += 1,
        // ASCII codes 9 through 13 span tab through carriage return.
        // Code 32 is the separate space character.
        9..=13 => counts.whitespace += 1,
        32 => counts.whitespace += 1,
        _ => counts.other += 1,
    }
}
```

From [`character_counts.lin`](../../examples/character_counts.lin).

When the categories come from the data, count them in a map:
[`Map`: values by key](01-linea-in-an-hour.md#map-values-by-key) counts votes
with `merge`, and [`frequency_report.lin`](../../examples/frequency_report.lin)
counts the lines of a file with `upsert`, which copies a line into a key only
the first time it is seen.

## Total by key into a map

`merge` adds a value to the one already stored under its key, or stores it
under a new key. The warehouse adds up each product's deliveries per
warehouse, with the product and the warehouse together as the key:

<!-- guide: excerpt examples/warehouse_stock.lin -->
```linea
for delivery in deliveries {
    // The pattern takes the delivery apart, and its product and warehouse
    // become the key.
    let Delivery { product, warehouse, units } = delivery
    let key = StockKey { product, warehouse }
    // `merge` adds the units to an existing entry, or inserts them for a
    // new product and warehouse. If allocation fails, the failure hands the
    // key and units back; `settled()` releases them and keeps only why.
    if &stock.merge(key, units, |sink current, sink added| current + added).settled().is_err() {
        io.eprintln("could not allocate warehouse stock")
        return .Ok(1)
    }
}
```

From [`warehouse_stock.lin`](../../examples/warehouse_stock.lin). A map keeps
no order; [`Map`: values by key](01-linea-in-an-hour.md#map-values-by-key)
introduces it.

## Group by key, in the order keys first appear

A map does not remember which key came first. When the report must list
groups in the order they first appear, keep the groups in a `Vec` and look for
the item's group with `for inout`, which lends each group to the loop so it
can be changed. A key not found starts a new group at the end:

<!-- guide: excerpt examples/uptime_report.lin -->
```linea
fn record(inout tallies: Vec[Tally], check: Check) -> Result[(), mem.Oom] {
    for inout tally in tallies {
        if tally.service.view() == check.service.view() {
            count(&tally, check)
            return .Ok(())
        }
    }
    var tally = Tally { service = check.service.view().to_owned()?, checks = 0, failed = 0, slowest_ms = 0 }
    count(&tally, check)
    // `settled()` releases a tally the vector had no room for and keeps the
    // reason.
    &tallies.push(tally).settled()?
    .Ok(())
}
```

From [`uptime_report.lin`](../../examples/uptime_report.lin). Each lookup
walks the groups seen so far, which suits a handful of groups; for many, count
in a map and sort its entries afterwards, as
[`frequency_report.lin`](../../examples/frequency_report.lin) does. [Four ways
to walk](05-iterating.md#four-ways-to-walk) explains `for inout`.

## Pick fields out of lines of text

`lines` hands out each line without its line break, and `split_once` cuts a
line at the first `=`. A line without one, such as a comment or a blank line,
answers `.None`, and `continue` skips it:

<!-- guide: excerpt examples/server_settings.lin -->
```linea
for line in settings.lines() {
    // `split_once` returns `None` for a comment or a blank line, which has
    // no `=`. The `else` block then runs `continue` to skip to the next line.
    let (name, value) = line.split_once("=") else {
        continue
    }
    if name.trim_ascii() == key {
        return .Some(value.trim_ascii())
    }
}
```

From [`server_settings.lin`](../../examples/server_settings.lin).
[Cutting text apart](08-text.md#cutting-text-apart-lines-and-split_once)
explains `lines` and `split_once`.

## Read lines until a blank one

A message often starts with a block of headers that ends at a blank line.
Keep the walk of lines in a `var` and walk it with `for line in &lines`, which
lends the walk to the loop instead of handing it over. `break` at the blank
line leaves the rest of the lines in `lines`, so a second loop picks up where
the first stopped:

```linea
import std.io

let message =
    \\From: tea-club@example.com
    \\Subject: Friday
    \\
    \\Tea is at four.
    \\Bring a cup.
    \\

fn main() -> Result[UInt8, io.IoError] {
    var lines = message.lines()
    // The headers end at the first blank line; `break` leaves the loop and
    // keeps the lines after it in `lines`.
    for line in &lines {
        if line.length() == 0 {
            break
        }
        io.println("header: {line}")?
    }
    // The second loop walks the lines the first one did not reach.
    for line in &lines {
        io.println("body: {line}")?
    }
    .Ok(0)
}
```

```
header: From: tea-club@example.com
header: Subject: Friday
body: Tea is at four.
body: Bring a cup.
```

[Draining, and walks that lend](05-iterating.md#draining-and-walks-that-lend)
explains `for … in &lines`, and [Multi-line text](08-text.md#multi-line-text)
the `\\` lines that hold the message.

## Stop at the first error

A `?` or a `return .Err(…)` inside a `for` leaves the loop and the function
together, so the first bad item ends the walk with its error. The inventory
refuses a product with no name or a count that is not a whole number, and a
total that would overflow:

<!-- guide: excerpt examples/json_inventory.lin -->
```linea
var total: UInt64 = 0
for product in items {
    let name = product.get("name") else {
        return .Err(.Product)
    }
    if name.as_str().is_none() {
        return .Err(.Product)
    }
    let units = product.get("units") else {
        return .Err(.Product)
    }
    let count = units.as_uint64()?
    if count > UInt64.max - total {
        return .Err(.Overflow)
    }
    total += count
}
.Ok(total)
```

From [`json_inventory.lin`](../../examples/json_inventory.lin). [Errors](03-errors.md#-pass-the-failure-up)
explains `?`, and [`let … else`](03-errors.md#let--else-bind-the-value-or-handle-the-failure-right-there)
the `else` blocks. To report a bad item and keep going instead, handle each
item's error in the loop, as [`uptime_report.lin`](../../examples/uptime_report.lin)
does with every line of a log, and [A file of records, one on each
line](05-iterating.md#a-file-of-records-one-on-each-line-json-lines) explains.
