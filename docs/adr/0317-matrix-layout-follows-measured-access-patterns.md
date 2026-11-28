# 317. Matrix layout follows measured access patterns

Status: Accepted — 2026-11-27.

## Context

Column-major storage makes one family of matrix/vector accesses contiguous;
row-major makes the opposite family contiguous. SIMD can accelerate independent
output lanes in either layout without reassociating each cell's reduction.
A layout choice needs actual CPU and GPU evidence, rather than a general claim
that one order is inherently faster or better suited to vector instructions.

## Decision

Keep fixed Matrix values and resident tensors row-major. Preserve ordinary
nested-array representation. Constructors continue to accept nested rows and
matrix indexing remains row, column. This is an implementation decision, not a
new public foreign ABI or a SIMD register-width promise.

Use the contiguous result axis as the innermost loop for fixed matrix products:
row/k/column for row-major output, column/k/row for column-major output. Initialize
result cells at positive zero. Each individual cell receives separately rounded
products and sums in increasing k order; no reassociation or contraction is
introduced. Generated loop count remains independent of matrix dimensions.

The [measurement report](../matrix-layout-measurements.md) retains benchmark
sources, raw samples, reproducible commands, instruction inspection and limits.
It includes both matrix/vector orientations, rectangular and larger products,
elementwise work, packing costs, actual Matrix operators and real Apple GPU
execution. GPU wall times are distinguished from isolated kernel timing.

## Consequences

The measured CPU Matrix products improve without changing their storage or
scalar meaning. Larger matrix-vector workloads can still favor column storage;
the opposite orientation favors row storage. Resident GPU measurements do not
establish a consistent reason to change tensor storage. Further devices or
workloads can motivate another measured decision; Apple measurements establish
no NVIDIA result.

## Alternatives considered

- **Choose column-major because vector instructions exist:** ignores opposing
  access patterns and small-value compiler optimizations.
- **Change every nested array and tensor together:** changes unrelated ABI and
  transfer conventions without supporting evidence.
- **Keep cell/k loop order regardless of layout:** prevents independent output
  cells from using contiguous vector lanes in the measured larger CPU products.
- **Reassociate a dot product or allow FMA:** changes promised scalar results
  and would make the comparison numerically inequivalent.
