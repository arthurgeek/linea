A manifest that will not parse is reported.

  $ linea check "$LINEA_ROOT"/tests/cmd/fixtures/a_program_whose_manifest_will_not_parse > out
  error: cannot read '$LINEA_ROOT/tests/cmd/fixtures/a_program_whose_manifest_will_not_parse'
    the linea.json marking its program is not JSON
  [74]
  $ cat out
