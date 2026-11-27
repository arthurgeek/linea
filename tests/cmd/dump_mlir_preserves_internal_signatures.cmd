Inspection externalizes bodies with the same internal ABI as definitions.

  $ linea dump-mlir --detail=full --function=main "$LINEA_ROOT"/tests/cmd/fixtures/inspection_abi.lin > out
  $ grep 'func.func private @"lin.' out
    func.func private @"lin.;narrow"(i64) -> i64
    func.func private @"lin.;pair"(!llvm.ptr, i64)
    func.func private @"lin.;main"() -> i64 attributes {llvm.linkage = #llvm.linkage<internal>, passthrough = [["probe-stack", "inline-asm"]]} {
  $ linea dump-mlir --detail=full --scope=all "$LINEA_ROOT"/tests/cmd/fixtures/inspection_abi.lin > all
  $ mlir-opt all -o /dev/null
