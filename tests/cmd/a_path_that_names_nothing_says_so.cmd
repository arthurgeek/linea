A path that names nothing says so.

  $ linea check tests/cmd/fixtures/a_file_that_is_not_there.lin > out
  error: cannot read 'tests/cmd/fixtures/a_file_that_is_not_there.lin'
    no file or directory of that name
  [74]
  $ cat out
