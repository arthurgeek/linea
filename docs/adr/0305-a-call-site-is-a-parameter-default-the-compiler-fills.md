# 305. A call site is a parameter default the compiler fills

Status: Accepted — 2026-11-22. Extends
[0017](0017-failure-is-a-trap-or-a-value.md) and
[0106](0106-a-non-completing-expression-has-type-never.md).

## Context

A panic reports the file, line and column of the `panic` expression that
raised it. For a panic written in a program that is the right place. For one
written inside a library operation it is not: `Option.unwrap` on `None`
reported `std/option/option.lin:301:21`, the line inside the library, and the
guide had to tell readers to go and look for the `unwrap` in their own code
that was handed the `None`. The program that made the mistake is the caller;
the library's line is the same for every caller and says nothing.

The location of a trap is fixed when the program is compiled. MIR carries a
span per instruction, and the backend turns a trap's span into the
`@linea_fileN` global holding the path and two constants for the line and
column, which it hands to `linea_panic`. Nothing about a call reached the
callee: the callee is compiled once per instantiation, and every caller shares
that body.

So the caller's location has to cross the call as a value, and some mechanism
has to decide which calls carry it and fill it in.

## Decision

### 1. `caller` is a parameter default

A function that wants its caller's location declares a parameter for it:

```linea
pub fn unwrap(sink self: Self, at: Location = caller) -> T where carries(self) {
    match self {
        Some(value) => value,
        None => panic("called Option.unwrap on None", at),
    }
}
```

Every call that leaves `at` out receives the location of that call: the file,
line and column of the called name, the operation's name in `value.op()` and
in `value.op[T]()`, so a chain continued on another line names the line the
operation is on. A call that
passes `at` passes a location on: `expect` written as a helper that takes its
own `at: Location = caller` and hands it to `Option.expect` reports the line
that called the helper.

`caller` is a contextual word ([T-Caller]). The parser reads it as the location
only when it is the whole default of a parameter, followed by `,`, `)` or `|`,
so a program may still bind `caller` as a value. The checker records it as a
third kind of default, `CallableDefault.call_site`, beside "none" and a folded
constant, in the same per-declaration table every other default is recorded in,
and requires the parameter's type to be the prelude's `Location`.

Because the default is part of the callable type, a call through a function
value, a callable parameter or a closure field fills in the location of that
call: `splicedCallableDefault`, which fills every omitted argument of every
call form, answers `.call_site` with the location of the call it is filling.
Callable identity compares the kind, so `fn(at: Location = caller)` and
`fn(at: Location)` stay two types, as a defaulted and an undefaulted parameter
already are.

A lambda's default is folded where the lambda is written, and no call is there,
so `caller` as a lambda's default is [T-Caller].

### 2. `panic(message, at)` reports a location it is given

`panic` takes an optional second operand of type `Location` and reports it in
place of its own span. It is a second node tag, `panic_at`, with a binary
payload, rather than an optional operand of `panic`, so every reader of a binary
payload finds both operands present. MIR's trap payload carries the
`Location`'s address beside the message; the backend loads the path pointer,
line and column from it and calls the same `linea_panic` entry, so the runtime
interface does not change.

### 3. `Location` is opaque, and the position is computed by the backend

`std.location.Location` is in the prelude, copyable and opaque, holding the path
as a `Str` and the line and column as `UInt32`. Only the compiler builds one;
`file()`, `line()` and `column()` read it, and it displays as `file:line:column`.

The path's `Str` addresses the same NUL-terminated `@linea_fileN` global a
trap's own location does, so the runtime reads it as a C string, as it reads
every other trap's path. Opaqueness is what makes that safe: no program can
build a `Location` whose path is not NUL-terminated.

Lowering builds the value at each call with `source_site` instructions, one per
part (path address, path length, line, column), each carrying the span of the
called name. Lowering holds no source text and no paths, and the backend
already holds both to name trap locations; a `source_site` lets the one pass
that answers "where is this span" answer it for both, so a location built for a
call and a trap's own location always agree. This adds an instruction tag
rather than a representation.

### 4. The library's panicking operations take `at`

`Option.unwrap`, `Result.unwrap` and the new `Option.expect` and
`Result.expect` (which panic with a message the caller writes) each take
`at: Location = caller`. A panic in a program that calls them names the call.

## Consequences

- `unwrap` on `None` reports `main.lin:4:10`, the call, rather than a line in
  the library. The guide no longer needs to explain where to look.
- Each call to a function with a `caller` default builds a 24-byte `Location`
  on the caller's stack and passes it. The panicking path is the only reader;
  the success path pays four stores and a pointer argument. A function's body
  is still compiled once per instantiation, not once per call site. Before
  `mlir-opt` runs, each such call is about twenty lines of MLIR (a stack slot,
  the four parts and their stores); the library calls `unwrap` often enough
  that `hello` grew by 57 lines (1%), `json_inventory` by 837 (2%) and
  `http-json-echo` by 6,061 (3%). A `Location` built once per call site
  as read-only data would cost a global and an address per call instead; it
  needs a module table of call sites the backend fills, and is left until the
  size of a build asks for it.
- A parameter is visible in the signature, in hover, in callable types and in
  the order of named arguments. That is the cost of using the ordinary
  parameter machinery rather than a hidden one, and it is also what lets a
  helper pass its own caller's location on by naming it.
- A default is part of exact callable identity, so `Option.unwrap` is no
  longer a value of `fn(sink Option[T]) -> T`. A callable type that writes
  `at: Location = caller` takes it, and each call through that type fills in
  its own location; a lambda `|sink value| value.unwrap()` fits the shorter
  type and reports the lambda's line.
- A `Location` holds the path as a `Str`, so by its type it could be a source
  of a returned view. A parameter defaulted to `caller` is weighed as a source
  of a signature without a `where` clause only where no other parameter could
  be one: adding `at` to a function that returns a view of its one other
  argument does not make its signature ambiguous, and
  `fn here(at: Location = caller) -> Location` still needs no clause.
- Forwarding is explicit. A function that calls `unwrap` without taking `at`
  itself reports its own line, which is the right line for a function that
  does not claim its caller is to blame.
- `caller` is not reserved, but a parameter default written `= caller` in a
  module that binds a constant `caller` means the location, not the constant.

## Alternatives considered

**An attribute marking a function whose panics report its caller, with a hidden
parameter.** The callee would get an extra parameter no signature shows, and
every direct call would pass the call's location. Lost because the hidden
parameter changes the function's callable type without the type saying so:
taking the function as a value, passing it as a callback or calling it through
a trait bound would each need a shim that fills the parameter, or a rule
refusing the function as a value. A visible defaulted parameter needs neither,
since a callable type already carries its defaults and every call form already
fills omitted arguments through one routine.

**An instance per call site.** Instantiating the function once per call, with
the call's location folded into the body, needs no parameter at all. Lost
because it multiplies the code of every such function by its call count —
`unwrap` is called over three thousand times in the library alone, most of them in tests — and it makes
instance discovery key on spans, which no other question it answers depends on.

**A location register the caller writes before the call.** The callee would
copy a thread-local location at entry. Lost because nothing ties the value to
the call that wrote it: a call through a function value, or one made by a
callee before reading it, would report a stale location, and the language
promises a trap names where it happened.

**A reserved word `caller`.** Reserving it would make the parser's job simpler
and cost every program the name. Lost for the reason `type`, `alias` and
`default` are contextual: the word is common and the position that gives it
meaning is narrow.

**Lowering computes the line and column.** Lowering would need each file's
source text and path, which it does not hold, and would be a second place that
turns a span into a position, beside the backend's. Lost to the `source_site`
instruction, which keeps one answer in one place.
