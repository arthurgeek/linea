Selected scalar device functions retain only the arithmetic imports they call.

  $ linea dump-mlir --target=gpu --function=increment "$LINEA_ROOT"/tests/cmd/fixtures/inspection_device.lin > scalar
  $ test "$(wc -l < scalar)" -le 30
  $ grep -c 'spirv.func @linea_f32_jam' scalar || test $? -eq 1
  0
  $ grep -c 'linea_f32_add' scalar
  2
  $ grep -c 'spirv.EntryPoint' scalar || test $? -eq 1
  0
  $ mlir-opt scalar -o /dev/null
