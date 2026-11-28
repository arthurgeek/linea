# Numerical tensors on CPU and GPU

`std.tensor` provides shaped Float32 computations on CPU or GPU storage. You choose
a device, upload a shaped array, submit work and download when the CPU needs the
result. The numerical functions are ordinary Linea functions; they need no GPU
attributes or separate kernel language.

A tensor's type fixes its rank. Its dimensions are runtime values: a
`tensor.Tensor[Float32, 1, S]` is a vector backed by storage `S`, rank two
is a matrix, and rank zero is a scalar. Upload checks that the product of the
dimensions matches the number of values. A zero dimension makes the tensor empty.
Rank does not prove the dimensions: two rank-two tensors can have different
sizes. Matrix inner dimensions and elementwise shape compatibility are checked
at runtime and reported as errors.

## Upload, compute and download

This program uploads four values, maps a function, reduces the resident result
and downloads the scalar. Its `?` operators propagate errors through `main`,
which reports the error and exits unsuccessfully.
The example is checked rather than run by the guide gate because it needs a GPU.

<!-- guide: check requires an available GPU device -->
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

Upload copies immediately, so the tensor does not borrow the source array.
Download immediately returns a separate host Vec. Map and reduce keep their
results on the device. The two functions above can also be called normally on
the CPU.

Each operation returns a completed tensor or an error. Waiting suspends the
calling fiber through its existing executor. Independent device storage is linear:
`defer let` releases its allocation. CPU storage preserves its allocator's
settlement and borrowing rules. There are no implicit transfers or CPU fallbacks.
Use ordinary tasks when operations should run concurrently.

## The same operations on the CPU

CPU-backed tensors use the same rank, shape and operation rules. This program
needs no device. The matrix constructor supplies Float32 context to its numeric
literals. `uniform` passes a runtime parameter to the ordinary `scale` function;
`zip_with` combines corresponding elements and requires identical dimensions.

```linea
import std.tensor

fn scale(value: Float32, factor: Float32) -> Float32 { value * factor }
fn add(left: Float32, right: Float32) -> Float32 { left + right }

fn main() -> Result[UInt8, tensor.CpuError] {
    defer let input = tensor.matrix([[1.0, 2.0], [3.0, 4.0]])?
    defer let scaled = input.map(tensor.uniform(scale, 0.5))?
    defer let combined = input.zip_with(scaled, add)?
    let values = combined.values()
    .Ok(if values[0] == 1.5 && values[3] == 6.0 { 0 } else { 1 })
}
```

`values()` borrows CPU storage. GPU storage requires an explicit download.
`tensor.matrix_in(allocator, values)` and `tensor.from_slice_in(allocator,
values, shape)` select storage through the first argument. Pass a host
allocator to copy the data into CPU storage, an open `gpu.Device` for independent
device storage, or `arena.handle()` for storage borrowing a device arena. A host arena's tensor borrows the arena and can be discarded
with it. System CPU and device tensors own allocations that must be settled.
A device tensor can allocate further results after its original device owner
has been released.

A numerical algorithm can be generic over storage rather than fixed to a GPU.
The public `examples/tensor_pipeline.lin` example calls one `compute` function on
CPU storage, then explicitly opens a device and uploads the same inputs through
the shared constructors. It also runs twice in an explicit device arena. It
reports an unavailable capability at that call site; other GPU errors propagate.
The CPU computation is an independent demonstration, not a fallback for a failed
GPU request.

<!-- guide: excerpt examples/tensor_pipeline.lin -->
```linea
// Run one numerical pipeline on host, system-device and arena-device storage.
import std.gpu
import std.io
import std.tensor
import std.testing

use io.IoError
use io.println

@derive(Display, Release, From[tensor.CpuError], From[gpu.GpuError], From[IoError])
enum PipelineError {
    Cpu(tensor.CpuError),
    Gpu(gpu.GpuError),
    Output(IoError),
}

fn scale(value: Float32, factor: Float32) -> Float32 {
    value * factor
}

fn add(left: Float32, right: Float32) -> Float32 {
    left + right
}

fn compute[S: tensor.Storage[Float32]](left: tensor.Matrix[Float32, S], right: tensor.Matrix[Float32, S]) -> Result[tensor.Scalar[Float32, S], S.Error] where carries(.Ok: left, right) {
    defer let product = left.matmul(right)?
    defer let scaled = product.map(tensor.uniform(scale, 0.5))?
    defer let combined = scaled.zip_with(product, add)?
    combined.reduce(0.0, add)
}

fn main() -> Result[UInt8, PipelineError] {
    defer let host_left = tensor.matrix([[1.0, 2.0, 3.0], [4.0, 5.0, 6.0]])?
    defer let host_right = tensor.matrix([[7.0, 8.0], [9.0, 10.0], [11.0, 12.0]])?
    defer let cpu = compute(host_left, host_right)?
    let reference = cpu.values()[0]
    println("CPU: {reference}")?

    defer let device = match gpu.Device.open() {
        Ok(device) => device,
        Err(Unavailable) => {
            println("GPU: unavailable")?
            return .Ok(0)
        },
        Err(error) => return .Err(.Gpu(error)),
    }
    defer let left = tensor.from_slice_in(device, host_left.values(), host_left.dimensions())?
    defer let right = tensor.from_slice_in(device, host_right.values(), host_right.dimensions())?
    defer let result = compute(left, right)?
    defer let values = gpu.download(result)?
    println("GPU: {values[0]}")?
    if values[0].to_bits() != reference.to_bits() {
        return .Ok(1)
    }

    defer var arena = gpu.Arena.open(device, byte_limit: 1048576)?
    for epoch in UInt64(0)..2 {
        let arena_left = tensor.matrix_in(arena.handle(), [[1.0, 2.0, 3.0], [4.0, 5.0, 6.0]])?
        let arena_right = tensor.matrix_in(arena.handle(), [[7.0, 8.0], [9.0, 10.0], [11.0, 12.0]])?
        let answer = compute(arena_left, arena_right)?
        defer let host = gpu.download(answer)?
        println("Arena epoch {epoch + 1}: {host[0]}")?
        if host[0].to_bits() != reference.to_bits() {
            return .Ok(2)
        }
        &arena.reset()?
    }
    .Ok(0)
}
```

The CPU, independent GPU storage and both arena epochs produce `622.5` on a
supported device. Without GPU capability, the
program still demonstrates the CPU pipeline and prints `GPU: unavailable`.
Only construction and observation choose placement. `compute` performs no
hidden transfer, and the final comparison checks exact Float32 bits.

## Bounded device arenas

`gpu.Arena.open(device, byte_limit)` owns blocks independently of the public
device owner. Its byte limit counts actual committed device memory, including
driver rounding and alignment, so usable tensor bytes can be smaller. Opening
commits no memory; capacity grows lazily and an allocation that cannot fit returns
`GpuError.Allocation`. An empty tensor still reserves four descriptor bytes, so
a zero-capacity arena cannot hold even an empty tensor. If an upload fails after
reservation, that range may stay occupied until reset.

The repeated-batch part of the pipeline allocates temporaries through the handle
and resets after each download:

<!-- guide: excerpt examples/tensor_pipeline.lin -->
```linea
defer var arena = gpu.Arena.open(device, byte_limit: 1048576)?
for epoch in UInt64(0)..2 {
    let arena_left = tensor.matrix_in(arena.handle(), [[1.0, 2.0, 3.0], [4.0, 5.0, 6.0]])?
    let arena_right = tensor.matrix_in(arena.handle(), [[7.0, 8.0], [9.0, 10.0], [11.0, 12.0]])?
    let answer = compute(arena_left, arena_right)?
    defer let host = gpu.download(answer)?
    println("Arena epoch {epoch + 1}: {host[0]}")?
    if host[0].to_bits() != reference.to_bits() {
        return .Ok(2)
    }
    &arena.reset()?
}
```

`arena.handle()` borrows the arena. Every tensor built with it, and the results
of its operations, preserve that borrow. The arena owns the reservations, so
these tensors are affine: the example uses `let` for them. Copying a handle keeps
the same borrow and does not create another arena. Inputs from different arenas
of one device can be combined; the result allocates from the left input's arena.

`&arena.reset()?` requires exclusive access. Resetting, moving or releasing an
arena while a tensor or handle is used afterwards is rejected by the ownership
checker. After the final observation, reset waits for native use by parking the
calling fiber, then invalidates the old reservations and rewinds its retained
blocks. Reset retains the arena's high-water physical allocation for the next
epoch; releasing the arena frees it. Downloads are independent host vectors, so
their lifetime does not prevent reset. Handles observing the unshareable arena
cannot cross into another task; an unobserved arena owner can move into a task.

Use `defer let value = operation()?` for a linear result that stays in the scope.
Generic code also uses it so one algorithm accepts both storage families.
The `defer` settles it on success and early returns; `?` propagates allocation,
shape and execution failures. A `main` returning `Result[UInt8, E]` reports its
error through the ordinary `Display` implementation. Match an error only when
the caller can recover, as the capability branch does here. These operations
lend their inputs, so failure leaves those owners with the caller and `?` is
sufficient here. APIs that hand an owned input back use the existing
[settling pattern](03-errors.md#failures-that-hand-a-value-back); tensors
introduce no separate error-handling style.

Ordinary functions pass directly to map, zip and reduction: no wrapper struct or
`impl MapBody` is needed. For runtime scalar arguments on both CPU and GPU, use
`tensor.uniform(scale, factor)`. For CPU-only code, an ordinary captured closure
such as `[factor] |value: Float32| value * factor` is also a map body. Captures
and uniform parameters are not interchangeable on the current GPU profile.
Custom `MapBody` and `BinaryBody` implementations remain CPU extension points;
the device adapter admits ordinary numerical functions and the uniform adapter.

## Which functions run on the device?

Map accepts `fn(value: Float32) -> Float32`, and reduce accepts
`fn(left: Float32, right: Float32) -> Float32`. A body may use Float32 and Bool
locals, arithmetic and comparisons, mutation, `if`, `while`, early returns and
statically named numerical helpers. Recursion, heap allocation, host I/O,
`inout`, indirect calls within the body and captured closures are outside the
current profile.

You can choose an ordinary named root function at runtime. The compiler includes
the admitted device implementations ahead of time; an unsupported choice returns
`GpuError.UnsupportedFunction`. It does not fall back to CPU execution.

Float32 operations preserve the CPU rules: each arithmetic operation rounds to
nearest with ties to even, subnormals survive and computed NaNs are canonical.
Comparisons handle signed zero and NaNs the same way too. Reduction uses a
specified parallel tree, so its result need not equal a sequential fold. The
initial value is applied once, last; empty input returns its bits unchanged.

## Keep a matrix product on the device

For rank-two tensors, `left.matmul(right)` checks that the left column count
equals the right row count and returns the completed output matrix or an error.
Storage is row-major. Each output starts at positive zero and visits the shared
dimension in order, rounding each product and sum separately. A zero shared
dimension produces positive zeros; zero output rows or columns produce an empty
matrix.

The [complete matrix example](../../examples/gpu_matrix.lin) multiplies two
matrices, maps over the resident product, and downloads once. Its CPU test
checks the ordinary `half` function. A separate GPU test uploads both matrices,
executes the product and map, downloads and checks all four results:

<!-- guide: excerpt examples/gpu_matrix.lin -->
```linea
// Multiply row-major matrices while their buffers stay on the GPU.
import std.gpu
import std.io
import std.tensor
import std.testing

use io.IoError
use io.println

@derive(Display, Release, From[gpu.GpuError], From[IoError])
enum MatrixError {
    Gpu(gpu.GpuError),
    Output(IoError),
}

fn half(value: Float32) -> Float32 { value * 0.5 }

test "halving preserves small Float32 readings" {
    let smallest = Float32.from_bits(2)
    testing.assert_eq(half(smallest).to_bits(), 1, "halving should preserve subnormal values")?
}

fn main() -> Result[UInt8, MatrixError] {
    defer let device = gpu.Device.open()?
    defer let left = tensor.matrix_in(device, [[1.0, 2.0], [3.0, 4.0]])?
    defer let right = tensor.matrix_in(device, [[2.0, 0.0], [0.0, 3.0]])?
    defer let product = left.matmul(right)?
    defer let result = product.map(half)?
    defer let host = gpu.download(result)?
    if host.length() != 4 { return .Ok(1) }
    println("[{host[0]}, {host[1]}]")?
    println("[{host[2]}, {host[3]}]")?
    .Ok(0)
}
```

Constructors infer rank from the shape or nested array dimensions. Both input
owners remain
available after `matmul`; `product` owns a separate allocation, and `result`
owns the mapped one. Only `download` moves the final values back to host memory.

## Compose GPU work with tasks and handle errors

GPU operations inherit an existing task's execution context. Here a numerical
task and an independent CPU task share a loop with one carrier. The numerical
task calls `compute`; its map needs no explicit `on` because it inherits that
loop. Waiting for the result lets other tasks progress.

`compute` uses `?` to propagate device and numerical errors. The ordinary outer
task sends that Result to `main`, which reports it:

<!-- guide: excerpt runtime/tests/gpu_runtime/numerical_tasks.lin -->
```linea
import std.gpu
import std.io
import std.session
import std.task

use session.Chan
use session.End
use session.Send

fn half(value: Float32) -> Float32 {
    value * 0.5
}

fn compute() -> Result[Float32, gpu.GpuError] {
    let values = [Float32(4.0), 8.0]
    defer let device = gpu.Device.open()?
    defer let input = device.upload(values.as_slice(), [UInt64(2)])?
    defer let output = input.map(half)?
    defer let host = gpu.download(output)?
    .Ok(host[0])
}

fn main() -> Result[UInt8, io.IoError] {
    let execution = io.Loop.open(carriers: 1)?
    let numerical = sink [] |sink me: Chan[Send[Result[Float32, gpu.GpuError], End]]| {
        me.send(compute()).close()
    }
    let independent = sink [] |sink me: Chan[Send[UInt64, End]]| {
        me.send(6 * 7).close()
    }
    let pending = task.start(numerical, on: execution).unwrap()
    let cpu = task.start(independent, on: execution).unwrap()
    let (answer, done) = pending.recv()
    done.close()
    let (cpu_value, cpu_done) = cpu.recv()
    cpu_done.close()
    io.println("CPU result: {cpu_value}")?
    match answer {
        Ok(value) => {
            io.println("GPU result: {value}")?
            .Ok(0)
        },
        Err(reason) => {
            io.println("GPU failed: {reason}")?
            .Ok(1)
        },
    }
}
```

Task startup still uses `unwrap()` here; the preceding [tasks chapter](13-tasks-and-sessions.md)
shows how to handle its preparation failure. Device allocation, upload,
submission, completion and download errors all travel through the GPU Result.

## Errors and verification

`GpuError.Shape` reports inconsistent dimensions or a host-side size overflow.
`Unavailable` reports an unavailable GPU capability, `Allocation` reports
allocation failure, and `Runtime(code)` preserves other native failures.
`UnsupportedFunction` reports a missing device implementation.

Compute runs in the calling task. Pass `on: execution` to the ordinary task
startup operation to select another executor. Waiting on a fiber parks it so
other tasks on its carrier can progress; it does not create a private I/O loop.

The implemented hardware path is Vulkan, verified locally on an Apple GPU
through MoltenVK. CUDA and NVIDIA execution have not been verified. To run the
hardware checks, use `nix develop --command zig build test-gpu`. The
`test-gpu-compile` builds the same Linea programs and embeds their device images
without executing them. The `test-gpu-shaders` and `test-gpu-runtime` targets
also need no device;
`test-gpu-language`, `test-gpu-float32` and `test-gpu-numerical` execute on
hardware. The [language definition](../linea-semantics.md#device-tensors) gives
the exact reduction order, and [ADR 0308](../adr/0308-device-tensors-run-ordinary-numerical-functions.md)
records the device boundary. [ADR 0309](../adr/0309-tensors-separate-storage-from-numerical-operations.md)
records shared storage and completed-value operations.

## Test both available and unavailable devices

Run `linea test examples/gpu_matrix.lin` or `linea test std --filter "gpu."` for real-device
tests. They open a device and execute the operations they assert. Only
`GpuError.Unavailable` returns `.Err(testing.skip("GPU device unavailable"))`.
Allocation and runtime errors fail; a CPU scalar test does not establish GPU
execution. A skipped GPU test appears as `SKIP` with its original reason and
increments the skipped count, never the passed count.

For qualification, run `linea test --deny-skips std --filter "gpu."` and
`linea test --deny-skips examples/gpu_matrix.lin`. The `test-gpu-language`
build target also runs strict tests for the GPU library and examples, including
the complete host/device tensor pipeline and two arena reset epochs with distinct
expected results. It requires the intended test names to report `ok`, so an empty
selection cannot qualify. When running tests directly,
check that the expected tests appear: `--deny-skips` rejects skipped tests but
does not reject an empty selection. A portable example may succeed after
reporting that its device is unavailable; that is not hardware qualification.
These checks compile device images, upload, submit, wait and download; they cost
substantially more than scalar CPU tests. The compile-only target establishes
compilation, not execution.

Application tests can force the unavailable path without changing device
discovery globally. [The readings example](../../examples/gpu_readings.lin)
passes an opener and a computation into `compute_with_device`. Its deterministic
test supplies an opener answering `.Err(.Unavailable)`, then checks both the
original error and that the computation callback was never invoked. No device
is fabricated and the test needs no GPU. Its real GPU test independently checks
the calibrated total after upload, map, reduction and download.

## Confirm GPU execution

A readable IR dump proves what was compiled, not what hardware executed it.
The runtime requires an integrated or discrete GPU; on macOS it selects Apple
hardware. It never substitutes a CPU computation for a missing device or image.

MoltenVK can log the actual dispatch, queue submission and fence wait calls:

```sh
MVK_CONFIG_LOG_LEVEL=3 MVK_CONFIG_TRACE_VULKAN_CALLS=1 \
  linea run examples/gpu_matrix.lin
```

The device log identifies the GPU. The matrix example submits two compute
operations: matrix multiplication and map. For a capture that can be opened in
Xcode, set a fresh output path (MoltenVK does not overwrite an existing trace):

```sh
METAL_CAPTURE_ENABLED=1 MVK_CONFIG_AUTO_GPU_CAPTURE_SCOPE=1 \
MVK_CONFIG_AUTO_GPU_CAPTURE_OUTPUT_FILE="$PWD/gpu_matrix.gputrace" \
  linea run examples/gpu_matrix.lin
```

These settings are documented in the [MoltenVK runtime guide](https://github.com/KhronosGroup/MoltenVK/blob/main/Docs/MoltenVK_Runtime_UserGuide.md#debugging-your-moltenvk-application-using-metal-frame-capture).
A CPU-only compiler build reports unavailable capability instead; see the
[CPU-only build instructions](../cpu-only-build.md).
