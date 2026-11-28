# Measuring a workload

A benchmark runs the same operation many times so a clock can resolve the
batch. Start with a function that has a known answer. Check the answer outside
the timed region, then use a runtime input and observe the result inside it.
`bench.black_box(value)` returns the very same value, including its bits and
ownership. It asks the compiler to materialize the value. Pass an input through
it when constant folding would change the work you want to measure.

## Named benchmark cases

Run `linea bench examples/benchmark_suite` to measure both cases below. Use
`linea bench --filter table examples/benchmark_suite` to run only the table
lookup. Each case runs in its own process. The driver builds the benchmark
with the same default optimization level as `linea build`, currently `-O 2`.
Pass the same explicit `-O` level to both commands when comparing configurations.
`-O 0` disables optimization; `-O 3` requests level 3 for that benchmark run.

<!-- guide: excerpt examples/benchmark_suite/main.lin -->
```linea
bench "square an integer" {
    bench.iter(|i: UInt64| i * i)
}
```

<!-- guide: excerpt examples/benchmark_suite/main.lin -->
```linea
bench "read the squares table" {
    let table: [UInt64; 8] = [0, 1, 4, 9, 16, 25, 36, 49]
    bench.iter([table] |i: UInt64| table[i % 8])
}
```

The table is set up once per case. The closure observes it during each
iteration. `bench.iter` observes the returned scalar automatically. A
callback that obtains an owned resource can inspect and release it and return
`()`. For fallible callbacks, `bench.try_iter` preserves the workload error
in `SampleError.Work`, or reports a refused sample allocation in
`SampleError.Allocation`. An explicit benchmark result type can carry those
errors to the runner.

The runner starts with one iteration and probes for a batch lasting at least
one millisecond, up to 1,048,576 iterations. After a separate warmup it
records nine batches. Each result line prints the median duration per iteration, the minimum and
p90, the sample count, and iterations per batch. Durations use readable units
from nanoseconds through minutes. Divide elapsed batch time by that count to
obtain per-iteration numbers, including fractions of a nanosecond. Work below the
clock's resolution may still report zero. The measured and failed counts
follow all selected cases. A failure prints its original error and makes the
command exit unsuccessfully.

## Warmup and raw samples

Run the following example with `linea run -O 3 examples/benchmark_samples.lin`.
It keeps one duration per measured round, in chronological order. Durations
vary from run to run, including zero on clocks too coarse to resolve a batch.

<!-- guide: excerpt examples/benchmark_samples.lin -->
```linea
    let schedule = bench.Schedule.new(warmups: 1, repetitions: 10000, samples: 3, cases: 1).unwrap()
```

`warmups` counts whole rounds. `repetitions` is the number of invocations
inside each timed batch. With three samples and one warmup this program runs
four batches. During a warmup `schedule.sample_index(round)` returns `None`.
It returns the zero-based sample number for each subsequent round.
`Schedule.new` returns `None` for zero repetitions, samples or cases, and
when warmups plus samples exceeds `UInt64.max`.

<!-- guide: excerpt examples/benchmark_samples.lin -->
```linea
        let elapsed = schedule.measure(
            inout [inout checksum] |iteration| {
                checksum += bench.black_box(iteration * iteration)
            },
        )
```

Each iteration receives an opaque index. The callback explicitly observes the
square and updates the checksum. Both operations count toward the elapsed
time. A fallible callback uses `schedule.try_measure`; an error returns
immediately with its original value and no time for a partial batch.
`bench.measure_once` times a single call and hands back its result, so a
caller can inspect or release a resource after the clock stops.

<!-- guide: excerpt examples/benchmark_samples.lin -->
```linea
    let stats = bench.summarize(&samples).unwrap()
```

`summarize` sorts the vector in place. Print or retain chronological samples
first. For a nonempty vector of length `n`, the median is element `n / 2`
and p90 is element `floor(9 * n / 10)`, counting from zero. The example
prints each time in nanoseconds **per batch**, including the summary. For
several cases, visit each turn of each round and call
`schedule.case_at(round, turn)` to rotate which case runs first. A full cycle
puts every case in every position once. Set up reusable inputs before timing.
If a device operation runs asynchronously, explicitly wait for completion
inside the callback to include execution.

## The same algorithm on CPU and GPU

`examples/benchmark_cpu_gpu` applies a nonlinear recurrence to 65,536
`Float32` elements (256 KiB of input and another 256 KiB of output). Each
output uses 32 dependent stages. The element function is ordinary Linea:

<!-- guide: excerpt examples/benchmark_cpu_gpu/main.lin -->
```linea
fn evolve_value(initial: Float32) -> Float32 {
    let first = four_stages(four_stages(initial))
    let second = four_stages(four_stages(first))
    let third = four_stages(four_stages(second))
    four_stages(four_stages(third))
}
```

`stage` computes `value * 0.75 + (value * value) * 0.125`, and
`four_stages` composes four calls to it. The fixed composition applies exactly
32 stages on both backends. Ordinary `Range` iteration over `UInt64` is outside
the current device admission profile; this example uses admitted direct
function calls instead. Compiler-generated counted index loops have a separate
checked device admission path.

The tensor algorithm has one definition too. Storage selects a sequential CPU
map or a GPU dispatch; both call `evolve_value`, with the same strict
`Float32` operations and order.

<!-- guide: excerpt examples/benchmark_cpu_gpu/main.lin -->
```linea
fn evolve[S: tensor.Storage[Float32]](input: tensor.Vector[Float32, S]) -> Result[tensor.Vector[Float32, S], S.Error] where carries(.Ok: input) {
    input.map(evolve_value)
}
```

Run `linea test examples/benchmark_cpu_gpu` for the CPU and GPU correctness
tests. The GPU test reports an explicit skip when no device is available.
Use `linea test --deny-skips --filter GPU examples/benchmark_cpu_gpu` to
require actual GPU execution: a skipped test makes that command fail.
From a checkout, run `nix develop -c zig build run -j2 -- test -O 3 examples/benchmark_cpu_gpu --deny-skips`.
This builds and uses that checkout's compiler and bundled standard library.
A `linea` found through `PATH` may be an older installation with different
bundled library APIs.
Run `linea bench --filter CPU examples/benchmark_cpu_gpu` to measure only
the CPU cases, including on a compiler built with `-Dgpu=false`.
`linea test --deny-skips --filter CPU examples/benchmark_cpu_gpu` likewise
qualifies the CPU tests without selecting the GPU test. Run
`linea bench examples/benchmark_cpu_gpu` on a machine with a supported GPU
to measure all six named cases. A GPU case reports `Gpu(Unavailable)` and
fails if no device is available; it never substitutes CPU work. Unsupported
device functions and other GPU errors also fail the case.

Before sampling, each GPU case compares **every output's raw bits** against
the CPU instantiation, outside the timed region. The original tensor CPU
case checks every output against a direct call of the element function. Input generation,
opening the device, and these checks happen once per case. The resident GPU
case also uploads its input before timing.

Each reported iteration processes the whole tensor: 65,536 elements with
32 stages each. The displayed duration is for that complete iteration, not
for one element or one stage; the formatter chooses readable time units.
The cases include:

- **CPU sequential:** output allocation, sequential computation, observation
  of the owned result and a runtime-selected output word, and release.
- **CPU chunks sequential:** 64 owned chunks of 1,024 elements through
  `task.map(.Sequential, ...)`, including result-vector allocation and chunk
  movement. Each chunk retains its input and a separate output array.
- **CPU chunks 4 OS threads:** the same chunks through `task.map(.Threads(4), ...)`
  on system I/O, including worker startup, dispatch, result collection and
  joining. Four is the worker limit, not a request to use every machine core.
- **CPU chunks 4 fibers 4 carriers:** the same policy on a persistent
  `io.Loop.open(carriers: 4)`. The four carrier threads permit CPU work to run
  in parallel. Loop creation and the root fiber's startup are outside timing;
  worker fiber preparation, scheduling, result collection and joining are inside.
- **GPU resident:** output allocation, kernel/pipeline preparation, dispatch,
  waiting for completion, observation of the owned result, and release.
- **GPU upload compute download:** input upload, the same resident computation,
  output download, observation of the owned host result and a runtime-selected
  output word, and release of all per-iteration resources. Device opening and
  input generation remain outside.

`map` already waits for completion before returning. Observing a device
buffer's descriptor alone would not wait for asynchronous work. Here the
completed owned output passes through `bench.black_box` and is explicitly
released inside the callback. Downloaded host output is observed and released
inside the transfer case as well.

These are elapsed host times for complete operations, including allocation
and runtime overhead. They are not isolated GPU kernel timestamps. GPU
pipeline caches may be warm after correctness checking and calibration. The
transfer case makes the cost of crossing the host/device boundary visible;
compare it with the resident case when deciding whether keeping data on the
GPU helps. This workload and size may favor either backend. Inspect the
minimum, median and p90 across repeated quiet runs before drawing a speedup
conclusion; do not use timings as a correctness golden.

The chunk cases preserve input arrays across iterations and overwrite output
arrays from those unchanged inputs. Setup copies the input into chunks once.
Every iteration transfers ownership of the same chunks into `task.map` and
retains the returned chunks for the next iteration. Any copying needed to move
those records, plus task and result-vector allocation, counts toward the time.
The sequential chunk case provides the matching data-handling baseline; the
original sequential tensor case has a different allocation and layout path.
All CPU cases use the same `evolve_value` function, and every chunk result is
checked against the tensor CPU reference before sampling.

The CPU tests run both system-thread and four-carrier fiber maps twice, checking
all 65,536 results' raw bits, original input bits and chunk order after each
round. Test-only callbacks check the actual worker route through
`task.current_carrier()`. The fiber loop has process lifetime; it is opened once
per named benchmark's process, rather than once per measured iteration.
