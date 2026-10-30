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
  llvm.mlir.global internal constant @linea_file0("tests/control/while_accumulates.lin\00") : !llvm.array<36 x i8>
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
    %v0 = arith.constant 0 : i64 loc("tests/control/while_accumulates.lin":2:24)
    %sw1 = arith.trunci %v0 : i64 to i8 loc("tests/control/while_accumulates.lin":2:5)
    llvm.store %sw1, %s0 : i8, !llvm.ptr loc("tests/control/while_accumulates.lin":2:5)
    %v2 = arith.constant 0 : i64 loc("tests/control/while_accumulates.lin":3:20)
    %sw3 = arith.trunci %v2 : i64 to i8 loc("tests/control/while_accumulates.lin":3:5)
    llvm.store %sw3, %s1 : i8, !llvm.ptr loc("tests/control/while_accumulates.lin":3:5)
    cf.br ^b1 loc("tests/control/while_accumulates.lin":4:5)
  ^b1:
    %lw5 = llvm.load %s1 : !llvm.ptr -> i8 loc("tests/control/while_accumulates.lin":4:11)
    %v5 = arith.extui %lw5 : i8 to i64 loc("tests/control/while_accumulates.lin":4:11)
    %v6 = arith.constant 5 : i64 loc("tests/control/while_accumulates.lin":4:15)
    %v7 = arith.cmpi ult, %v5, %v6 : i64 loc("tests/control/while_accumulates.lin":4:11)
    cf.cond_br %v7, ^b2, ^b3 loc("tests/control/while_accumulates.lin":4:5)
  ^b2:
    %lw9 = llvm.load %s0 : !llvm.ptr -> i8 loc("tests/control/while_accumulates.lin":5:17)
    %v9 = arith.extui %lw9 : i8 to i64 loc("tests/control/while_accumulates.lin":5:17)
    %lw10 = llvm.load %s1 : !llvm.ptr -> i8 loc("tests/control/while_accumulates.lin":5:25)
    %v10 = arith.extui %lw10 : i8 to i64 loc("tests/control/while_accumulates.lin":5:25)
    %v11 = arith.addi %v9, %v10 : i64 loc("tests/control/while_accumulates.lin":5:17)
    %k1m = arith.constant 255 : i64 loc("tests/control/while_accumulates.lin":5:23)
    %k1 = arith.cmpi ugt, %v11, %k1m : i64 loc("tests/control/while_accumulates.lin":5:23)
    cf.cond_br %k1, ^t1, ^c1 loc("tests/control/while_accumulates.lin":5:23)
  ^t1:
    %tk1 = arith.constant 0 : i32 loc("tests/control/while_accumulates.lin":5:23)
    %tf1 = llvm.mlir.addressof @linea_file0 : !llvm.ptr loc("tests/control/while_accumulates.lin":5:23)
    %tl1 = arith.constant 5 : i32 loc("tests/control/while_accumulates.lin":5:23)
    %tc1 = arith.constant 23 : i32 loc("tests/control/while_accumulates.lin":5:23)
    func.call @linea_trap(%tk1, %tf1, %tl1, %tc1) : (i32, !llvm.ptr, i32, i32) -> () loc("tests/control/while_accumulates.lin":5:23)
    llvm.unreachable loc("tests/control/while_accumulates.lin":5:23)
  ^c1:
    %p12 = arith.constant 0 : i64 loc("tests/control/while_accumulates.lin":5:23)
    %v12 = arith.addi %v11, %p12 : i64 loc("tests/control/while_accumulates.lin":5:23)
    %sw13 = arith.trunci %v12 : i64 to i8 loc("tests/control/while_accumulates.lin":5:9)
    llvm.store %sw13, %s0 : i8, !llvm.ptr loc("tests/control/while_accumulates.lin":5:9)
    %v14 = arith.constant 0 : i64 loc("tests/control/while_accumulates.lin":5:9)
    %lw15 = llvm.load %s1 : !llvm.ptr -> i8 loc("tests/control/while_accumulates.lin":6:13)
    %v15 = arith.extui %lw15 : i8 to i64 loc("tests/control/while_accumulates.lin":6:13)
    %v16 = arith.constant 1 : i64 loc("tests/control/while_accumulates.lin":6:17)
    %v17 = arith.addi %v15, %v16 : i64 loc("tests/control/while_accumulates.lin":6:13)
    %k2m = arith.constant 255 : i64 loc("tests/control/while_accumulates.lin":6:15)
    %k2 = arith.cmpi ugt, %v17, %k2m : i64 loc("tests/control/while_accumulates.lin":6:15)
    cf.cond_br %k2, ^t2, ^c2 loc("tests/control/while_accumulates.lin":6:15)
  ^t2:
    %tk2 = arith.constant 0 : i32 loc("tests/control/while_accumulates.lin":6:15)
    %tf2 = llvm.mlir.addressof @linea_file0 : !llvm.ptr loc("tests/control/while_accumulates.lin":6:15)
    %tl2 = arith.constant 6 : i32 loc("tests/control/while_accumulates.lin":6:15)
    %tc2 = arith.constant 15 : i32 loc("tests/control/while_accumulates.lin":6:15)
    func.call @linea_trap(%tk2, %tf2, %tl2, %tc2) : (i32, !llvm.ptr, i32, i32) -> () loc("tests/control/while_accumulates.lin":6:15)
    llvm.unreachable loc("tests/control/while_accumulates.lin":6:15)
  ^c2:
    %p18 = arith.constant 0 : i64 loc("tests/control/while_accumulates.lin":6:15)
    %v18 = arith.addi %v17, %p18 : i64 loc("tests/control/while_accumulates.lin":6:15)
    %sw19 = arith.trunci %v18 : i64 to i8 loc("tests/control/while_accumulates.lin":6:9)
    llvm.store %sw19, %s1 : i8, !llvm.ptr loc("tests/control/while_accumulates.lin":6:9)
    %v20 = arith.constant 0 : i64 loc("tests/control/while_accumulates.lin":6:9)
    cf.br ^b1 loc("tests/control/while_accumulates.lin":4:5)
  ^b3:
    %v22 = arith.constant 0 : i64 loc("tests/control/while_accumulates.lin":4:5)
    %lw23 = llvm.load %s0 : !llvm.ptr -> i8 loc("tests/control/while_accumulates.lin":8:5)
    %v23 = arith.extui %lw23 : i8 to i64 loc("tests/control/while_accumulates.lin":8:5)
    func.return %v23 : i64 loc("tests/control/while_accumulates.lin":8:5)
  }
  func.func @main(%argc: i32, %argv: !llvm.ptr) -> i32 {
    func.call @linea_set_args(%argc, %argv) : (i32, !llvm.ptr) -> ()
    %status = func.call @"lin.;main"() : () -> i64
    %status32 = arith.trunci %status : i64 to i32
    func.return %status32 : i32
  }
}
