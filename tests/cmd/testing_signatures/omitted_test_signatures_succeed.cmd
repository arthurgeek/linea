Omitted test signatures succeed.

  $ linea test "$LINEA_ROOT"/tests/cmd/fixtures/omitted_test_signatures_succeed > out
  $ cat out
  ok    an explicit trap remains expected
  ok    bare return succeeds
  ok    deferred cleanup runs before success
  ok    explicit custom signature is preserved
  ok    fallthrough succeeds
  ok    trailing conditional succeeds
  ok    trailing integer match succeeds
  ok    trailing match succeeds
  ok    trailing match with returning first arm succeeds
  
  9 passed, 0 failed
