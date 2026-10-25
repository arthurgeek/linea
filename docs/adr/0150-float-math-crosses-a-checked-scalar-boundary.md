# 142. Float math crosses a checked scalar boundary

Status: Accepted — 2026-09-21. Extends 0068. "General Float64 foreign calls remain unsupported" is superseded by [0228](0228-a-granted-module-calls-c.md). Extended by
[0249](0249-a-float-has-a-total-order-and-a-computed-nan-is-canonical.md),
which canonicalises a NaN a math operation returns.

## Context

The standard library needs square roots, integral rounding, powers, trigonometry
and natural logarithms/exponentials. They must handle every binary64 input,
including signed zeros, infinities, NaNs and subnormals. The ordinary extern ABI
admits integer representations; admitting arbitrary Float64 externs would widen
the trusted boundary beyond these ten operations. Reimplementing transcendental
algorithms in Linea would introduce a numerical library maintenance burden.

## Decision

The public surface is ten ordinary Float64 methods backed by private externs
in `std.scalar`. Type checking recognizes their trusted declaration identities
and validates their complete signatures before recording an intrinsic fact.
Another module or an ordinary body with the same spelling receives no special
meaning. Malformed trusted signatures are diagnosed before code generation.

One normalized math operation enum owns arity and runtime symbol spelling.
The checked declaration table crosses into instantiation and lowering, which
produce one `float_math` MIR family. Verification requires Float64 value
operands/results with exact arity. The backend calls the runtime's scalar ABI;
general Float64 foreign calls remain unsupported. Runtime symbol reservation
prevents exports from replacing these implementations.

The runtime uses the platform libc/libm for finite transcendentals, with no
universal ULP or cross-platform bit-identity promise and no exact finite
transcendental boundary-classification promise. Basic rounding and sqrt retain
their exact stated rounding contracts. The runtime supplies the complete
special-value table, nearest-even evaluation, gradual underflow and restoration
of ambient floating-point state and errno. Public math calls allocate and
release nothing and return defined IEEE values rather than trapping on domains.

## Consequences

- New numerical operations require coordinated enum, library and runtime work;
  adding an arbitrary float extern remains an error.
- One checked fact answers identity and signature questions. Later passes
  consume it, including retained-library compilation and generic callers.
- The backend's declaration scan is linear in instructions, with a constant
  ten-operation set; recognition is bounded by ten declarations per query.
- Platform library versions may change ordinary finite transcendental results.
  Exact special-value checks and reference-sample tests cover separate promises;
  samples do not establish a universal accuracy bound.
- Native executables and C library drivers link the math dependency on platforms
  that separate it. The runtime documents external object consumers' linkage.

## Alternatives considered

**General Float64 extern support.** This admits a wider foreign surface than the
library requires and leaves the new signatures outside the normalized checked
math boundary. The narrow intrinsic exception retains the existing ABI rule.

**Recognize public method names in lowering.** This duplicates semantic name
resolution and makes user declarations with the same spelling surprising.
Lowering instead reads the checked declaration table.

**Bundle a correctly rounded transcendental provider.** It adds a maintained
numerical dependency and target integration burden to obtain a stronger precision
contract than the approved platform-library model requires.

**Implement the operations in Linea.** It duplicates mature mathematical
algorithms and complicates guarantees for subnormals, enormous trigonometric
arguments and power parity. Runtime implementations keep that responsibility
at the numerical boundary.
