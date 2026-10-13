A log filter selects complete numeric records.

  $ linea run "$LINEA_ROOT"/examples/log_filter.lin -- 40 < "$LINEA_ROOT"/tests/cmd/io/a_log_filter_selects_complete_numeric_records.stdin > out
  log record has no valid severity field
  $ cat out
  42 service ready
  99 alert
