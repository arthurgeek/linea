Fmt refuses to damage a file.

  $ linea fmt "$LINEA_ROOT"/tests/cmd/fixtures/the_walk_would_damage_this.fixture > out
  error: refusing to format $LINEA_ROOT/tests/cmd/fixtures/the_walk_would_damage_this.fixture: the result would be a different program
  [1]
  $ cat out
