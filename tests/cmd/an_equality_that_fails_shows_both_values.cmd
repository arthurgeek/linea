An equality that fails shows both values.

  $ linea test "$LINEA_ROOT"/tests/cmd/fixtures/an_equality_shows_both_values 2> /dev/null
  FAIL  a_number_that_differs_shows_both
          expected 6, got 7
          error: seven is not six
  ok    an_equality_that_holds_says_nothing
  ok    assertions_borrow_linear_values_on_both_outcomes
  FAIL  custom_enum_payloads_are_visible
          expected Sent("Lin"), got Sent("Ada")
          error: different recipients
  FAIL  option_variants_and_payloads_are_visible
          expected None, got Some(7)
          error: a present value is not absent
  FAIL  text_that_differs_shows_both
          expected "ola", got "olá"
          error: an accent is a byte of its own
  
  2 passed, 4 failed
  [1]
