# Apple GPU qualification evidence, 2026-11-25

This records the native floating-point qualification that motivated the strict
integer implementation. It is historical evidence, not a claim about the current
production helper results. The original standalone probe was replaced by the
production compiler/runtime and is no longer a build target.

macOS 27.0; Apple M1 Pro, vendor `0x106b`; Vulkan API 1.1.350; loader
1.4.350; MoltenVK 1.4.1, driver value 10401; Zig 0.16.0; MLIR 21.1.8;
SPIRV-Tools v2026.2 (Nix package 1.4.350.0).

The driver advertises signed-zero/Inf/NaN preservation and round-to-nearest for
Float32, but not subnormal preservation. Profile 6 was selected.

| Workload | Cases | Mismatches |
| --- | --- | --- |
| Copy | lengths 0, 1, 1000, 1024, with output sentinels | 0 |
| Float32 identity | 18 bit patterns | 0 |
| Float32 negation | 18 bit patterns | 0 |
| Addition | 11 operand pairs | 2 |
| Subtraction | 6 operand pairs | 1 |
| Multiplication | 9 operand pairs | 3 |
| Division | 9 operand pairs | 2 |

All eight arithmetic differences involve subnormals:

| Operation | Left bits | Right bits | Actual bits | Linea expected bits |
| --- | --- | --- | --- | --- |
| Add | 00000001 | 00000001 | 00000000 | 00000002 |
| Add | 007fffff | 00000001 | 00000000 | 00800000 |
| Subtract | 00800000 | 00000001 | 00800000 | 007fffff |
| Multiply | 00800000 | 3f000000 | 00000000 | 00400000 |
| Multiply | 00000001 | 3fc00000 | 00000000 | 00000002 |
| Multiply | 007fffff | 40000000 | 00000000 | 00fffffe |
| Divide | 00800000 | 40000000 | 00000000 | 00400000 |
| Divide | 00000003 | 40000000 | 00000000 | 00000002 |

The hardware target exits 1 for this result. This establishes compute execution
and a concrete arithmetic incompatibility; it does not establish a compatible
Float32 GPU implementation. The subsequent compiler design must address it
explicitly, without silently weakening ordinary Float32 semantics. Vulkan's
permitted division precision is also weaker than Linea's scalar contract;
passing these division samples would not establish general compatibility.

Authored MLIR arithmetic contains one operation per entry point, without
relaxed-precision or fast-math annotations, followed by computed-NaN
canonicalization. No fused arithmetic or reduction-order claim is made.

## Production regression boundary

The current `test-gpu-float32` target exercises
`src/backend/gpu/float32.mlir` against an independent CPU binary32 oracle. It
checks raw bits, including the failing subnormal categories above, separate
rounding, NaN canonicalization and signed zeros. The native tests cover
1,048,935 operand pairs for each arithmetic operation and 1,116,491 pairs for
each comparison, with trailing output guards. See the
[regression harness documentation](../runtime/tests/gpu_float32/README.md).

```sh
nix develop --command zig build test-gpu-float32
```

Those finite samples are regression evidence, not an exhaustive IEEE proof.
Replacing the software helpers with native arithmetic requires establishing the
same language semantics on each supported device; native execution alone and
an advertised round-to-nearest mode do not establish subnormal preservation or
correctly rounded division. [ADR 0308](adr/0308-device-tensors-run-ordinary-numerical-functions.md)
records this decision, and [ADR 0309](adr/0309-tensors-separate-storage-from-numerical-operations.md)
preserves it for shared tensor operations.
