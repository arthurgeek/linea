A program with no source says so.

  $ linea check "$LINEA_ROOT"/tests/cmd/fixtures/a_program_whose_source_root_holds_no_file > out
  error[S-Entry]: a program declares exactly one `main`
   --> $LINEA_ROOT/tests/cmd/fixtures/a_program_whose_source_root_holds_no_file/src:1:1
    |
  1 | 
    | ^ found 0
  [1]
  $ cat out
