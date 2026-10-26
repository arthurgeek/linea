A program that declares no `test fn` has nothing to run, so `linea test` says
so and succeeds.

  $ linea test "$LINEA_ROOT"/tests/cmd/fixtures/a_pair_is_returned_from_a_tail.lin
  no tests found in $LINEA_ROOT/tests/cmd/fixtures/a_pair_is_returned_from_a_tail.lin
