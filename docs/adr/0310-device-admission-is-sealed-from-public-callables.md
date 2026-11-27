# 310. Device admission is sealed from public callables

Status: Accepted — 2026-11-26. Extends
[0309](0309-tensors-separate-storage-from-numerical-operations.md)'s numerical
callable and storage boundaries without changing its completed-value API.

## Context

An opaque kernel token prevents forging an address, but a legitimate token can
still describe the wrong computation. A public map adapter was able to multiply
by two on the CPU and return a valid halving kernel for the GPU. An executable
counterexample produced 8 on the CPU and 2 on the GPU from the same input, 4.
Valid representation
and equivalent computation are separate obligations.

A private admission trait alone is insufficient: its methods can be inherited
through a public supertrait. At the storage boundary, a user implementation can
also return a different length from the one its operation's shape requires.
The original constructor check did not cover those subsequent adoption paths.

## Decision

**Public numerical callable traits define only computation.** `MapBody` and
`BinaryBody` expose their element type and `call`. Internal admission supertraits
have universal absent-image defaults and trusted implementations for exact
function values and the library's uniform adapter. A user-defined callable
remains useful on CPU storage and receives UnsupportedFunction on GPU storage.

**Admission requires an unconstructible external witness.** Internal methods
take an opaque `_Admission` value with no public constructor. Only the internal
library helpers create it. External code cannot implement the hidden admission
traits, invoke the internal helpers, manufacture the witness, or replace the
foreign implementations for builtin functions or Uniform. The trusted adapters
derive both CPU computation and device selection from the same function value
and runtime uniform. The opaque `mem.GpuKernel` still protects native descriptor
representation inside this boundary.

**Every tensor operation validates storage adoption.** Storage implements Release
without becoming unconditionally linear. Map, zip, reduction and matrix
multiplication pass returned storage through the same checked constructor as
`from_storage`. A mismatched count releases that returned storage exactly once
and returns the storage's shape error. The inputs remain owned by their callers.

## Consequences

- CPU extension implementations need no GPU kernel, uniform or entry-point
  methods. Admitted ordinary functions preserve their meaning across backends.
- The internal witness is a library capability, not a source-language feature,
  runtime handle or new execution primitive.
- Storage's Release supertrait removes a redundant generic constraint from
  numerical algorithms while preserving allocator-dependent affine/linear rules.
- Extensible storage still has ordinary behavioral contracts, including truthful
  length and element access. The library independently checks the dimension
  invariant at each adoption rather than trusting operation output lengths.

## Alternatives considered

**Opaque kernel tokens alone.** They establish representation validity, not that
the token matches the public callable's computation. The counterexample used a
real token, not a forged address.

**A hidden trait without a witness.** An external generic function could call an
inherited method through its public callable bound. The witness prevents such a
call from acquiring admission capability even when the method is inherited.

**GPU hooks on public callable traits.** They expose backend details to CPU-only
extensions and let those extensions select unrelated kernels.

**Trust every storage result.** It permits a tensor whose advertised dimensions
and resident element count disagree. The canonical constructor already answers
this question and can settle a rejected result safely.

**Seal all storage implementations.** It removes legitimate extension points.
Validating returned storage preserves extensibility without adding another
representation or ownership model.
