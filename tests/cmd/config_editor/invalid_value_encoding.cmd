Invalid value encoding.

  $ linea run "$LINEA_ROOT"/examples/config_editor.lin -- --stdin unused.cfg name "$(printf '\377')" < "$LINEA_ROOT"/tests/cmd/config_editor/invalid_value_encoding.stdin > out
  configuration key and value arguments must be valid UTF-8
  [1]
  $ cat out
