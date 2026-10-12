# 220. A function that allocates pairs a system form with an `_in` form

Status: Accepted — 2026-10-12. Supersedes the clause of
[0191](0191-the-caller-chooses-every-allocator.md) that every allocating
standard-library API takes its allocator from its caller.

## Context

[0191](0191-the-caller-chooses-every-allocator.md) made every allocating
standard-library API take its allocator as an argument, and rejected a
convenience form over the system allocator as "a second spelling of one
operation whose only content is the hidden choice". Constructors have since
moved past that: `Vec`, `String`, `collections.Map` and `http.Router` build
with `T.new()` in the system allocator and `T.new_in(allocator)` in the one
given, and `fs.read_text` and `io.read_text` pair with `read_text_in` the same
way ([0218](0218-the-library-gives-up-no-value-at-question-mark.md)).

Every other allocating function still took the allocator first. A census of
the library, the examples, the guide and the corpus found 44 public functions
that take an allocator, and about 580 of their calls passed `mem.system()`
(or a local bound to it and used for nothing else): `"text".to_owned(mem.system())`
98 times, `json.parse(mem.system(), text)` 62, `fmt.render_owned(mem.system(), value)`
49, `Vec.filled(mem.system(), ...)` 44. The argument names the same allocator at
almost every call and teaches nothing after the first, while the constructors
beside these calls already spell the system choice with a name. A reader saw
two conventions for one decision.

## Decision

**A standard-library function or method whose first parameter (after `self`)
is the allocator its result or its scratch storage comes from is a pair: `x(...)`
uses the system allocator, and `x_in(allocator, ...)` takes the allocator
first.** The system form calls the `_in` form with `mem.system()` and nothing
else, so the two cannot drift; its result names the system allocator in its
type (`String`, `Vec[UInt8]`, `json.Value`), and its contract drops the
allocator from the `_in` form's (`where carries()` where the `_in` form wrote
`carries(.Ok: allocator)`).

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

`fs.read_text` and `io.read_text` already had this shape and keep it.

Three kinds of allocator parameter stay as they are, because the allocator is
not incidental to them:

- **A constructor named `new_in` or `open`.** `new_in` is already the second
  half of a pair. An `open` constructor (`fs.File.open` and `create`,
  `io.BufferedReader.open`, `io.BufferedWriter.open`, `mem.Closure.open`,
  `log.Logger.open`) acquires a resource and keeps its allocator argument; the
  constructor rule decides its name, and doubling it is a separate decision.
- **An allocator built over a backing.** `mem.Arena.open(backing, size)`,
  `mem.AllocationLog.open(backing, refuse_at)` and
  `testing.each_allocation_failure(backing, body, is_refusal)` each build an
  allocator, and the backing is what that allocator is made of.
  [0191](0191-the-caller-chooses-every-allocator.md) rejected a walk without
  a backing for that reason, and the reason stands.
- **A parameter that is not any allocator.** `http.new_request(memory, ...)`
  takes a request arena's `mem.Handle[P]`; a system form has no arena to name.

## Consequences

- About 580 calls lose an argument that said nothing; the rest, which pass an
  arena, a refusing allocator, a test allocator or a generic `A`, now say
  `_in` at the call, so a reader sees where the allocator matters.
- The library has two names for each allocating function. The `_in` form is
  the one generic code calls, since a default is refused in an
  allocator-generic declaration ([T-DefaultedAllocator]).
- A system form's signature no longer says that it allocates; the name of its
  partner does. This is the property [0095](0095-the-system-allocator-is-named-rather-than-received.md)
  already gave up for any function, now spent deliberately in the library.
- `json.Value.null()`, `Value.array()` and `Value.object()` read like the
  `new()` constructors of the owning types they sit beside.
- A function of a program, not of the library, is free to follow the same
  convention; nothing in the compiler knows the suffix.

## Alternatives considered

**A trailing defaulted argument, `f(x, allocator: A = .System)`**
([0219](0219-a-function-type-parameter-and-its-parameter-may-default.md)
makes it expressible). One name per operation, but the allocator moves from
the first position to the last at every call that passes one, every
`where carries(allocator)` clause keeps naming a parameter most calls never
write, and the constructors already chose the pair. `http.listen_and_serve`
keeps its defaulted `parent:` argument: the parent arena there is a tuning
knob beside other named settings, not the place the result's memory comes
from.

**Keep the allocator argument and change nothing** (0191's rule). Rejected for
the census above: the argument was the same value at almost every call, and
the constructors had already stopped writing it.

**Pair only the most-called functions** (`to_owned`, `parse`,
`render_owned`). Rejected because the convention is only useful if a reader
can predict it: a reader who has met `to_owned_in` should find `filled_in` and
`read_all_in` without looking.

**Rename `Recorder.of` to `open`, which would make it an excluded
constructor.** Rejected: it would keep `mem.system()` at every test that
records output, the call this record removes, and `of` with `of_in` follows
the rule without a second rename.
