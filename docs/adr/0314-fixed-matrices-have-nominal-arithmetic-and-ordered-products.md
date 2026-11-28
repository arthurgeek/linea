# 314. Fixed matrices have nominal arithmetic and ordered products

Status: Accepted — 2026-11-27.

## Context

Numeric arrays already use componentwise multiplication. Matrix multiplication
has a different result shape and contracts an inner dimension, so assigning both
meanings to arrays would make the same representation ambiguous. General user
operator overloading is not needed to distinguish these numerical values.

## Decision

The standard library declares `num.Matrix[T, rows, columns]` and constructs it
from nested rows with `num.matrix`. Indexing uses the ordinary tuple-key `Index`
implementation. The compiler recognizes the library declaration by identity and
certifies its generic representation: one nested-array field whose element and
two lengths name the corresponding declaration parameters. A same-named user
record earns no arithmetic. Equal concrete lengths cannot hide a malformed
generic representation. The retained type pool preserves this declaration and
provides one representation query to typing and lowering.

Numeric matrices support addition, subtraction and negation; multiplication
supports matrix products, both matrix/vector orientations, and scalar scaling on
either side. The element domain and operations preserve the scalar rules. No
scalar addition, matrix division or implicit element conversion is introduced.
Compound assignment requires its result to have the destination's exact type.

Observe binary operands once, left to right. Every result owns independent
components. A product starts each cell at positive zero and visits contraction
indexes in increasing order, separately multiplying and adding. No reassociation
or fused operation is permitted. Empty inner dimensions produce zero cells;
empty output shapes still evaluate operands. The MIR uses bounded loops rather
than expanding dimensions into instruction streams.

The ordinary library operations `num.dot` and `num.hadamard` express array dot
products and corresponding-component matrix products through the existing
Additive, Multiplicative and Copyable contracts. They add no compiler-owned
callable category.

## Consequences

Matrix dimensions are checked while typing products. Index expressions retain
ordinary runtime bounds checks. Matrices have inline storage and their element
ownership obligations; they do not imply device residency, allocation or SIMD.
Nested arrays retain their established ABI. Matrix arithmetic is not added to
the syntactic constant-expression domain.

## Alternatives considered

- **Use nested arrays for matrix multiplication:** conflicts with their
  componentwise vector meaning and weakens shape diagnostics.
- **General operator overloading:** adds an unrelated language mechanism.
- **Recognize the spelling Matrix or inspect concrete field shapes:** admits
  user impostors or misclassifies malformed square generic representations.
- **Unroll every cell:** makes compiler work scale with dimensions rather than
  with the bounded numerical operation.
