A test written inside an inherent `impl` runs under `linea test` like one at
module scope, and is reported by its own name.

  $ linea test "$LINEA_ROOT"/tests/decl/a_test_sits_in_an_inherent_impl.lin
  ok    holds its value
  
  1 passed, 0 failed

A `test trap` inside an `impl` passes when its body traps.

  $ linea test "$LINEA_ROOT"/tests/decl/a_test_trap_sits_in_an_inherent_impl.lin
  ok    divides by zero
  
  1 passed, 0 failed

A test inside a generic `impl` runs once, over the concrete types it names.

  $ linea test "$LINEA_ROOT"/tests/decl/a_test_in_a_generic_impl.lin
  ok    creates concrete box
  
  1 passed, 0 failed
