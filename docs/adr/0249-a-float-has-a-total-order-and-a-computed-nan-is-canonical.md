# 249. A float has a total order, and a computed NaN is canonical

Status: Accepted — 2026-10-16. Extends [0013](0013-no-undefined-behaviour.md),
[0143](0143-checked-decimal-conversion-uses-integer-rounding.md),
[0150](0150-float-math-crosses-a-checked-scalar-boundary.md) and
[0226](0226-float32-is-a-second-binary-floating-point-width.md).

## Context

A float is `Comparable` and not `Ordered`, so `Vec.sort` refuses one, and a
program sorting floats wrote its own comparison deciding where NaN goes. IEEE
754 defines a total order over every float, `totalOrder`, which Rust exposes as
`f64::total_cmp`: the negative NaNs, `-inf`, the negative numbers, `-0.0`,
`0.0`, the positive numbers, `inf`, the positive NaNs. It orders bit patterns,
so it needs a float's sign bit, a NaN's included.

No operation exposed a float's bits. The library rebuilt them with exact
arithmetic for display and parsing, which ADR 0143 chose over a bit cast, and
that arithmetic cannot see a NaN's sign.

Exposing bits makes a NaN's sign and payload observable, and LLVM does not
determine them: which NaN an arithmetic operation produces is left to the
target and to constant folding. x86-64 produces a negative quiet NaN, AArch64
a positive one, and the constant folder a positive one, so `0.0 / 0.0`
computed at run time on x86-64 differs from the same division folded. A total
order over such a value would sort it first on one machine and last on
another, or differently at `-O0` and `-O2`, which ADR 0013 forbids.

## Decision

**`to_bits` and `from_bits` reinterpret a float as the unsigned integer of its
width and back**, keeping every bit: `Float64` with `UInt64`, `Float32` with
`UInt32`. They are public methods over four trusted `std.mem` declarations
that lowering replaces with one `bit_cast` MIR instruction, emitted as
`arith.bitcast`. The checker holds the declarations to the runtime symbol
table and admits their float parameter or result there; floats still cross no
foreign boundary.

**Every NaN that arithmetic, a conversion between the float types or a math
method produces is the positive quiet NaN**: `0x7FF8000000000000` and
`0x7FC00000`. Emission follows each `addf`, `subf`, `mulf`, `divf`, `extf`,
`truncf` and math call with `select(cmpf uno r r, canonical, r)`. Negation is
not arithmetic (LLVM `fneg` flips the sign bit only), and neither are copies,
loads, stores, selects and bit casts, so a NaN's sign and payload are what the
program made them. A select is exact, and folding it can produce only the
canonical NaN, so the no-fast-math rule holds.

**`total_less` is `totalOrder`** for each float type, in Linea: a set sign bit
maps the bits `b` to `max - b` and a clear one to `b + 2^(n-1)`, and the keys
compare unsigned. Neither branch overflows. `<` stays the partial order, and
`total_less` is not `Comparable.less`. `values.sort_by(Float64.total_less)`
sorts any floats; a NaN the program computes sorts last, and `-nan` first.

The display and parse paths read and build bits with the primitives, and the
arithmetic reconstruction they used is removed.

## Consequences

- A float's bits are part of a program's meaning, and are the same on every
  target and at every optimisation level.
- Each NaN-producing float operation costs a compare and a select. On x86-64
  at `-O2` a run-time division becomes `divsd`, `cmpunordsd` and a blend. A
  loop of four dependent float operations per iteration, 200 million times at
  `-O2` on AArch64, took 1.25 s against 0.85 s without the selects: the cost
  is real where floats are the whole of the work, and it is the price of a
  result that does not depend on the machine.
- A Linea program can read binary32 and binary64 data from bytes.
- NaN canonicalisation lives here rather than in 0226, because until bits are
  observable, which NaN an operation produces cannot be seen.

## Alternatives considered

**NaN is one class, ordered last.** `total_less` would tie every NaN and need
no compiler change, but it is not `totalOrder`: `-nan` would not sort first,
and Rust's `total_cmp` would disagree with it.

**Raw bits, with a NaN's sign left unspecified.** A result would depend on the
target and the optimisation level, which ADR 0013 forbids.

**Canonicalise in `to_bits` only.** The sign negation gives a NaN would be lost,
so `-nan` could not sort first, and every read would pay a select.

**Keep rebuilding bits with arithmetic.** It cannot see a NaN's sign, which the
order needs.
