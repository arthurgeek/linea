# 311. Numeric arrays apply scalar arithmetic elementwise

Status: Accepted — 2026-11-27. Extends
[0061](0061-an-array-is-a-value-of-a-fixed-size-type.md) and
[0020](0020-a-constant-expression-is-defined.md).

## Context

Fixed arrays already describe small mathematical vectors: their element type
and length are static, indexing is checked, and their storage is contiguous.
Requiring a second vector container solely to write arithmetic would duplicate
that representation. Explicit SIMD has a different promise about lane lowering
and remains a separate capability.

Scalar operations already define overflow, integer division, floating-point
rounding and NaN behavior. A numerical array must not create weaker versions of
those rules or duplicate the implementations of their checks.

## Decision

Numeric arrays support elementwise scalar arithmetic. Two arrays must have the
same type; an array may also combine with a scalar of its exact element type on
either side. Unary negation and compound assignment use the same operations.
There is no implicit numeric conversion or multidimensional broadcasting.

Observe each operand once, left to right, and produce a new array. Visit lanes
in increasing index order, retaining scalar checks and strict floating behavior.
Empty arrays evaluate their operands and perform no lane operations. Numeric
arithmetic does not admit arrays of resources, Bool or arbitrary records.

Extend the shared constant folder for integer-array arithmetic rather than
classifying array operations differently at runtime and at constant bindings.
The folder retains graph values; typing validates their scalar ranges and
division obligations. Symbolic Integer elements retain runtime checks.

Lower through existing array storage and scalar MIR operations. Emit a loop,
not one instruction stream per statically written lane, so large array types
do not cause proportional expansion of generated MIR.

## Consequences

Ordinary arrays serve as numerical vectors without losing their existing ABI,
explicit aggregate copying or ownership rules. Literal context reaches the
element type, while expressions retain their actual scalar or array shapes.
There is no promise that an ordinary array resides in a SIMD register.

Array arithmetic allocates a result value in ordinary value storage. Constant
graph construction and scalar validation cost the number of constant lanes;
runtime lowering has bounded IR size independently of an array type's length.

## Alternatives considered

**A separate mathematical vector type.** It would duplicate existing array
construction, indexing and storage before adding a distinct semantic benefit.

**General user-defined operator overloading.** Not required to define scalar
operations over a closed numeric element domain; it introduces unrelated
coherence and dispatch decisions.

**Silently broadcast every scalar into an array.** The arithmetic context can
check an element type without changing the operand's shape. Keeping those two
facts distinct prevents scalar assignment from becoming an implicit array
construction and does not introduce conversions elsewhere.

**Unroll every array operation during MIR generation.** A large fixed-size type
would produce a large instruction stream before optimizers decide whether
unrolling helps. A bounded loop preserves that choice for the backend.
