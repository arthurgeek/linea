Commands share a shell, and the checkout root is named, not spelled.

  $ greeting=hello
  $ echo "$greeting from $LINEA_ROOT"
  hello from $LINEA_ROOT
  $ linea help > /dev/null
  $ linea run $LINEA_ROOT/tests/cmd/fixtures/a_program_that_says_something.lin
  one two
  Olá
  $ exit_three() { return 3; }; exit_three
  [3]
