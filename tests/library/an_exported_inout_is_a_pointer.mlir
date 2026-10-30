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
  llvm.mlir.global internal constant @linea_file0("tests/library/an_exported_inout_is_a_pointer/main.lin\00") : !llvm.array<54 x i8>
  func.func private @linea_set_args(i32, !llvm.ptr)
  func.func private @linea_trap(i32, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @linea_panic(i64, i64, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @"lin.;set"(%a0: !llvm.ptr) -> i64 attributes {llvm.linkage = #llvm.linkage<internal>, passthrough = [["probe-stack", "inline-asm"]]} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x !llvm.ptr {alignment = 8 : i64} : (i64) -> !llvm.ptr
    llvm.store %a0, %s0 : !llvm.ptr, !llvm.ptr
    cf.br ^b0
  ^b0:
    %v0 = arith.constant 7 : i64 loc("tests/library/an_exported_inout_is_a_pointer/main.lin":2:13)
    %v1 = llvm.load %s0 : !llvm.ptr -> !llvm.ptr loc("tests/library/an_exported_inout_is_a_pointer/main.lin":2:5)
    %iw2 = arith.trunci %v0 : i64 to i32 loc("tests/library/an_exported_inout_is_a_pointer/main.lin":2:5)
    llvm.store %iw2, %v1 : i32, !llvm.ptr loc("tests/library/an_exported_inout_is_a_pointer/main.lin":2:5)
    %v3 = arith.constant 0 : i64 loc("tests/library/an_exported_inout_is_a_pointer/main.lin":2:5)
    func.return %v3 : i64 loc("tests/library/an_exported_inout_is_a_pointer/main.lin":2:5)
  }
  func.func @set(%p0: !llvm.ptr) {
    %answer = func.call @"lin.;set"(%p0) : (!llvm.ptr) -> i64
    func.return
  }
}
