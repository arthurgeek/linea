A transcript is ordered by name.

  $ linea test "$LINEA_ROOT"/tests/cmd/fixtures/tests_that_finish_out_of_order > out
  $ cat out
  ok    a_slow_one
  ok    z_quick_one
  
  2 passed, 0 failed
