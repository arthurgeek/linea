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
  llvm.mlir.global internal constant @linea_file0("tests/codegen/a_float_division_is_not_guarded.lin\00") : !llvm.array<50 x i8>
  func.func private @linea_set_args(i32, !llvm.ptr)
  func.func private @linea_trap(i32, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @linea_panic(i64, i64, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @"lin.;main"() -> i64 attributes {llvm.linkage = #llvm.linkage<internal>} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x f64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    cf.br ^b0
  ^b0:
    %v0 = arith.constant 0x3FF8000000000000 : f64 loc("tests/codegen/a_float_division_is_not_guarded.lin":6:23)
    %v1 = arith.constant 0x3FE0000000000000 : f64 loc("tests/codegen/a_float_division_is_not_guarded.lin":6:28)
    %v2 = func.call @"lin.;quotient"(%v0, %v1) : (f64, f64) -> f64 loc("tests/codegen/a_float_division_is_not_guarded.lin":6:14)
    llvm.store %v2, %s0 : f64, !llvm.ptr loc("tests/codegen/a_float_division_is_not_guarded.lin":6:5)
    %v4 = arith.constant 0 : i64 loc("tests/codegen/a_float_division_is_not_guarded.lin":7:5)
    func.return %v4 : i64 loc("tests/codegen/a_float_division_is_not_guarded.lin":7:5)
  }
  func.func private @"lin.;quotient"(%a0: f64, %a1: f64) -> f64 attributes {llvm.linkage = #llvm.linkage<internal>} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x f64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 1 : i64
    %s1 = llvm.alloca %z1 x f64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    llvm.store %a0, %s0 : f64, !llvm.ptr
    llvm.store %a1, %s1 : f64, !llvm.ptr
    cf.br ^b0
  ^b0:
    %v0 = llvm.load %s0 : !llvm.ptr -> f64 loc("tests/codegen/a_float_division_is_not_guarded.lin":2:5)
    %v1 = llvm.load %s1 : !llvm.ptr -> f64 loc("tests/codegen/a_float_division_is_not_guarded.lin":2:9)
    %nr2 = arith.divf %v0, %v1 : f64 loc("tests/codegen/a_float_division_is_not_guarded.lin":2:5)
    %nu2 = arith.cmpf uno, %nr2, %nr2 : f64 loc("tests/codegen/a_float_division_is_not_guarded.lin":2:5)
    %nq2 = arith.constant 0x7FF8000000000000 : f64 loc("tests/codegen/a_float_division_is_not_guarded.lin":2:5)
    %v2 = arith.select %nu2, %nq2, %nr2 : f64 loc("tests/codegen/a_float_division_is_not_guarded.lin":2:5)
    func.return %v2 : f64 loc("tests/codegen/a_float_division_is_not_guarded.lin":2:5)
  }
  func.func @main(%argc: i32, %argv: !llvm.ptr) -> i32 {
    func.call @linea_set_args(%argc, %argv) : (i32, !llvm.ptr) -> ()
    %status = func.call @"lin.;main"() : () -> i64
    %status32 = arith.trunci %status : i64 to i32
    func.return %status32 : i32
  }
}
