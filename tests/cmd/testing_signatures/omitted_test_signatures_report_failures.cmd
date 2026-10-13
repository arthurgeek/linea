Omitted test signatures report failures.

  $ linea test "$LINEA_ROOT"/tests/cmd/fixtures/omitted_test_signatures_report_failures > out
  [1]
  $ cat out
  FAIL  assertion_failure_propagates
          cleanup
          error: assertion failure
  FAIL  explicit_failure_is_returned
          cleanup
          error: explicit failure
  FAIL  trailing_match_propagates_failure
          error: match failure
  FAIL  trailing_match_returns_explicit_failure
          error: returned match failure
  
  0 passed, 4 failed
