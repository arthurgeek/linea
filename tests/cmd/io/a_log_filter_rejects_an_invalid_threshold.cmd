A log filter rejects an invalid threshold.

  $ linea run "$LINEA_ROOT"/examples/log_filter.lin -- 4x > out
  minimum severity must be an unsigned decimal integer
  [1]
  $ cat out
