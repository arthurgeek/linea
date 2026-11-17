A failing test is reported and the command says so.

  $ linea test "$LINEA_ROOT"/tests/cmd/fixtures/tests_that_do_not_pass > out
  [1]
  $ cat out
  ok    a conversion out of range is expected
  ok    a nan conversion is expected
  ok    a passing test still runs
  FAIL  a returned failure is reported
          error: Write failed (Other) after 0 bytes; errno 7
  FAIL  a trap is contained and explained
          linea: value out of range for its type at $LINEA_ROOT/tests/cmd/fixtures/tests_that_do_not_pass/main.lin:30:13
  FAIL  an expected trap that returns is reported
          expected the test to trap
  ok    an explicit panic is expected
  ok    an index out of bounds is expected
  ok    an integer overflow is expected
  ok    division by runtime_zero is expected
  
  7 passed, 3 failed
