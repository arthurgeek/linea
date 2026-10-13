A mir dump stops at a diagnostic.

  $ linea dump-mir "$LINEA_ROOT"/tests/control/comparison_not_chained.lin > out
  error[S-Chain]: comparisons cannot be chained
   --> $LINEA_ROOT/tests/control/comparison_not_chained.lin:2:21
    |
  2 |     let bad = 1 < 2 < 3;
    |                     ^ compare one pair at a time
  error[S-Expr]: expected an expression
   --> $LINEA_ROOT/tests/control/comparison_not_chained.lin:2:15
    |
  2 |     let bad = 1 < 2 < 3;
    |               ^^^^^^^^^ this is not the start of an expression
  [1]
  $ cat out
