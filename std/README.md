# Using Linea's standard library

Import an ordinary module, then qualify its API or bring selected names into scope:

```linea
import std.io
use io.println

fn main() -> Result[UInt8, io.IoError] {
    println("hello")?
    .Ok(0)
}
```

The prelude puts two groups of names in every module. `Option`, `Result`,
`Str`, `Range`, `Display`, `Debug`, the comparison and indexing traits and the
iteration traits are there because the syntax requires them. The core
vocabulary is there because most programs write it: `Release`, `Equivalent`,
`Ordered`, `From`, `Into`, `TryFrom`, `TryInto`, `Default`, `Allocator`, `Vec`,
`String` and `Writer`. Everything else, including functions such as
`mem.system()` and `io.println`, requires an import of its module. A module may
declare its own type or trait under a prelude name; its declaration shadows the
prelude's there. The [prelude tables](../docs/linea-semantics.md#37-modules) are
authoritative.

| Module | Start here | Ownership/error convention |
| --- | --- | --- |
| [io](io/io.lin) | Reader, ByteWriter, Close, BufferedReader, BufferedWriter, read_all, read_text, prompt; stdin/stdout/stderr | Allocating reads require a byte limit. `Close` consumes a resource whose disposal can fail and reports that failure; its `Release` closes too but drops the result. Borrowed lines protect reader storage; owned lines retain their allocator. Output tracks accepted bytes; finish or abort settles buffered output explicitly. |
| [text](text/string.lin) | String.from_bytes, view; Str.to_owned, slice, find, split, trim; [Parse](text/parse.lin), Str.parse | String owns validated UTF-8; String.new and String.new_in create an empty value without allocating. Str and slices carry their backing owners; byte indexes and slices respect UTF-8 boundaries. Every integer type and Float64 implement Parse; `s.parse[UInt32]()` names the type to read, as does a result annotation such as `let year: UInt32 = s.parse()?`, and a program's own type can implement Parse the same way. Validation and parsing errors report byte offsets. |
| [fs](fs/file.lin) | Path, File, read_file, read_text, write_file, save_atomic | Paths preserve POSIX bytes and reject NUL. Reads preserve partial bytes on failure; explicit close reports errors. Writes require CreateNew or Replace policy. Atomic save keeps an existing mode, and gives a new file 0666 less the umask, unless given `permissions: .Exact(bits)`, and reports publication and cleanup separately. |
| [json](json/README.md) | parse, Value, write, render; decode, from_value, encode; Encode/Decode derives | Owned documents and decoded values retain their allocator, not input bytes. Queries borrow text; mutation returns refused/replaced owners; typed errors own field/index paths, and parse and decode errors display as the problem and where it is. Decode input of a known shape, as the [settings example](../examples/json_settings.lin) does; walk a Value to edit a document, as the [inventory](../examples/json_inventory.lin) does. |
| [fmt](fmt/traits.lin) | Display, Debug, structural derives; render_owned; [Spec, Align, write_display, write_debug, write_integer, write_float](fmt/spec.lin) | Render through a Writer; render_owned produces allocated text from a formattable value. [A format spec](#lay-out-values-with-a-format-spec) such as `{total:>8.2}` lays an interpolated value out, and a Spec, from `Spec.default()` with struct update, lays a value out with fill, alignment and a width counted in Unicode scalars, and a number with a `+` sign, zero padding and a Float64 precision that rounds the shortest digits half away from zero. Library errors and failures implement Display by rendering their reason and borrow any resources they return; containers do not implement Display. |
| [env](env/env.lin) | args, Args.count, Args.at, Args.bytes_at | Borrow process arguments as validated text or exact POSIX bytes; missing indices return Option.None. |
| [option](option/option.lin) | map, and_then, unwrap_or, unwrap_or_else | Consumes the option. unwrap traps on absence; matching/defaults handle it explicitly. |
| [result](result/result.lin) | map, map_err, and_then, unwrap_or, unwrap_or_else, settled | Error values remain explicit. `?` propagates the function's own error type unchanged and converts another through the function's `From` implementation; map_err changes it at one site. `settled()` releases what a failure hands back and keeps its reason. |
| [iter](iter/iter.lin) | `Sequence` provides map, filter, filter_map, fold, find, find_map, any, all, for_each, collect and collect_in, enumerate, zip, take, skip; `Iterator` provides find_counted; [extend](iter/collection.lin) | Every sequence offers `Sequence`'s operations and every iterator `Iterator`'s, so a pipeline is a chain: `values.as_slice().map(f).filter(p).fold(0, add)`. Every iterator is a sequence of itself. Adapters/terminals have ownership bounds; `filter` drops rejected items, so they must be Discardable, while `filter_map` accepts linear items. `map` and `filter_map` may change the item type. find_counted searches its iterator in place and reports the matching item and inspected count. extend preserves the accepted prefix on allocation refusal; collect returns the vector and iterator on either outcome, with the rejected item on failure. Empty collection allocates nothing. Arrays and Vecs enter borrowed pipelines through as_slice(). `enumerate` pairs each item with its position from zero; `zip` pairs the items of two sequences and ends with the first, disposing of an item the first produced when the second ends before it; `take(n)` yields at most n items and stops asking the source after that; `skip(n)` disposes of the first n items it passes and yields the rest. |
| [range](range/range.lin) | `start..end`, `start..=end`, Range | Bounds supply the element type; generic ranges use Steppable. |
| [tuple](tuple/tuple.lin) | Tuple2 to Tuple8, with components `_0` to `_7` | A tuple is a positional aggregate of two to eight components. Write `(1, "a")` to build one, `let (n, name) = pair` to take it apart, and `pair._0` to select a component by its field name; the long form `tuple.Tuple2[UInt8, Str] { _0 = 1, _1 = "a" }` builds the same value. It is copyable where every component is and linear where any is. It is Equatable, Equivalent, Comparable, Ordered, Hash, Default and Release wherever every component is: order compares the components by position, and Release settles them last first. Display writes `(1, a)` and Debug `(1, "a")`. |
| [index](index/index.lin) | Index, FromEnd, `collection[index]`, `collection[^1]` | Index projections identify places; a reader can inspect or mutate the same element. |
| [cmp](cmp/cmp.lin) | Equatable/Comparable; Equivalent/Ordered | Partial comparison and total-order promises differ. Algorithms needing total order should require Ordered. |
| [convert](convert/try_from.lin) | TryFrom and TryInto, [From and Into](convert/into.lin), and numeric conversion syntax | TryFrom observes its source and returns Option, supplying TryInto automatically; From consumes its source and returns the destination directly, supplying Into automatically. All four are in the prelude and all are explicit. `Target(value)` performs a primitive numeric conversion; `Target?(value)` is reserved for newtype construction. Bool is not numeric. |
| [default](default/default.lin) | Default, derived Default | `Default.default()`, or `UInt8.default()` through the type, builds the value a type starts from: zero, false, empty text, None, and a struct whose fields all have defaults when derived. Owning collections do not implement it, because they need an allocator the caller chooses. `http.Limits` and `json.ParseLimits` default to their standard limits; `http.Limits { connections = .Some(1), ..http.Limits.default() }` changes one and keeps the rest. |
| [scalar](scalar/float.lin) | Float64.sqrt, floor, ceil, trunc, round, pow, sin, cos, ln, exp; abs/is_nan; integer bounds | Math returns Float64, including defined NaN/infinity results. round uses ties to even; transcendental precision follows the platform math library. Float64 [Display and Debug](fmt/float.lin) print the shortest decimal that reads back as the same value: fixed notation from 1e-6 up to 1e16 and an exponent outside that range; Nonfinite values print as `inf`, `-inf` and `NaN`. |
| [mem](mem/allocator.lin) | system, Allocator, Buffer; Arena; [Vec](mem/vec.lin); [Closure](mem/closure.lin); [AllocationLog](mem/refusing.lin) | Allocator requires Copyable. Vec.new and Vec.new_in create an empty vector without allocating; growth is fallible. System-backed buffers and vectors require explicit settlement; arena-backed containers may be discarded when their elements are discardable. Buffer release uses its stored allocator. Vec.filled repeats a Copyable value; Vec.from_fn constructs elements by index, including Linear elements. Both allocate exact capacity before initialization when the count is nonzero. Vec.push returns the rejected value on allocation failure; remove transfers an element and shifts the later ones; pop transfers the last element without shifting; drain consumes the vector and hands its elements over first to last; truncate and clear release trailing or all elements, last first, and keep the capacity; finish consumes the vector and succeeds only if it holds nothing. Arena.rewind takes back everything an arena handed out, zeroing only the bytes that were used. Closure.open moves a closure, function or function value into bytes from the system allocator, and Closure.open_in into bytes from an allocator the caller names, so callables with different captures share one `Closure[fn(...), A]` type; a closure requires a releasable callable, allocates nothing for a lambda that captures nothing, and must be released where its allocator's buffers must be; in an arena it may be dropped, so a callable kept there captures nothing that must be released. `AllocationLog.open(backing, refuse_at)` takes its words and every allocation it records from the caller's backing allocator, which may be `mem.system()` or an arena handle, and hands out a `RefusingAllocator[H]` that refuses a chosen acquisition, so a test can walk each allocation-failure path and check with `all_disposed()` that every allocation was disposed once. |
| [hash](hash/hash.lin) | Hash, Hasher; structural Hash derivation | Keys require Equivalent equality and equal keys must hash alike. Integer, Bool, unit, Str and owned String keys are supported, and tuples of them. Hashing is noncryptographic; digests are not persistent identifiers. |
| [collections](collections/map.lin) | Map.new, Map.new_in, get, insert, update, merge, upsert, remove, entries, drain | Empty construction allocates nothing. Lookup/iteration borrow the map. Replacement returns the prior complete entry; insertion refusal returns both incoming fields. Upsert reserves before constructing a missing entry and updates existing values without allocating. Drain transfers owned entries; Release requires releasable keys and values. |
| [release](release/release.lin) | Release, Settle, discard | An optional explicit consuming capability. Deriving it does not schedule it. `Settle` reduces a failure that holds an owned value to its reason; import `std.release` to implement it. |
| [net](net/listener.lin) | listen, serve, Acceptor, Listener, Connection, connect; Address, loopback, any, Backlog | Listener and Connection are linear: close consumes and reports failure, Release makes one best-effort close, and a path that does neither is refused. A listener, connection or file closes with its own `close()`, which needs no import; generic code closes one through `io.Close`. Accept through `use net.Acceptor`, which refines `io.Close`. A connection is an io.Reader, ByteWriter and Writer, so the buffered reader and writer wrap it and return it through abandon and finish. `net.listen(address)` queues 128 connections; port 0 asks for any free port. `net.serve(listener, &handler, connections: .None)` accepts from any Acceptor and calls the handler once per connection with `sink connection` and the peer's address, one connection at a time, so a slow client holds up those queued behind it. The handler owns the connection and closes it, reports its own failures, and may be a closure that keeps state across connections: `var handler = inout [sink visitors = UInt64(0)] \|sink connection: net.Connection, peer: net.Address\| { ... }`, read back with `handler.into_captures()` once serve returns. A reset or exhausted accept is retried after a growing pause, any other accept failure ends serving with `ServeError.Accept`, `connections: .Some(n)` ends it with `Ok` after n connections, and the listener is closed on every exit. `http.serve` runs the same loop through the pieces `net` exposes: `net.accept_attempt` (one try, answering a connection, a retry with its pause, or a failure that ends serving), `net.reached`, `net.finish`, `net.retryable` and `net.accept_pause`. `net.scripted(listener, script, close_failure)` makes a `ScriptedListener` for tests, an `Acceptor` that reports the failures its four-step script names before accepting from the real listener. |
| [time](time/time.lin) | now, sleep, Timestamp, Instant, Duration | `now` reads the wall clock as a UTC Timestamp that displays in RFC 3339; `Instant.now` reads the monotonic clock, and `since`/`elapsed` measure a Duration. `sleep` blocks for at least a Duration on the monotonic clock, sleeping again after an interruption for what remains. A clock the system cannot read panics. |
| [log](log/log.lin) | Logger, to_stderr, Level, LogError, field, and; Sink, Fields, Visitor | A Logger writes leveled lines with key–value fields to a Sink the caller chooses, building each in a buffer from the caller's allocator and writing it whole. Logging reads the logger, so a logger to standard error copies freely; one that owns a file moves and is released. A line below the minimum level costs one comparison. `log` reports a line that could not be written; `debug`, `info`, `warn` and `error` drop it. A field borrows its value. |
| [http](http/serve.lin) | serve, Router, Handler, Endpoint, Observer, Event, Request, Response, Error; Extract, Path, Query, Json, Form, Params, ParamValue; text, json, bytes, status, stream, error; logged; with_request_ids, with_request_ids_in; with_state; new_request; listen_and_serve | A handler is a named function whose parameters are an optional `inout` state, up to six extractors and a read-only request last, and returns `Result[Response, Error]`; `Router.route` reads each extractor (`http.Path`, `http.Query`, `http.Json`, `http.Form` or a type of its own that implements `Extract`) in parameter order, answers the first refusal with its status, and releases what it read, last first, and `route_raw` registers a closure or a function of the state and the request that reads its own inputs with `request.extract[T]()`; `with_state` owns the state and lends it down through every middleware to the route that answers, and releases it with the server. Requests are served from one arena carved from the caller's allocator: each request is read into it, the handler builds its response in it with `request.allocator()`, and it is rewound once the response is written, so a handler releases nothing. The body is read before the handler runs, bounded by Limits. `?` turns the library's errors into the status that answers them. `stream` writes a body through a BodyWriter after the head is sent, from a closure that may capture what its handler computed. `listen_and_serve(address, handler, state:, parent:, limits:)` opens the listener, announces its bound address to the handler as `Event.Listening` (`http.logged` logs it), serves, closes the listener and releases the handler on every exit, and fails with `ListenAndServeError` (`Listen(NetError)`, or `Serve(ServeError)` for what ended serving); it announces the address once serving can begin, so a server that refuses its limits logs no `listening` line. `state:` defaults to `()` and `parent:` to the system allocator; a call that passes `state:` shares it with the routes and gets it back when serving ends, which the caller releases, and a call without it returns `()`. A program that opens its own listener calls `serve(listener, &handler, parent:, limits:)`, whose `parent:` also defaults to the system allocator. serve takes a 4 KiB buffer from the parent before accepting, which each 503 discards the unread request into, and ends with `ServeError.Memory` when that is refused. serve owns the listener and closes it on every exit; one failed connection never stops it, and it writes no log of its own: each exchange is reported through `Observer`, which every handler ignores unless it implements it, and `http.logged` logs them. `with_request_ids(handler)` numbers each request 1, 2, 3, ...: the handler reads the number as the request's `X-Request-Id` header (a client-sent one is removed), the handler's response or refusal carries it, and, placed outside `logged`, the number appears in the logged line as `request_id=N`, read from a field only this middleware sets; it keeps two buffers for the rebuilt request, from the system allocator or from the one `with_request_ids_in(allocator, handler)` takes, which keep the size of the largest head seen, and answers 500 without a number when they cannot grow. |
| [testing](testing/testing.lin) | assert, assert_eq, assert_ok_eq, assert_err; Recorder; each_allocation_failure, refused, oom_is_a_refusal; AllocationLog, RefusingAllocator | A test function may omit its return type; `?` on an assertion fails the test. assert checks Bool; assert_eq compares complete Equatable + Debug values and reports both sides. Give assertions a useful message; `Recorder.of(bytes)` records formatted output into a buffer from the system allocator, and `Recorder.of_in(allocator, bytes)` from the caller's, so a test can inspect it without pretending to expose owned Str. `each_allocation_failure(backing, body, is_refusal)` runs an `inout fn(allocator) -> Result[(), E]` body, which may change a place it is lent `inout`, over logs opened from `backing` once to count its allocation attempts, then once per attempt with that allocation refused, and returns the attempts it walked; the unrefused run must succeed and attempt at least one allocation, and a refused run may complete when the refusal was optional or return an error `is_refusal` accepts, so any other error, such as a failed assertion, fails the walk. A body that asserts reports its refusal with `testing.refused(...)` and passes `testing.Failure.is_refusal`. A body whose only error is `mem.Oom` passes `testing.oom_is_a_refusal`, which takes nothing but `Oom`, so an asserting body cannot pass it and have its assertions bind only the unrefused run. Which variants of a library error type are refusals is that library's own classification, so the per-type `is_refusal` methods are internal, and a caller outside the library names one of these two instead. AllocationLog and RefusingAllocator are mem's, re-exported here so a test finds them beside the assertions that use them. |

A signature spells out a fact the programmer decides: which allocator a
container takes memory from, whether an argument is lent with `inout` or given
away with `sink`, and which parameter a result borrows from or carries.
Repetition that proves nothing is removed instead: a call infers what has one
possible answer, and a container's allocator parameter defaults to the system
allocator, so `Vec[Str]` is `Vec[Str, mem.SystemAllocator]`. A declaration that
declares an allocator parameter of its own writes the allocator of every type
that has one ([T-DefaultedAllocator]). Ceremony that carries an ownership proof
stays; incidental repetition goes.

The same rule names the system allocator by name rather than by argument. A
constructor or function that allocates has a system form and an `_in` form:
`Vec.new()`, `io.BufferedReader.open(capacity:, reader:)`, `"tea".to_owned()`,
`fmt.render_owned(value)` and `json.parse(text)` use the system allocator, and
`Vec.new_in`, `BufferedReader.open_in`, `to_owned_in`, `render_owned_in` and
`json.parse_in` take the allocator first. An allocator built over a backing,
such as `mem.Arena.open(backing, size)` or
`testing.each_allocation_failure(backing, ...)`, keeps its backing argument.

Parameter names are part of APIs: `text.slice(from: 0, to: 3)` explains the
two bounds, while `text.length()` needs no extra label. Callback implementations
choose their own parameter names: `|sink parcel|` can satisfy a signature whose
parameter is called `item`. Named calls through a callable use its contextual
interface labels; direct calls retain the function's declared labels. Types,
conventions, defaults and ownership effects still have to satisfy that interface.

Defaults must be constant expressions in the supported constant-expression model.
Literal-backed text, integers and booleans are supported; generic-value and
parameter-dependent defaults are not available. Do not
invent a default capacity, error policy or resource merely to make an argument
optional.

An arena handle borrows its arena. Buffers retain the allocator used to
create them, and their `release()` dispatches through that allocator. Keep an
Arena alive until its handles, buffers, vectors and text have had their last use.
Copied owned text can outlive the input it copied; a `Str` view still observes
its backing owner.

Line reads preserve raw pending bytes after allocation, input, encoding or limit
failure. Inspect or take those bytes, resume an incomplete record, discard under
a byte budget, or abandon the reader. Taking pending bytes disables resume;
discard still remembers whether the failed record's delimiter was consumed.
Prompts write and flush stderr before reading the supplied buffered stdin, also
under redirection. `prompt_with` accepts a supplied reader and writer.

The [log filter](../examples/log_filter.lin) demonstrates bounded borrowed lines
and explicit output settlement. The [config editor](../examples/config_editor.lin)
keeps parsed views in an input owner, renders owned output, and saves atomically.
Its batch stdin mode never prompts from the same consumed stream.

Set collections, HTTP clients, TLS and concurrency APIs are not provided; the
HTTP server answers one request per connection, one connection at a time.
Only a root whose `linea.json` grants `"extern": true` may declare `extern`
functions; the standard library's manifest,
`{ "kind": "library", "name": "std", "extern": true }`, is the one that does.
That manifest is also what makes this directory the standard library, so
`linea check std` and `linea test path/to/std` compile it as itself from any
working directory.

## Derive structural traits

Put a shared structural implementation beside its type with an attribute:

```linea
@derive(Equatable, Equivalent, Comparable, Ordered)
struct Version { major: UInt8, minor: UInt8 }
```

The [release comparison](../examples/release_comparison.lin) uses this complete
request. Prerequisites stay explicit: Equivalent and Comparable both require
Equatable, while Ordered requires both. Comparison follows field-declaration
order, so major versions take priority over minor versions. Reordering fields
changes that comparison. Keep handwritten implementations when domain equality
or ordering differs from the representation; Float64 fields cannot promise total
order through Ordered.

`@derive` may join policies in a group, such as
`@(copyable, derive(Equatable, Debug))`. Imports and qualified trait names work
normally, and separate attributes retain their written order. Attributes attach
to structs, enums and newtypes. The closed set is `opaque`, `linear`, `copyable`
and `derive(...)`; these are not user-defined annotation functions. The
[copying, settling and sealing guide](../docs/learn/04-copying-settling-and-sealing.md)
explains when to choose each policy.

An attached derive on a generic type requires the trait of each field type
that names a parameter, and nothing more:

```linea
@derive(Equatable, Debug)
struct Labelled[T] { label: Str, value: T }
```

`Labelled[T]` compares and debugs where `T` does, so `Labelled[Token]` may
exist while `Token` has no equality; comparing one is refused at the
comparison, naming `Token`. A field such as `tag: Tag[T]` requires only
`Tag[T]: Equatable`, a phantom parameter requires nothing, and the type's own
declared bounds still apply. A recursive field, such as
`children: Vec[Tree[T], A]`, relies on the implementation being derived.

An array compares, orders, hashes and prints through its elements, so a field
such as `octets: [UInt8; 4]` derives `Equatable`, `Equivalent`, `Comparable`,
`Ordered`, `Hash` and `Debug`.

A derived `Release` settles fields in reverse declaration order: the last field
first. A field whose type implements `Release` is released. A field whose type
is discardable without implementing `Release` — an allocator, an array of
numbers, a copyable record — is discarded with `release.discard`, which runs
nothing. So `struct Pool[A: Allocator] { allocator: A, items: Vec[UInt64, A] }`
releases its vector and keeps nothing else to settle. Declare a field before
the fields that depend on it, so it is released after them.

Write a standalone request to state the implementation's environment
yourself, such as a stronger bound than its fields need:

```linea
struct Cell[T] { value: T }

derive[T: Equatable + Copyable] Equatable for Cell[T]
```

A standalone request states its whole environment; the compiler adds no bound
to it. Derivation never adds unrequested prerequisite implementations. Deriving
Hash also uses the ordinary same-type Key default; borrowed queries can supply
a distinct Key implementation as described below.

## Convert a domain value

Implement `From[Source]` for the destination of a total, consuming conversion.
The library supplies `Into[Destination]` for Source from that implementation.
Both are in the prelude, so `let celsius: Celsius = fahrenheit.into()` needs no
import; the result type selects the
destination. `Into.into(fahrenheit)` and `From.from(fahrenheit)` accept the same
result context, and `Celsius.from(fahrenheit)` names the destination through
its type. Without a known destination, supply a type annotation. Ordinary
assignment does not invoke conversions, and neither trait supplies the reverse
conversion.

A local construction can name its type directly, such as
`let reading = Fahrenheit { value = 68.0 }`. Conversion remains explicit; a
struct literal does not invoke From, Into, TryFrom or TryInto.

From is the implementation point: a handwritten Into implementation overlaps
the library bridge under Linea's structural coherence rule. Predicates do not
make overlapping headers disjoint. Implementation ownership also remains
Linea's: From belongs in the trait or destination's module. Declaring only the
source locally does not permit implementing From for a foreign destination.
Because Into comes only from that bridge, neither trait converts an application
type into a library type such as `Float64` or `Str`. Give the application type
a method instead, such as `celsius.degrees()`.

The [temperature report](../examples/temperature_conversion.lin) uses From/Into
for Fahrenheit-to-Celsius conversion, then TryInto for a thermostat setting
restricted to 5–35°C. The report handles both acceptance and refusal and reads
the Celsius value again after the conversion. Float64 rounding and nonfinite values
follow ordinary arithmetic; a total conversion promises no value-level refusal,
not exact physical measurement.

From/Into transfers owned obligations and can preserve external dependencies
from its source. It cannot return a view into storage destroyed by consuming
that source. Implement the observing, destination-oriented
`TryFrom[T] -> Option[Self]` for conversions that can refuse a value; the
library supplies `TryInto` from it as it supplies `Into` from `From`. Use a
Result-returning API when the caller needs an error or allocation-failure
information. Implementing From does not make a fallible conversion infallible.

For integer conversion that reports an out-of-range value, write
`let narrowed: Option[UInt8] = source.try_into()`.
Primitive conversion such as `UInt8(source)` instead traps if the value does
not fit. `Percent?(source)` asks a newtype's refinement to accept or refuse its
construction; this syntax does not invoke TryFrom and is not numeric conversion.

## Wrap an error while propagating it

`?` converts an error of another type through the enclosing function's error
type's `From` implementation. Implement `From[ParseError] for ConfigError`
once, and every `parse(text)?` in a function returning
`Result[T, ConfigError]` wraps the parse error the same way. An error of the
function's own type passes through unchanged. Without an implementation, `?`
reports which `From` it needs; it never searches other enums for a matching
variant.

When the implementation only wraps the source in the variant that holds it,
derive it: `@derive(From[ParseError])` on `enum ConfigError { Parse(ParseError),
... }` writes that `impl`. The entry names the source, so only a named source
converts, and each entry needs exactly one variant whose only field has that
type: a source no variant holds, or two variants holding the same type, is
refused at the entry. A conversion that chooses a status or
answers with a variant that carries nothing stays an `impl`.

Write `operation().map_err(.Allocation)?` when the wrapping belongs to one site
rather than to every error of that type. The enclosing Result's error enum
supplies the `Allocation` variant, which must carry exactly the operation's
error. A typed result such as
`let mapped: Result[UInt8, RenderError] = source.map_err(.Allocation)` also
supplies that enum. Without a result context, keep the qualified
`RenderError.Allocation` constructor.

The [config editor](../examples/config_editor.lin) derives `From` for its
path, input, file, parse, prompt, render and save errors and for the
allocation failures of rendering, and propagates each with plain `?`; reading
text releases the bytes of a failed read or decode itself, as described below.
Its callbacks whose variant names the step that failed rather than the error's type
remain explicit closures. A nullary variant or a variant carrying several
values also needs a closure; constructor callbacks consume one payload.

## Settle a failure that hands a value back

An operation that consumes a value and then fails hands the value back inside
its failure, so nothing is lost: `Vec.push` returns the element in
`PushFailure`, `Map.insert` the key and value in `InsertFailure`,
`json.Value.insert` the member in `MutationFailure`, `String.from_bytes` the
bytes in `Utf8Failure`, `fs.read_file` the bytes it read in
`ReadFileFailure`, and a buffered reader or writer that cannot allocate its
buffer the stream it was given in `BufferOpenFailure`. When the caller has no use for the
returned value, `settled()` releases it and keeps only the reason:

```linea
let previous = &document.insert("summary", summary).settled()?
```

A refused insertion releases `summary`, and `?` converts the
`json.MutationReason` through the function's `From` implementation, like any
other error. A successful insertion still returns the member it replaced.
`?` never gives up a value for you: no `From` conversion in the library
releases what a failure hands back, so `&items.push(item).settled()?` is how a
function returning `mem.Oom`, `http.Error` or any other error drops a refused
item. The written `settled()` is the one place a reader sees the drop, and a
failure that closes a stream, such as `BufferOpenFailure`, is dropped in the same
visible way.

`fs.read_text(path, max_bytes)` and `io.read_text(&reader, max_bytes)` read and
decode UTF-8 in one call, from the system allocator; `fs.read_text_in` and
`io.read_text_in` take the allocator first. They release the bytes
of a failed read or decode, so their errors, `fs.ReadTextError` and
`io.ReadTextError[E]`, own nothing. Use `read_file` or `read_all` and
`String.from_bytes` to keep the bytes a decode refuses.

`Release` and `Settle` answer different questions, and every failure that
holds an owned value implements both. `Release` consumes the whole failure and
returns nothing, so a match arm that drops the failure, reason included, calls
`failure.release()`. `Settle` consumes the owned part and returns the reason,
so `Result.settled()` is the idiom wherever the code goes on with the reason:
propagating it with `?`, printing it, or mapping it with `map_err`.

`Release` never returns a reason, so it may drop a failed close; `Settle` never
does. Settling a failure that holds a stream closes the stream through
`io.Close` and keeps a failed close beside the original reason:
`fs.ReadFileReason` holds the read error and the close error,
`io.BufferOpenReason` the buffer refusal and the close error, and
`io.FinishReason` the write failure and the close error. Each renders the
close failure after the reason it accompanies.

A program's own failure type implements `release.Settle` after `import
std.release`, naming its reason as `type Reason`. `settled()` needs no import,
but calling `settle` on a failure directly, as `failure.settle()`, needs the
trait in scope with `use release.Settle`. Match the failure instead of settling
it when the returned value is still wanted, for example to retry a push after
freeing room.

Use a written `defer output.release()` when several failure exits must dispose
partial output. Returning the output moves it to the caller and skips that
schedule on the successful path. The config editor's parser and renderer use
this pattern; an earlier explicit `release()` remains useful when storage must
be freed before the scope ends.

For complete test values, `testing.assert_eq(result, .Err(.Overflow(2)), message)?`
checks both the Result variant and payload and reports their Debug forms; the
expected value takes its type from the result. `testing.assert_ok_eq(result,
expected, message)?` compares only a success payload, and
`testing.assert_err(result, message)?` accepts any error. For another shape
check, use `testing.assert(match read result { ... }, message)?`.
Reading the pattern leaves the result owned by the caller. Schedule an eligible
release before the assertion, or settle its resources before propagating an
assertion failure.

## Pick the verb that ends a value

Values that own something end through one of a few verbs. They are not
interchangeable: each promises something different, and a type offers the ones
its contract allows.

| Verb | What it promises | Where |
| --- | --- | --- |
| `release()` | Disposal that cannot fail and answers nothing. `Release` is optional: a type that needs a choice, such as commit or roll back, leaves it out. A failure's `release()` drops the reason along with the owned part. | Every type that implements `Release`; `defer value.release()` schedules it. |
| `close()` | Disposal that can fail, answering `Result[(), CloseError]`. Its `Release` closes too and drops the result, so call `close()` when a failed close matters. | `io.Close`: `fs.File`, `net.Listener`, `net.Connection` |
| `reset()` | A close the peer sees as a reset, discarding what was never sent. The descriptor is closed even when the reset cannot be arranged, and that failure is the one reported. | `net.Connection` |
| `finish()` | Completes a protocol or a producer, and what it answers depends on the type. It is not a synonym for cleanup: where storage is freed, that is a consequence of completion. `Vec` and a map `Drain`: `Ok(())` only when the collection is empty (a collection with linear elements is finished once every element was handed over), otherwise the value comes back intact. `BufferedWriter`: the writer is flushed, every pending byte written, and the writer returned, or the whole buffered writer comes back with the failure. `Hasher`: the digest is complete, and the stream stays usable. A response body is complete when it is finished. | `Vec`, `Map` drains, `io.BufferedWriter`, `hash.Hasher` |
| `abort()`, `abandon()` | Gives up buffered data deliberately and returns the underlying resource: `abort` drops a writer's pending bytes, `abandon` drops a reader's buffered input. Neither can fail. | `io.BufferedWriter`, `io.BufferedReader` |
| `into_inner()`, `into_parts()`, `into_captures()` | Takes a wrapper apart and hands back what it held, without disposing of anything: an adapter's iterator, an adapter's iterator and callback, or what a closure captured. | iterator adapters, closures |
| `settle()`, `settled()` | Releases the owned value a failure handed back and keeps the reason, so `?` and `map_err` can go on with it. `settled()` applies it to a `Result`. | `release.Settle` |

`release()` and `close()` differ in what they let you ignore: `release()`
promises there is nothing to report, and `close()` reports what could go wrong.
`finish` completes something and `abandon` gives something up; neither is a
disposal verb, and `finish` is never a synonym for cleanup. To end a value that
only needs disposing, use `release()` or `close()`. Each of the two belongs to
the types above, and their entries in the module table say what the type owes
you.

A `defer` schedules one of these verbs where the value is made. It runs on
every way out where the value is still held, and a path that hands the value on
skips it, so it is wrong only when every path hands the value on
([`O-DeferDead`](../docs/learn/04-copying-settling-and-sealing.md#a-defer-and-a-move)).

## Errors by module

Every fallible operation answers its own error type, named in its signature. A
function that calls several of them wraps each in its own enum through
[`From`](#wrap-an-error-while-propagating-it); no shared error trait or context
type does that for you.

| Module | Error types | Raised by |
| --- | --- | --- |
| mem | `Oom`, `PushFailure[T]` | `Oom` for a refused allocation. `Vec.push` hands the value back inside `PushFailure[T]`. |
| text | `Utf8Error`, `Utf8Failure[A]`, `TextError`, `ParseError`, `SplitError` | `Str.from_bytes`; `String.from_bytes` (hands its bytes back); appends (`Encoding` or `Allocation`); `Str.parse`; `Str.split` with an empty separator. |
| io | `IoError`, `WriteFailure[E]`, `InputFailure[E]`, `LineError[E]`, `ExactError[E]`, `ReadAllError[E]`, `ReadAllFailure[A, E]`, `ReadTextError[E]`, `PromptError[I, O]`, `BufferError`, `BufferOpenFailure[R]`, `FinishFailure[W, A, E]` | Console and descriptor calls answer `IoError`; readers and writers carry their own error type `E`; buffered operations that consume a stream hand it back in a `...Failure`. |
| fs | `FsError`, `FsFailure`, `PathError`, `ReadFileError`, `ReadFileFailure[A]`, `ReadTextError` | `File` and `write_file`/`save_atomic` answer `FsFailure`; `Path` construction `PathError`; `read_file` hands the partial bytes back in `ReadFileFailure`; `read_text` answers a `ReadTextError` that owns nothing. |
| net | `NetError`, `ServeError` | `listen` and `connect` answer `NetError`; closing a socket answers `io.IoError`; `net.serve` ends with `ServeError`. |
| http | `Error[P]`, `RouteError`, `RequestError`, `HeaderError`, `ParamError`, `ServeError`, `ListenAndServeError` | A handler answers `Error[P]`, which carries the status; `Router.route` answers `RouteError`; `new_request` and header and parameter parsing answer the others; `serve` ends with `ServeError`, and `listen_and_serve` with `ListenAndServeError`: `Listen`, or `Serve` carrying the `ServeError`. |
| json | `ParseError`, `DecodeError[A]`, `EncodeError[E]`, `NumberError`, `NumberAccessError`, `KindError`, `MutationFailure[A]` | One per operation: parsing, decoding into a type, encoding, reading numbers, asking a value for the wrong kind, and editing a document (which hands the member back). |
| collections | `InsertFailure[K, V]`, `UpsertFailure[K, V, E]` | `Map.insert` and `merge` return the key and value on refusal; `upsert` also carries its constructor's own error `E`. |
| log | `LogError[E]` | `Logger.log`; `debug`, `info`, `warn` and `error` drop it. |

A `...Failure` that holds an owned value converts to its reason with
[`settled()`](#settle-a-failure-that-hands-a-value-back). A program with several
of these writes its own enum, one variant per error, and a derived `From` for
each, as the [config editor](../examples/config_editor.lin) does.

## Calculate with floating-point values

Float64 methods are available without an additional import. Use `sqrt()` for
distances, `sin()` and `cos()` for angles in radians, and `pow(exponent: ...)`,
`ln()` and `exp()` for powers, natural logarithms and exponentials:

```linea
let width = 3.0
let length = 4.0
let diagonal = (width * width + length * length).sqrt()
let balance = 1000.0 * Float64.pow(1.05, exponent: 10.0)
```

`floor()`, `ceil()`, `trunc()` and `round()` return integral **Float64** values.
They round toward negative infinity, positive infinity, zero and the nearest
integer, respectively. `round()` sends halfway values to the even integer:
`Float64.round(2.5)` is `2.0`, and `Float64.round(3.5)` is `4.0`. An integer
conversion remains a separate, explicit operation and traps when out of range.

These functions return values directly. `sqrt()` and `ln()` of negative nonzero
inputs produce NaN; `Float64.ln(0.0)` produces negative infinity. Applications that
reject these inputs should validate their domain. Square roots are correctly
rounded; finite powers, trigonometric functions, logarithms and exponentials
have platform-dependent precision. Do not rely on their last bits matching
across platforms. The doc comment at the top of
[scalar/float.lin](scalar/float.lin) states the special values the methods must
return for signed zero, infinities and NaN, such as `(0.0 / 0.0).pow(0.0) == 1.0`.

The [room diagonal](../examples/room_diagonal.lin) rounds a distance to
millimetres. The [periodic signal](../examples/periodic_signal.lin) samples sine
and cosine, and the [growth forecast](../examples/growth_forecast.lin) compares
annual and continuous growth and calculates the time to a target balance.

## Lay out values with a format spec

A colon inside an interpolation lays its value out. The spec is written
`[[fill]align][+][0][width][.precision][?]`, every part optional and in that
order:

| Interpolation | Value | Writes |
| --- | --- | --- |
| `{name:<10}` | `"tea"` | `tea       ` |
| `{count:>4}` | `42` | `  42` |
| `{title:=^11}` | `" menu "` | `== menu ===` |
| `{day:02}` | `7` | `07` |
| `{change:+}` | `3` | `+3` |
| `{loss:04}` | `-5` | `-005` |
| `{price:.2}` | `3.5` | `3.50` |
| `{weight:>8.3}` | `1.25` | `   1.250` |
| `{name:*^9?}` | `"tea"` | `**"tea"**` |

`<`, `>` and `^` put the value on the left, the right or in the middle of the
width, and a character written before the alignment is the fill. Without an
alignment a number sits on the right and anything else on the left. The width
counts Unicode scalars, so `café` takes four columns, and a wider value is
written whole. `+` signs a number that is not negative, `0` pads a number
with zeros after its sign in place of a fill and an alignment, and
`.precision` gives a `Float64` that many digits after its point, rounding the
shortest digits that print it half away from zero, so `2.675` with `.2` is
`2.68`. `?` renders through `Debug` and combines with the rest. The compiler
refuses a part the value's type does not take, such as a sign or a precision
on text.

`Display` and `Debug` for `Float64` print the shortest decimal that reads back
as the same finite value, so `0.1` prints as `0.1` and `0.1 + 0.2` as
`0.30000000000000004`. Magnitudes from `1e-6` inclusive to `1e16` exclusive use
fixed notation, and other nonzero magnitudes use scientific notation, as in
`1e16`, `1e21` and `5e-324`. A fixed integral value keeps its `.0`; positive and
negative zero print as `0.0` and `-0.0`, infinities as `inf` and `-inf`, and
every NaN as `NaN`. With a precision, a negative value keeps its minus sign
after rounding, so `-0.001` with `.2` is `-0.00`, and infinity and NaN ignore the
precision, are padded with the fill rather than zeros, and NaN takes no sign.
Formatting propagates the writer's first error. Library error and failure types
implement `Display` by rendering their reason, and a failure that owns resources
such as partial bytes or a returned writer is borrowed while it renders, so its
owner still settles it. `Range` renders as `lo..hi` or `lo..=hi` and `FromEnd`
as `^k`; containers do not implement `Display`.

A layout chosen at run time is a `fmt.Spec`. `fmt.Spec.default()` is the
layout of an interpolation without a colon, and struct update changes only what
differs from it:

```linea
// Pad every name to the longest one, so the columns after it line up.
let name_column = fmt.Spec { width = widest, ..fmt.Spec.default() }
fmt.write_display(purchase.name, name_column, &w)?
io.line(" {purchase.amount:>9.3} {purchase.unit:<3} {dollars:>6}.{cents:02}", &w)?
```

`fmt.write_display`, `write_debug`, `write_integer` and `write_float` apply a
spec to a value and a writer. An interpolation calls one of them with the parts
it wrote, chosen by the value's type once that is concrete, so a generic
`{value:5}` puts an integer on the right of its width and text on the left. The [grocery receipt](../examples/grocery_receipt.lin)
prints a receipt this way, and the
[frequency report](../examples/frequency_report.lin) right-aligns its counts.

## Count and look up keyed values

```linea
import std.collections
import std.mem
import std.io

fn main() -> Result[UInt8, io.IoError] {
    var counts: collections.Map[Str, UInt64] = collections.Map.new()
    defer counts.release()
    &counts.insert("tea", value: 1).unwrap().release()
    let _updated = &counts.update("tea", |sink count| count + 1)
    let total = *counts.get("tea").unwrap()
    io.println("tea: {total}")?
    .Ok(0)
}
```

`get` returns an observation of the stored value. Its last use must precede a
mutation or release of the map. `insert` returns `Ok(None)` for a new key and
`Ok(Some(entry))` for a replacement; the old entry includes both its key and
value. `Err(failure)` owns the rejected key/value and its allocation error.
The `.release()` above explicitly disposes a possible replaced entry.
`remove` likewise returns ownership of the removed entry.

`update` invokes a consuming value transform exactly once when the key exists,
keeps its key, and allocates nothing. `entries()` yields borrowed key/value
pairs in unspecified order. For values without Release, consume the map with
`drain()`, walk it lent with `for entry in &drain { … }`, settle each entry,
and finish with `drain.finish()`. Early release of a
map or drain is available only when both key and value implement Release.

`&map.upsert(query, make_entry, transform)` combines lookup and the choice
between insertion and update. It takes both callbacks, which may change a
place they are lent `inout`, drops them when it returns, and returns
`Result[(), UpsertFailure[K, V, E]]`, which `settled()` reduces to an
`UpsertReason[E]`. For an existing key, only the consuming
`transform` runs; it settles the old value and returns its replacement. For a
missing key, the map reserves storage and then calls `make_entry(query, allocator)`
once. The factory returns a complete Entry or its own error. It can copy owned
text from the query without making the map retain that temporary query.
`&map.upsert_inout(query, &make_entry, &transform)` borrows both callbacks
instead, so one factory can serve many calls and what it owns can be recovered
afterwards.

Use `upsert` when a missing key needs owned storage built from a borrowed query,
so a hit allocates nothing. Its factory may carry only the map's allocator and
its own captures, never the query.

When the key is cheap to build, `&map.merge(key, value, combine)` is the
one-call form. A hit calls `combine(current, incoming)` once, keeps the
resident key, discards the incoming one and allocates nothing; a miss inserts
the key and value. Allocation refusal returns both in `InsertFailure` and
leaves the map unchanged. The key type must be discardable, because a hit
drops it. The [warehouse stock](../examples/warehouse_stock.lin) example adds
deliveries this way.

`Allocation(reason)` reports reservation refusal before either callback runs.
`Factory(error)` returns the factory's error, and `KeyMismatch(entry)` returns
an entry whose key does not match the query or its hash. Factory failure and
mismatch preserve logical contents, but reservation may already have grown or
rehashed storage. `upsert` consumes both callbacks and drops them on every
path, so neither may own anything that requires explicit settlement; with
`upsert_inout` the caller keeps both callbacks on every path, including any
captures requiring explicit settlement. Release of the failure is available
only when its key, value and factory error support Release.

The [frequency report](../examples/frequency_report.lin) uses owned String keys,
so counts outlive the file contents they came from. It trims Unicode whitespace,
skips blank lines and preserves case. Run its sample or supply a UTF-8 file:

```sh
nix develop -c zig build run -- run examples/frequency_report.lin
nix develop -c zig build run -- run examples/frequency_report.lin -- names.txt
```

Insertion requires `hash.Hash`, whose `Equivalent` supertrait defines reflexive,
symmetric and transitive equality. Key equality and hash results must remain
stable while stored. Derive Equatable, Equivalent and Hash together for structural
keys; a custom equality policy needs a compatible explicit Hash implementation.
Lookup, removal, update and upsert require `hash.Key`, with an associated `Query` type
and `matches(self, query)` operation. Scalar and Str keys query by their own type;
String keys query by Str, so `counts.get("tea")` needs no temporary owned string.
Hashable concrete keys receive a default Key implementation with `type Query = Self`
and an equality comparison. Explicit Key implementations override this default,
as String's Str query does. Generic lookup helpers require a Key bound and accept
`K.Query`; they cannot assume that every key queries by its own type.
Matching queries and stored keys must have equal hashes,
and a query must match at most one key equality class. Equivalent stored keys match the same queries.

The [warehouse stock example](../examples/warehouse_stock.lin) derives equality
and Hash for a `{ product, warehouse }` struct and totals
deliveries separately for each product and warehouse. Fresh struct values query
the totals without allocating text or requiring an explicit Key implementation.

`let tea = "tea"` already creates a Str without allocation. Use
`tea.to_owned()?`, or `tea.to_owned_in(allocator)?`, when independent owned storage is needed; the returned
String retains its allocator but not the source text. The frequency report
copies only newly inserted keys. String hashes contents, not allocation addresses. Different keys may collide;
probe chains still compare equality. Hash values and map order can change with
the implementation. This deterministic hash does not provide adversarial
collision resistance for untrusted network input.

## Borrow a collection for a pipeline

Arrays and Vecs expose `as_slice()`. An array also reports its count with
`length()` without building a view, and on a constant array that count is a
constant. A Slice's `iterate()` yields `borrow T`,
keeping each element in its original owner. Subspans use the same iterator.
`Sequence` provides the pipeline operations `map`, `filter`, `filter_map`, `fold`,
`find`, `find_map`, `any`, `all`, `for_each`, `collect`, `enumerate`, `zip`,
`take`, `skip` and their `_inout` forms, and `Iterator` provides the in-place
searches `find_counted` and `find_counted_inout`; every iterator is also a
sequence, so it offers both, and `Sequence.map(values, f)` is the same operation
as `values.map(f)`. A callback is taken `sink`, so a named callback is moved by
its first use and a copyable one is passed as `copy(f)` to be used again; the
comment after `Sequence` in [iter/iter.lin](iter/iter.lin) states the rest of
the convention.
Slices compare, order, hash and print by their elements, so
`testing.assert_eq(values.as_slice(), expected.as_slice(), message)` checks a
vector against an array in one assertion.
Reading a scalar with `*parcel` produces an independent value; moving an owned
record out of an observation is rejected. Keep the owner alive until the last
use of the iterator or any yielded observations. Later mutation is allowed once
those observations are no longer used.

The [parcel manifest](../examples/parcel_manifest.lin) filters a borrowed array
prefix using a configurable limit, transforms borrowed weights through a named
callback, collects independent shipping weights, and walks the resulting Vec.
It also recovers the inspection callback's counter and handles insertion failure.

```sh
linea run examples/parcel_manifest.lin
linea test examples/parcel_manifest.lin
```

`iterate` allocates nothing and discarding its view does not release source
values. `collect` retains its existing explicit failure/remaining-iterator
contract. Consuming array/Vec adapters, flatten, generic array
lengths and mutable stored views are separate capabilities and are not supplied
by borrowed iteration.

`enumerate` pairs each item with its position, counting from zero, and `zip`
pairs the items of two sequences. A tuple pattern in the `for` takes each pair
apart. This program prints each parcel's name beside its weight:

```linea
import std.io

fn main() -> Result[UInt8, io.IoError] {
    let names = ["crate", "drum", "pallet"]
    let weights: [UInt64; 3] = [12, 40, 95]
    for (name, weight) in names.as_slice().zip(weights.as_slice()) {
        io.println("{name}: {*weight} kg")?
    }
    .Ok(0)
}
```

Each item of a slice is still borrowed from its owner, so `*weight` reads the
number, and the owner stays unchanged while the walk runs. `zip` stops when
either sequence ends. It draws from the first sequence first, so when the
second ends first, `zip` disposes of the one item it already drew from the
first. Only the first sequence's items must therefore be Discardable; the
second sequence's items are never disposed of that way. A linear first item is
refused at the call:

```text
error[T-Bound]: `Self.Iter.Item` requires `Discardable`, and `Job` does not have that capability
   --> tests/iter/a_zip_over_a_linear_first_item_is_refused.lin:34:26
    |
34  |     for (job, n) in jobs.zip(UInt8(1)..3) {
    |                          ^^^ `zip` may dispose of a `Job`, so it requires the type to be Discardable; give the value to an operation that keeps it, or settle it before. `zip` draws an item from the first sequence before asking the second, and if the second sequence ends first it disposes of that first item, so the first sequence's items must be Discardable; zip in the other order, with the sequence whose items are Discardable first, or walk both sequences by hand
   ::: std/iter/iter.lin
100 |         Self.Iter.Item: Discardable
    |         -------------- required by this `where` clause
```

Putting the sequence of linear values second, as in `(UInt8(1)..3).zip(jobs)`,
is accepted.

Use `&iterator.find_counted(predicate)` when a search also needs its
inspection count. The returned `FindReport` contains `found: Option[Item]` and
`inspected: UInt64`. The count includes a matching item; an unsuccessful search
reports every yielded item. The search stops before reading the next item and
leaves the iterator with the caller. `&iterator.find_counted_inout(&predicate)`
also preserves a mutable callback for reuse.

Both forms require discardable items because unmatched items are discarded.
`find_counted` also drops its predicate when it returns, so it requires a
Discardable predicate; a predicate owning something that must be released is
lent to `find_counted_inout` instead.
They allocate nothing and invoke no Release. A found observation retains its
backing-owner dependencies. The [parcel inspection](../examples/parcel_inspection.lin)
uses this report without extracting a closure's captures; a plain loop and local
counter remain suitable when the application needs different state.

`values.finish()` consumes a Vec or Map and succeeds only if it holds
nothing: `Ok(())` proves every element was handed over, and the storage is
disposed. It is how a container of elements without Release ends. A nonempty
container returns as `Err(still_owned)` with its elements intact; keep
processing that returned owner. A Vec's or Map's `Drain.finish` follows the
same rule, so an early exit can recover the drain and resume it.
`values.finish()?` works where the enclosing error can carry the returned
container. `BufferedWriter.finish` is a different operation: it flushes
pending output and returns the writer.

`values.drain()` consumes a Vec and hands its elements over first to last,
each once, without shifting the rest. `for item in values.drain()` takes the
drain and walks it when abandoning it is allowed: its elements need no
settling and its storage came from an arena. Any other drain is walked lent,
`for item in &pending { … }`, which keeps it with its owner. The loop may leave
early with `break`, `return` or `?`, and the owner settles the drain after the
loop: `pending.finish()` succeeds once every element was handed over and
returns a drain that still holds elements as `Err`, and `pending.release()`,
or `defer pending.release()` written before the loop, releases what is left
when the elements implement Release. `&values.pop()` takes the last element
without moving any other. The [payment batch](../examples/payment_batch.lin)
drains its transactions in order and commits or rolls back each one before
finishing the drain.

For owned text, `line.to_owned()?` copies a Str, while
`fmt.render_owned("name={name}\n")?` builds formatted text; `to_owned_in` and
`render_owned_in` take the allocator first. Both expose
allocation refusal and release partial construction through their written
cleanup. A successful String retains its allocator, so keep that allocator's
backing owner alive until the String is settled. Use an existing writer directly
when the caller does not need an owned intermediate string.

## Read and rewrite a file

The configuration editor is a working file-I/O example. In the development
shell, with `linea` on PATH, create a disposable configuration and change a key:

```sh
printf 'name=Ada\ncount=3\n' > /tmp/linea-config.txt
linea run examples/config_editor.lin -- /tmp/linea-config.txt name Grace
cat /tmp/linea-config.txt
```

The resulting file contains `name=Grace` and `count=3`. Omit the final value to
enter it interactively. The example uses `fs.read_text` and `fs.save_atomic`,
with a read-size limit, UTF-8 validation, owned output and explicit errors. Saving
normalizes key/value lines and removes comments and blank lines.

## Serve HTTP

A handler is a function whose parameters name what it reads, and returns the
response. `http.with_state` owns the state, a router picks the handler by
method and path, and `http.listen_and_serve` opens a listener, accepts
connections and answers one request on each:

```linea
import std.http
import std.io
import std.net

// `Greeter` is the state every handler shares.
@derive(Release)
struct Greeter {
    greeted: UInt64,
}

// `http.Path[Str]` reads the route's one path value, `{name}`, before the
// router calls `hello`.
fn hello(inout greeter: Greeter, name: http.Path[Str], request: http.Request) -> Result[http.Response, http.Error] {
    greeter.greeted += 1
    http.text(request, "hello, {name.value}, visitor {greeter.greeted}\n")
}

fn main() -> UInt8 {
    // The annotation names the state the routes take.
    var router: http.Router[Greeter] = http.Router.new()
    if &router.route(r"GET /hello/{name}", hello).is_err() {
        router.release()
        return 2
    }
    // `listen_and_serve` takes the router, opens the listener, and closes it
    // and releases the router on every path. `state:` is lent to the router
    // on every request and returned when serving ends. `let … else |error|`
    // reports why listening or serving failed and leaves `main`.
    let greeter = http.listen_and_serve(net.loopback(8080), router, state: Greeter { greeted = 0 }) else |error| {
        io.eprintln("{error}")
        return 1
    }
    greeter.release()
    0
}
```

`curl http://127.0.0.1:8080/hello/ada` answers `hello, ada, visitor 1`, and
the next request counts 2. The most specific
pattern matching the method and path answers: at the first segment where two
patterns differ, a literal wins over `{name}`, which wins over `{name...}`. A
path matched only under other methods is answered 405 with `Allow`, and no
match 404.

Requests are served from one arena of `limits.request_arena_bytes` (48 MiB by
default) carved from the `parent:` allocator given to `serve`, which defaults
to the system allocator as it does for `listen_and_serve`. A request's text and body
live there, and so does everything the handler builds through
`request.allocator()`: `http.text` renders any `Display` value, `http.json`
encodes any `json.Encode` value, `http.bytes` answers with bytes already built
there, and `http.status` answers with an empty body. The arena is rewound once
the response is written, zeroing only what the request used, so a handler
releases nothing, and a response kept past it does not compile. A handler refuses a
request with `http.error(request, status, message)`, and `?` converts the
library's own errors into the status that answers them: a body that is not
JSON is 400, a full arena 500. A refused push, insertion or document change
hands its value back, and `?` does not drop it: write `&items.push(item).settled()?`
and the reason answers with its status.

`http.stream(request, write)` answers with a body that `write` produces after
the head is sent, through an `http.BodyWriter`, which is a `Writer`. A
body larger than the arena, such as a generated report, goes out as it is
written, and `body.request()` gives `write` the request it answers. `write` is
any closure or function taking the writer, so it captures what the handler
computed: `http.stream(request, [sink year] |inout body| write_days(year, &body))?`
keeps the checked year in the request's arena until the body runs. When
`write` fails partway, the connection is reset so the client does not take a
short body for a whole one. A test reads a streamed body with
`response.recorded_body()`, which runs it into the arena. The closure lives in
the arena with the rest of the response and is dropped with it, so it may
capture nothing that must be released, such as a vector from `mem.system()`.

What `write` produces is buffered and sent 4 KiB at a time. A body that paces
itself, a line now and the next later, calls `body.flush()` (with
`use io.ByteWriter`) to send each line before it waits:

```linea
fn count_down[P: Allocator](seconds: UInt64, inout body: http.BodyWriter[P]) -> Result[(), http.Error[P]] {
    var left = seconds
    while left > 0 {
        "T-{left}\n".fmt(&body)?
        let _sent = &body.flush()?
        time.sleep(time.Duration.from_seconds(1))
        left -= 1
    }
    &body.write_str("liftoff\n")?
    .Ok(())
}
```

`curl -N` prints each line as it arrives. The
[countdown server](../examples/countdown-server/main.lin) serves it.

The listener is linear, so a path that returns between `net.listen` and
`http.serve` must close it (`listener.close()`) or the
program does not compile. `limits.connections` stops serving after that many
connections, which transcripts use:
`http.Limits { connections = .Some(1), ..http.Limits.default() }` serves one
connection under the standard limits.

`serve` takes its limits from `http.Limits.default()` unless the caller passes
its own. A production server keeps the defaults or raises one it needs; a test
lowers the limit it exercises, so a small request reaches the refusal at once
and a silent client times out in a tenth of a second:

| Limit | Production default | Past it | The library's tests set |
| --- | --- | --- | --- |
| `max_line_bytes` | 8192 | 414 for the request line, 431 for a header line | 32 to 1024 |
| `max_headers` | 100 | 431 | 2 to 8 |
| `max_query_pairs` | 100 | 414 | the default |
| `max_form_pairs` | 100 | 413 | the default |
| `max_body_bytes` | 1048576 (1 MiB) | 413 | 4 to 16384 |
| `request_arena_bytes` | 50331648 (48 MiB) | `serve` refuses to start below what the other limits need; a request that fills it is 500 | 98304, or the least the other limits need |
| `read_timeout_ms` | 5000 | 408 once the whole request, head and body, has taken this long from accept | 100 |
| `write_timeout_ms` | 5000 | one write waits no longer; a stalled write fails and the exchange ends | the default |
| `connections` | `.None`: serve until stopped | `serve` returns | `.Some(n)` for the n connections a test sends |

```linea
// A test of the body limit: a 17-byte body is refused with 413.
let limits = http.Limits { max_body_bytes = 16, connections = .Some(1), ..http.Limits.default() }
```

A JSON document is bounded the same way by `json.ParseLimits`, which `parse`,
`parse_bytes` and `decode` take from `json.ParseLimits.default()`:

| Limit | Production default | The library's tests set |
| --- | --- | --- |
| `max_input_bytes` | 8388608 (8 MiB) | 0 to 4 |
| `max_depth` | 128 | 0 to 1 |
| `max_nodes` | 100000 | 0 to 2 |
| `max_string_bytes` | 1048576 (1 MiB) | the default |
| `max_number_bytes` | 1024 | the default |
| `max_object_members` | 4096 | the default |

Everything the routes share and change lives in one state, like axum's
`State`: `http.with_state(state, handler)` owns it, lends it as `inout state`
through every middleware to the route that answers, and releases it with the
server, so the state may hold a database connection or a vector from
`mem.system()`. `serve` answers one request at a time, so no lock is needed,
and `server.state()` reads it back, such as a count to log once serving
stops. A `Router[S, P]` takes a state of type `S`, named by an annotation on
`Router.new()` or `Router.new_in(allocator)`. A program with nothing to share
leaves the annotation out and serves a `Router[()]`. A handler takes the state
`inout`, even one that only reads it, because the state is one convention; a
handler that does not use it leaves it out and is registered on a router of
any state.

`route` registers a named function whose parameters are an optional leading
`inout state`, up to six extractors and the request last. The router reads
each extractor in parameter order, answers the first refusal with its status,
and releases what it read, last first. `route_raw` registers a closure or a
function taking `inout state` and the request, such as
`[limit] |inout app, request| search(app, request, limit)`. A closure is called for
reading, so its captures are fixed configuration for that one route, and they
may hold nothing that must be released. A count that changes between requests
belongs in the state.

A handler names each input it needs as a parameter, like axum's extractors.
The router answers the request with the refusal when an input cannot be read.
`http.Path[T]` reads the path values the router matched, `http.Query[T]` the
query, `http.Json[T]` a JSON body, and `http.Form[T]` a body sent as
`application/x-www-form-urlencoded`, each wrapping the `T` it read in `.value`.
A type that implements `http.Extract` is read straight into its parameter, and
every extractor implements `Release`. A handler that reads an input itself calls
`request.extract[T]()`, which returns the `T`, and is registered with
`route_raw`:

```linea
@derive(http.Params, Release)
struct Listing {
    page: UInt32,
    limit: Option[UInt32],
}

@derive(Release, json.Decode[mem.Handle])
struct Message {
    text: String[mem.Handle],
}

// A `Message` reads itself from the JSON body.
impl http.Extract[mem.SystemAllocator] for Message {
    fn extract(request: http.Request) -> Result[Message, http.Error] {
        request.extract[http.Json[Message]]()
    }
}

// GET /boards/{board}?page=2
fn list(board: http.Path[UInt64], listing: http.Query[Listing], request: http.Request) -> Result[http.Response, http.Error] {
    let shown = copy(listing.value.limit).unwrap_or(20)
    http.text(request, "board {board.value}: page {listing.value.page} of {shown}")
}

// POST /echo
fn echo(inout app: App, caller: Caller, message: Message, request: http.Request) -> Result[http.Response, http.Error] {
    app.echoed += 1
    http.json(request, Echo { to = copy(caller.name), echo = message.text.view() })
}
```

`derive(http.Params)` fills a struct field by field from the values of the
same names. A field is any `text.Parse` type, such as a number, read by
parsing its value; `Str`, the value as sent; or an `Option` of one, `None`
when the request does not name it. `Path` also reads a single value, such as
`Path[UInt64]` for a route with one `{board}`, from the only value there is;
every query value has a name, so `Query` reads only a struct. The router has
percent-decoded path values, and a query is decoded as an HTML form encodes
it, `+` for a space. A value that cannot be read is answered 400, naming it:
`cannot read path value "board" from "next": invalid decimal syntax at byte 0`.
So is a query that names a field twice, since which value was meant is
ambiguous. A query of more than `limits.max_query_pairs` pairs, 100 by
default, is refused with 414 when the request is read. A field the route has
no value for is the program's mistake and answers 500.

`http.Form[T]` reads a struct the same way from a body sent as
`Content-Type: application/x-www-form-urlencoded`, such as `name=Ada&age=30`;
a body sent as anything else is answered 415, and one of more than
`limits.max_form_pairs` pairs, 100 by default, is refused with 413 when the
request is read, whether or not a route reads it. `request.form_params()`
returns the same `ParamValues` a program's own extractor reads with `field`,
as `request.query_params()` does for the query.

`http.Json[T]` decodes the body into the request's arena with `json.decode`.
A body not sent as `Content-Type: application/json` is answered 415, one that
is not UTF-8 or not JSON 400, and one that does not decode into `T` 422,
naming the problem and where it is: `{}` is answered `missing field at
$["text"]`. An arena too small for the message is the server's shortage and
is answered 500. `Message` owns its text, so it must be released, whichever
allocator it came from: with `mem.system()` the release frees the text, and in
a request's arena it costs nothing.

Any type becomes an extractor by implementing `http.Extract` for every
allocator `P`: `extract` reads the request and returns the value, or the
`http.Error` that answers it instead. `Caller` reads who is calling from an
`Authorization: Bearer <name>` header, and a 401 names the scheme to use in
`WWW-Authenticate`:

```linea
struct Caller {
    name: Str,
}

impl[P: Allocator] http.Extract[P] for Caller {
    fn extract(request: http.Request[P]) -> Result[Caller, http.Error[P]] {
        let name = bearer_name(request.header("Authorization")) else {
            var refused = http.error(request, .Unauthorized, "name the caller with `Authorization: Bearer <name>`")
            &refused.set_header(request, "WWW-Authenticate", "Bearer")?
            return .Err(refused)
        }
        .Ok(.{ name })
    }
}
```

`Caller` borrows its name from the request, so it lives as long as the request
does. `App` is the state, a struct
holding the program's logger and the count of messages echoed; every handler
logs through `app.logger`, so the logger is given once, to `with_state`, and
no route needs a closure to carry it. `request.path_value(name)`,
`request.query()` and `request.header(name)` still read the raw text when a
handler wants it.

The by-name reading is open to a program's own extractors.
`request.path_params()` and `request.query_params()` return the decoded
`http.ParamValues` that `Path` and `Query` read, and `values.field[T](name)`
reads one of them as `Params` does, so an extractor can fill a struct by
hand. A check across fields refuses a value with
`http.ParamProblem.Refused(reason)`, which `Path` and `Query` answer with
400:

```linea
impl http.Params for Paging {
    fn from_params(values: http.ParamValues) -> Result[Paging, http.ParamError] where carries(values) {
        let page: UInt32 = values.field("page")?
        let limit: Option[UInt32] = values.field("limit")?
        .Ok(.{ page, per_page = limit.unwrap_or(10) })
    }
}
```

The [JSON echo server](../examples/http-json-echo/main.lin) reads its caller
through its own extractor, decodes a JSON message, greets a path value,
counts the messages it echoes in its state,
logs from its handlers, and tests its handlers
by calling them with requests built by `http.new_request`; the
[calendar export](../examples/calendar-export/main.lin) streams a year of
dates as CSV. The [TCP echo example](../examples/tcp_echo.lin) accepts and echoes
clients one at a time, the [bounded echo](../examples/bounded_echo.lin) serves
each connection with `net.serve`, bounds its time and size, and logs it, and the
[visitor counter](../examples/visitor_counter.lin) counts visitors across
connections in a closure's captured state.

## Log what a program does

A `log.Logger` writes one line per event to the sink you give it, at a
minimum level:

```linea
import std.log

fn main() -> UInt8 {
    let logger = log.to_stderr(minimum: .Info)
    logger.info("listening", log.field("port", 8080))
    logger.debug("not written", ())
    0
}
```

writes `2026-09-25T09:31:02Z INFO listening port=8080` to standard error.
`debug`, `info`, `warn` and `error` write at their level, and
`log(level, message, fields)` at one chosen at run time. `()` is a line with
no fields. A field borrows its value, which is any `Display` type, so the
program keeps using what it logs. A literal or a computed value lives until
the end of the statement that logs it; a field kept for a later statement
borrows a variable instead. The value is written through Display and
quoted when it is empty or holds a space, `=`, `"` or a control character.
Building fields formats nothing, so a line below the minimum costs one
comparison. Ask `logger.enabled(level)` before computing a field that is
costly in itself.

Logging reads the logger and never changes it, so `logger.info(...)` needs no
`&`. `log.to_stderr(minimum)` makes a logger over standard error, building lines in the system allocator (`log.to_stderr_in(allocator, minimum)` takes one),
which it does not own: it copies freely, and a program hands `copy(logger)` to
whatever else logs, such as a closure that keeps its copy with
`[sink logger = copy(logger)]`, or a router's state, from which every
[HTTP handler](#serve-http) logs. `log.Logger.open(file, minimum)`, or `log.Logger.open_in(allocator, file, minimum)`, makes one that
owns a file: it moves, and releasing it closes the file. Anything that
implements `log.Sink` can take the lines.

Each line is built in a buffer from the logger's allocator and handed to the
sink whole, so lines never interleave within a line. A line the allocator
cannot hold or the sink refuses is not written: `log` returns a
`log.LogError` saying which, and the level methods drop it, since a program
whose log has failed has nowhere better to say so. A type of your own
implements `log.Fields` to be logged as the fields it chooses.

## Time a request and log it: middleware

A middleware is a handler that holds another handler. It passes each request
on, with the state it was lent, and may change what comes back or the state.
`http.logged` is one: wrap a whole router in it, and it logs one line per
request once the response has been written or streamed:

```linea
let logger = log.to_stderr(minimum: .Info)
var server = http.logged(copy(logger), router)
defer server.release()
match http.serve(listener, &server) {
    Ok(_) => 0,
    Err(error) => {
        logger.error("serving stopped", log.field("error", error))
        1
    },
}
```

```text
2026-09-25T09:31:02Z INFO request method=GET path=/health status=200 bytes=2 duration=41µs
2026-09-25T09:31:03Z WARN refused a message reason="missing field at $[\"text\"]"
2026-09-25T09:31:03Z WARN request method=POST path=/echo status=400 bytes=27 duration=87µs error="the handler refused the request: missing field at $[\"text\"]"
```

The second line is the echo handler's own, written while it answered; the
request line follows once the answer has been sent. A 2xx or 3xx is logged
at `Info`, a 4xx at `Warn`, and a 5xx or an answer
that could not be written at `Error`. The duration runs from before the
handler to the end of the response; a request refused before any handler ran
is logged without one. `serve` writes no log of its own: it reports each
exchange, each failed accept it retries, and the address `listen_and_serve` bound, to its handler through
`http.Observer`. Every type ignores those events unless it implements
`Observer` itself, so a plain handler writes nothing for them, and an
unlogged server is silent.

`http.with_request_ids` is a middleware that numbers requests, so an
application needs no `Observer` to add request IDs. Wrap it around `logged` to
put the number in each logged line:

```linea
var server = http.with_request_ids(http.logged(copy(logger), router))
```

```text
2026-09-25T09:31:02Z INFO request method=GET path=/health request_id=1 status=200 bytes=2 duration=41µs
```

The handler reads the number with `request.header("X-Request-Id")`, and the
response carries the same header.

Write your own middleware the same way. It implements `http.Handler` to pass
requests and the state on, and `http.Observer` to pass events on; without the
second, the handler it holds, and anything logging inside it, would never see
an event. This one counts responses, works over any state `S`, and keeps its
count in a field of its own:

```linea
use http.Handler
use http.Observer

struct Counted[H] {
    next: H,
    served: UInt64,
}

impl[P: Allocator, S, H: http.Handler[S, P]] http.Handler[S, P] for Counted[H] {
    fn serve_http(inout self: Self, inout state: S, request: http.Request[P]) -> Result[http.Response[P], http.Error[P]] {
        self.served += 1
        var response = &self.next.serve_http(&state, request)?
        var count = String.new_in(request.allocator())
        self.served.fmt(&count)?
        &response.set_header("X-Served", count.view())?
        .Ok(response)
    }
}

impl[H: Observer] Observer for Counted[H] {
    fn observe[P: Allocator](inout self: Self, event: http.Event[P]) -> () {
        &self.next.observe(event)
    }
}
```

A middleware that works with the application's own state implements
`http.Handler[App, P]` instead, and reads or changes `state` before passing it
on. The [JSON echo server](../examples/http-json-echo/main.lin) wraps its router in `http.logged`, then in
`http.with_request_ids`, then in `http.with_state`. A middleware placed inside
`http.logged` is timed with the handler it holds.
