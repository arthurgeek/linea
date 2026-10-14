A program's own directory named `std` is part of the program, and its modules
are not the standard library's even where their paths match: `std/mem` here
declares a `system` of its own beside the library's `mem.system`.

  $ linea test "$LINEA_ROOT"/tests/cmd/fixtures/a_program_directory_named_std_is_its_own_module
  ok    std.mem.its_own_system_answers_seven
  
  1 passed, 0 failed
