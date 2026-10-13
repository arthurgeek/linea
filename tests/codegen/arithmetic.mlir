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
  llvm.mlir.global internal constant @linea_file0("tests/codegen/arithmetic.lin\00") : !llvm.array<29 x i8>
  func.func private @linea_set_args(i32, !llvm.ptr)
  func.func private @linea_trap(i32, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @linea_panic(i64, i64, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @"lin.;main"() -> i64 attributes {llvm.linkage = #llvm.linkage<internal>} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 1 : i64
    %s1 = llvm.alloca %z1 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    cf.br ^b0
  ^b0:
    %v0 = arith.constant 20 : i64 loc("tests/codegen/arithmetic.lin":2:20)
    %sw1 = arith.trunci %v0 : i64 to i8 loc("tests/codegen/arithmetic.lin":2:5)
    llvm.store %sw1, %s0 : i8, !llvm.ptr loc("tests/codegen/arithmetic.lin":2:5)
    %v2 = arith.constant 3 : i64 loc("tests/codegen/arithmetic.lin":3:20)
    %sw3 = arith.trunci %v2 : i64 to i8 loc("tests/codegen/arithmetic.lin":3:5)
    llvm.store %sw3, %s1 : i8, !llvm.ptr loc("tests/codegen/arithmetic.lin":3:5)
    %lw4 = llvm.load %s0 : !llvm.ptr -> i8 loc("tests/codegen/arithmetic.lin":4:5)
    %v4 = arith.extui %lw4 : i8 to i64 loc("tests/codegen/arithmetic.lin":4:5)
    %lw5 = llvm.load %s1 : !llvm.ptr -> i8 loc("tests/codegen/arithmetic.lin":4:9)
    %v5 = arith.extui %lw5 : i8 to i64 loc("tests/codegen/arithmetic.lin":4:9)
    %v6 = arith.muli %v4, %v5 : i64 loc("tests/codegen/arithmetic.lin":4:5)
    %k1m = arith.constant 255 : i64 loc("tests/codegen/arithmetic.lin":4:7)
    %k1 = arith.cmpi ugt, %v6, %k1m : i64 loc("tests/codegen/arithmetic.lin":4:7)
    cf.cond_br %k1, ^t1, ^c1 loc("tests/codegen/arithmetic.lin":4:7)
  ^t1:
    %tk1 = arith.constant 0 : i32 loc("tests/codegen/arithmetic.lin":4:7)
    %tf1 = llvm.mlir.addressof @linea_file0 : !llvm.ptr loc("tests/codegen/arithmetic.lin":4:7)
    %tl1 = arith.constant 4 : i32 loc("tests/codegen/arithmetic.lin":4:7)
    %tc1 = arith.constant 7 : i32 loc("tests/codegen/arithmetic.lin":4:7)
    func.call @linea_trap(%tk1, %tf1, %tl1, %tc1) : (i32, !llvm.ptr, i32, i32) -> () loc("tests/codegen/arithmetic.lin":4:7)
    llvm.unreachable loc("tests/codegen/arithmetic.lin":4:7)
  ^c1:
    %p7 = arith.constant 0 : i64 loc("tests/codegen/arithmetic.lin":4:7)
    %v7 = arith.addi %v6, %p7 : i64 loc("tests/codegen/arithmetic.lin":4:7)
    %v8 = arith.constant 4 : i64 loc("tests/codegen/arithmetic.lin":4:13)
    %k2z = arith.constant 0 : i64 loc("tests/codegen/arithmetic.lin":4:11)
    %k2 = arith.cmpi eq, %v8, %k2z : i64 loc("tests/codegen/arithmetic.lin":4:11)
    cf.cond_br %k2, ^t2, ^c2 loc("tests/codegen/arithmetic.lin":4:11)
  ^t2:
    %tk2 = arith.constant 1 : i32 loc("tests/codegen/arithmetic.lin":4:11)
    %tf2 = llvm.mlir.addressof @linea_file0 : !llvm.ptr loc("tests/codegen/arithmetic.lin":4:11)
    %tl2 = arith.constant 4 : i32 loc("tests/codegen/arithmetic.lin":4:11)
    %tc2 = arith.constant 11 : i32 loc("tests/codegen/arithmetic.lin":4:11)
    func.call @linea_trap(%tk2, %tf2, %tl2, %tc2) : (i32, !llvm.ptr, i32, i32) -> () loc("tests/codegen/arithmetic.lin":4:11)
    llvm.unreachable loc("tests/codegen/arithmetic.lin":4:11)
  ^c2:
    %p9 = arith.constant 0 : i64 loc("tests/codegen/arithmetic.lin":4:11)
    %v9 = arith.addi %v8, %p9 : i64 loc("tests/codegen/arithmetic.lin":4:11)
    %v10 = arith.divsi %v7, %v9 : i64 loc("tests/codegen/arithmetic.lin":4:5)
    %k3m = arith.constant 255 : i64 loc("tests/codegen/arithmetic.lin":4:11)
    %k3 = arith.cmpi ugt, %v10, %k3m : i64 loc("tests/codegen/arithmetic.lin":4:11)
    cf.cond_br %k3, ^t3, ^c3 loc("tests/codegen/arithmetic.lin":4:11)
  ^t3:
    %tk3 = arith.constant 0 : i32 loc("tests/codegen/arithmetic.lin":4:11)
    %tf3 = llvm.mlir.addressof @linea_file0 : !llvm.ptr loc("tests/codegen/arithmetic.lin":4:11)
    %tl3 = arith.constant 4 : i32 loc("tests/codegen/arithmetic.lin":4:11)
    %tc3 = arith.constant 11 : i32 loc("tests/codegen/arithmetic.lin":4:11)
    func.call @linea_trap(%tk3, %tf3, %tl3, %tc3) : (i32, !llvm.ptr, i32, i32) -> () loc("tests/codegen/arithmetic.lin":4:11)
    llvm.unreachable loc("tests/codegen/arithmetic.lin":4:11)
  ^c3:
    %p11 = arith.constant 0 : i64 loc("tests/codegen/arithmetic.lin":4:11)
    %v11 = arith.addi %v10, %p11 : i64 loc("tests/codegen/arithmetic.lin":4:11)
    %v12 = arith.constant 5 : i64 loc("tests/codegen/arithmetic.lin":4:17)
    %v13 = arith.subi %v11, %v12 : i64 loc("tests/codegen/arithmetic.lin":4:5)
    %k4m = arith.constant 255 : i64 loc("tests/codegen/arithmetic.lin":4:15)
    %k4 = arith.cmpi ugt, %v13, %k4m : i64 loc("tests/codegen/arithmetic.lin":4:15)
    cf.cond_br %k4, ^t4, ^c4 loc("tests/codegen/arithmetic.lin":4:15)
  ^t4:
    %tk4 = arith.constant 0 : i32 loc("tests/codegen/arithmetic.lin":4:15)
    %tf4 = llvm.mlir.addressof @linea_file0 : !llvm.ptr loc("tests/codegen/arithmetic.lin":4:15)
    %tl4 = arith.constant 4 : i32 loc("tests/codegen/arithmetic.lin":4:15)
    %tc4 = arith.constant 15 : i32 loc("tests/codegen/arithmetic.lin":4:15)
    func.call @linea_trap(%tk4, %tf4, %tl4, %tc4) : (i32, !llvm.ptr, i32, i32) -> () loc("tests/codegen/arithmetic.lin":4:15)
    llvm.unreachable loc("tests/codegen/arithmetic.lin":4:15)
  ^c4:
    %p14 = arith.constant 0 : i64 loc("tests/codegen/arithmetic.lin":4:15)
    %v14 = arith.addi %v13, %p14 : i64 loc("tests/codegen/arithmetic.lin":4:15)
    %v15 = arith.constant 1 : i64 loc("tests/codegen/arithmetic.lin":4:21)
    %v16 = arith.addi %v14, %v15 : i64 loc("tests/codegen/arithmetic.lin":4:5)
    %k5m = arith.constant 255 : i64 loc("tests/codegen/arithmetic.lin":4:19)
    %k5 = arith.cmpi ugt, %v16, %k5m : i64 loc("tests/codegen/arithmetic.lin":4:19)
    cf.cond_br %k5, ^t5, ^c5 loc("tests/codegen/arithmetic.lin":4:19)
  ^t5:
    %tk5 = arith.constant 0 : i32 loc("tests/codegen/arithmetic.lin":4:19)
    %tf5 = llvm.mlir.addressof @linea_file0 : !llvm.ptr loc("tests/codegen/arithmetic.lin":4:19)
    %tl5 = arith.constant 4 : i32 loc("tests/codegen/arithmetic.lin":4:19)
    %tc5 = arith.constant 19 : i32 loc("tests/codegen/arithmetic.lin":4:19)
    func.call @linea_trap(%tk5, %tf5, %tl5, %tc5) : (i32, !llvm.ptr, i32, i32) -> () loc("tests/codegen/arithmetic.lin":4:19)
    llvm.unreachable loc("tests/codegen/arithmetic.lin":4:19)
  ^c5:
    %p17 = arith.constant 0 : i64 loc("tests/codegen/arithmetic.lin":4:19)
    %v17 = arith.addi %v16, %p17 : i64 loc("tests/codegen/arithmetic.lin":4:19)
    func.return %v17 : i64 loc("tests/codegen/arithmetic.lin":4:5)
  }
  func.func @main(%argc: i32, %argv: !llvm.ptr) -> i32 {
    func.call @linea_set_args(%argc, %argv) : (i32, !llvm.ptr) -> ()
    %status = func.call @"lin.;main"() : () -> i64
    %status32 = arith.trunci %status : i64 to i32
    func.return %status32 : i32
  }
}
