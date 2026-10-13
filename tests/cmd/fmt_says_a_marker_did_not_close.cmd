Fmt says a marker did not close.

  $ linea fmt --check "$LINEA_ROOT"/tests/cmd/fixtures/a_marker_that_does_not_close.fixture > out
  note: $LINEA_ROOT/tests/cmd/fixtures/a_marker_that_does_not_close.fixture:8: `// linea fmt: on` does not close the region here, which reaches to the end of the declaration around it
  $ cat out
