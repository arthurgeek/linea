The default host inspection shows the project and declares the standard library.

  $ linea dump-mlir "$LINEA_ROOT"/examples/hello.lin > user
  $ grep -c 'func.func.* {' user
  2
  $ linea dump-mlir --scope=all "$LINEA_ROOT"/examples/hello.lin > all
  $ test "$(grep -c 'func.func.* {' all)" -gt 2
