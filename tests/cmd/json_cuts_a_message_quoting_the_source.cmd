Json cuts a message quoting the source.

  $ linea check "$LINEA_ROOT"/tests/diag/a_message_quoting_the_source_is_cut.lin --error-format=json > out
  {"severity":"error","code":"N-Undefined","message":"undefined name `qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq ... (truncated)","file":"$LINEA_ROOT/tests/diag/a_message_quoting_the_source_is_cut.lin","labels":[{"file":"$LINEA_ROOT/tests/diag/a_message_quoting_the_source_is_cut.lin","line":2,"column":5,"start":25,"end":625,"style":"primary","message":"no binding with this name is in scope"}],"help":[],"notes":[],"fixes":[]}
  [1]
  $ cat out
