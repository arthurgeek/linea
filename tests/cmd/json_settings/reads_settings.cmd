The settings reader, built once, decodes each file below into its settings
and writes them back as JSON, or says why it cannot.

  $ linea build "$LINEA_ROOT"/examples/json_settings.lin -o settings

A file that holds every field decodes and is written back.

  $ ./settings "$LINEA_ROOT"/tests/cmd/json_settings/settings.json > out
  $ cat out
  {"name":"gateway","ports":[443,8443],"enabled":true}

A field the settings do not declare is refused, naming where it sits.

  $ ./settings "$LINEA_ROOT"/tests/cmd/json_settings/unknown.json > out
  unknown field at $["extra"]
  [1]
  $ cat out

A value of the wrong kind inside a list is refused, naming its index.

  $ ./settings "$LINEA_ROOT"/tests/cmd/json_settings/nested.json > out
  wrong kind of value at $["ports"][1]
  [1]
  $ cat out

Settings that decode but break a rule of their own are refused with the rule.

  $ ./settings "$LINEA_ROOT"/tests/cmd/json_settings/domain.json > out
  ports must be nonzero
  [1]
  $ cat out
