A `.` inside a directory's name is part of that name, so `a.b` and `a/b` are
two modules of one program. Each test is named by the path that holds it, with
a `.` the directory's own name holds written `\.`.

  $ linea test "$LINEA_ROOT"/tests/cmd/fixtures/a_dot_in_a_directory_name_is_part_of_it > out
  $ cat out
  ok    a.b.holds_seven
  ok    a\.b.holds_seven
  
  2 passed, 0 failed
