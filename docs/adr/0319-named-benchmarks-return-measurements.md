# 0319. Named benchmarks return measurements

**Status:** Accepted

## Context

A measurement library supports custom comparisons that retain raw samples. A
suite also needs named cases that the driver can find, filter and run without
timing unrelated setup, process startup or another case on the same runner.

## Decision

A contextual `bench "name" { … }` declaration has a zero-argument body with a
typed result. The success type is the standard library's nominal
`bench.Measurement`. The default failure is `mem.Oom`. An explicitly written
failure implements Display; a linear failure also implements Release. As with
tests, a case belongs to its declaring module, even inside an implementation.
Tests and benchmarks use the same qualified-name rules.

`linea bench` builds an optimized case dispatcher and runs the selected
benchmarks serially in isolated processes. `linea test` selects ordinary tests.
The outer body prepares inputs; `std.bench` reads the clock around repeated
callbacks and returns the measurement. The library prints the distribution.
The driver handles selection, child lifetime, errors and the final totals.

## Consequences

The benchmark function can prepare owned resources, choose an explicit batch
size or propagate a workload failure. An early failure never becomes a
measurement. A one-repetition calibration probe permits expensive operations
to run in small batches; fast operations can use larger batches up to a
bounded cap. Warmups and calibration produce no reported samples. Fractional
per-iteration timings derive from measured batch times and actual iteration
counts. Another process on the machine may still affect a benchmark.

## Alternatives considered

A naming convention on ordinary tests would give a spelling two meanings and
make the normal test command responsible for excluding benchmark work. Timing
an entire test subprocess would include compilation-independent setup and
process startup. A global current timing context would hide the owner of the
samples. A required mutable manager argument would add a special entry-point
parameter to a case whose only required output is its measurement. Returning
that value lets ordinary closures and library calls describe the timed work.
