# 176. A function name is a value, and its uses instantiate it

Status: Accepted — 2026-09-26. Extends
[0105](0105-callable-values-have-static-call-targets.md),
[0152](0152-an-integer-literals-type-is-settled-by-its-uses.md),
[0153](0153-an-inherent-impl-function-is-a-function-value.md) and
[0173](0173-a-capturing-closure-is-erased-into-allocator-owned-storage.md).
Extended by [0177](0177-a-parameter-name-is-a-label-not-part-of-a-function-type.md).
Refined by [0181](0181-a-call-may-name-its-type-arguments.md).

## Context

[N-NotAValue] admitted a function as a value only where one exact structural
callable type flowed inward. Everywhere else a function's name was refused:

```linea
let strengthen = Coffee.add_shot      // [N-NotAValue]
let strengthen: fn(inout coffee: Coffee) -> () = Coffee.add_shot
```

The annotation repeats a signature the declaration already states, and the
checker even printed it in the refusal's help. Rust, Swift, Go and Zig all
accept the first line. A generic function was worse off: `let same = identity`
had no annotation that did not also fix its instance, so the only way to hold
it was to name the instance at the binding, before the uses that decide it.
A trait's operation, `Priced.cents`, was refused even under an annotation,
because its path names a trait rather than a body.

The checker already settles one kind of type from later uses. An integer
literal with no expected type has an open type, a variable in a union-find,
which the first type it must equal settles, and which falls back to `Int64`
when its body finishes ([ADR 0152](0152-an-integer-literals-type-is-settled-by-its-uses.md)).
A generic function named without a type has the same shape of problem: its
type parameters are unknown where it is written and known where it is used.

## Decision

**A function's name is a value wherever an expression is written.** A test, an
`extern` and a projection remain refused: a test is run only by the compiler,
an `extern`'s body is outside the program, and a projection names a place.

**Where one exact structural callable type flows inward, the value converts to
it at once**, as before: matching selects every type parameter, and a parameter
the interface leaves unselected is [T-Infer].

**Where none does, the value has its declaration's own signature**, parameter
names, conventions, defaults and contracts included. `let increment = add_one`
holds a `fn(read value: UInt8) -> UInt8`. Each type parameter the signature is
written over -- the function's own, a generic inherent head's, a trait
operation's `Self`, and its trait's -- becomes an **open type**: a variable in
the table open integers use, marked as free to settle on any type. `meet`, the
routine that settles an open integer, settles it: an argument of a call through
the value, the parameter or annotation it flows into, and another open type it
meets. An open type met by an open integer must be an integer and falls back
with it. When the body finishes, a parameter still open is [T-Infer], and the
help names the parameter and the function type to write; a settled one must
meet its bounds, checked by the routine a call's bounds use, and the report
points at the use that settled it.

A value's type is its declaration's signature, whose parameter names are not
part of it ([0177](0177-a-parameter-name-is-a-label-not-part-of-a-function-type.md)),
so `let f = add_one; takes(f)` is accepted wherever `takes(add_one)` is. A named
call through `f` uses `add_one`'s names.

**A trait operation is a value once its `Self` is settled**, by context or by
its uses. `Self` must implement the trait. The value records the same
`CallImpl` a call through the trait records, and discovery and lowering read
both through one routine (`implementedBody`, `calleeThrough`), so a converted
operation and a called one name one instance. Where `Self` settles to a type
parameter, the implementation is selected when the enclosing function is
instantiated. The same record replaces the `self_ty` a generic inherent
member's value carried.

**An operation the compiler provides is a value too.** Where the
implementation that answers is one the compiler supplies, such as
`Equatable.equals` at `UInt8`, discovery keys a generated body,
`BodyOrigin.built_in`, and lowering emits into it the instruction a direct
call to the operation lowers to, through one routine (`builtInOperation`).
An array that answers through its slice view gets a generated body too,
`BodyOrigin.viewed`, which views each array argument and calls the slice's
member, as a direct call is lowered. The same `valueMember` selection runs in
discovery and lowering, so a generic body naming `Equatable.equals`
instantiates at every type its bound admits, arrays included.

**A function value and a closure share the function type.** A value held in a
local is a structural `fn` like any other, so a lambda can stand in its place
where that type is expected, in either arm of an `if`, and `mem.Closure.open`
erases either. A name passed to `open` is checked with nothing expected, as a
local's initializer is, so a generic function or a trait operation passed
directly has its open parameters settled by the erased closure's calls.

## Consequences

- `let f = add_one`, `let strengthen = Coffee.add_shot`, `let same = identity`
  and `let price = Priced.cents` need no annotation. Annotations written only to
  make a function a value are removed from the standard library and examples.
- A function named alone as a statement is a value that is discarded, so it is
  [T-Discard], with help that says to call it. It was [N-NotAValue].
- Named arguments and defaults work through a value, by the names of the
  function it was bound to, and binding a function first loses nothing that
  naming it in place would have.
- The table the checker holds for open values is sized by the bodies being
  checked: a value leaves it when its body closes, and each is visited once.
  The open types themselves live in the open-type table, one entry per
  parameter of a value named without a type.
- A settled reference written in a trait operation's signature (`Self.Unit`)
  waits on an open `Self` as it waits on a type parameter, and is read once
  `Self` settles.
- A generated body is one instance per operation and receiver type, keyed like
  a closure's release, whether it performs a compiler-provided operation or
  views an array.

## Alternatives considered

**A type of its own per function, converting later.** Rust gives each function
item a unique zero-sized type that converts to a function pointer where one is
expected. That needs a representation MIR, closures' erasure and ownership
would each learn. The declared signature is a type every pass already knows,
and once labels are not part of it
([0177](0177-a-parameter-name-is-a-label-not-part-of-a-function-type.md)) it
fits every place the name itself would.

**Refuse a compiler-provided operation as a value.** A generic body that checks
under its bound would then fail at each instantiation with an integer type,
reported where the caller cannot see it, and whether the type was written
would change what is possible.

**Instantiate from the first use only, as a separate walk over the local's
uses.** It would find the instance by reading statements after the binding, a
second inference beside the one the body already runs, and it would disagree
with it wherever the first use is itself an open integer or a callback. The
open type is settled by the same `meet` every other type in the body goes
through.

**Default an unsettled parameter.** A literal falls back to `Int64` because
every integer type is a valid answer and one must be chosen. A type parameter
has no such answer; picking one would compile a program whose meaning nobody
wrote. It is [T-Infer] instead.

**Keep trait operations refused.** The operation's `Self` is one more type
parameter, and the implementation it selects is what a call through the trait
already records. Refusing it kept a forwarding function per operation for no
reason the checker needed.
