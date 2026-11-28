# Matrix layout measurements — 2026-11-27

## Decision

Keep fixed `num.Matrix` values and resident tensors row-major. Ordinary nested
arrays keep their existing contiguous-inner-array ABI. Neither layout wins every
workload. Row-major wins the small 4×4 CPU matrix-vector workload, while larger
matrix-vector products favor column-major and vector-matrix products favor
row-major. Layout-appropriate matrix products are close. The GPU measurements
provide no consistent reason to change resident storage. Retaining row-major
also avoids packing nested rows when constructing fixed values or uploading
existing row-major tensor data.

Change the fixed-matrix **product loop order**, rather than its storage:
initialize positive-zero result cells, then visit row/k/column for row storage
(column/k/row for column storage). Every individual cell still receives its
products in increasing k order, with separate scalar multiply and add rounding.
Independent output cells can use vector instructions. Other matrix operations
and tensor algorithms retain their existing order.

These results apply to this machine and these workloads. They do not establish
a universal layout winner, NVIDIA performance, a public matrix ABI guarantee,
or a promise that ordinary arrays always use SIMD registers.

## Machine and method

- Apple M1 Pro, arm64 CPU and 14-core Apple GPU, macOS.
- Nix shell: Zig 0.16.0; MLIR/LLVM and Clang 21.1.8; SPIRV-Tools v2026.2.
- CPU and Linea GPU benchmarks built with `-O 3`. GPU arithmetic uses the actual
  integer-only strict binary32 helpers; there is no relaxed native-float path.
- The compiler before loop reordering is `b6bcdc6b`. Both versions compile the
  same benchmark sources in this change. The before version already includes
  first-lane construction for repeated array/matrix values.
- CPU fixtures have distinct left/right operands and runtime seeds. Every
  timed iteration varies all input lanes; checksums consume all result bits.
  A separate cell-at-a-time scalar oracle checks every product cell, both layout
  prototypes and the actual Matrix operator before timing. Matvec and vecmat
  prototypes are checked against each other and the real operator.
- CPU timing includes the input perturbation and checksum, and the actual
  operator path includes its ordinary Matrix constructors. Initial fixture
  construction/transposition is outside the samples.
- Nine samples rotate row/column order. GPU value samples rotate all three
  variants. Warmup/validation precedes sampling. Final CPU and GPU measurements
  run sequentially without concurrent repository validation or compilation.
- Resident-buffer GPU timing includes pipeline creation, native completion
  thread overhead, submit, wait and cleanup. Allocation/upload and packing are
  reported separately. These are **wall times, not GPU timestamps**.
- Fixed-value GPU timing maps over 65,536 resident Float32 inputs. It includes
  output allocation, pipeline creation, completion and release, with three maps
  per sample. Download and exact-bit CPU-reference validation are outside the
  samples. Input upload is outside all samples. Twelve ordinary Linea functions
  exercise four operations in row/column prototypes and actual Matrix operators.
- All benchmark data is finite signed dyadic Float32. Numerical conformance and
  hardware regressions separately cover NaNs, zeros, subnormals and overflow;
  the timing sample is not a replacement for those correctness checks.

## CPU layout tradeoffs

Median column time / median row time, before loop reordering. Below 1 favors
column storage. Vector dimensions here use the left M×K matrix; N is the right
matrix's column count for matmul. Elementwise includes a copy, shift and hash.

| Shape M×K×N | Matvec | Vecmat | Matmul | Elementwise |
| --- | ---: | ---: | ---: | ---: |
| 3x4x5 | 0.999 | 0.388 | 0.980 | 2.925 |
| 4x4x4 | 1.870 | 0.658 | 1.081 | 1.000 |
| 8x8x8 | 0.936 | 1.318 | 1.003 | 1.016 |
| 16x16x16 | 0.530 | 1.893 | 1.044 | 0.998 |
| 32x64x16 | 0.098 | 7.875 | 0.926 | 0.450 |
| 128x128x128 | 0.076 | 13.140 | 0.999 | 1.005 |

The opposing large matvec/vecmat results are important: contiguous access across
independent output lanes can vectorize without reassociating a reduction. They
do not justify changing every matrix, nested array or tensor to one layout.

## Actual fixed-matrix product improvement

Median time per operation, including the benchmark's perturbation/checksum and
constructor costs. Before/after use identical data and repetitions. The after
range gives the nine sample values, rather than implying exact timings.

| Shape | Before µs/product | After µs/product | Speedup | After min–max µs/product |
| --- | ---: | ---: | ---: | ---: |
| 3x4x5 | 0.04118 | 0.01679 | 2.45× | 0.01676–0.01682 |
| 4x4x4 | 0.04396 | 0.01348 | 3.26× | 0.01342–0.01350 |
| 8x8x8 | 0.33267 | 0.07617 | 4.37× | 0.07602–0.07645 |
| 16x16x16 | 2.87640 | 0.62990 | 4.57× | 0.62890–0.63270 |
| 32x64x16 | 43.00450 | 4.88700 | 8.80× | 4.88400–4.92000 |
| 128x128x128 | 3517.51000 | 260.51500 | 13.50× | 258.47500–262.65000 |

`otool -tvV` on the actual optimized executables shows ARM `fmul.4s` and
`fadd.4s`. The complete benchmark executable has 883/1,629 such instructions
before and 986/1,727 after. Both have zero `fmla`, `fmadd`, `fmls` or `fmsub`
instructions. These are whole-executable instruction counts, not executed
instruction counts or a claim that every individual product vectorizes.

## GPU interpretation

Across 18 resident matmul/matvec/vecmat shapes, median column/row wall ratios are
0.987–1.030. Setup/pipeline/completion costs dominate these small dispatches;
there is no demonstrated kernel-only layout advantage. The harness transposes
inputs explicitly and checks every output word against an independent volatile
CPU multiply/add reference after each sample. Production row shaders and the
column indexing variant both pass Vulkan 1.1 SPIR-V validation and the existing
integer32 shader checker.

For fixed values, row/column prototypes and the actual Matrix operators all
match the scalar CPU reference bit for bit. The actual 4×4 matmul operator's
median was 10.873 ms before and 10.537 ms after **for three complete map calls**.
Unchanged control functions also vary between runs; this is not evidence of a
GPU speedup or a consistent regression. CPU gains are the demonstrated benefit
of the loop-order change. GPU execution remains qualified for correctness.

## Reproduction and retained data

Sources: [CPU workload](../bench/matrix_layout.lin),
[resident GPU harness](../bench/matrix_layout_gpu.c), and
[ordinary Linea GPU value workload](../bench/matrix_values_gpu.lin).

Run from a quiet checkout inside the Nix shell:

```sh
nix develop --command zig build
nix develop --command zig-out/bin/linea build bench/matrix_layout.lin -O 3 -o /tmp/linea-layout-cpu
nix develop --command /tmp/linea-layout-cpu
nix develop --command zig build bench-matrix-layout-gpu
nix develop --command zig-out/bin/linea build bench/matrix_values_gpu.lin -O 3 -o /tmp/linea-layout-values
nix develop --command /tmp/linea-layout-values
otool -tvV /tmp/linea-layout-cpu
```

For a before/after comparison, use a compiler built from `b6bcdc6b` and the final
compiler with these same benchmark source files. Native GPU shaders are composed
from production templates; the comparison changes only physical indexing and
retains the same kernel algorithm and strict helpers. The native harness uses
the production runtime archive from its build. Missing GPU capability fails;
none of the hardware benchmarks falls back to CPU.

Raw samples are in `bench/results/2026-11-27-matrix-*.csv`. CPU files have a
`shape` row before each group; following rows match their header. Resident GPU
`setup,M,K,N,row_upload_ns,column_upload_ns,transpose_ns` rows describe setup;
`resident` rows match their timing header. GPU-value files have one rectangular
CSV table. Warmups are excluded from timing rows; all nine samples are retained and no
outliers were discarded.
