# 179. The prelude holds the core vocabulary, and yields to a module's own names

Status: Accepted — 2026-09-26. Supersedes two clauses of
[0085](0085-the-library-is-imported.md): that a name is in the prelude if and
only if the language's syntax obliges it, and that a prelude name shadows
nothing and is shadowed by nothing.

## Context

[0085](0085-the-library-is-imported.md) cut the prelude to the thirteen names
the syntax obliges, because a name in the prelude was in every module's scope
with no way out: declaring `Writer` for a program's own purposes collided with a
library type the program never asked for. Keeping the prelude small was the only
way to keep that collision surface small.

The rule held, and its cost turned out to be concentrated in a handful of names
every program writes. Measured over `std/`, `examples/` and `tests/` before this
change, counting bare uses of each name in `.lin` files and the `use` lines that
existed only to bring it into scope:

| Name | Bare uses | Files | `use` lines |
| --- | ---: | ---: | ---: |
| `Release` | 668 | 315 | 266 |
| `Allocator` | 523 | 144 | 75 |
| `Vec` | 501 | 108 | 14 |
| `Writer` | 315 | 93 | 54 |
| `String` | 221 | 58 | 2 |
| `From` | 99 | 32 | 23 |
| `Equivalent` | 96 | 33 | 17 |
| `Ordered` | 43 | 18 | 14 |
| `Into` | 39 | 16 | 12 |

The qualified spellings add to that: `mem.Allocator` was written 553 times,
`mem.Vec` 291, `text.String` 115, and `use release.Release` stood in 283 files
counting the documentation. These are signature and bound
vocabulary: a program writing a generic container writes `[A: Allocator]`, a
linear type writes `impl Release`, a rendering implementation writes
`[W: Writer]`. None of them is optional for the program that needs it, and none
of them is a function a reader wants to see qualified to know where it came
from.

The collision that made 0085 keep the prelude small is a property of the
prelude being unshadowable, not of its size.

## Decision

**A module's own name shadows the prelude's.** A module's scope holds its own
declarations first and then each prelude binding whose name it does not
declare. A top-level declaration or a `use` of a prelude name therefore binds
that name in the module and is not [N-Duplicate]; two such declarations in one
module still are. Primitive type names are not prelude names and stay
unshadowable.

**Syntax finds the prelude by identity, never by name.** `?`, literals,
interpolation, `==`, `<`, `..`, brackets, `for` and the entry point's `Result`
already found the prelude's declarations through `Resolution.prelude`; the entry
point's check now compares declarations too, and reads a qualified
`result.Result` through its module. A module that declares its own `Option`
keeps `?` working and gets its own `Option` in its signatures, and reaches the
prelude's as `option.Option` after `import std.option`. Each syntax-obliged name
has a case under `tests/prelude/` holding this.

**The prelude gains a core vocabulary.** Beside the thirteen syntax-obliged
names it publishes `Release`, `Equivalent`, `Ordered`, `From`, `Into`, `TryFrom`,
`TryInto`, `Default`, `Allocator`, `Vec`, `String` and `Writer`. `io.Writer` and
`fmt.Writer` are one trait, re-exported from `std.io.core`. `Copyable` is a
capability the compiler provides and needs no entry. Collections without syntax
of their own, such as `collections.Map`, and a library area's own vocabulary,
such as `http.Observer`, stay behind their imports: the first has no claim
beyond usefulness that `Vec` does not answer, and the second names a protocol
only an HTTP program implements.

**The vocabulary is one documented list.** The semantics document's
core-vocabulary table is that list, and `build.zig` reads it: every name the
compiler looks up must be published, every published name must be looked up or
listed in the table, and every listed name must be published and must not be
looked up. Adding a name to the manifest without a row, or a row without the
name, fails the build.

**Conversion has one vocabulary.** `Convert[T]` was Rust's `TryFrom` under
another name. It is renamed `TryFrom[T]` with `fn try_from(x: T) -> Option[Self]`,
and a blanket `TryInto` is supplied over it exactly as `Into` is over `From`.
The Option form stays: the survey found two implementations, the integer
family and the thermostat range in the temperature example, whose only refusal
is "does not fit", and no caller that inspected a reason. A conversion with a
reason to report, such as parsing, already returns `Result` from an ordinary
function, and a consuming `Result` form would have to hand the refused source
back inside its error to avoid losing owned values, which the observing Option
form never needs.

**`Default` is added.** `trait Default { fn default() -> Self }` is derivable for
a struct whose fields all implement it, by the same perfect-derive rule as the
other derives: the bound is on each component type, not on the type's
parameters. It is implemented for the integers and `Float64` (zero), `Bool`
(false), `Str` (empty), `()` and `Option[T]` (None), and for `http.Limits` and
`json.ParseLimits`, whose public `default_limits` constants it replaces. An enum
implements it by hand, naming the variant it starts from. Owning collections
(`Vec`, `String`, `Map`) do not implement it: each needs an allocator the caller
chooses, and a default that picked one silently would hide the only policy
decision their construction makes. `Vec.open(allocator)` already allocates
nothing. Generic code uses it where a starting value is needed: `mem.take`
leaves a place's default behind, which `http.logged` uses to take its start
time. `Map` counters were surveyed and need nothing: `merge` already takes the
first value explicitly.

**`default` becomes a contextual word.** It was reserved for
`default impl[T] Trait for T`, which would have made `fn default()` and
`Default.default()` unwritable. It is now a keyword only immediately before
`impl` at the start of a declaration, like `type`, `proj`, `trav`, `it` and
`via` in their positions, and every editor grammar still spells it: the gates
that hold the five places in agreement cover contextual words as well as
reserved ones. [0084](0084-test-is-a-reserved-word-not-a-contextual-one.md)
kept `test` reserved because no one had asked for it as a name; `default` is
asked for by the trait this record adds.

## Consequences

A prelude trait is a visible trait everywhere, so its operations take part in
postfix lookup in every module. A type declaring its own `release` and also
implementing `Release` draws [N-Shadowed] at the implementation, and a program
trait declaring `release` or `write_str` for a type that also implements the
prelude's makes `x.release()` [N-Ambiguous], to be written out as
`Release.release(x)`. `into` and `try_into` reach further: the blanket
`impl[T, U: From[T]] Into[U] for T`, with a library `From` implemented for
every `E` such as `impl[E] From[E] for EncodeError[E]`, means every type
implements `Into`, so a program trait declaring `into` or `try_into` is
ambiguous on every receiver. Cases record both.

A derived implementation reaches a prelude name by identity. Its template
writes the name bare; where the target's module shadows that name, the
generated member imports the declaring module and qualifies the name through
it, so a module declaring its own `Result` still derives `Debug`.

The language server's semantic tokens classify contextual words as names,
and `default` before `impl` is now one of them: it is published as a variable
rather than a keyword, like `type`, `proj` and `via` in their positions. The
editor grammars colour it as a keyword only before `impl`. This is the price 0085 named, and a
module can still avoid it by declaring its own trait under the prelude name.

Every library module now sees the whole prelude, whatever order the manifest
names them in: the prelude is taken from the manifest's `pub use` bindings
before any library module is declared, and those bindings are resolved in place.
The ordering note the manifest carried is gone.

Programs got shorter. The adoption removed every now-redundant `use` of these
names and every qualified spelling that existed only for want of one, across
`std/`, `examples/`, the tests that are not about imports, and the documentation
snippets.

Adding a name to the prelude is still a breaking change for any program with a
trait declaring an operation under the same name, as described above. That is
why the list is written down and gated rather than grown.

## Alternatives considered

**Keep the minimal prelude.** Rejected on the measured cost: 266 `use` lines for
`Release` alone, written by programs that had no choice, and signatures spelling
`mem.Allocator` where the module prefix says nothing a reader needs. The
collision that justified it is answered by shadowing, which costs one lookup per
prelude name per module.

**Rust's prelude verbatim.** Rust publishes `Box`, `ToOwned`, `Clone`, `Drop`,
`Fn*`, `Iterator`, `Extend`, `FromIterator`, `ToString` and more. Several have no
Linea counterpart (`Clone` is `copy`, `Drop` does not exist, `Fn*` are function
types), and the rest map onto names this record adds or onto functions rather
than traits: `collect` and `extend` are functions in `std.iter`, and there is no
`ToString` because `fmt.render_owned` does that. Copying a list designed around
another language's capabilities would publish names that mean nothing here.

**Keep shadowing forbidden and add names anyway.** Rejected because it is the
arrangement 0085 escaped: every name added is one no program may declare, and a
program's own `Writer` becomes an error the day the library publishes one.

**`Default` with an allocator-taking form for collections.** A second trait,
`fn default(allocator: A) -> Self`, would give `Vec` and `Map` a default. It
would be a constructor under another name, since `Vec.open(allocator)` already
exists, and it would split one question into two traits a generic bound would
have to choose between.
