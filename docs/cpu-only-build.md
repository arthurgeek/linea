# CPU-only builds

The default `nix develop` shell and `zig build` include Vulkan GPU support.
To build the compiler and both runtime archives without Vulkan headers, a
Vulkan loader, SPIR-V tools or MoltenVK, use:

```sh
nix develop .#cpu
zig build -Dgpu=false
zig build -Dgpu=false test-cpu-only
```

The CPU shell retains Zig, the CPU MLIR toolchain, Clang and rustls-ffi.
The build flag selects the unavailable implementation of the same internal
GPU ABI. The compiler also refuses its certified device-acquisition call, so
linking a GPU-enabled archive cannot enable a device in a CPU-only compiler.
CPU tensor operations and the existing thread and fiber executors remain
available. Public GPU APIs still compile, but device acquisition reports
`GpuError.Unavailable` (internal runtime code `-19`); explicit GPU requests never
execute on the CPU.
The compiler does not prepare device images or invoke SPIR-V tools in this
mode. Explicit GPU test targets explain that a GPU-enabled build is required.

After building, the shared numerical example runs the CPU pipeline and reports
the unavailable GPU capability explicitly:

```sh
zig-out/bin/linea run examples/tensor_pipeline.lin
```

Its output is `CPU: 622.5` followed by `GPU: unavailable`. Allocation and other
errors still propagate normally; this program does not turn failed GPU work
into a CPU fallback.

The existing blocking CI `check` job also runs:

```sh
nix develop .#cpu --command bash .github/scripts/cpu-only.sh /tmp/linea-cpu-only
```

Use a fresh scratch directory for a cold dependency check. The script evaluates
the build graph with Vulkan variables unset, then builds with poisoned Vulkan
paths and GPU tool wrappers in a separate cache and install prefix. It executes
CPU code, checks the unavailable GPU ABI against both archives, and runs existing
fiber programs. Positive fake-device archives additionally prove acquisition
would succeed if called: the CPU compiler must still answer unavailable. CI
uses its normal GPU compiler as the positive acquisition control and also checks
that compiler against the CPU archives, with no hardware requirement. The CPU
shell retains the common checkout and editor setup; only the Vulkan driver hook
is omitted. Two filtered unit tests verify the mode-sensitive tool-cache salt
and that the compiler gates only certified device acquisition. A wrapper
invocation fails the check. The CPU Nix shell excludes the GPU packages even when they are physically present elsewhere in the Nix
store. The normal full GPU build remains independently tested by CI.

When a normal GPU compiler has already been built, pass its path as the optional
second argument to run both compiler modes against the fake-positive and CPU
archives (the CI step does this):

```sh
nix develop .#cpu --command bash .github/scripts/cpu-only.sh /tmp/linea-cpu-only "$PWD/zig-out/bin/linea"
```

The fake provider emits an acquisition marker. Its native and GPU-compiler
positive controls must observe that marker; the CPU compiler must observe none,
so a runtime override cannot silently acquire a device before discarding it.
