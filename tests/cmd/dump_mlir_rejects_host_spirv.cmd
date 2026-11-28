Host inspection refuses an unavailable stage before loading source.

  $ linea dump-mlir --target=host --stage=spirv missing.lin
  error: --stage=spirv requires --target=gpu
  [64]
