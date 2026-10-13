Invalid key encoding.

  $ linea run "$LINEA_ROOT"/examples/config_editor.lin -- --stdin unused.cfg "$(printf '\377')" replacement > out
  configuration key and value arguments must be valid UTF-8
  [1]
  $ cat out
