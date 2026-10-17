# 220. A constructor or function that allocates pairs a system form with an `_in` form

Status: Accepted — 2026-10-12. Supersedes the clause of
[0191](0191-the-caller-chooses-every-allocator.md) that every allocating
standard-library API takes its allocator from its caller. The server's
parent-allocator clause is superseded by
[0225](0225-a-library-signature-states-its-allocator.md).

## Context

[0191](0191-the-caller-chooses-every-allocator.md) made every allocating
standard-library API take its allocator as an argument, and rejected a
convenience form over the system allocator as "a second spelling of one
operation whose only content is the hidden choice". Constructors have since
moved past that: `Vec`, `String`, `collections.Map` and `http.Router` build
with `T.new()` in the system allocator and `T.new_in(allocator)` in the one
given, and `fs.read_text` and `io.read_text` pair with `read_text_in` the same
way ([0218](0218-the-library-gives-up-no-value-at-question-mark.md)).

Every other allocating constructor and function still took the allocator
first. A census of the library, the examples, the guide and the corpus found 44
public functions that take an allocator, and about 580 of their calls passed
`mem.system()` (or a local bound to it and used for nothing else), with about
140 more at the `open` and `create` constructors of readers, writers, files,
loggers, closures and the JSON object decoder: `"text".to_owned(mem.system())`
98 times, `json.parse(mem.system(), text)` 62, `fmt.render_owned(mem.system(), value)`
49, `Vec.filled(mem.system(), ...)` 44. The argument names the same allocator at
almost every call and teaches nothing after the first, while the constructors
beside these calls already spell the system choice with a name. A reader saw
two conventions for one decision.

## Decision

**A standard-library constructor, function or method that takes the allocator
its result or its scratch storage comes from is a pair: `x(...)` uses the system
allocator, and `x_in(allocator, ...)` takes the allocator first, or first
after the receiver for a method (`text.to_owned_in(allocator)`).** The
constructor rule still decides the base name: `new` builds and cannot fail, and
`open` (or `create`) can fail or acquires a resource, so a resource constructor
is `open` with `open_in`, as a plain one is `new` with `new_in`.

The system form calls the `_in` form with `mem.system()` and nothing else, so
the two cannot drift. The one exception is `mem.Closure.open`: it calls the
private routine `open_in` calls, with `mem.system()`, because forwarding a
callback whose type is still a parameter to `open_in` would be refused where
the closure's signature has to be settled. The system form's result names the
system allocator in its type (`String`, `Vec[UInt8]`, `json.Value`), and its
contract is the `_in` form's without the allocator: what the `_in` form
carries from `allocator`, the system form carries from nothing.

```linea
let name = "Ada".to_owned()                          // String
let kept = "Ada".to_owned_in(arena.handle())         // String[mem.Handle]
let document = json.parse(text)?                     // json.Value
let scratch = json.parse_in(arena.handle(), text)?   // json.Value[mem.Handle]
```

The pairs are:

| module | system form | `_in` form |
| --- | --- | --- |
| `fmt` | `render_owned(value)` | `render_owned_in(allocator, value)` |
| `text` | `Str.to_owned()`, `String.to_owned()` | `to_owned_in(allocator)` |
| `io` | `read_all(&reader, max_bytes)`, `BufferedReader.read_exact(count, max_bytes)` | `read_all_in`, `read_exact_in` |
| `fs` | `read_file`, `write_file`, `save_atomic` | `read_file_in`, `write_file_in`, `save_atomic_in` |
| `log` | `to_stderr(minimum)` | `to_stderr_in(allocator, minimum)` |
| `json` | `parse`, `parse_bytes`, `decode`, `from_value`, `render` | the same names with `_in` |
| `json` | `Value.null`, `boolean`, `array`, `object`, `string`, `number`, `from_int`, `from_uint`; `Number.parse`, `from_int`, `from_uint` | the same names with `_in` |
| `json` | `DecodeError.failure(reason)`, `error.at_field(name)` | `failure_in`, `at_field_in` |
| `mem` | `Vec.filled`, `Vec.from_fn`, `Vec.from_fn_inout` | `filled_in`, `from_fn_in`, `from_fn_inout_in` |
| `testing` | `Recorder.of(bytes)` | `Recorder.of_in(allocator, bytes)` |
| `io` | `BufferedReader.open(capacity, reader)`, `BufferedWriter.open(capacity, writer)` | `open_in(allocator, capacity, ...)` |
| `fs` | `File.open(path)`, `File.create(path, policy)` | `File.open_in`, `File.create_in` |
| `log` | `Logger.open(output, minimum)` | `Logger.open_in(allocator, output, minimum)` |
| `mem` | `Closure.open(callback)` | `Closure.open_in(allocator, callback)` |
| `json` | `ObjectDecoder.open(value)` | `ObjectDecoder.open_in(allocator, value)` |

`fs.read_text` and `io.read_text` already had this shape and keep it.

`Logger.open_in` and `ObjectDecoder.open_in` move the allocator from second
to first place, so every `_in` form reads alike. `mem.Closure.open` and
`open_in` share one private routine that stores the callable, and the checker
holds both to the closure's signature.

Two kinds of allocator parameter stay as they are, because the allocator is
not incidental to them:

- **An allocator built over a backing.** `mem.Arena.open(backing, size)`,
  `mem.AllocationLog.open(backing, refuse_at)` and
  `testing.each_allocation_failure(backing, body, is_refusal)` each build an
  allocator, and the backing is what that allocator is made of.
  [0191](0191-the-caller-chooses-every-allocator.md) rejected a walk without
  a backing for that reason, and the reason stands.
- **A parameter that is not any allocator.** `http.new_request(memory, ...)`
  takes a request arena's `mem.Handle[P]`; a system form has no arena to name.

Two more keep their allocator where it is, for reasons of their own:

- **The `json.Decode` protocol.** `Decode.decode(value, allocator)`,
  `missing(allocator)` and `DecodeKey.from_name(name, allocator)` are trait
  methods a program implements for its own types, and the decoder calls them
  with the allocator it was given. Callers reach them through `json.decode` and
  `decode_in`, which follow the rule; the protocol's signature is what an
  implementation writes, and it takes the allocator last so the value being
  decoded leads.
- **A server's parent allocator.** `http.serve` and `http.listen_and_serve`
  take `parent:` as a defaulted named argument
  ([0219](0219-a-function-type-parameter-and-its-parameter-may-default.md)),
  beside the other settings a server is tuned with, so leaving it out is the
  system form.

## Consequences

- About 720 calls lose an argument that said nothing; the rest, which pass an
  arena, a refusing allocator, a test allocator or a generic `A`, now say
  `_in` at the call, so a reader sees where the allocator matters.
- The library has two names for each allocating constructor and function. The `_in` form is
  the one generic code calls, since a default is refused in an
  allocator-generic declaration ([T-DefaultedAllocator]).
- A system form's signature no longer says that it allocates; the name of its
  partner does. This is the property [0095](0095-the-system-allocator-is-named-rather-than-received.md)
  already gave up for any function, now spent deliberately in the library.
- `json.Value.null()`, `Value.array()` and `Value.object()` read like the
  `new()` constructors of the owning types they sit beside.
- A function of a program, not of the library, is free to follow the same
  convention. The compiler knows the names only where it already knew
  `Closure.open`: it finds `open` and `open_in` on `mem.Closure` to hold each
  callback to the closure's signature.

## Alternatives considered

**A trailing defaulted argument, `f(x, allocator: A = .System)`**
([0219](0219-a-function-type-parameter-and-its-parameter-may-default.md)
makes it expressible). One name per operation, but the allocator moves from
the first position to the last at every call that passes one, every
`where carries(allocator)` clause keeps naming a parameter most calls never
write, and the constructors already chose the pair. `http.serve` and
`http.listen_and_serve` keep a defaulted `parent:` argument: the parent there
is a tuning knob beside other named settings, not the place the result's
memory comes from.

**Keep the allocator argument and change nothing** (0191's rule). Rejected for
the census above: the argument was the same value at almost every call, and
the constructors had already stopped writing it.

**Pair only the most-called functions** (`to_owned`, `parse`,
`render_owned`). Rejected because the convention is only useful if a reader
can predict it: a reader who has met `to_owned_in` should find `filled_in` and
`read_all_in` without looking.

**Rename `Recorder.of` to `open`.** Rejected: a recorder acquires nothing a
test must close, and `of` with `of_in` follows the rule without a second
rename.

**Leave `open` constructors taking the allocator.** The constructor rule
decides `open`'s name, and pairing it was first weighed as a separate decision.
Rejected because the same `mem.system()` argument sat at most of their calls
(every buffered reader and writer over standard input and output, every kept
closure in the system allocator), and a reader who has learned `new_in` and
`to_owned_in` would look for `open_in`.
