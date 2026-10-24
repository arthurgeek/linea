Check json format.

  $ linea check "$LINEA_ROOT"/tests/diag/undefined_name.lin --error-format=json > out
  {"severity":"error","code":"N-Undefined","message":"undefined name `y`","file":"$LINEA_ROOT/tests/diag/undefined_name.lin","labels":[{"file":"$LINEA_ROOT/tests/diag/undefined_name.lin","line":2,"column":5,"start":25,"end":26,"style":"primary","message":"no binding with this name is in scope"}],"help":[],"notes":[],"fixes":[]}
  [1]
  $ cat out
