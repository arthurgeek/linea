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
  llvm.mlir.global internal constant @linea_file0("tests/codegen/unit_values_have_a_computation.lin\00") : !llvm.array<49 x i8>
  func.func private @linea_set_args(i32, !llvm.ptr)
  func.func private @linea_trap(i32, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @linea_panic(i64, i64, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @"lin.;main"() -> i64 attributes {llvm.linkage = #llvm.linkage<internal>} {
    cf.br ^b0
  ^b0:
    %v0 = arith.constant 0 : i64 loc("tests/codegen/unit_values_have_a_computation.lin":10:13)
    %v1 = func.call @"lin.;consume[$28$29]"(%v0) : (i64) -> i64 loc("tests/codegen/unit_values_have_a_computation.lin":10:5)
    %v2 = func.call @"lin.;empty"() : () -> i64 loc("tests/codegen/unit_values_have_a_computation.lin":11:5)
    %v3 = func.call @"lin.;bare"() : () -> i64 loc("tests/codegen/unit_values_have_a_computation.lin":12:5)
    %v4 = arith.constant 0 : i64 loc("tests/codegen/unit_values_have_a_computation.lin":13:5)
    func.return %v4 : i64 loc("tests/codegen/unit_values_have_a_computation.lin":13:5)
  }
  func.func private @"lin.;consume[$28$29]"(%a0: i64) -> i64 attributes {llvm.linkage = #llvm.linkage<internal>} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    llvm.store %a0, %s0 : i64, !llvm.ptr
    cf.br ^b0
  ^b0:
    %v0 = arith.constant 0 : i64 loc("tests/codegen/unit_values_have_a_computation.lin":1:32)
    func.return %v0 : i64 loc("tests/codegen/unit_values_have_a_computation.lin":1:32)
  }
  func.func private @"lin.;empty"() -> i64 attributes {llvm.linkage = #llvm.linkage<internal>} {
    cf.br ^b0
  ^b0:
    %v0 = arith.constant 0 : i64 loc("tests/codegen/unit_values_have_a_computation.lin":3:18)
    func.return %v0 : i64 loc("tests/codegen/unit_values_have_a_computation.lin":3:18)
  }
  func.func private @"lin.;bare"() -> i64 attributes {llvm.linkage = #llvm.linkage<internal>} {
    cf.br ^b0
  ^b0:
    %v0 = arith.constant 0 : i64 loc("tests/codegen/unit_values_have_a_computation.lin":6:5)
    func.return %v0 : i64 loc("tests/codegen/unit_values_have_a_computation.lin":6:5)
  }
  func.func @main(%argc: i32, %argv: !llvm.ptr) -> i32 {
    func.call @linea_set_args(%argc, %argv) : (i32, !llvm.ptr) -> ()
    %status = func.call @"lin.;main"() : () -> i64
    %status32 = arith.trunci %status : i64 to i32
    func.return %status32 : i32
  }
}
