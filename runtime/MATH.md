# Binary64 math runtime

`math_runtime.h` is the internal C ABI consumed by scalar intrinsics. The
runtime implements square root, floor, ceiling, truncation, ties-to-even
rounding, sine, cosine, natural logarithm, exponential and binary power.

Integral rounding uses binary64 bit operations. Square root uses the platform
square-root instruction or C implementation under nearest-even rounding.
Sine, cosine, logarithm, exponential and power use the platform `<math.h>`
implementation. Their ordinary finite precision, including rounding at
finite overflow and underflow boundaries, depends on that implementation.
There is no universal representable-step error guarantee.

The runtime handles NaNs, infinities, signed zeros, domains and power identity
priority before calling the platform library. It determines power exponent
parity from binary64 bits, without converting an unbounded value to an integer.
Each platform calculation temporarily uses nearest-even rounding with gradual
underflow and masked exceptions, then restores the caller's complete floating
environment and `errno`. Operations allocate no memory.

The supported control-register paths are AArch64 (FPCR) and x86-64 (MXCSR).
C binary64 representation and evaluation assumptions are checked at compile
time; an unsupported architecture fails compilation. Linux links the system
math library with `-lm`; Darwin provides the functions through libSystem.
The math object uses the same runtime sanitizers as the other C objects, with
strict floating-point compilation and contraction disabled.

`zig build test-native-math` and `zig build test-native-math --release=safe`
exercise exact special values, rounding, hostile caller environments, and
independent reference samples. See [reference generation](../tests/tools/README.md)
for the optional offline oracle. Its dependencies are absent from runtime and
ordinary development builds.
