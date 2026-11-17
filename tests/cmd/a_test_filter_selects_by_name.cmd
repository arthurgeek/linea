`--filter` runs the tests whose names hold its text, and says when none does,
quoting the text as a string.

  $ linea test --filter withdrawal "$LINEA_ROOT"/tests/cmd/fixtures/tests_named_by_strings > out
  $ cat out
  ok    a fee is charged on every withdrawal
  ok    withdrawal deducts amount and fee
  
  2 passed, 0 failed
  $ linea test --filter "every withdrawal" "$LINEA_ROOT"/tests/cmd/fixtures/tests_named_by_strings > out
  $ cat out
  ok    a fee is charged on every withdrawal
  
  1 passed, 0 failed
  $ linea test --filter deposit "$LINEA_ROOT"/tests/cmd/fixtures/tests_named_by_strings > out
  $ cat out
  no test name in $LINEA_ROOT/tests/cmd/fixtures/tests_named_by_strings holds "deposit"
  $ linea test --filter '"' "$LINEA_ROOT"/tests/cmd/fixtures/tests_named_by_strings > out
  $ cat out
  no test name in $LINEA_ROOT/tests/cmd/fixtures/tests_named_by_strings holds "\""
