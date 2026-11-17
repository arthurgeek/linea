A test is reported by the string that names it.

  $ linea test "$LINEA_ROOT"/tests/cmd/fixtures/tests_named_by_strings > out
  $ cat out
  ok    a fee is charged on every withdrawal
  ok    withdraw
  ok    withdrawal deducts amount and fee
  
  3 passed, 0 failed
