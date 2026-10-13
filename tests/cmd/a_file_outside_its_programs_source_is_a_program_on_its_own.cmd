A file named on the command line that no program's source holds is a program
on its own, even beside a program's manifest.

  $ linea check "$LINEA_ROOT"/tests/cmd/fixtures/a_program_and_a_file_outside_its_source/scratch/spare.lin > out
  error[N-Undefined]: undefined name `nope`
   --> $LINEA_ROOT/tests/cmd/fixtures/a_program_and_a_file_outside_its_source/scratch/spare.lin:2:5
    |
  2 |     nope
    |     ^^^^ no binding with this name is in scope
  [1]
  $ cat out
