Run production reduction and matrix hardware tests through the native build:

```sh
nix develop --command zig build test-gpu-numerical
```

`test-gpu-kernels` runs these alongside the strict Float32 helper tests.
`nix develop --command zig build test-gpu-shaders` validates all 16 images
and runs the native checker unit tests without executing a hardware harness. The
build composes production `reduce_globals.mlir`, `reduce.mlir`,
`matmul_globals.mlir`, `matmul.mlir` and strict Float32 helpers. It removes unreachable private helpers with MLIR symbol DCE, checks MLIR,
serializes and validates Vulkan 1.1 SPIR-V, then runs a native Zig disassembly
checker. Floating-point types and integer widths other than 32 are refused;
each reduction must contain exactly seven workgroup barriers. The checker also
follows calls from every entry point and refuses unreachable function bodies.
Identity and half kernels pin empty and minimal arithmetic helper closures. Generated sources
and images remain build-owned artifacts. The C harness links the fresh
production runtime archive supplied by the same build.

Reduction is tested with addition and subtraction as its binary function.
Subtraction exposes assumptions about an identity or associativity. The CPU
reference mirrors each lane's strided left fold, the six width-halving tree
stages and the initial value applied once, last. Empty reduction returns the
untouched initial bits. Matrix multiplication starts each output at positive
zero and rounds every product and ascending-k sum separately. Volatile CPU
binary32 operations use round-to-nearest, ties-to-even, and canonical computed
NaNs; known subnormal answers check this reference first.

Coverage includes 129 reductions and 22 matrix products: counts 0, 1, partial
workgroups and 65,537; zero matrix dimensions and K=0; non-square products and
aliased matrix inputs; signed zeros, NaNs, infinities and subnormals; trailing
output guards; dimension, extent, descriptor-kind and device-coherence refusal;
input access restored after completion; and buffer/device owners released
before waiting. A missing real GPU or any mismatch fails the target.

A fourth numerical image instruments the production reduction template with an
atomic call counter. Counts 0, 1, 3, 63, 64 and 65 make exactly N calls for N
real inputs, including the final initial-value call for nonempty input. This
checks that padded lanes and empty input never evaluate the user function.

These are regression samples, not an exhaustive numerical proof. The runtime
requires an integrated or discrete GPU, and on macOS selects an Apple GPU.
No sanitizer result is claimed.
