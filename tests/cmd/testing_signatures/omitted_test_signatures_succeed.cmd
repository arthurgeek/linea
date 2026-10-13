Omitted test signatures succeed.

  $ linea test "$LINEA_ROOT"/tests/cmd/fixtures/omitted_test_signatures_succeed > out
  $ cat out
  ok    an_explicit_trap_remains_expected
  ok    bare_return_succeeds
  ok    deferred_cleanup_runs_before_success
  ok    explicit_custom_signature_is_preserved
  ok    fallthrough_succeeds
  ok    trailing_conditional_succeeds
  ok    trailing_integer_match_succeeds
  ok    trailing_match_succeeds
  ok    trailing_match_with_returning_first_arm_succeeds
  
  9 passed, 0 failed
