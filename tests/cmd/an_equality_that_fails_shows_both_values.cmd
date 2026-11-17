An equality that fails shows both values.

  $ linea test "$LINEA_ROOT"/tests/cmd/fixtures/an_equality_shows_both_values 2> /dev/null
  FAIL  a number that differs shows both
          expected 6, got 7
          error: seven is not six
  ok    an equality that holds says nothing
  ok    assertions borrow linear values on both outcomes
  FAIL  custom enum payloads are visible
          expected Sent("Lin"), got Sent("Ada")
          error: different recipients
  FAIL  option variants and payloads are visible
          expected None, got Some(7)
          error: a present value is not absent
  FAIL  text that differs shows both
          expected "ola", got "olá"
          error: an accent is a byte of its own
  
  2 passed, 4 failed
  [1]
