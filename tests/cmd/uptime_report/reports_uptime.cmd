The uptime report, built once, summarizes each log of health checks below.

  $ linea build "$LINEA_ROOT"/examples/uptime_report.lin -o uptime

Each service gets one summary line, in the order the log first names it. A
blank line is skipped, and each line that is not a check is reported with its
number while the rest are still counted.

  $ ./uptime "$LINEA_ROOT"/tests/cmd/uptime_report/checks.jsonl > out
  line 5: missing field at $["ms"]
  line 6: invalid syntax at byte 37
  2 lines were not checks
  [1]
  $ cat out
  {"service":"checkout","checks":3,"failed":1,"slowest_ms":2950}
  {"service":"search","checks":1,"failed":0,"slowest_ms":38}
  {"service":"login","checks":1,"failed":1,"slowest_ms":5000}

With no file named, the checks are read from standard input.

  $ ./uptime < "$LINEA_ROOT"/tests/cmd/uptime_report/clean.jsonl
  {"service":"search","checks":2,"failed":1,"slowest_ms":4100}

A log that cannot be opened is refused with the reason.

  $ ./uptime "$LINEA_ROOT"/tests/cmd/uptime_report/absent.jsonl
  cannot open the checks: file operation failed after 0 bytes: Open failed (NotFound) after 0 bytes; errno 2
  [1]
