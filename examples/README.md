# Examples

Every program here is complete: it compiles, runs, and carries its own tests.
Their expected exit status and output live in `tests/examples/`. The programs
show what a task looks like in Linea; the [guide](../docs/learn/README.md)
explains each construct. Within a level the programs run from simplest to most
involved, so reading top to bottom is a path through the language.

## First programs

Values, functions, control flow, and ordinary errors.

- [hello.lin](hello.lin): prints a greeting; `main`, `let`, and `Result`.
- [greet.lin](greet.lin): greets each name on the command line; arguments and loops.
- [launch_sequence.lin](launch_sequence.lin): prints a countdown; ranges and `for`.
- [room_diagonal.lin](room_diagonal.lin): measures room diagonals; floats and conversions.
- [periodic_signal.lin](periodic_signal.lin): samples a cosine and a sine; floating-point math.
- [growth_forecast.lin](growth_forecast.lin): compares annual and continuous growth; loops and a stopping condition.
- [savings_planner.lin](savings_planner.lin): plans growing monthly deposits; default arguments.
- [character_counts.lin](character_counts.lin): counts letters, digits, and whitespace; `match` and bytes.
- [temperature_extremes.lin](temperature_extremes.lin): finds a week's coldest and warmest readings; one pass with `Option`.
- [temperature_readings.lin](temperature_readings.lin): calibrates and averages readings; `for read` and `for inout`.
- [loyalty_points.lin](loyalty_points.lin): awards points under two reward plans; structs holding functions.
- [print_orders.lin](print_orders.lin): prices print jobs; structs, defaults, and `..base` updates.
- [shipping_quotes.lin](shipping_quotes.lin): quotes delivery from a rate card; enums and explicit `copy`.
- [tournament_board.lin](tournament_board.lin): updates scores and prints standings; arrays, indexing and a stable `sort_by`.
- [office_directory.lin](office_directory.lin): updates and looks up contacts; `Index` and `^1` indexing.
- [accounts](accounts/main.lin): withdraws from an account; modules, named arguments, and errors.

## Everyday applications

Strings, collections, parsing, and files.

- [grocery_receipt.lin](grocery_receipt.lin): prints an aligned receipt; text formatting and padding.
- [prime_sieve.lin](prime_sieve.lin): counts primes below a limit; `Vec` as a runtime-sized table.
- [warehouse_stock.lin](warehouse_stock.lin): totals deliveries per warehouse; `Map` and `@derive`.
- [parcel_inspection.lin](parcel_inspection.lin): stops at the first overweight parcel; iterator chains.
- [parcel_manifest.lin](parcel_manifest.lin): builds a shipping manifest; `filter`, `collect`, and lent counters.
- [pricing_rules.lin](pricing_rules.lin): prices a cart through a list of rules; closures in a `Vec`.
- [frequency_report.lin](frequency_report.lin): counts how often each line appears in a file and lists them most frequent first; reading `lines()`, counting with a `Map`, and sorting with `Vec.sort_by`.
- [server_settings.lin](server_settings.lin): reads a listen address from `key = value` lines; `lines()`, `split_once`, and `let ... else`.
- [form-letters](form-letters/main.lin): fills a letter template per order; files embedded with `embed`, `split_once`, JSON decoding and string building.
- [json_settings.lin](json_settings.lin): reads, validates, and prints settings as JSON; `json.decode`, `json.decode_file`, and `json.encode`.
- [json_inventory.lin](json_inventory.lin): totals an inventory and adds a summary; loading with `json.read_file` and editing a `json.Value` document.
- [discounts](discounts/main.lin): applies a validated discount; newtypes with `where` checks and opaque types.

## Resource-aware code

Ownership transfer, `defer let`, and explicit endings.

- [histogram.lin](histogram.lin): groups request durations into ranges; a `@linear` type that must be closed.
- [payment_batch.lin](payment_batch.lin): commits or rolls back each payment; `@linear` values moved out of a `Vec`.
- [knight_moves.lin](knight_moves.lin): finds shortest knight routes; several tables in one `Arena`.

## Generic libraries

Traits, allocator parameters, borrow contracts, and `From`.

- [cash_register.lin](cash_register.lin): totals coins and notes; a trait and a bounded generic function.
- [network_allowlist.lin](network_allowlist.lin): checks connections against rules; a generic type and `Equatable` bounds.
- [release_comparison.lin](release_comparison.lin): plans an upgrade from release versions; derived ordering.
- [temperature_conversion.lin](temperature_conversion.lin): converts sensor readings; `From` and `TryFrom` conversions.
- [electricity_bill.lin](electricity_bill.lin): bills JSON meter readings; `From` impls so `?` joins several error types.
- [config_editor.lin](config_editor.lin): sets one key and saves atomically; `parse_in` and `render_in` that take an allocator beside system forms, and `carries` borrow contracts.

## Streams and recovery

Reading input that may be malformed or never ends, and recovering from bad records.

- [log_filter.lin](log_filter.lin): filters log records from stdin; buffered streams and recovery from bad records.

## TCP servers

Sockets, connections, and what a server owes each one.

- [tcp_echo.lin](tcp_echo.lin): echoes text over TCP; a server, a client, `io.read_text`, and `defer let` for connections.
- [visitor_counter.lin](visitor_counter.lin): numbers visitors across connections; state shared by a server.
- [bounded_echo.lin](bounded_echo.lin): an echo server a slow client cannot hold up; timeouts, deadlines, and size caps.

## Web services

HTTP routing, request bodies, and responses, from two routes to a full JSON service.

- [hello_http.lin](hello_http.lin): an HTTP service with two routes; routing and JSON bodies.
- [party_rsvp.lin](party_rsvp.lin): collects party replies from a web form; a handler run as a CGI program with `http.serve_cgi`.
- [site-icon](site-icon/main.lin): serves a page and the icon a browser shows on its tab, as a CGI program; files embedded with `embed` and `embed_bytes`, and bytes answered with `http.bytes`.
- [countdown-server](countdown-server/main.lin): streams a countdown one line a second; path values and streamed responses.
- [welcome_back.lin](welcome_back.lin): greets a visitor by name and counts visits in a cookie; reading and setting cookies, and escaping user text in HTML.
- [calendar-export](calendar-export/main.lin): serves a year's calendar as CSV; writing a response as it is produced.
- [http-json-echo](http-json-echo/main.lin): a JSON service with headers, forms, and shared counters; the largest example.
