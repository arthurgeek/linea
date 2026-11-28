# Running the benchmarks

Build in the Nix development shell. Both Linea matrix programs require an
unsigned decimal seed. An optional second argument, `--verify-only`, runs
the exact-component checks and exits before timing. The programs print the
seed before their measurements. For example, use the same seed for every
variant you compare.

```sh
nix develop
zig build
mkdir -p .scratch/matrix-benchmark
zig-out/bin/linea build -O 3 --keep bench/matrix_layout.lin -o .scratch/matrix-benchmark/cpu
zig-out/bin/linea build -O 3 --keep bench/matrix_values_gpu.lin -o .scratch/matrix-benchmark/gpu
.scratch/matrix-benchmark/cpu 17 --verify-only
.scratch/matrix-benchmark/gpu 17 --verify-only
```

Keep source and binary identities with the figures. Record the device and
driver version as well as the active ICD. `--keep` retains each actual SPIR-V
binary beside the GPU executable. On macOS the selected ICD is available
inside the shell through `VK_DRIVER_FILES`.

```sh
git status --short
git rev-parse HEAD 'HEAD^{tree}'
shasum -a 256 zig-out/bin/linea .scratch/matrix-benchmark/cpu .scratch/matrix-benchmark/gpu .scratch/matrix-benchmark/*.spv
cat "$VK_DRIVER_FILES"
system_profiler SPDisplaysDataType
```

On a quiet machine, capture the nine measured rounds in new files. Each
workload emits a configuration row containing its actual warmups, samples,
cases and repetitions. CPU times
include input perturbation, checksum and the optimizer barriers. GPU times
include three complete map calls, including allocation, pipeline creation,
waiting and release. Host verification and download take place outside the
timed batches. Each program compares its own implementations on the same
device. The original [matrix layout report](../docs/matrix-layout-measurements.md)
and its 2026-11-27 raw files describe the earlier benchmark revision.

```sh
.scratch/matrix-benchmark/cpu 17 > .scratch/matrix-benchmark/cpu.csv
.scratch/matrix-benchmark/gpu 17 > .scratch/matrix-benchmark/gpu.csv
```

`bench/tasks.lin` prints the duration of each measured batch, followed by
order statistics. The label preceding each group specifies nanoseconds per
batch, item, or session round trip. Each task benchmark uses the caller's
execution context.
