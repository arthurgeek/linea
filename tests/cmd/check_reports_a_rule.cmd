Check reports a rule.

  $ linea check "$LINEA_ROOT"/tests/diag/undefined_name.lin > out
  error[N-Undefined]: undefined name `y`
   --> $LINEA_ROOT/tests/diag/undefined_name.lin:2:5
    |
  2 |     y + 1
    |     ^ no binding with this name is in scope
  [1]
  $ cat out
