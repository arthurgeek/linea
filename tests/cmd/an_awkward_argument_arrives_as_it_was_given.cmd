An awkward argument arrives as it was given.

  $ linea run "$LINEA_ROOT"/tests/cmd/fixtures/reports_its_arguments -- one 'two words' '' héllo -v 'a'"$(printf '\303')"'z' > out
  $ cat out
  count 7
  [one]
  [two words]
  []
  [héllo]
  [-v]
  <none>
  past the end is nothing
