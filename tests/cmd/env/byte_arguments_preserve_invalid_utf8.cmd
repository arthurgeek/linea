Byte arguments preserve invalid utf8.

  $ linea run "$LINEA_ROOT"/tests/env/byte_arguments.lin -- 'a'"$(printf '\377')"'z' '' > out
  $ cat out
  arguments 2
  3: 97 255 122
  0:
