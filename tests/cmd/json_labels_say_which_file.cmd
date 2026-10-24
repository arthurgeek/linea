Json labels say which file.

  $ linea check --error-format=json "$LINEA_ROOT"/tests/modules/a_label_in_another_file_says_which > out
  {"severity":"error","code":"T-Mismatch","message":"expected `Bool`, found `Int64`","file":"$LINEA_ROOT/tests/modules/a_label_in_another_file_says_which/main.lin","labels":[{"file":"$LINEA_ROOT/tests/modules/a_label_in_another_file_says_which/main.lin","line":16,"column":13,"start":760,"end":761,"style":"primary","message":"expected `Bool`, found `Int64`"},{"file":"$LINEA_ROOT/tests/modules/a_label_in_another_file_says_which/other/other.lin","line":1,"column":10,"start":9,"end":10,"style":"secondary","message":"expected because of this parameter"}],"help":[],"notes":[],"fixes":[]}
  [1]
  $ cat out
