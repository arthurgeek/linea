A root of tests alone needs no main.

  $ linea test "$LINEA_ROOT"/tests/cmd/fixtures/a_root_of_tests_alone > out
  $ cat out
  ok    a_thing_holds
  
  1 passed, 0 failed
