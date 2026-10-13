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
  llvm.mlir.global internal constant @linea_file0("tests/enums/match_returns_a_value.lin\00") : !llvm.array<38 x i8>
  func.func private @linea_set_args(i32, !llvm.ptr)
  func.func private @linea_trap(i32, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @linea_panic(i64, i64, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @"lin.;main"() -> i64 attributes {llvm.linkage = #llvm.linkage<internal>} {
    cf.br ^b0
  ^b0:
    %v0 = arith.constant 1 : i64 loc("tests/enums/match_returns_a_value.lin":12:11)
    %v1 = func.call @"lin.;sides"(%v0) : (i64) -> i64 loc("tests/enums/match_returns_a_value.lin":12:5)
    %v2 = arith.constant 2 : i64 loc("tests/enums/match_returns_a_value.lin":12:33)
    %v3 = func.call @"lin.;sides"(%v2) : (i64) -> i64 loc("tests/enums/match_returns_a_value.lin":12:27)
    %v4 = arith.addi %v1, %v3 : i64 loc("tests/enums/match_returns_a_value.lin":12:5)
    %k1m = arith.constant 255 : i64 loc("tests/enums/match_returns_a_value.lin":12:25)
    %k1 = arith.cmpi ugt, %v4, %k1m : i64 loc("tests/enums/match_returns_a_value.lin":12:25)
    cf.cond_br %k1, ^t1, ^c1 loc("tests/enums/match_returns_a_value.lin":12:25)
  ^t1:
    %tk1 = arith.constant 0 : i32 loc("tests/enums/match_returns_a_value.lin":12:25)
    %tf1 = llvm.mlir.addressof @linea_file0 : !llvm.ptr loc("tests/enums/match_returns_a_value.lin":12:25)
    %tl1 = arith.constant 12 : i32 loc("tests/enums/match_returns_a_value.lin":12:25)
    %tc1 = arith.constant 25 : i32 loc("tests/enums/match_returns_a_value.lin":12:25)
    func.call @linea_trap(%tk1, %tf1, %tl1, %tc1) : (i32, !llvm.ptr, i32, i32) -> () loc("tests/enums/match_returns_a_value.lin":12:25)
    llvm.unreachable loc("tests/enums/match_returns_a_value.lin":12:25)
  ^c1:
    %p5 = arith.constant 0 : i64 loc("tests/enums/match_returns_a_value.lin":12:25)
    %v5 = arith.addi %v4, %p5 : i64 loc("tests/enums/match_returns_a_value.lin":12:25)
    func.return %v5 : i64 loc("tests/enums/match_returns_a_value.lin":12:5)
  }
  func.func private @"lin.;sides"(%a0: i64) -> i64 attributes {llvm.linkage = #llvm.linkage<internal>} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 1 : i64
    %s1 = llvm.alloca %z1 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    llvm.store %a0, %s0 : i64, !llvm.ptr
    cf.br ^b0
  ^b0:
    %v0 = llvm.load %s0 : !llvm.ptr -> i64 loc("tests/enums/match_returns_a_value.lin":4:16)
    %v1 = arith.constant 0 : i64 loc("tests/enums/match_returns_a_value.lin":4:5)
    %v2 = arith.cmpi eq, %v0, %v1 : i64 loc("tests/enums/match_returns_a_value.lin":4:5)
    cf.cond_br %v2, ^b2, ^b3 loc("tests/enums/match_returns_a_value.lin":4:5)
  ^b1:
    %lw20 = llvm.load %s1 : !llvm.ptr -> i8 loc("tests/enums/match_returns_a_value.lin":4:5)
    %v20 = arith.extui %lw20 : i8 to i64 loc("tests/enums/match_returns_a_value.lin":4:5)
    func.return %v20 : i64 loc("tests/enums/match_returns_a_value.lin":4:5)
  ^b2:
    %v4 = arith.constant 0 : i64 loc("tests/enums/match_returns_a_value.lin":5:19)
    %sw5 = arith.trunci %v4 : i64 to i8 loc("tests/enums/match_returns_a_value.lin":4:5)
    llvm.store %sw5, %s1 : i8, !llvm.ptr loc("tests/enums/match_returns_a_value.lin":4:5)
    cf.br ^b1 loc("tests/enums/match_returns_a_value.lin":4:5)
  ^b3:
    %v7 = arith.constant 1 : i64 loc("tests/enums/match_returns_a_value.lin":4:5)
    %v8 = arith.cmpi eq, %v0, %v7 : i64 loc("tests/enums/match_returns_a_value.lin":4:5)
    cf.cond_br %v8, ^b4, ^b5 loc("tests/enums/match_returns_a_value.lin":4:5)
  ^b4:
    %v10 = arith.constant 4 : i64 loc("tests/enums/match_returns_a_value.lin":6:19)
    %sw11 = arith.trunci %v10 : i64 to i8 loc("tests/enums/match_returns_a_value.lin":4:5)
    llvm.store %sw11, %s1 : i8, !llvm.ptr loc("tests/enums/match_returns_a_value.lin":4:5)
    cf.br ^b1 loc("tests/enums/match_returns_a_value.lin":4:5)
  ^b5:
    %v13 = arith.constant 2 : i64 loc("tests/enums/match_returns_a_value.lin":4:5)
    %v14 = arith.cmpi eq, %v0, %v13 : i64 loc("tests/enums/match_returns_a_value.lin":4:5)
    cf.cond_br %v14, ^b6, ^b7 loc("tests/enums/match_returns_a_value.lin":4:5)
  ^b6:
    %v16 = arith.constant 1 : i64 loc("tests/enums/match_returns_a_value.lin":7:18)
    %sw17 = arith.trunci %v16 : i64 to i8 loc("tests/enums/match_returns_a_value.lin":4:5)
    llvm.store %sw17, %s1 : i8, !llvm.ptr loc("tests/enums/match_returns_a_value.lin":4:5)
    cf.br ^b1 loc("tests/enums/match_returns_a_value.lin":4:5)
  ^b7:
    %tk1 = arith.constant 3 : i32 loc("tests/enums/match_returns_a_value.lin":4:5)
    %tf1 = llvm.mlir.addressof @linea_file0 : !llvm.ptr loc("tests/enums/match_returns_a_value.lin":4:5)
    %tl1 = arith.constant 4 : i32 loc("tests/enums/match_returns_a_value.lin":4:5)
    %tc1 = arith.constant 5 : i32 loc("tests/enums/match_returns_a_value.lin":4:5)
    func.call @linea_trap(%tk1, %tf1, %tl1, %tc1) : (i32, !llvm.ptr, i32, i32) -> () loc("tests/enums/match_returns_a_value.lin":4:5)
    llvm.unreachable loc("tests/enums/match_returns_a_value.lin":4:5)
  }
  func.func @main(%argc: i32, %argv: !llvm.ptr) -> i32 {
    func.call @linea_set_args(%argc, %argv) : (i32, !llvm.ptr) -> ()
    %status = func.call @"lin.;main"() : () -> i64
    %status32 = arith.trunci %status : i64 to i32
    func.return %status32 : i32
  }
}
