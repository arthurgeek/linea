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
  llvm.mlir.global internal constant @linea_file0("tests/codegen/checked_wide_divide.lin\00") : !llvm.array<38 x i8>
  func.func private @linea_set_args(i32, !llvm.ptr)
  func.func private @linea_trap(i32, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @linea_panic(i64, i64, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @"lin.;main"() -> i64 attributes {llvm.linkage = #llvm.linkage<internal>, passthrough = [["probe-stack", "inline-asm"]]} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 1 : i64
    %s1 = llvm.alloca %z1 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    cf.br ^b0
  ^b0:
    %v0 = arith.constant 100 : i64 loc("tests/codegen/checked_wide_divide.lin":2:20)
    llvm.store %v0, %s0 : i64, !llvm.ptr loc("tests/codegen/checked_wide_divide.lin":2:5)
    %v2 = arith.constant 5 : i64 loc("tests/codegen/checked_wide_divide.lin":3:20)
    llvm.store %v2, %s1 : i64, !llvm.ptr loc("tests/codegen/checked_wide_divide.lin":3:5)
    %v4 = llvm.load %s0 : !llvm.ptr -> i64 loc("tests/codegen/checked_wide_divide.lin":4:11)
    %v5 = llvm.load %s1 : !llvm.ptr -> i64 loc("tests/codegen/checked_wide_divide.lin":4:15)
    %k1z = arith.constant 0 : i64 loc("tests/codegen/checked_wide_divide.lin":4:13)
    %k1 = arith.cmpi eq, %v5, %k1z : i64 loc("tests/codegen/checked_wide_divide.lin":4:13)
    cf.cond_br %k1, ^t1, ^c1 loc("tests/codegen/checked_wide_divide.lin":4:13)
  ^t1:
    %tk1 = arith.constant 1 : i32 loc("tests/codegen/checked_wide_divide.lin":4:13)
    %tf1 = llvm.mlir.addressof @linea_file0 : !llvm.ptr loc("tests/codegen/checked_wide_divide.lin":4:13)
    %tl1 = arith.constant 4 : i32 loc("tests/codegen/checked_wide_divide.lin":4:13)
    %tc1 = arith.constant 13 : i32 loc("tests/codegen/checked_wide_divide.lin":4:13)
    func.call @linea_trap(%tk1, %tf1, %tl1, %tc1) : (i32, !llvm.ptr, i32, i32) -> () loc("tests/codegen/checked_wide_divide.lin":4:13)
    llvm.unreachable loc("tests/codegen/checked_wide_divide.lin":4:13)
  ^c1:
    %p6 = arith.constant 0 : i64 loc("tests/codegen/checked_wide_divide.lin":4:13)
    %v6 = arith.addi %v5, %p6 : i64 loc("tests/codegen/checked_wide_divide.lin":4:13)
    %k2ca = arith.constant -9223372036854775808 : i64 loc("tests/codegen/checked_wide_divide.lin":4:11)
    %k2a = arith.cmpi eq, %v4, %k2ca : i64 loc("tests/codegen/checked_wide_divide.lin":4:11)
    %k2cb = arith.constant -1 : i64 loc("tests/codegen/checked_wide_divide.lin":4:11)
    %k2b = arith.cmpi eq, %v6, %k2cb : i64 loc("tests/codegen/checked_wide_divide.lin":4:11)
    %k2 = arith.andi %k2a, %k2b : i1 loc("tests/codegen/checked_wide_divide.lin":4:11)
    cf.cond_br %k2, ^t2, ^c2 loc("tests/codegen/checked_wide_divide.lin":4:11)
  ^t2:
    %tk2 = arith.constant 0 : i32 loc("tests/codegen/checked_wide_divide.lin":4:11)
    %tf2 = llvm.mlir.addressof @linea_file0 : !llvm.ptr loc("tests/codegen/checked_wide_divide.lin":4:11)
    %tl2 = arith.constant 4 : i32 loc("tests/codegen/checked_wide_divide.lin":4:11)
    %tc2 = arith.constant 11 : i32 loc("tests/codegen/checked_wide_divide.lin":4:11)
    func.call @linea_trap(%tk2, %tf2, %tl2, %tc2) : (i32, !llvm.ptr, i32, i32) -> () loc("tests/codegen/checked_wide_divide.lin":4:11)
    llvm.unreachable loc("tests/codegen/checked_wide_divide.lin":4:11)
  ^c2:
    %v7 = arith.divsi %v4, %v6 : i64 loc("tests/codegen/checked_wide_divide.lin":4:11)
    %p8 = arith.constant 0 : i64 loc("tests/codegen/checked_wide_divide.lin":4:13)
    %v8 = arith.addi %v7, %p8 : i64 loc("tests/codegen/checked_wide_divide.lin":4:13)
    %k3m = arith.constant 255 : i64 loc("tests/codegen/checked_wide_divide.lin":4:5)
    %k3 = arith.cmpi ugt, %v8, %k3m : i64 loc("tests/codegen/checked_wide_divide.lin":4:5)
    cf.cond_br %k3, ^t3, ^c3 loc("tests/codegen/checked_wide_divide.lin":4:5)
  ^t3:
    %tk3 = arith.constant 2 : i32 loc("tests/codegen/checked_wide_divide.lin":4:5)
    %tf3 = llvm.mlir.addressof @linea_file0 : !llvm.ptr loc("tests/codegen/checked_wide_divide.lin":4:5)
    %tl3 = arith.constant 4 : i32 loc("tests/codegen/checked_wide_divide.lin":4:5)
    %tc3 = arith.constant 5 : i32 loc("tests/codegen/checked_wide_divide.lin":4:5)
    func.call @linea_trap(%tk3, %tf3, %tl3, %tc3) : (i32, !llvm.ptr, i32, i32) -> () loc("tests/codegen/checked_wide_divide.lin":4:5)
    llvm.unreachable loc("tests/codegen/checked_wide_divide.lin":4:5)
  ^c3:
    %p9 = arith.constant 0 : i64 loc("tests/codegen/checked_wide_divide.lin":4:5)
    %v9 = arith.addi %v8, %p9 : i64 loc("tests/codegen/checked_wide_divide.lin":4:5)
    func.return %v9 : i64 loc("tests/codegen/checked_wide_divide.lin":4:5)
  }
  func.func @main(%argc: i32, %argv: !llvm.ptr) -> i32 {
    func.call @linea_set_args(%argc, %argv) : (i32, !llvm.ptr) -> ()
    %status = func.call @"lin.;main"() : () -> i64
    %status32 = arith.trunci %status : i64 to i32
    func.return %status32 : i32
  }
}
