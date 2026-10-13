Every command that compiles prints its notes, whether or not it then succeeds.

  $ linea check "$LINEA_ROOT"/tests/cmd/fixtures/a_note_does_not_stop_a_program.lin
  note[S-Continuation]: the next line begins with `-`, which could have continued the expression above
   --> $LINEA_ROOT/tests/cmd/fixtures/a_note_does_not_stop_a_program.lin:5:5
    |
  5 |     -short
    |     ^ end the previous line with it if that was meant
  $ linea test "$LINEA_ROOT"/tests/cmd/fixtures/a_note_does_not_stop_a_program.lin
  note[S-Continuation]: the next line begins with `-`, which could have continued the expression above
   --> $LINEA_ROOT/tests/cmd/fixtures/a_note_does_not_stop_a_program.lin:5:5
    |
  5 |     -short
    |     ^ end the previous line with it if that was meant
  ok    change_is_what_was_paid_over_the_price
  
  1 passed, 0 failed
  $ linea run "$LINEA_ROOT"/tests/cmd/fixtures/a_note_does_not_stop_a_program.lin
  note[S-Continuation]: the next line begins with `-`, which could have continued the expression above
   --> $LINEA_ROOT/tests/cmd/fixtures/a_note_does_not_stop_a_program.lin:5:5
    |
  5 |     -short
    |     ^ end the previous line with it if that was meant
  [3]

Both streams sent to one file keep everything each wrote, in order.

  $ linea test "$LINEA_ROOT"/tests/cmd/fixtures/a_note_does_not_stop_a_program.lin > both 2>&1
  $ cat both
  note[S-Continuation]: the next line begins with `-`, which could have continued the expression above
   --> $LINEA_ROOT/tests/cmd/fixtures/a_note_does_not_stop_a_program.lin:5:5
    |
  5 |     -short
    |     ^ end the previous line with it if that was meant
  ok    change_is_what_was_paid_over_the_price
  
  1 passed, 0 failed
