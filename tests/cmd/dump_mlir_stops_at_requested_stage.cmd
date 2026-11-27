Inspection never invokes tools downstream of the requested stage.

  $ mkdir tools
  $ printf '#!/bin/sh\nexit 91\n' > tools/mlir-translate
  $ cp tools/mlir-translate tools/spirv-val
  $ chmod +x tools/*
  $ PATH="$PWD/tools:$PATH" linea dump-mlir --target=gpu --stage=spirv --function=twice "$LINEA_ROOT"/tests/cmd/fixtures/inspection_device.lin > structured
  $ grep -c 'spirv.module' structured
  1
  $ cp tools/mlir-translate tools/mlir-opt
  $ PATH="$PWD/tools:$PATH" linea dump-mlir --target=gpu --function=twice "$LINEA_ROOT"/tests/cmd/fixtures/inspection_device.lin > lowered
  $ grep -c 'gpu.module' lowered
  1
  $ PATH="$PWD/tools:$PATH" linea dump-mlir --scope=all "$LINEA_ROOT"/tests/cmd/fixtures/inspection_device.lin > host
  $ grep -c linea_gpu_image host || test $? -eq 1
  0
  $ grep 'func.func private @linea_gpu_function' host
    func.func private @linea_gpu_function(!llvm.ptr) -> i64
  $ mlir-opt host -o /dev/null
