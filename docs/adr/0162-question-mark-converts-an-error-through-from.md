# 162. `?` converts a different error through `From`

Status: Accepted — 2026-09-24.

## Context

[T-TryAnswer] required the error type of a `Result` under `?` to be identical
to the enclosing function's. A function whose failures come from several
sources had to wrap each one by hand before propagating it:
`parse(text).map_err(ConfigError.Parse)?`, or a `match` whose failing arm
returns `.Err(convert.From.from(error))`. The library already declares the
conversion that wrapping performs, `std.convert.From`, and programs already
implement it for their error types; `std.http` implements
`From[io.IoError] for http.Error` and `From[HeaderError] for http.Error`
so that a handler can report either as a status. The rule left those
implementations to be called by hand at every propagation site.

## Decision

**`?` over a `Result` whose error type differs from the enclosing function's
converts the error through `From[Operand] for Enclosing`.** The failing path
returns `.Err(From.from(error))`. An error of the function's own error type
passes through unchanged and needs no implementation. Where no implementation
or bound supplies `From[Operand] for Enclosing`, the `?` is [T-TryAnswer], and
the diagnostic names that implementation.

- **The target is always the enclosing function's error type**, so there is
  one candidate implementation per `?` and a conversion is never ambiguous.
- **An open error settles before conversion.** An error type the operand's
  call leaves open, an open callback result or the type of an integer literal
  argument, settles on the enclosing function's error type before conversion
  is considered, so adding a `From` implementation never makes an open error
  ambiguous and never changes which variant a contextual constructor builds.
  An integer literal's type takes the enclosing error type only where that is
  an integer type, as any use settles a literal: `fail(5)?` in a function
  failing with `UInt16` fails with `UInt16`, where it used to default to
  `Int64` and be refused. Otherwise the literal defaults to `Int64`, and a
  `From[Int64]` implementation converts it.
- **A bound supplies the implementation in a generic body.** Inside
  `fn f[E: From[ParseError]]() -> Result[T, E]`, a `?` over
  `Result[T, ParseError]` is admitted by the bound, and each instantiation
  calls the implementation its concrete `E` selects.
- **The trait is found by declaration identity**, by module and name as
  [0085](0085-the-library-is-imported.md) finds the traits the compiler
  implements for primitives. `?` does not oblige a program to write `From`,
  so it stays out of the prelude; a program's own trait named `From` does not
  convert.
- **Ownership and contracts follow the call.** The error is moved into
  `from`, so a Linear error is settled by the conversion. The converted error
  carries what `From.from`'s declaration says its result carries,
  `where carries(source)`, as a written `From.from(error)` does. The
  conversion runs before the function's scheduled operations, as the operand
  of a `return` does.
- `Option` is unchanged, and there is no conversion between `Option` and
  `Result`.

The checker decides whether a `?` converts and records the `From` trait, its
`from` operation and the two error types in `Typing.try_conversions`, keyed by
the `?`. Instance discovery selects the implementation for each instance's
substituted types, and lowering calls it on the failing edge. Neither
re-derives whether a conversion happens: inside a generic body the two error
types may coincide in one instantiation and still convert, because the
checker's answer was made over the parameters.

## Consequences

- Error wrapping is written once, as a `From` implementation, and every `?`
  over that error uses it. A `.map_err(Variant)?` that only wraps becomes `?`.
- A `?` now can run code: the `from` of the selected implementation. It is
  visible at the implementation, not at the `?`, which is the same trade every
  trait call makes.
- Linea has no blanket identity implementation. A bound such as
  `R.Error: Into[io.IoError]` still needs `From[IoError] for IoError` written
  out, which is why `std.io` keeps its hand-written identity implementation.
- A generic function whose error parameter is converted into needs the
  `From` bound on that parameter, as any trait call does.
- Per `?`, the checker asks one implementation query, only where the error
  types differ; discovery and lowering do one selection each per converting
  `?` per instance. A `?` that passes its error through costs what it did.

## Alternatives considered

**Identical error types only, the previous rule.** Every propagation across
an error boundary spells its wrapping, usually as `.map_err(Variant)?`. The
wrapping is already declared as a `From` implementation in the programs that
want it, so the rule made programs say the same conversion twice and gave the
reader no information the implementation did not.

**Always call `From`, with a blanket identity implementation.** This is
Rust's definition of `?`: every propagation calls `From::from`, and
`impl<T> From<T> for T` makes the same-type case a call to the identity. In
Linea a blanket `impl[T] From[T] for T` answers for every type and argument
pair that coincide, so under
[0093](0093-two-implementations-that-could-answer-once-are-refused.md) it
overlaps every written identity implementation, such as `std.io`'s
`From[IoError] for IoError`, and every generic `From` implementation whose
head and argument can name one type. It would also add an instance and a call
to every `?` whose error already agrees, with nothing to convert. Stating the identity case in the rule
gives the same programs their meaning without either cost.

**`Into` instead of `From`.** `?` could call `Into[Enclosing]` on the
operand's error. Every `From` implementation supplies the corresponding `Into`
through the library's bridge, and a direct `Into` implementation that
overlaps the bridge is refused, so `Into` would reach the same implementations
through one more step, and a diagnostic would name a trait the program does not
implement. `From` is what the program writes, and the enclosing error type is
its `Self`.
