# Running the benchmarks

Build in the Nix development shell. Both Linea matrix programs require an
unsigned decimal seed. An optional second argument, `--verify-only`, runs
the exact-component checks and exits before timing. The programs print their
schema revision, seed and successful validation before measurements. Use the
same seed for every variant you compare.

```sh
nix develop
zig build
mkdir -p .scratch/matrix-benchmark
zig-out/bin/linea build -O 3 --keep bench/matrix_layout.lin -o .scratch/matrix-benchmark/cpu
zig-out/bin/linea build -O 3 --keep bench/matrix_values_gpu.lin -o .scratch/matrix-benchmark/gpu
.scratch/matrix-benchmark/cpu 17 --verify-only
.scratch/matrix-benchmark/gpu 17 --verify-only
```

Validation and performance inputs serve different purposes. The timed seeds
retain the original small dyadic patterns. CPU validation separately checks
rectangular and odd shapes using non-dyadic values, signed zeros, subnormals,
infinities and NaNs, against a cell-at-a-time reference with increasing
contraction order. Known answers distinguish reassociation and FMA contraction.
The finite `17×3` fixture has 51 distinct component bit patterns, checked by a
separate uniqueness property, so a repeating row pattern cannot hide a permutation.
GPU validation checks every component for all three implementations and exact
download lengths. A separate 23-pattern corpus includes exceptional values and
rounding-sensitive cancellation; a two-input identity kernel observes subnormals and
NaN payloads before arithmetic can hide them. None of these validation maps is
timed. This broader correctness coverage does not make the timed input pattern
representative of all matrix workloads.

The CPU-only validation tests need no GPU device:

```sh
zig-out/bin/linea test -O3 bench/matrix_layout.lin
zig-out/bin/linea test -O3 bench/matrix_values_gpu.lin
```

Keep source and binary identities with the figures. Record the device and
driver version as well as the active ICD. `--keep` retains each actual SPIR-V
binary beside the GPU executable. On macOS the selected ICD is available
inside the shell through `VK_DRIVER_FILES`.

```sh
git status --short
git rev-parse HEAD 'HEAD^{tree}'
shasum -a 256 bench/matrix_layout.lin bench/matrix_values_gpu.lin
shasum -a 256 zig-out/bin/linea .scratch/matrix-benchmark/cpu .scratch/matrix-benchmark/gpu .scratch/matrix-benchmark/*.spv
shasum -a 256 "${LINEA_RUNTIME:-zig-out/lib/liblinea_rt.a}"
zig version
mlir-opt --version
mlir-translate --version
spirv-val --version
cc --version
cat "$VK_DRIVER_FILES"
system_profiler SPDisplaysDataType
```

Record the exact build arguments and runtime archive actually used, including
any `LINEA_RUNTIME` or sanitizer override. Commit/tree IDs describe the committed
base; retain modified and untracked inputs or a complete source manifest for a
dirty build. The executable and compiler hashes identify the measured artifacts.
Keep the machine/OS description and timing conditions with the raw output.

Current output begins with `schema,matrix_layout,2` or
`schema,matrix_values_gpu,2`. CPU schema 2 adds complete-result observation;
both programs identify their independent validation corpus. This is a harness
revision, not a compiler version. Preserve these metadata rows when parsing the CSV. Earlier files without
these rows remain historical results and need a fresh run for comparisons using
the current timing boundary.

On a quiet machine, capture the nine measured rounds in new files. Each
workload emits a configuration row containing its actual warmups, samples,
cases and repetitions. CPU times
include input perturbation, observation of each complete typed result, checksum
and optimizer barriers. The complete result is observed before its checksum;
equal checksums alone are not the correctness oracle. GPU times
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
