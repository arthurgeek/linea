Formats supplied source.

  $ linea fmt --stdin < "$LINEA_ROOT"/tests/cmd/stdin/formats_supplied_source.stdin > out
  $ cat out
  fn greeting() -> Str {
      "olá"
  }
