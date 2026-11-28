Benchmarks run independently of tests. The filter matches the qualified name.
A sample's measured values vary, but its units, actual count and percentile
labels are part of the report. A failed case leaves the other case's result.

  $ linea build --help | grep -o 'optimisation level.*' > build-level
  $ linea bench --help | grep -o 'optimisation level.*' > bench-level
  $ cmp -s build-level bench-level
  $ linea bench --filter fixed "$LINEA_ROOT"/tests/cmd/fixtures/named_benchmarks > out
  $ LC_ALL=C grep -Ec '^bench fixed count \.\.\. [0-9]+\.[0-9]{3} (ns|µs|ms|s|min)/iter \(min [0-9]+\.[0-9]{3} \1, p90 [0-9]+\.[0-9]{3} \1; 3 samples x 8 iterations\)$' out
  1
  $ tail -n 1 out
  1 measured, 0 failed
  $ linea bench -O 0 "$LINEA_ROOT"/tests/cmd/fixtures/named_benchmarks > out
  [1]
  $ tail -n 6 out
  bench owned failure ... FAILED
  Work(owned workload error)
  released owned workload error
  bench workload fails ... FAILED
  fixture could not prepare its workload
  1 measured, 2 failed
  $ linea bench --filter missing "$LINEA_ROOT"/tests/cmd/fixtures/named_benchmarks
  no benchmark name in $LINEA_ROOT/tests/cmd/fixtures/named_benchmarks holds "missing"
  0 measured, 0 failed
  $ linea test "$LINEA_ROOT"/tests/cmd/fixtures/named_benchmarks > out
  $ grep -v '^$' out
  ok    ordinary check
  1 passed, 0 failed
