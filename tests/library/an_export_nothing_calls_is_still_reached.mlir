module {
  llvm.mlir.global external @linea_runtime_abi_1() {addr_space = 0 : i32} : i64
  llvm.mlir.global internal @linea_abi() {addr_space = 0 : i32} : !llvm.ptr {
    %a = llvm.mlir.addressof @linea_runtime_abi_1 : !llvm.ptr
    llvm.return %a : !llvm.ptr
  }
  llvm.mlir.global appending @llvm.used() {addr_space = 0 : i32, section = "llvm.metadata"} : !llvm.array<1 x ptr> {
    %a = llvm.mlir.addressof @linea_abi : !llvm.ptr
    %u = llvm.mlir.undef : !llvm.array<1 x ptr>
    %v = llvm.insertvalue %a, %u[0] : !llvm.array<1 x ptr>
    llvm.return %v : !llvm.array<1 x ptr>
  }
  llvm.mlir.global internal constant @linea_file0("tests/library/an_export_nothing_calls_is_still_reached/main.lin\00") : !llvm.array<64 x i8>
  func.func private @linea_set_args(i32, !llvm.ptr)
  func.func private @linea_trap(i32, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @linea_panic(i64, i64, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @"lin.;published"(%a0: i64) -> i64 attributes {llvm.linkage = #llvm.linkage<internal>, passthrough = [["probe-stack", "inline-asm"]]} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x i32 {alignment = 4 : i64} : (i64) -> !llvm.ptr
    %pw0 = arith.trunci %a0 : i64 to i32
    llvm.store %pw0, %s0 : i32, !llvm.ptr
    cf.br ^b0
  ^b0:
    %lw0 = llvm.load %s0 : !llvm.ptr -> i32 loc("tests/library/an_export_nothing_calls_is_still_reached/main.lin":2:5)
    %v0 = arith.extsi %lw0 : i32 to i64 loc("tests/library/an_export_nothing_calls_is_still_reached/main.lin":2:5)
    func.return %v0 : i64 loc("tests/library/an_export_nothing_calls_is_still_reached/main.lin":2:5)
  }
  func.func @published(%p0: i32) -> i32 {
    %w0 = arith.extsi %p0 : i32 to i64
    %answer = func.call @"lin.;published"(%w0) : (i64) -> i64
    %narrow = arith.trunci %answer : i64 to i32
    func.return %narrow : i32
  }
}
