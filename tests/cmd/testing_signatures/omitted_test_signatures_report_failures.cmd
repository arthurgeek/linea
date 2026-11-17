Omitted test signatures report failures.

  $ linea test "$LINEA_ROOT"/tests/cmd/fixtures/omitted_test_signatures_report_failures > out
  [1]
  $ cat out
  FAIL  assertion failure propagates
          cleanup
          error: assertion failure
  FAIL  explicit failure is returned
          cleanup
          error: explicit failure
  FAIL  trailing match propagates failure
          error: match failure
  FAIL  trailing match returns explicit failure
          error: returned match failure
  
  0 passed, 4 failed
