Compact presentation keeps real operations with source names and optional locations.

  $ linea dump-mlir --detail=compact --function=twice "$LINEA_ROOT"/tests/cmd/fixtures/inspection_device.lin > compact
  $ grep -c 'func.call @source.increment' compact
  1
  $ grep -c 'func.func private @source.twice' compact
  1
  $ grep -c ' loc(' compact || test $? -eq 1
  0
  $ grep -c 'probe-stack' compact || test $? -eq 1
  0
  $ mlir-opt compact -o /dev/null
  $ linea dump-mlir --detail=full --locations --function=twice "$LINEA_ROOT"/tests/cmd/fixtures/inspection_device.lin > full
  $ grep -c 'func.call @"lin.;increment"' full
  1
  $ test "$(grep -c ' loc(' full)" -gt 0
  $ grep -c 'probe-stack' full
  1
  $ mlir-opt full -o /dev/null
  $ linea dump-mlir --detail=full --function=twice "$LINEA_ROOT"/tests/cmd/fixtures/inspection_device.lin > full-no-locations
  $ grep -c ' loc(' full-no-locations || test $? -eq 1
  0
