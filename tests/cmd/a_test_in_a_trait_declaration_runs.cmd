A test written inside a trait declaration runs under `linea test` like one at
module scope, and is reported by its own name. A `test trap` there passes
when its body traps.

  $ linea test "$LINEA_ROOT"/tests/decl/a_test_sits_in_a_trait_declaration.lin
  ok    doubling a meter doubles its reading
  ok    doubling past the largest reading traps
  
  2 passed, 0 failed
