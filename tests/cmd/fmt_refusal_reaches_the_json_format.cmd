Fmt refusal reaches the json format.

  $ linea fmt "$LINEA_ROOT"/tests/cmd/fixtures/the_walk_would_damage_this.fixture --error-format=json > out
  {"severity":"error","message":"refusing to format $LINEA_ROOT/tests/cmd/fixtures/the_walk_would_damage_this.fixture: the result would be a different program","file":null,"labels":[],"notes":[]}
  [1]
  $ cat out
