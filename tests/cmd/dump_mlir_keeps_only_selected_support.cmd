A pure helper inspection contains its body without unrelated program support.

  $ linea dump-mlir --function=increment "$LINEA_ROOT"/tests/cmd/fixtures/inspection_device.lin > helper
  $ grep -c 'func.func' helper
  1
  $ grep -E -c 'linea_(file|str|static)|linea_set_args|@main|std.io' helper || test $? -eq 1
  0
  $ mlir-opt helper -o /dev/null
  $ linea dump-mlir --function=twice "$LINEA_ROOT"/tests/cmd/fixtures/inspection_device.lin > caller
  $ grep -c 'func.func' caller
  2
  $ mlir-opt caller -o /dev/null
