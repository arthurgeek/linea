A test written inside a trait declaration runs under `linea test` like one at
module scope, and is reported by its own name. A `test trap fn` there passes
when its body traps.

  $ linea test "$LINEA_ROOT"/tests/decl/a_test_sits_in_a_trait_declaration.lin
  ok    doubling_a_meter_doubles_its_reading
  ok    doubling_past_the_largest_reading_traps
  
  2 passed, 0 failed
