Device inspection preserves imported helper signatures through production conversion.

  $ linea dump-mlir --target=gpu --function=twice "$LINEA_ROOT"/tests/cmd/fixtures/inspection_device.lin > lowered
  $ grep -c 'func.func.*source.increment.*linkage_attributes' lowered
  1
  $ grep -c 'spirv.func.*linea_f32_mul.*linkage_attributes' lowered
  1
  $ linea dump-mlir --target=gpu --stage=spirv --function=twice "$LINEA_ROOT"/tests/cmd/fixtures/inspection_device.lin > structured
  $ grep -c 'spirv.func.*source.increment.*linkage_attributes' structured
  1
  $ grep -c 'spirv.func.*linea_f32_mul.*linkage_attributes' structured
  1
  $ grep -c linea_gpu_image structured || test $? -eq 1
  0
  $ linea dump-mlir --scope=all --target=gpu --stage=lowered "$LINEA_ROOT"/tests/cmd/fixtures/inspection_device.lin > all-lowered
  $ grep -c 'linkage_attributes = #spirv.linkage_attributes' all-lowered || test $? -eq 1
  0
  $ linea dump-mlir --scope=all --target=gpu --stage=spirv "$LINEA_ROOT"/tests/cmd/fixtures/inspection_device.lin > all-structured
  $ grep -c 'spirv.module' all-structured
  1
  $ linea dump-mlir --target=gpu --function=main "$LINEA_ROOT"/tests/cmd/fixtures/inspection_device.lin
  error: no admitted GPU implementation matches the selected source functions
  [64]
