Independent device modules keep unique symbol scopes at both inspection stages.

  $ linea dump-mlir --target=gpu "$LINEA_ROOT"/runtime/tests/gpu_runtime/numerical_map.lin > lowered
  $ grep -c 'gpu.module' lowered
  2
  $ mlir-opt lowered -o /dev/null
  $ linea dump-mlir --target=gpu --stage=spirv "$LINEA_ROOT"/runtime/tests/gpu_runtime/numerical_map.lin > structured
  $ grep -c 'spirv.module' structured
  2
  $ mlir-opt structured -o /dev/null
