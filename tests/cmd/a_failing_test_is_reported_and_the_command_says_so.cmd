A failing test is reported and the command says so.

  $ linea test "$LINEA_ROOT"/tests/cmd/fixtures/tests_that_do_not_pass > out
  [1]
  $ cat out
  ok    a_conversion_out_of_range_is_expected
  ok    a_nan_conversion_is_expected
  ok    a_passing_test_still_runs
  FAIL  a_returned_failure_is_reported
          error: Write failed (Other) after 0 bytes; errno 7
  FAIL  a_trap_is_contained_and_explained
          linea: value out of range for its type at $LINEA_ROOT/tests/cmd/fixtures/tests_that_do_not_pass/main.lin:30:13
  FAIL  an_expected_trap_that_returns_is_reported
          expected the test to trap
  ok    an_explicit_panic_is_expected
  ok    an_index_out_of_bounds_is_expected
  ok    an_integer_overflow_is_expected
  ok    division_by_runtime_zero_is_expected
  
  7 passed, 3 failed
