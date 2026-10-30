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
  llvm.mlir.global internal constant @linea_file0("tests/codegen/a_float_is_held_in_d.lin\00") : !llvm.array<39 x i8>
  func.func private @linea_set_args(i32, !llvm.ptr)
  func.func private @linea_trap(i32, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @linea_panic(i64, i64, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @"lin.;main"() -> i64 attributes {llvm.linkage = #llvm.linkage<internal>, passthrough = [["probe-stack", "inline-asm"]]} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x f64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 1 : i64
    %s1 = llvm.alloca %z1 x f64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    cf.br ^b0
  ^b0:
    %v0 = arith.constant 0x3FF8000000000000 : f64 loc("tests/codegen/a_float_is_held_in_d.lin":6:22)
    llvm.store %v0, %s0 : f64, !llvm.ptr loc("tests/codegen/a_float_is_held_in_d.lin":6:5)
    %v2 = llvm.load %s0 : !llvm.ptr -> f64 loc("tests/codegen/a_float_is_held_in_d.lin":7:23)
    %v3 = func.call @"lin.;identity"(%v2) : (f64) -> f64 loc("tests/codegen/a_float_is_held_in_d.lin":7:14)
    llvm.store %v3, %s1 : f64, !llvm.ptr loc("tests/codegen/a_float_is_held_in_d.lin":7:5)
    %v5 = arith.constant 0 : i64 loc("tests/codegen/a_float_is_held_in_d.lin":8:5)
    func.return %v5 : i64 loc("tests/codegen/a_float_is_held_in_d.lin":8:5)
  }
  func.func private @"lin.;identity"(%a0: f64) -> f64 attributes {llvm.linkage = #llvm.linkage<internal>, passthrough = [["probe-stack", "inline-asm"]]} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x f64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    llvm.store %a0, %s0 : f64, !llvm.ptr
    cf.br ^b0
  ^b0:
    %v0 = llvm.load %s0 : !llvm.ptr -> f64 loc("tests/codegen/a_float_is_held_in_d.lin":2:5)
    func.return %v0 : f64 loc("tests/codegen/a_float_is_held_in_d.lin":2:5)
  }
  func.func @main(%argc: i32, %argv: !llvm.ptr) -> i32 {
    func.call @linea_set_args(%argc, %argv) : (i32, !llvm.ptr) -> ()
    %status = func.call @"lin.;main"() : () -> i64
    %status32 = arith.trunci %status : i64 to i32
    func.return %status32 : i32
  }
}
