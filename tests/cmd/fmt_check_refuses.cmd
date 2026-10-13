Fmt check refuses.

  $ linea fmt --check "$LINEA_ROOT"/tests/diag/unexpected_character.lin > out
  error[S-Char]: unexpected character '#'
   --> $LINEA_ROOT/tests/diag/unexpected_character.lin:3:13
    |
  3 |     let y = #;
    |             ^ not a valid token
  [1]
  $ cat out
