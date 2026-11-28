User scope hides generated derive bodies while explicit selection remains available.

  $ linea dump-mlir "$LINEA_ROOT"/examples/gpu_matrix.lin > user
  $ grep -c 'source generated_declaration' user || test $? -eq 1
  0
  $ grep -c 'func.func.*source.MatrixError.* {$' user || test $? -eq 1
  0
  $ linea dump-mlir --function=MatrixError.fmt "$LINEA_ROOT"/examples/gpu_matrix.lin > selected
  $ grep -c 'source generated_declaration MatrixError.fmt' selected
  1
  $ grep -c 'func.func.*source.MatrixError.fmt.* {$' selected
  1
  $ mlir-opt selected -o /dev/null
