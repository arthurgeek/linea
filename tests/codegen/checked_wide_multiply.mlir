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
  llvm.mlir.global internal constant @linea_file0("tests/codegen/checked_wide_multiply.lin\00") : !llvm.array<40 x i8>
  func.func private @linea_set_args(i32, !llvm.ptr)
  func.func private @linea_trap(i32, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @linea_panic(i64, i64, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @"lin.;main"() -> i64 attributes {llvm.linkage = #llvm.linkage<internal>} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 1 : i64
    %s1 = llvm.alloca %z1 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    cf.br ^b0
  ^b0:
    %v0 = arith.constant 3 : i64 loc("tests/codegen/checked_wide_multiply.lin":2:20)
    llvm.store %v0, %s0 : i64, !llvm.ptr loc("tests/codegen/checked_wide_multiply.lin":2:5)
    %v2 = arith.constant 4 : i64 loc("tests/codegen/checked_wide_multiply.lin":3:20)
    llvm.store %v2, %s1 : i64, !llvm.ptr loc("tests/codegen/checked_wide_multiply.lin":3:5)
    %v4 = llvm.load %s0 : !llvm.ptr -> i64 loc("tests/codegen/checked_wide_multiply.lin":4:11)
    %v5 = llvm.load %s1 : !llvm.ptr -> i64 loc("tests/codegen/checked_wide_multiply.lin":4:15)
    %m6 = "llvm.intr.smul.with.overflow"(%v4, %v5) : (i64, i64) -> !llvm.struct<(i64, i1)> loc("tests/codegen/checked_wide_multiply.lin":4:11)
    %v6 = llvm.extractvalue %m6[0] : !llvm.struct<(i64, i1)> loc("tests/codegen/checked_wide_multiply.lin":4:11)
    %k1 = llvm.extractvalue %m6[1] : !llvm.struct<(i64, i1)> loc("tests/codegen/checked_wide_multiply.lin":4:13)
    cf.cond_br %k1, ^t1, ^c1 loc("tests/codegen/checked_wide_multiply.lin":4:13)
  ^t1:
    %tk1 = arith.constant 0 : i32 loc("tests/codegen/checked_wide_multiply.lin":4:13)
    %tf1 = llvm.mlir.addressof @linea_file0 : !llvm.ptr loc("tests/codegen/checked_wide_multiply.lin":4:13)
    %tl1 = arith.constant 4 : i32 loc("tests/codegen/checked_wide_multiply.lin":4:13)
    %tc1 = arith.constant 13 : i32 loc("tests/codegen/checked_wide_multiply.lin":4:13)
    func.call @linea_trap(%tk1, %tf1, %tl1, %tc1) : (i32, !llvm.ptr, i32, i32) -> () loc("tests/codegen/checked_wide_multiply.lin":4:13)
    llvm.unreachable loc("tests/codegen/checked_wide_multiply.lin":4:13)
  ^c1:
    %p7 = arith.constant 0 : i64 loc("tests/codegen/checked_wide_multiply.lin":4:13)
    %v7 = arith.addi %v6, %p7 : i64 loc("tests/codegen/checked_wide_multiply.lin":4:13)
    %k2m = arith.constant 255 : i64 loc("tests/codegen/checked_wide_multiply.lin":4:5)
    %k2 = arith.cmpi ugt, %v7, %k2m : i64 loc("tests/codegen/checked_wide_multiply.lin":4:5)
    cf.cond_br %k2, ^t2, ^c2 loc("tests/codegen/checked_wide_multiply.lin":4:5)
  ^t2:
    %tk2 = arith.constant 2 : i32 loc("tests/codegen/checked_wide_multiply.lin":4:5)
    %tf2 = llvm.mlir.addressof @linea_file0 : !llvm.ptr loc("tests/codegen/checked_wide_multiply.lin":4:5)
    %tl2 = arith.constant 4 : i32 loc("tests/codegen/checked_wide_multiply.lin":4:5)
    %tc2 = arith.constant 5 : i32 loc("tests/codegen/checked_wide_multiply.lin":4:5)
    func.call @linea_trap(%tk2, %tf2, %tl2, %tc2) : (i32, !llvm.ptr, i32, i32) -> () loc("tests/codegen/checked_wide_multiply.lin":4:5)
    llvm.unreachable loc("tests/codegen/checked_wide_multiply.lin":4:5)
  ^c2:
    %p8 = arith.constant 0 : i64 loc("tests/codegen/checked_wide_multiply.lin":4:5)
    %v8 = arith.addi %v7, %p8 : i64 loc("tests/codegen/checked_wide_multiply.lin":4:5)
    func.return %v8 : i64 loc("tests/codegen/checked_wide_multiply.lin":4:5)
  }
  func.func @main(%argc: i32, %argv: !llvm.ptr) -> i32 {
    func.call @linea_set_args(%argc, %argv) : (i32, !llvm.ptr) -> ()
    %status = func.call @"lin.;main"() : () -> i64
    %status32 = arith.trunci %status : i64 to i32
    func.return %status32 : i32
  }
}
