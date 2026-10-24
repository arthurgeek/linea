# 226. Float32 is a second binary floating-point width

Status: Accepted — 2026-10-15. Extends [0018](0018-the-integer-model.md) and
[0152](0152-an-integer-literals-type-is-settled-by-its-uses.md); admits the
second width the float design declined until a program needed it.

## Context

`Float64` was the only float. The float design declined `Float32` until a
program could name a need for it, and left the record that admits it to
answer how a literal, a conversion and a narrowing behave. The need is memory
and interchange: a `Vec[Float32]` of samples, vertices or weights is half the
size of its `Float64` form, and audio, mesh and model formats store binary32.

Three things make a second width more than a new name:

- A float literal was always `Float64`; the checker ignored the expected type,
  which only stopped mattering because there was one width.
- A decimal rounded to binary64 and then to binary32 can differ from the
  decimal rounded once to binary32. The two roundings meet at a binary32
  halfway point that the decimal lay just beyond.
- `Float64` to `Float32` loses range as well as precision, and the language
  had to say whether that is a value or a trap.

## Decision

**`Float32` is IEEE 754 binary32**, a primitive beside `Float64`: four bytes,
aligned to four, computed and stored as MLIR `f32`, C `float` in a layout. It
is a scalar, copyable and releasing nothing. It implements `Equatable` and
`Comparable` with `Float64`'s partial order (NaN is equal to and ordered
against nothing) and neither `Equivalent` nor `Ordered`. Arithmetic is binary32
arithmetic, each operation rounded to nearest with ties to even, under the same
rule that no float transformation is permitted that is not exact. `%` is
refused for it as for `Float64`.

**A float literal's type is settled by its uses, as an integer literal's is.**
With no expected type a float literal has an open float type, settled where it
must equal a float type and falling back to `Float64`. An open float and an
open integer never become one: no type is both. A float literal converted to a
float type, `Float32(0.1)`, settles on the conversion's target, so it is
rounded once. Only a literal does: a binding or an expression over literals
converted to `Float32` is a `Float64` first, so the conversion narrows a value
and never changes the type of a binding or the width of arithmetic.

**A literal must be representable in the type it finally has.** Rounding to
nearest is admitted, since `0.1` is inexact in every binary format, but a
literal that rounds to an infinity, or a nonzero literal that rounds to zero,
is refused with [T-Literal] at the literal, labelled where its type was
settled. This applies to `Float64` too: `1e-400` is refused, as
`text.parse_float64` already refused it. The compiler rounds a literal in one
routine, at the literal's final width.

**Conversions are written and defined for every value.** `Float64(x)` of a
`Float32` is exact. `Float32(x)` of a `Float64` rounds to nearest, ties to
even; a finite value beyond binary32's range becomes the infinity of its sign,
which IEEE 754 defines, and NaN stays NaN. An integer converts to `Float32` by
rounding. A `Float32` converts to an integer as a `Float64` does: truncating
toward zero, trapping on NaN and on a value whose truncation the target cannot
hold. One routine gives both widths their bounds.

**Display and parsing are per width.** `Float32` prints the shortest decimal
that reads back as the same `Float32`, with `Float64`'s notation, and
`text.parse_float32` rounds once to binary32. Both use the runtime's existing
providers at `f32` and cross the foreign interface as the bits of the `Float64`
holding the same value, which it holds exactly. Floats still do not cross
`extern`.

## Consequences

- The type pool's float kind carries its width, and MIR's float
  representation carries its bits, so every routine that asks about a float
  asks which one.
- Two MIR instructions, `float_extend` and `float_truncate`, lower to
  `arith.extf` and `arith.truncf`.
- The open-type table gives each variable a family (integer, float, or any),
  which supplies its candidates and its fallback.
- A NaN's sign and payload stay unobservable: display prints every NaN as
  `NaN`, and no operation reads a float's bits. So this record says nothing
  about which NaN an operation produces.
- The `Float32` math methods are not provided. `sqrt`, `floor`, `ceil`,
  `trunc` and `round` could later be added exactly through `Float64` and
  narrowing; the transcendental functions could not.
- JSON numbers interchange as binary64, so `Float32` has no JSON
  implementation; a program converts.

## Alternatives considered

**Literals typed only by an expected type.** `let gain = 0.5` followed by
`sample * gain` would be refused for the order of its lines, which is the gap
0152 closed for integers.

**A literal suffix.** A suffix spells what an annotation or a use already
settles, and the float design refused one.

**Narrowing traps on overflow.** It would make `Float32(x)` the one float
operation that traps without leaving the float world; binary32 has an
infinity to stand for the result, which is what IEEE 754 gives.

**A separate pool kind for each width.** Every routine asking "is this a
float" would ask twice; one kind with a width asks once.

**Parsing through binary64.** It rounds twice, and for some inputs gives the
other neighbour.

**A `Float32` C ABI.** The runtime entries pass integers today, and the exact
binary64 encoding carries a binary32 value without one.
