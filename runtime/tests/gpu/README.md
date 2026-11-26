# Apple GPU qualification

Run device-independent checks with `nix develop --command zig build test-gpu-probe`.
They also run in the unfiltered test suite and require no GPU dependencies.
These checks include independently authored expected bits checked against strict
host Float32 arithmetic.

Run injected host-dispatch failures with
`nix develop .#gpu --command zig build test-gpu-host`. This requires the pinned
Vulkan headers and SPIR-V tools, but no GPU. The Vulkan boundary is replaced;
the real host allocation, bounds, submission and cleanup code runs. Failures at
every fallible dispatch call, device loss, and indeterminate completion are
checked. No in-flight allocation may be destroyed after an indeterminate wait;
the standalone process exits instead.

Run the real hardware target with `nix develop .#gpu --command zig build gpu-probe`.
This shell adds the pinned Vulkan loader/headers, SPIR-V tools, and MoltenVK ICD
on Darwin. It installs no global SDK. A requested hardware run fails when no
Apple compute device is available; software Vulkan is not a substitute.
Shaders are readable MLIR fixtures, serialized and validated as SPIR-V for
Vulkan 1.1. Eight floating-point control profiles are validated; the run selects
only the controls the device advertises.

For the probe executable, exit 0 means all selected samples passed, 1 means shader execution completed
but numerical/bit comparisons differed, and 2 means setup or execution failed.
The `zig build` wrapper reports a build failure for either nonzero executable status.
A passing sample does not prove complete IEEE conformance. There is no public
Linea GPU API in this deliverable, and the probe is never linked into the
production runtime. Its synchronous fence wait is confined to this standalone
executable; it is not an interface for Linea fibers.

## Observed Apple result, 2026-11-25

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
