Fmt refuses what it cannot parse.

  $ linea fmt "$LINEA_ROOT"/tests/recovery/missing_name.lin > out
  error[S-Name]: expected a name after `let`
   --> $LINEA_ROOT/tests/recovery/missing_name.lin:2:9
    |
  2 |     let = 1;
    |         ^ a binding needs a name
  [1]
  $ cat out
