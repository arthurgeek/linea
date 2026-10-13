# 0143: Checked decimal conversion uses integer rounding

## Status

Accepted — 2026-09-21. Implemented locally, with focused Debug/ReleaseSafe runtime and native
public-API verification.

Builds on [0013](0013-no-undefined-behaviour.md),
[0017](0017-failure-is-a-trap-or-a-value.md) and
[0123](0123-observations-carry-owner-dependencies-through-callable-contracts.md).
Supports the explicit numeric access contract in
[0141](0141-json-documents-own-bounded-trees-and-number-tokens.md).
No compiler or foreign-ABI language rule changes.

## Context

Text conversion must report malformed input and range loss as values. JSON
also needs explicit binary floating conversion while retaining decimal tokens
unchanged during parsing. A locale-dependent C parser, a NUL-terminated input
contract, or ambient-mode-dependent rounding would make results depend on
state absent from the public API.

The existing foreign interface accepts integers. The pinned Zig parser has an
integer conversion path with bounded decimal storage, but its public parseFloat
entry point also selects native floating arithmetic for common inputs.

## Decision

Expose `text.parse_float64(Str) -> Result[Float64, FloatParseError]` with
independent result/error lifetimes. Decimal syntax admits an optional sign,
leading zeroes, an optional fraction and an optional exponent. Required digit
positions, full consumption and a 65,536-byte token bound are checked by one
runtime scanner. JSON keeps its own stricter token grammar.

Round to nearest binary64 with ties to even. Admit subnormals and preserve
signed zero. Report rounding to infinity and nonzero underflow to zero as
OutOfRange. Syntax errors carry byte offsets; oversized tokens return
TokenLimit before scanning or dereferencing input.

Pass a certified byte address and explicit extent through a private std.mem
adapter. The runtime returns an integer status and initialized UInt64 output
words for exact IEEE bits and syntax offset. No runtime pointer or temporary
view escapes. Linea reconstructs the finite result with an exactly representable
integer significand and exact powers of two.

Use Zig 0.16.0's integer-only `convertSlow` provider. The build makes an unchanged
generated copy of its four required files to avoid conflicting ownership with
Zig's standard-library module. Retain and install the upstream MIT notice.
There is no separately maintained conversion implementation. Provider state
contains 768 significant decimal digits and a discarded-tail flag; integer
rounding chooses the final bits without reading or changing the floating
rounding mode.

## Consequences

This is a reusable text API and ordinary runtime boundary, with no JSON-specific
compiler hook. Conversion and errors outlive their source text and require no
allocation. Input work is O(N); decimal rounding storage is fixed, and exact
Linea reconstruction takes at most 1,074 power-of-two steps.

The build depends on private files of the pinned Zig toolchain. Upgrades must
review that dependency and run known-answer, discarded-tail, boundary and
rounding-mode tests in Debug and ReleaseSafe. Generated C remains covered by
the existing runtime sanitizer compilation path. Native public API tests also
exercise the Linea reconstruction and ownership boundary.

## Alternatives considered

- C strtod: its locale, floating environment and terminated-string behavior
  require additional state and adaptation outside the desired contract.
- Zig's public parseFloat directly: its native floating fast path does not
  establish ambient-rounding independence.
- Change and restore the floating environment: introduces mutable process or
  thread state and optimizer-sensitive ordering for an integer-solvable task.
- Maintain a new parser or checked-in provider fork: duplicates difficult
  rounding logic already supplied by the pinned toolchain.
- Broaden the foreign ABI or add a bit-cast intrinsic for this API: unnecessary;
  existing integer transport and exact arithmetic express the contract.
