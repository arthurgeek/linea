# Numerical values

Use a fixed array for a small mathematical vector. Its element type and length
are part of the type. Arithmetic follows the scalar rules at each position;
integer overflow remains checked, and floating operations retain their normal
rounding. An ordinary array does not promise a SIMD register.

```linea
import std.io

fn advance(position: [Float32; 3], velocity: [Float32; 3], time: Float32) -> [Float32; 3] {
    position + velocity * time
}

fn main() -> Result[UInt8, io.IoError] {
    var point = advance([2.0, 3.0, 4.0], [1.0, 2.0, 3.0], 2.0)
    point.xy = point.yx
    io.println("[{point.x}, {point.y}, {point.z}]")?
    .Ok(0)
}
```

```text
[7.0, 4.0, 10.0]
```

The parameter types supply Float32 context to the array arguments. An explicitly
written Float32 element also supplies context to the rest of that array literal.
Both operands evaluate once. Array operations observe their inputs and produce
an independent result, so the caller can continue using the original values.
Components are read after both operands finish evaluating. If a later operand
mutates an input, bind `copy(input)` beforehand to keep its earlier contents.

Component names `x`, `y`, `z`, `w` select positions zero through three. Color
names `r`, `g`, `b`, `a` select the same positions; choose one family within a
selection. Reading multiple components gathers a new array. Repetition is useful
when reading: `point.xx` makes two copies of the first component.

The assignment `point.xy = point.yx` swaps two components. The right-hand side
is read completely before any destination component changes. Assignment must
name distinct destinations; `point.xx = ...` is refused. A gathered array is
not a contiguous view of its source: bind it before borrowing or mutably lending
it. A scalar selection such as `point.x` remains an ordinary scalar place.

Arrays preserve their existing allocation and ownership behavior. These numeric
values require no explicit heap allocation. Resident tensors, their explicit
transfers, and device selection are covered in [GPU tensors](15-gpu-tensors.md).

The [knight routes example](../../examples/knight_moves.lin) stores each move as
a two-component signed array. Adding it to the current `[row, column]` produces
the next position; `.x` and `.y` select its coordinates before the board's bounds
are checked. Keeping both offsets together avoids parallel tables whose indexes
must stay aligned.

## Fixed matrices

`num.matrix` constructs a fixed-size matrix from nested rows. The array types
settle the element type and both dimensions. Index with a row and column;
assignment checks both bounds and follows ordinary binding mutability.

```linea
import std.io
import std.num

fn main() -> Result[UInt8, io.IoError] {
    var grid = num.matrix([[1.0, 2.0], [3.0, 4.0]])
    grid[0, 1] = 9.0
    io.println("{grid[0, 0]}, {grid[0, 1]}")?
    .Ok(0)
}
```

```text
1.0, 9.0
```

Its type is `num.Matrix[Float64, 2, 2]`: without another floating-point context,
these literals take Float64. An expected `num.Matrix[Float32, 2, 2]` supplies
Float32 context to the same constructor. Numerical matrices store their elements
inline and require no allocator. The implementation uses contiguous rows;
column-major storage is not inherently faster for every vector operation. The
[layout measurements](../matrix-layout-measurements.md) explain the CPU/GPU
tradeoffs and preserve ordinary nested-array layout. Their copyability follows their elements;
`copy(grid)` makes an independent value.

The dimensions are static and the row/column expressions are checked at access.
Literal integer components take the compatible key type from `Index`; a component
whose type is already known keeps that type. With several compatible integer
keys, write explicit component types. Nested arrays retain their usual one-index
per level access; a matrix uses the tuple-key Index protocol.

## Products and scaling

Matrix multiplication contracts the left columns with the right rows. For
`Matrix[T, r, k] * Matrix[T, k, c]` the result is `Matrix[T, r, c]`. A matrix
can also multiply a column vector on its right or a row vector on its left.
These operations observe both inputs and create independent results.

```linea
import std.io
import std.num

fn main() -> Result[UInt8, io.IoError] {
    let transform = num.matrix([[1.0, 0.0, 7.0], [0.0, 1.0, 4.0]])
    let position = transform * [1.0, 2.0, 1.0]
    io.println("{position.x}, {position.y}")?
    let brightness = [2.0, 3.0] * 0.5
    io.println("{brightness.x}, {brightness.y}")?
    io.println("dot: {num.dot(position, brightness)}")?
    .Ok(0)
}
```

```text
8.0, 6.0
1.0, 1.5
dot: 17.0
```

An array product is componentwise. Use `num.dot(a, b)` for a dot product;
use `num.hadamard(a, b)` for componentwise matrix multiplication. Matrices
support addition and subtraction with identical matrix types, negation, and
scalar multiplication on either side. They do not support scalar addition or
division. Arrays support scalar addition, subtraction, multiplication and
division on either side.

Each built-in matrix product starts its sum at positive zero and visits the
inner dimension in increasing order. Multiplication and addition round separately,
including for Float32; contraction into a fused operation is forbidden. An empty
inner dimension produces zero in every result cell. Integer intermediates retain
the scalar overflow checks. `num.dot` uses the same order through the existing
`Additive` and `Multiplicative` contracts.

## Local values inside a GPU function

Fixed arrays and matrices are small values inside a function; a resident tensor
owns a device allocation. Mapping an ordinary Float32 function over a tensor can
use local array arithmetic, swizzles and fixed matrix products. The same function
remains callable on the CPU, with the same scalar semantics.

This example keeps the input and output tensors on the explicitly opened device.
`project` accepts and returns a fixed array; its matrix is local to each function
invocation. The CPU unit test calls `calibrate` normally. After download, `main`
compares every result's bits with the CPU call before printing it.

<!-- guide: excerpt examples/numerical_gpu.lin -->
```linea
// Reuse ordinary fixed-value arithmetic inside a resident tensor map.
import std.gpu
import std.io
import std.num
import std.testing

@derive(Display, Release, From[gpu.GpuError], From[io.IoError])
enum ExampleError {
    Gpu(gpu.GpuError),
    Output(io.IoError),
}

fn project(point: [Float32; 2]) -> [Float32; 2] {
    let transform: num.Matrix[Float32, 2, 2] = num.matrix([[2.0, 1.0], [-1.0, 3.0]])
    transform * point
}

fn calibrate(value: Float32) -> Float32 {
    let projected = project([value, 1.0])
    projected.x + projected.y
}

test "calibration uses the same ordinary CPU function" {
    testing.assert_eq(calibrate(-2.0), 2.0, "negative input")?
    testing.assert_eq(calibrate(2.0), 6.0, "positive input")?
}

fn main() -> Result[UInt8, ExampleError] {
    let values: [Float32; 3] = [-2.0, 0.0, 2.0]
    defer let device = gpu.Device.open()?
    defer let input = device.upload(values.as_slice(), [UInt64(3)])?
    defer let result = input.map(calibrate)?
    defer let host = gpu.download(result)?
    for index in UInt64(0)..3 {
        if host[index].to_bits() != calibrate(values[index]).to_bits() {
            return .Ok(1)
        }
    }
    io.println("{host[0]}, {host[1]}, {host[2]}")?
    .Ok(0)
}
```

On a supported device, run `linea run examples/numerical_gpu.lin` to print
`2.0, 4.0, 6.0`. A missing GPU is an error; this program never falls back to CPU
execution. The ordinary CPU test runs with `linea test examples/numerical_gpu.lin`.

Device admission is a checked subset of ordinary functions. Local Float32 arrays
and fixed matrices, direct numeric helper calls, and compiler-generated bounded
arithmetic loops are supported. Arbitrary UInt64 indexes, aggregate `inout`
parameters and ordinary range-iterator state remain outside this subset. In
particular, the library implementations of `num.dot` and `num.hadamard` use
ordinary iterators and currently return `UnsupportedFunction` when selected for
device execution. They remain ordinary CPU operations; an unsupported function
never acquires different arithmetic or an implicit CPU fallback.
