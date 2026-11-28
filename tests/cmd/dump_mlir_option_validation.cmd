Inspection validates its own options before loading a program.

  $ linea dump-mlir --scope=bad missing.lin
  error: invalid --scope value
  [64]
  $ linea dump-mlir --target=bad missing.lin
  error: invalid --target value
  [64]
  $ linea dump-mlir --stage=bad missing.lin
  error: invalid --stage value
  [64]
  $ linea dump-mlir --function= missing.lin
  error: --function requires a qualified source function
  [64]
  $ linea dump-mlir --function=missing "$LINEA_ROOT"/tests/cmd/fixtures/inspection_abi.lin
  error: unknown source function: 'missing'
  [64]
  $ linea dump-mlir --detail=bad missing.lin
  error: invalid --detail value
  [64]
