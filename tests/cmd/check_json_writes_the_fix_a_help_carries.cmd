Check writes the fix a help carries in the json format.

  $ linea check "$LINEA_ROOT"/tests/borrows/contracts/a_clause_goes_before_a_comment_on_the_header.lin --error-format=json
  {"severity":"error","code":"T-BorrowContract","message":"the result has more than one eligible observation source","file":"$LINEA_ROOT/tests/borrows/contracts/a_clause_goes_before_a_comment_on_the_header.lin","labels":[{"file":"$LINEA_ROOT/tests/borrows/contracts/a_clause_goes_before_a_comment_on_the_header.lin","line":2,"column":4,"start":21,"end":25,"style":"primary","message":"the result may come from `a` or `b`; add `where carries(a)` or `where carries(b)`, or `where carries(a, b)` where it may come from either"}],"help":[],"notes":[],"fixes":[{"kind":"where_clause","help":null,"edits":[{"file":"$LINEA_ROOT/tests/borrows/contracts/a_clause_goes_before_a_comment_on_the_header.lin","line":2,"column":31,"start":48,"end":48,"text":" where carries(a, b)"}]}]}
  [1]
