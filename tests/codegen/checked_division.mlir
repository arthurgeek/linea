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
  llvm.mlir.global internal constant @linea_file0("tests/codegen/checked_division.lin\00") : !llvm.array<35 x i8>
  func.func private @linea_set_args(i32, !llvm.ptr)
  func.func private @linea_trap(i32, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @linea_panic(i64, i64, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @"lin.;main"() -> i64 attributes {llvm.linkage = #llvm.linkage<internal>, passthrough = [["probe-stack", "inline-asm"]]} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 1 : i64
    %s1 = llvm.alloca %z1 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    cf.br ^b0
  ^b0:
    %v0 = arith.constant 60 : i64 loc("tests/codegen/checked_division.lin":2:20)
    %sw1 = arith.trunci %v0 : i64 to i8 loc("tests/codegen/checked_division.lin":2:5)
    llvm.store %sw1, %s0 : i8, !llvm.ptr loc("tests/codegen/checked_division.lin":2:5)
    %v2 = arith.constant 4 : i64 loc("tests/codegen/checked_division.lin":3:20)
    %sw3 = arith.trunci %v2 : i64 to i8 loc("tests/codegen/checked_division.lin":3:5)
    llvm.store %sw3, %s1 : i8, !llvm.ptr loc("tests/codegen/checked_division.lin":3:5)
    %lw4 = llvm.load %s0 : !llvm.ptr -> i8 loc("tests/codegen/checked_division.lin":4:5)
    %v4 = arith.extui %lw4 : i8 to i64 loc("tests/codegen/checked_division.lin":4:5)
    %lw5 = llvm.load %s1 : !llvm.ptr -> i8 loc("tests/codegen/checked_division.lin":4:9)
    %v5 = arith.extui %lw5 : i8 to i64 loc("tests/codegen/checked_division.lin":4:9)
    %k1z = arith.constant 0 : i64 loc("tests/codegen/checked_division.lin":4:7)
    %k1 = arith.cmpi eq, %v5, %k1z : i64 loc("tests/codegen/checked_division.lin":4:7)
    cf.cond_br %k1, ^t1, ^c1 loc("tests/codegen/checked_division.lin":4:7)
  ^t1:
    %tk1 = arith.constant 1 : i32 loc("tests/codegen/checked_division.lin":4:7)
    %tf1 = llvm.mlir.addressof @linea_file0 : !llvm.ptr loc("tests/codegen/checked_division.lin":4:7)
    %tl1 = arith.constant 4 : i32 loc("tests/codegen/checked_division.lin":4:7)
    %tc1 = arith.constant 7 : i32 loc("tests/codegen/checked_division.lin":4:7)
    func.call @linea_trap(%tk1, %tf1, %tl1, %tc1) : (i32, !llvm.ptr, i32, i32) -> () loc("tests/codegen/checked_division.lin":4:7)
    llvm.unreachable loc("tests/codegen/checked_division.lin":4:7)
  ^c1:
    %p6 = arith.constant 0 : i64 loc("tests/codegen/checked_division.lin":4:7)
    %v6 = arith.addi %v5, %p6 : i64 loc("tests/codegen/checked_division.lin":4:7)
    %v7 = arith.divsi %v4, %v6 : i64 loc("tests/codegen/checked_division.lin":4:5)
    %k2m = arith.constant 255 : i64 loc("tests/codegen/checked_division.lin":4:7)
    %k2 = arith.cmpi ugt, %v7, %k2m : i64 loc("tests/codegen/checked_division.lin":4:7)
    cf.cond_br %k2, ^t2, ^c2 loc("tests/codegen/checked_division.lin":4:7)
  ^t2:
    %tk2 = arith.constant 0 : i32 loc("tests/codegen/checked_division.lin":4:7)
    %tf2 = llvm.mlir.addressof @linea_file0 : !llvm.ptr loc("tests/codegen/checked_division.lin":4:7)
    %tl2 = arith.constant 4 : i32 loc("tests/codegen/checked_division.lin":4:7)
    %tc2 = arith.constant 7 : i32 loc("tests/codegen/checked_division.lin":4:7)
    func.call @linea_trap(%tk2, %tf2, %tl2, %tc2) : (i32, !llvm.ptr, i32, i32) -> () loc("tests/codegen/checked_division.lin":4:7)
    llvm.unreachable loc("tests/codegen/checked_division.lin":4:7)
  ^c2:
    %p8 = arith.constant 0 : i64 loc("tests/codegen/checked_division.lin":4:7)
    %v8 = arith.addi %v7, %p8 : i64 loc("tests/codegen/checked_division.lin":4:7)
    func.return %v8 : i64 loc("tests/codegen/checked_division.lin":4:5)
  }
  func.func @main(%argc: i32, %argv: !llvm.ptr) -> i32 {
    func.call @linea_set_args(%argc, %argv) : (i32, !llvm.ptr) -> ()
    %status = func.call @"lin.;main"() : () -> i64
    %status32 = arith.trunci %status : i64 to i32
    func.return %status32 : i32
  }
}
