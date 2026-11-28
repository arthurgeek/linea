Skipped capabilities are counted separately, retain their reason and settle normally.

  $ linea test "$LINEA_ROOT/tests/cmd/fixtures/test_skips" --filter 'capability' > out
  $ cat out
  SKIP  capability skips
          cleanup ran
          GPU capability unavailable: original reason
  
  0 passed, 0 failed, 1 skipped
  $ linea test "$LINEA_ROOT/tests/cmd/fixtures/test_skips" --filter 'capability' --deny-skips > out
  [1]
  $ cat out
  SKIP  capability skips
          cleanup ran
          GPU capability unavailable: original reason
  
  0 passed, 0 failed, 1 skipped
  $ linea test "$LINEA_ROOT/tests/cmd/fixtures/test_skips" --deny-skips --filter 'available passes'
  ok    available passes
  
  1 passed, 0 failed
  $ linea test "$LINEA_ROOT/tests/cmd/fixtures/test_skips" > out
  [1]
  $ cat out
  FAIL  assertion fails
          error: real assertion failure
  ok    available passes
  SKIP  capability skips
          cleanup ran
          GPU capability unavailable: original reason
  FAIL  custom unavailable fails
          error: GPU capability unavailable: original reason
  FAIL  trap cannot skip
          a trap test returned a skip
  
  1 passed, 3 failed, 1 skipped
