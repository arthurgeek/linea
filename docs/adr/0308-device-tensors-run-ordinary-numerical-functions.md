# 308. Device tensors run ordinary numerical functions

Status: Superseded in library placement and result API by
[0309](0309-tensors-separate-storage-from-numerical-operations.md). Accepted —
2026-11-26.

## Context

Preserves the Float32 contracts of
[0226](0226-float32-is-a-second-binary-floating-point-width.md) and
[0249](0249-a-float-has-a-total-order-and-a-computed-nan-is-canonical.md), and
uses the certified library boundary of
[0255](0255-an-erased-value-is-reached-through-an-address-that-names-its-type.md).

A numerical function should have one meaning whether it runs on the CPU or a
GPU. Native device arithmetic is insufficient evidence: the tested Apple path
flushes Float32 subnormals, while Linea preserves them. The exact eight
observed arithmetic mismatches and tool/device versions are retained in the
[qualification evidence](../gpu-qualification.md). A tensor also owns a
device allocation that can remain in use after its caller submits work; a
CPU function pointer alone neither identifies a device implementation nor
keeps those resources alive.

The existing machinery already supplies ordinary numerical functions, verified
MIR, linear owners, typed sessions and inherited execution contexts. Device
execution needs a lowering and an ownership boundary, rather than another
source language or a second task scheduler.

## Decision

**`std.gpu` exposes an explicit linear `Device` and linear resident
`Tensor[T, rank]`.** The rank is a length parameter; dimensions are runtime
`UInt64` values. Public construction and numerical operations currently support
Float32. Upload and download copy immediately and explicitly across the host
boundary. A map, reduction or matrix product allocates a separate result on the
same device; operations do not implicitly download it.

**Numerical bodies are ordinary Linea functions.** Map takes
`fn(value: Float32) -> Float32`; reduction takes
`fn(left: Float32, right: Float32) -> Float32`. Their device call graph admits
Float32 and Bool values, arithmetic and comparisons, local mutation,
conditionals, loops, early returns and statically named calls. Recursion, heap
allocation, host I/O, `inout`, indirect calls inside the body and captured
closures are outside this profile. No GPU attribute or indexing DSL changes
the source function.

Root selection may be dynamic: an immutable table maps admitted ordinary CPU
function addresses to ahead-of-time device images. A root absent from that
table produces `GpuError.UnsupportedFunction`; it is not a new source diagnostic
and does not silently execute on the CPU. The three private `std.mem` selectors
for map, reduction and matrix multiplication retain compiler-certified
signatures under the existing [T-Extern] rule. Their identity is recorded once
and carried into MIR.

**Device Float32 arithmetic preserves Linea's existing meaning.** Every
operation rounds to binary32, nearest with ties to even, with subnormal values
preserved and computed NaNs canonical. Transfers and copies preserve bits;
negation changes only the sign bit. The current SPIR-V helpers implement this
with integer32 and Boolean operations, without native floating-point arithmetic
or integer64 requirements. Comparisons preserve signed-zero equality and the
unordered behavior of NaNs.

**Reduction has a specified tree, without an associativity requirement.** One
64-lane workgroup folds lane `i` over input positions `i`, `i + 64`, and so on,
starting at its first existing value. Stages of width 32, 16, 8, 4, 2 and 1
combine each left lane with its right neighbor. Absent lanes contribute no
value and assume no identity. The final call is `body(initial, tree_result)`;
empty input returns the initial bits without calling the body for a result.
Reduction produces a rank-zero tensor. Rank-two row-major matrix multiplication
visits the shared dimension in ascending order, starting each output at positive
zero and rounding multiplication and addition separately. A zero shared dimension
therefore produces positive zeros.

**Successful compute returns a linear result session on the inherited
executor.** The outer Result reports selection, submission or task preparation
failure. The session receives the completion Result and then reaches End, which
its caller closes. The runtime retains every input, output and device needed by
a pending submission. A native completion thread waits for its fence; callers
wait through the ordinary runtime park, releasing a fiber's carrier. Failure to
prepare the delivery task settles its already-owned job. No private I/O loop or
new root executor policy is introduced.

**The backend consumes verified MIR and emits text; the driver runs tools.**
The existing MLIR control-flow lifting and SPIR-V conversions structure device
functions. The driver serializes and validates images for Vulkan 1.1 before the
CPU emitter embeds immutable descriptors. No new semantic representation or
mutable compiler cache is introduced. The current device runtime uses Vulkan;
the recorded hardware validation is the Apple M1 Pro through MoltenVK. This
establishes neither CUDA nor NVIDIA hardware support.

## Consequences

- Device allocation, transfer, shape, selection and completion failures remain
  explicit values. Device, tensor and session obligations remain visible to the
  ownership checker.
- A function can remain useful on the CPU even when its device profile is
  unavailable. Runtime root selection does not imply device-side indirect calls.
- The defined reduction order can differ from a sequential CPU fold. Its result
  is reproducible without claiming that Float32 addition is associative.
- Strict integer arithmetic costs more instructions than native shader
  arithmetic. Ahead-of-time images and per-root tool invocations also cost
  executable space and build time.
- Shader validation and fault/lifetime tests run without a GPU; numerical and
  complete Linea execution tests require actual hardware. Those are separate
  claims, and neither substitutes for the other.

## Alternatives considered

**A GPU DSL or source annotation.** It would duplicate the language's numerical
rules and require users to maintain another function body. Verified MIR already
contains the computation and control flow needed by the admitted profile.

**Native floating point with relaxed results.** The observed subnormal flushing
would change program values and their observable bits, contradicting 0226 and
0249. Canonicalizing NaNs alone does not repair underflow or rounding.

**A CPU fallback for unsupported functions.** It would conceal the absence of a
device implementation and make execution placement implicit. The library instead
returns UnsupportedFunction before allocating a result for that computation.

**A sequential fold called a parallel reduction.** It would preserve a different
order while discarding the requested device parallelism. A specified tree is
both parallel and meaningful for non-associative functions.

**An identity value in every lane.** An arbitrary binary function has no promised
identity. Applying the caller's initial value repeatedly would change its result.
Absent-lane tracking and one final application require no such assumption.

**Waiting for fences on carriers or disposing pending resources.** The first
prevents unrelated tasks from progressing; the second invalidates submitted
commands. Retained references and completion workers preserve both progress and
resource lifetime.
