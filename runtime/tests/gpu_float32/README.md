Run the strict Float32 hardware tests through the native Zig build graph:

```sh
nix develop --command zig build test-gpu-float32
```

`test-gpu-kernels` also runs these checks alongside reduction and matrix tests.
For shader validation and native checker unit tests without hardware, run
`nix develop --command zig build test-gpu-shaders`.
The build composes the production `src/backend/gpu/float32.mlir` helpers with
`pair.mlir`, removes unreachable private helpers with MLIR symbol DCE, checks
MLIR, serializes SPIR-V and validates each image for Vulkan
1.1. A native Zig checker examines disassembly and rejects floating-point types,
integer widths other than 32, unexpected workgroup barriers and function bodies
not reachable by calls from an entry point. Generated
sources, checked modules, binaries and disassembly are build-owned artifacts.
The native C harnesses link the fresh runtime archive supplied by this build.

Each kernel reads packed operand pairs at `2*i` and `2*i+1` from binding0 and
writes one result at `i` in binding1. A count push constant bounds the partial
last workgroup; local size is 64. Arithmetic writes raw result bits. Comparisons
return Boolean results encoded by a select as exactly 0 or 1.

The arithmetic harness checks all four operations against volatile CPU binary32
arithmetic under round-to-nearest, ties-to-even, canonicalizing computed NaNs.
It covers independently specified boundary answers, signed zeros, infinities,
both NaN kinds, all 256 × 256 exponent pairs at six significand edges and two
relative signs, and 262,144 deterministic random pairs: 1,048,935 pairs per
operation. Known answers first check that the CPU reference preserves subnormals.

The comparison harness covers `eq`, `ne`, `lt`, `le`, `gt`, `ge`: 1,048,576
random pairs plus 67,915 special/exponent/adjacency pairs per operation. It checks
signed-zero equality and unordered NaNs, preserves input signs/payloads by
comparing every input bit after dispatch, and pins independent expected truths
before trusting CPU comparisons. Each operation checks 1,116,491 pairs.

Both harnesses check 16 trailing guard words. A missing hardware device, runtime
failure, invalid image or numerical mismatch fails the target. These samples
provide regression coverage, not exhaustive coverage of all 2^64 operand pairs.
They run separately from the ordinary suite. No sanitizer result is claimed.
