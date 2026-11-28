Selected scalar device code keeps real operations and imports the numerical library.

  $ linea dump-mlir --target=gpu --detail=compact --function=half "$LINEA_ROOT"/tests/cmd/fixtures/inspection_half_device.lin > lowered
  $ test "$(wc -l < lowered)" -lt 30
  $ grep -c 'func.func.*source.half' lowered
  1
  $ grep -c 'spirv.func.*linea_f32_mul' lowered
  1
  $ grep -c 'spirv.func.*linea_f32_mul.* {$' lowered || test $? -eq 1
  0
  $ mlir-opt lowered -o /dev/null
  $ linea dump-mlir --target=gpu --stage=spirv --function=half "$LINEA_ROOT"/tests/cmd/fixtures/inspection_half_device.lin > structured
  $ test "$(wc -l < structured)" -lt 30
  $ grep -c 'spirv.func.*source.half' structured
  1
  $ mlir-opt structured -o /dev/null
  $ linea dump-mlir --target=gpu --detail=full --function=half "$LINEA_ROOT"/tests/cmd/fixtures/inspection_half_device.lin > full-user
  $ grep -c 'spirv.func.*linea_f32_mul.* {$' full-user || test $? -eq 1
  0
  $ linea dump-mlir --target=gpu --scope=all --function=half "$LINEA_ROOT"/tests/cmd/fixtures/inspection_half_device.lin > all
  $ grep -c 'spirv.func.*linea_f32_mul.* {$' all
  1
  $ mlir-opt all -o /dev/null
