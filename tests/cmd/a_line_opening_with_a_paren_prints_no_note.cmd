A line opening with `(` and an expression is not noted, whether it is a
function's tail or a statement of its own, and neither is a variant holding
the unit value.

  $ linea check "$LINEA_ROOT"/tests/cmd/fixtures/a_sum_is_returned_from_a_tail.lin
  $ linea check "$LINEA_ROOT"/tests/cmd/fixtures/a_unit_success_is_returned_from_a_tail.lin
  $ linea check "$LINEA_ROOT"/tests/newline/a_paren_begins_the_next_line.lin
  $ linea check "$LINEA_ROOT"/tests/newline/a_variant_line_ends_a_function.lin
