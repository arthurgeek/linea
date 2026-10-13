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
  llvm.mlir.global internal constant @linea_file0("tests/control/loop_yields_through_break.lin\00") : !llvm.array<44 x i8>
  func.func private @linea_set_args(i32, !llvm.ptr)
  func.func private @linea_trap(i32, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @linea_panic(i64, i64, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @"lin.;main"() -> i64 attributes {llvm.linkage = #llvm.linkage<internal>} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 1 : i64
    %s1 = llvm.alloca %z1 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z2 = arith.constant 1 : i64
    %s2 = llvm.alloca %z2 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    cf.br ^b0
  ^b0:
    %v0 = arith.constant 0 : i64 loc("tests/control/loop_yields_through_break.lin":2:20)
    %sw1 = arith.trunci %v0 : i64 to i8 loc("tests/control/loop_yields_through_break.lin":2:5)
    llvm.store %sw1, %s0 : i8, !llvm.ptr loc("tests/control/loop_yields_through_break.lin":2:5)
    cf.br ^b1 loc("tests/control/loop_yields_through_break.lin":3:24)
  ^b1:
    %lw3 = llvm.load %s0 : !llvm.ptr -> i8 loc("tests/control/loop_yields_through_break.lin":4:13)
    %v3 = arith.extui %lw3 : i8 to i64 loc("tests/control/loop_yields_through_break.lin":4:13)
    %v4 = arith.constant 1 : i64 loc("tests/control/loop_yields_through_break.lin":4:17)
    %v5 = arith.addi %v3, %v4 : i64 loc("tests/control/loop_yields_through_break.lin":4:13)
    %k1m = arith.constant 255 : i64 loc("tests/control/loop_yields_through_break.lin":4:15)
    %k1 = arith.cmpi ugt, %v5, %k1m : i64 loc("tests/control/loop_yields_through_break.lin":4:15)
    cf.cond_br %k1, ^t1, ^c1 loc("tests/control/loop_yields_through_break.lin":4:15)
  ^t1:
    %tk1 = arith.constant 0 : i32 loc("tests/control/loop_yields_through_break.lin":4:15)
    %tf1 = llvm.mlir.addressof @linea_file0 : !llvm.ptr loc("tests/control/loop_yields_through_break.lin":4:15)
    %tl1 = arith.constant 4 : i32 loc("tests/control/loop_yields_through_break.lin":4:15)
    %tc1 = arith.constant 15 : i32 loc("tests/control/loop_yields_through_break.lin":4:15)
    func.call @linea_trap(%tk1, %tf1, %tl1, %tc1) : (i32, !llvm.ptr, i32, i32) -> () loc("tests/control/loop_yields_through_break.lin":4:15)
    llvm.unreachable loc("tests/control/loop_yields_through_break.lin":4:15)
  ^c1:
    %p6 = arith.constant 0 : i64 loc("tests/control/loop_yields_through_break.lin":4:15)
    %v6 = arith.addi %v5, %p6 : i64 loc("tests/control/loop_yields_through_break.lin":4:15)
    %sw7 = arith.trunci %v6 : i64 to i8 loc("tests/control/loop_yields_through_break.lin":4:9)
    llvm.store %sw7, %s0 : i8, !llvm.ptr loc("tests/control/loop_yields_through_break.lin":4:9)
    %v8 = arith.constant 0 : i64 loc("tests/control/loop_yields_through_break.lin":4:9)
    %lw9 = llvm.load %s0 : !llvm.ptr -> i8 loc("tests/control/loop_yields_through_break.lin":5:12)
    %v9 = arith.extui %lw9 : i8 to i64 loc("tests/control/loop_yields_through_break.lin":5:12)
    %v10 = arith.constant 5 : i64 loc("tests/control/loop_yields_through_break.lin":5:16)
    %v11 = arith.cmpi ugt, %v9, %v10 : i64 loc("tests/control/loop_yields_through_break.lin":5:12)
    cf.cond_br %v11, ^b3, ^b4 loc("tests/control/loop_yields_through_break.lin":5:9)
  ^b2:
    %lw21 = llvm.load %s2 : !llvm.ptr -> i8 loc("tests/control/loop_yields_through_break.lin":3:24)
    %v21 = arith.extui %lw21 : i8 to i64 loc("tests/control/loop_yields_through_break.lin":3:24)
    %sw22 = arith.trunci %v21 : i64 to i8 loc("tests/control/loop_yields_through_break.lin":3:5)
    llvm.store %sw22, %s1 : i8, !llvm.ptr loc("tests/control/loop_yields_through_break.lin":3:5)
    %lw23 = llvm.load %s1 : !llvm.ptr -> i8 loc("tests/control/loop_yields_through_break.lin":9:5)
    %v23 = arith.extui %lw23 : i8 to i64 loc("tests/control/loop_yields_through_break.lin":9:5)
    func.return %v23 : i64 loc("tests/control/loop_yields_through_break.lin":9:5)
  ^b3:
    %lw13 = llvm.load %s0 : !llvm.ptr -> i8 loc("tests/control/loop_yields_through_break.lin":6:19)
    %v13 = arith.extui %lw13 : i8 to i64 loc("tests/control/loop_yields_through_break.lin":6:19)
    %sw14 = arith.trunci %v13 : i64 to i8 loc("tests/control/loop_yields_through_break.lin":6:13)
    llvm.store %sw14, %s2 : i8, !llvm.ptr loc("tests/control/loop_yields_through_break.lin":6:13)
    cf.br ^b2 loc("tests/control/loop_yields_through_break.lin":6:13)
  ^b4:
    cf.br ^b5 loc("tests/control/loop_yields_through_break.lin":5:9)
  ^b5:
    %v19 = arith.constant 0 : i64 loc("tests/control/loop_yields_through_break.lin":5:9)
    cf.br ^b1 loc("tests/control/loop_yields_through_break.lin":3:24)
  }
  func.func @main(%argc: i32, %argv: !llvm.ptr) -> i32 {
    func.call @linea_set_args(%argc, %argv) : (i32, !llvm.ptr) -> ()
    %status = func.call @"lin.;main"() : () -> i64
    %status32 = arith.trunci %status : i64 to i32
    func.return %status32 : i32
  }
}
