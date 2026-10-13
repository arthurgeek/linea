# Numerical reference generation

Ordinary builds and tests use the committed `tests/native/math_vectors.h`.
Only regenerating those vectors needs the optional environment:

```sh
nix develop .#math-reference -c cc -std=c11 -O2 tests/tools/math_reference.c -lmpfr -lgmp -o /tmp/linea-math-reference
/tmp/linea-math-reference > /tmp/linea-math-vectors.h
```

Inspect the generated output before replacing `tests/native/math_vectors.h`.
The locked Nix input supplies MPFR 4.2.2 and GMP 6.3.0. Neither library is a
runtime dependency or part of the ordinary development shell.

The generator uses MPFR's precision-53 binary64 exponent model with
`mpfr_subnormalize` to avoid double rounding of subnormal results. Directed
high-precision enclosures independently confirm finite transcendental results;
precision doubles until both endpoints select the same binary64 encoding.
Samples include exact landmarks, representational boundaries, fixed-seed bit
patterns, and neighborhoods of exponential/reduction thresholds. Encodings are
hexadecimal integers, so decimal parsing cannot change a reference input.

The native harness checks exact basic operations, required signs/classifications,
and compares sampled transcendental results with a 64-representable-step
regression threshold. That test threshold is not a universal accuracy or
overflow/underflow-classification guarantee: ordinary finite transcendental
precision depends on the platform math library. Binary power samples include
identity priority, exponent parity and both signs across the magnitude range. Its
separate tests put the caller in nondefault rounding and flush modes and check
that results are independent and the original environment is restored.
