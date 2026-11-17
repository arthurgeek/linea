Omitted test signatures need no testing import.

  $ linea test "$LINEA_ROOT"/tests/cmd/fixtures/omitted_test_signatures_need_no_testing_import > out
  $ cat out
  ok    bare return without an import
  ok    fallthrough without an import
  
  2 passed, 0 failed
