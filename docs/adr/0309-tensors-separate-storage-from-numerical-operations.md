# 309. Tensors separate storage from numerical operations

Status: Accepted — 2026-11-26. Supersedes the library placement and result-session
API of [0308](0308-device-tensors-run-ordinary-numerical-functions.md). Preserves
its admission, numerical, explicit-transfer and native-lifetime contracts.
Extended by [0310](0310-device-admission-is-sealed-from-public-callables.md).

## Context

An algorithm accepting `gpu.Tensor` fixes GPU storage in its signature. A
generic numerical interface needs a real second implementation to establish
which operations belong to the tensor and which require a device. Exposing
submission/completion sessions for every matrix operation also duplicates
orchestration that callers already express through ordinary tasks.

## Decision

**`std.tensor` owns `Tensor[T, rank, S: Storage[T]]`.** Its first two storage
implementations are sequential `tensor.Cpu[A]` over an allocator-backed Vec and
linear `gpu.Storage` over a device buffer. Shape validation, map, identical-shape
zip, fixed-tree reduction and rank-two matrix multiplication share one numerical
interface. CPU callables retain ordinary host facilities and captured closures.
Tensor linearity and borrowed dependencies follow its storage; CPU tensors do
not acquire GPU storage's unconditional linearity.

**Operations return completed values or errors.** The GPU adapter waits directly
through the existing runtime park, suspending a fiber without occupying its
carrier. Callers use existing tasks and execution contexts for concurrency.
There are no asynchronous name pairs, automatic delivery tasks, public GPU job
types or pending tensors. Placement is explicit and remains distinct from
host execution policy. No implicit transfer or CPU fallback is introduced.

**Numerical functions remain ordinary functions.** Callable traits dispatch
sequential CPU bodies and select admitted named device functions. A uniform
adapter carries a binary function and a runtime Float32 parameter through the
same map operation. Binary device images expose reduction, uniform-map and zip
entry points for the same admitted body; they retain one compiler-owned image
identity per binary function. Zip requires identical dimensions and introduces
no broadcasting rule.

**Device selection crosses an opaque token boundary.** Public callable traits
return `mem.GpuKernel`, not a numeric native address. Its public constructor
only creates an absent image. The certified private selectors wrap actual
compiler descriptors; callers cannot forge a descriptor by writing an integer.
Native submission entry points consume this token only inside the trusted
standard-library adapter.

**GPU support is a build capability.** The default shell and build include it.
`-Dgpu=false` selects an unavailable implementation of the same native ABI,
requires no Vulkan headers or loader, and skips device emission and SPIR-V
tools. The public GPU API reports `GpuError.Unavailable`; CPU numerical and
concurrent programs remain available. CI executes this mode with GPU tools
poisoned to establish that it does not depend on them.

## Consequences

- One generic numerical algorithm can execute against CPU or GPU storage.
  Choosing storage still determines accessibility and available device bodies.
- Waiting between dependent GPU operations prevents device-side pipelining.
  Pending dependencies and deferred error settlement require a future design.
- A CPU allocator's ownership and borrowed dependencies remain visible through
  the numerical abstraction. There is no erased allocation backend.
- Binary images contain three small entry wrappers; arithmetic helpers are
  shared and unreachable helpers are removed before image serialization.
- GPU-specific errors remain distinct from CPU allocation errors through the
  storage trait's associated error type.

## Alternatives considered

**Rename a GPU-only type.** This would leave the storage interface shaped by a
single backend. Two executable implementations and one shared algorithm test
the boundary instead.

**Expose completion sessions or duplicate asynchronous methods.** Both make
every numerical operation carry a second concurrency API. Existing tasks
already give callers explicit concurrency and ownership settlement.

**Pending tensors.** They permit device dependency chaining, but asynchronous
errors and unobserved computations need a new settlement contract. Completed
values retain the existing contract for this slice.

**Raw kernel integers in an extensible callable trait.** User implementations
could forge a pointer and reach unchecked native memory. An opaque compiler
token keeps representation access inside the existing trusted boundary.

**Implicit transfers or CPU fallback.** They hide execution placement and can
turn an unavailable GPU implementation into an unexpectedly expensive CPU path.
This decision preserves explicit errors instead.
