# Linea

Linea is a general-purpose systems programming language combining linear ownership,
mutable value semantics, and typed concurrency, with explicit CPU and GPU execution.
Ordinary numerical functions can be compiled ahead of time for both CPU and GPU
execution, without handwritten kernels or separate device-language semantics.

The compiler is written in Zig and produces native code through MLIR and LLVM,
with Vulkan compute for GPU execution. Linea is unreleased and changes without notice.

## Memory safety and resource ownership

What if memory bugs and resource leaks were impossible to express?

In Linea, resources are values with owners. When you release a resource, that value is consumed. You can't release it twice, and you can't keep using it afterwards:

#### Double free?

```linea
scores.release()
scores.release() // error[O-Move]: `scores` has already been moved
```

#### Use-after-free?

```linea
scores.release()
io.println("{scores.length()}")? // error[O-Move]: `scores` has already been moved
```

#### Resource leak?

```linea
fn worker() -> Result[(), io.IoError] {
    let scores: Vec[UInt64] = Vec.new()
    io.println("{scores.length()}")? // error[O-Leak]: `scores` is still owned when this path leaves
    .Ok(())
}
```

These aren't runtime checks, address sanitizer warnings, or garbage collector sweeps. The compiler rejects these programs outright before emitting native code.

Because the first call consumes `scores`, it no longer exists in that scope. And because `scores` is a linear resource, abandoning it without settlement is a compile error. You can settle it explicitly on every path, or ensure clean exit with `defer scores.release()`.

---

## Linear ownership and mutable value semantics

### Linear types: settle every resource

Numbers and `Bool` copy freely. A value of your own type moves from one owner to the next; declare its type `@copyable` and `copy(value)` duplicates it. Types that manage resources go further and declare themselves `@linear`.

A linear value **must be settled on every execution path**. Ownership can move
from one function or task to another; the old owner cannot reuse the value, and
the new owner inherits its obligation to settle it. Copyability is a separate
capability: a copy never silently removes that obligation.

This principle extends beyond memory:

- **Buffers and collections** must be released.
- **Files and sockets** must be closed.
- **Database connections** must be returned to the pool.
- **Transactions** must be explicitly committed or rolled back.

If any branch exits without settling an owned resource, the compiler refuses the program.

### Mutable value semantics: explicit mutation

Linea adopts **mutable value semantics (MVS)**:

- Variables own their data. There are no implicit shared mutable references.
- In-place mutation is explicit at the signature with `inout`, and marked with `&` at the call site.
- A consuming position transfers ownership; `sink` marks a consuming parameter.
- Read-only views may alias; mutation is checked against every live observation.

```linea
import std.io

fn add_tip(inout bill: UInt64) {
    bill += bill / 10
}

fn main() -> Result[UInt8, io.IoError] {
    var bill = UInt64(40)
    add_tip(&bill)
    io.println("Total: {bill}")?
    .Ok(0)
}
```

You get in-place mutation while the compiler prevents conflicting access to the
same storage. [Borrowing](docs/learn/06-borrowing.md) explains how views keep
their owners alive and how exclusive mutation composes with ownership.

---

## Typed concurrency

Concurrency uses ordinary functions, closures, and owned values. There is no
`async` function category or `await` syntax. For independent work, `task.map`,
`task.all`, `task.lazy_map`, and `task.join` start and join tasks for you.
Choose `.Sequential` to run on the caller or `.Threads(max)` to bound concurrent
work, without changing the function being called:

```linea
import std.io
import std.mem
import std.task

fn square(sink n: UInt64) -> UInt64 {
    n * n
}

fn main() -> Result[UInt8, io.IoError] {
    var items: mem.Vec[UInt64] = mem.Vec.new()
    for n in 1..=4 {
        &items.push(n).unwrap()
    }
    defer let squares = task.map(.Threads(2), items, square)
    for squared in squares.as_slice() {
        io.println("{*squared}")?
    }
    .Ok(0)
}
```

`map` consumes the inputs and returns owned results in input order. Jobs transfer
owned state, and values read by several tasks must satisfy `Shareable`; the
compiler prevents conflicting access across tasks as it does within one function.

For tasks that exchange messages, **typed sessions** describe the conversation.
A `Chan[Recv[UInt64, Send[UInt64, End]]]` receives a number, sends a number, then
closes; its peer follows the dual protocol. Each operation consumes the endpoint
and returns its next state. Sending the wrong type, receiving out of order, or
leaving an endpoint unsettled is a compile error. Closing the task's completed
handle joins it, so tasks cannot be silently detached. Protocol branches express
cooperative stopping, and wait sets let a task wait on several sessions or a timer.

The same task APIs run on **system threads or fibers**. The default system
execution context gives each task an operating-system thread. Explicitly open an
`io.Loop` to run fibers across a chosen number of carrier threads; socket,
session, and timer waits let other fibers run. Child tasks inherit the current
execution context. The task policy bounds concurrent jobs, while the loop's
carrier count bounds their CPU parallelism. A one-carrier loop overlaps waiting
work; it does not run two computations in parallel.

Read [Tasks and sessions](docs/learn/13-tasks-and-sessions.md), or explore
[delivery routes](examples/delivery_routes.lin) for bounded parallel work,
[the chat room](examples/chat_room.lin) for sessions and timers, and
[the guest book](examples/guest-book/main.lin) for HTTP fibers talking to a
system-thread SQLite owner.

## Numerical work on CPU and GPU

Fixed arrays serve as small mathematical vectors, with componentwise arithmetic
and swizzles such as `point.xy = point.yx`. `num.Matrix` adds fixed dimensions,
matrix products, and matrix-vector products. These values live inline and use
the same checked integer and strict floating-point arithmetic as scalars.

For larger shaped computations, `std.tensor` provides Float32 tensors backed by
CPU or GPU storage. An algorithm can be generic over storage: the same `map`,
`zip_with`, reduction, and matrix operations select CPU computation or GPU dispatch.
The functions passed to them remain ordinary Linea functions:

```linea
import std.gpu

fn adjust(value: Float32) -> Float32 {
    if value < 0.0 { -value } else { value * 0.5 }
}

fn add(left: Float32, right: Float32) -> Float32 {
    left + right
}

fn main() -> Result[UInt8, gpu.GpuError] {
    let values: [Float32; 4] = [-2.0, 4.0, 6.0, 8.0]
    defer let device = gpu.Device.open()?
    defer let input = device.upload(values.as_slice(), [UInt64(4)])?
    defer let resident = input.map(adjust)?
    defer let scalar = resident.reduce(0.0, add)?
    defer let host = gpu.download(scalar)?
    .Ok(if host.length() == 1 && host[0] == 11.0 { 0 } else { 1 })
}
```

Here `adjust` and `add` compile ahead of time into SPIR-V for Vulkan compute;
they can also be called normally on the CPU. Device execution admits a checked
numerical subset of ordinary functions, including local Float32 arrays, fixed
matrices, and direct numerical helper calls. General application code stays on
the host. CPU and GPU arithmetic follow the same rules, including operation
order and separate rounding of multiplication and addition.

Device choice, uploads, and downloads are explicit. Intermediate tensors stay
resident, their allocations obey linear ownership, and operations return completed
results or errors. A missing device or unsupported function reports an error;
there is no implicit CPU fallback. The current hardware backend is Vulkan,
including Apple GPUs through MoltenVK.

Start with [numerical values](docs/learn/16-numerical-values.md) and
[CPU/GPU tensors](docs/learn/15-gpu-tensors.md). The
[shared tensor pipeline](examples/tensor_pipeline.lin) runs one algorithm on both
storage types; [numerical GPU work](examples/numerical_gpu.lin) uses local
vectors and matrices inside an ordinary mapped function. The
[CPU/GPU benchmark](examples/benchmark_cpu_gpu/main.lin) checks matching output
bits and measures sequential CPU work, parallel work on threads or fibers,
resident GPU work, and upload-compute-download separately.
[Measuring a workload](docs/learn/17-benchmarks.md) explains the timing
boundaries and how to compare results on your hardware.

## What Linea promises

- **No undefined behaviour**: Operations have defined results or defined failure,
  diagnosed at compile time or reported at runtime as an error or trap. The compiler
  never assumes undefined behaviour to justify an optimisation.
- **Explicit memory**: No garbage collector. Containers state their allocators;
  allocating APIs offer a system form and an `_in` form that takes the caller’s allocator.
- **Static ownership enforcement**: Ownership, borrowing, and settlement are
  checked before native code is emitted. Runtime bounds and arithmetic checks
  preserve defined behaviour where a static proof is unavailable.

## Get started

The Nix development shell supplies Zig 0.16.0, MLIR, and a C toolchain:

```sh
nix develop
zig build

linea init hello
linea run hello
linea test hello

linea test examples/numerical_gpu.lin
linea bench examples/benchmark_suite
```

## Featured examples

- [notes](examples/notes/main.lin): CLI note-taking app with subcommands, tabular rendering, and atomic JSON persistence.
- [guest-book](examples/guest-book/main.lin): full-stack web application combining SQLite, C FFI, concurrent HTTP routing, cookies, and HTML templating.
- [delivery routes](examples/delivery_routes.lin): bounded task mapping, streaming results, and fibers on a shared loop.
- [CPU/GPU benchmark](examples/benchmark_cpu_gpu/main.lin): one numerical algorithm, correctness tests, and explicit measurement of compute and transfer costs.
- [All examples](examples/README.md): complete programs from introductory scripts to network services.

## Learn

- [Learn Linea](docs/learn/README.md): the guide, one chapter per topic.
- [Standard library](std/README.md): modules, collections, I/O, and allocators.
- [Language definition](docs/linea-semantics.md): every rule by its diagnostic name.

## Contribute

Read [AGENTS.md](AGENTS.md) for how changes are made and verified, and the [ADRs](docs/adr/README.md) for the technical decisions behind the language.

## Licence

[Apache License 2.0](LICENSE).
