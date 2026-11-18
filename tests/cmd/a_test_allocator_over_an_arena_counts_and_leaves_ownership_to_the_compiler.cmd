A test allocator over an arena counts what tests acquire and dispose, and a test
that drops an arena buffer fails only where it asserts that nothing is
outstanding.

  $ linea test "$LINEA_ROOT"/tests/cmd/fixtures/tests_over_an_arena_test_allocator > out
  [1]
  $ cat out
  ok    a shared test allocator over an arena lets a test drop a buffer
  FAIL  a test asserting nothing is outstanding fails when a buffer was dropped
          expected 0, got 1
          error: a buffer was not given back
  ok    a test dropping an arena buffer passes
  FAIL  a test failing with an arena buffer live reports its own failure
          error: the total is wrong
  
  2 passed, 2 failed
