# 225. A library's public signature states its allocator

Status: Accepted — 2026-10-15. Extends
[0215](0215-a-type-parameter-may-default-its-argument.md) and
[0219](0219-a-function-type-parameter-and-its-parameter-may-default.md).
Supersedes the server's parent-allocator clause of
[0220](0220-a-constructor-or-function-that-allocates-pairs-a-system-form-with-an-in-form.md).

## Context

[0215](0215-a-type-parameter-may-default-its-argument.md) let a written type
leave out a defaulted allocator, so a program writes `Vec[Str]` for
`Vec[Str, mem.SystemAllocator]`. Its guard, [T-DefaultedAllocator], refused the
short form only inside a declaration that is generic over an allocator itself.
A library function that was not generic could still write `-> Vec[Str]`. That
compiled, and fixed every caller to the system allocator without the signature
saying so. A program holding an arena then met a [T-Mismatch] far from the
library that caused it.

A probe library showed all of these accepted without a word:

- a `pub fn` returning `Vec[Str]`, taking one, or returning `Option[Vec[Str]]`;
- a `pub struct` field `titles: Vec[Str]`;
- a `pub alias Titles = Vec[Str]`;
- a `pub fn chosen[P: Allocator = mem.SystemAllocator](parent: P = .System)`.

The standard library, which every program depends on, had 42 such sites in 18
files: 18 written types in 16 public functions, 22 heads of inherent
implementations with public members (`impl[T] Vec[T]`), and the defaulted
`parent:` of `http.serve` and `http.listen_and_serve`.
[0229](0229-an-application-depends-on-a-library-by-path.md) makes libraries
other than the standard one usable, so the question is now a library author's
and not only the standard library's.

The two spellings are one type and one implementation key (0215, rule 6). No
question asked of the settled type can tell an omitted default from the system
allocator written out.

## Decision

**In a library root, every public signature states its allocator, either as a
type parameter bounded by `Allocator` or as `mem.SystemAllocator` written out,
and a public function's allocator type parameter takes no default.** It is a
second clause of [T-DefaultedAllocator]. There is no warning tier.

A library root is the standard library, a dependency, or a primary root whose
manifest says `"kind": "library"`. A signature is public in these positions:

- a `pub` function's parameters, result, bounds and `where` clause, up to its
  body;
- a `pub` trait's signatures;
- the head of an inherent implementation of a public type that has a `pub`
  member, since every member's `Self` is that head;
- the signatures of those `pub` members;
- a type a public type settles for a trait;
- a `pub` struct's fields and a `pub` enum's payloads;
- a `pub` alias, newtype or constant.

The arguments of a wrapper (`Option[Vec[Str]]`), the components of a tuple, and
the parameters and result of a callable type are written types in the same
position. So is a type parameter's default in a public declaration. A private
alias that a public signature names counts as what it writes, and so does the
default a public signature leaves a private declaration's type parameter to
(`struct Hidden[T = Vec[UInt16]]` named as `Hidden`): the report sits at the use
and points at the alias or the default.

"Written out" is the parser's own record of the arguments. The one routine that
turns a head and its arguments into a type (`settledWith`, and `appliedAlias`
for an alias) already compares the written count with the declaration's before
filling defaults, and the first clause already fires there. The second clause
asks, at that same point, whether the declaration that wrote the type publishes
it. A call that takes a default never reaches it. Because the type is the system
form either way, the type settles as written and nothing downstream is refused
because of it.

The report is:

```
error[T-DefaultedAllocator]: Public library signature uses the default allocator for `Vec`.
 --> shelf/shelf.lin:3:19
  |
3 | pub fn names() -> Vec[Str] {
  |                   ^^^ Specify `mem.SystemAllocator` to make this restriction intentional, or make the allocator a generic parameter to preserve allocator polymorphism.
```

Where the declaration is itself generic over an allocator, the first clause's
report is given instead, since its help names the parameter to write. A type a
trait implementation settles cannot take an allocator parameter, since nothing
in the implementation's key would recover it, so there the help offers
`mem.SystemAllocator` alone. A public function's defaulted allocator parameter
is already generic, so its report names the function and says to drop the
default and offer the `x` and `x_in` pair.

The help writes `mem.SystemAllocator`, the spelling a library outside
`std.mem` writes.

**`http.serve` and `http.listen_and_serve` become pairs.** The system forms take
no `parent:`, and `serve_in(parent, listener, &handler, limits:)` and
`listen_and_serve_in(parent, address, handler, state:, limits:)` take the
allocator first, as every other `_in` form does. `state:` keeps its default,
since only allocator defaults are refused.

## Consequences

- The standard library's system forms say what they return:
  `fs.read_text(path, max_bytes) -> Result[String[mem.SystemAllocator], ReadTextError]`,
  and `impl[T] Vec[T, SystemAllocator]` declares `Vec.new()` and the other
  system constructors. Programs are unchanged. Hover, diagnostics and the
  types a program infers were already the expanded form, and `Vec[Str]` in a
  program still means the system vector.
- A library author decides once per signature whether a caller may choose. The
  `_in` pairs of 0220 are how a library offers both.
- 0219's function defaults stay for programs and for parameters that are not
  allocators.
- The ten calls that passed `parent:` were all in the standard library's own
  tests and move to the `_in` forms. Calls that left it out compile unchanged.
- Cost: the second clause runs only after the first has found an omitted
  allocator parameter. It is a module lookup, a visibility read and one offset
  comparison against the body. Inherent implementations with a public member
  are found in one pass over the declarations, made once. No walk over the
  program is added.

## Alternatives considered

**Check the settled type.** A rule that refused any `SystemAllocator` in a
public signature would also refuse the spelling that makes the restriction
deliberate. One that refused an argument the default filled would need the
type to remember which arguments were filled, splitting one type into two
identities that 0215 decided are one.

**A parser flag on each written type, or a separate pass over public
signatures.** Either would restate `args.len() < params.len()` somewhere that
does not know the declaration's parameters or their bounds. That makes two
routines answering whether a written type omits an allocator.

**A warning or a lint.** A library that compiles with the short form has
already published the restriction, and the guard 0215 introduced is an error.

**Refuse defaulted allocators on library types too.** That would take the short
form away from every program, which 0215 gave them on purpose. What leaks is
the omission in a library's signature, and that is refused where it is written.

**Check every library declaration, not only public ones.** A private helper's
allocator is no caller's business. The standard library has 247 omissions in
bodies and 29 in private signatures that change nothing for a caller.

**Exempt function defaults.** `parent: P = .System` hides the same choice
behind a defaulted argument, so the rule would have a hole the width of 0219.
