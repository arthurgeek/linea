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
  llvm.mlir.global internal constant @linea_file0("tests/codegen/an_aggregate_returned_by_return.lin\00") : !llvm.array<50 x i8>
  func.func private @linea_set_args(i32, !llvm.ptr)
  func.func private @linea_trap(i32, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @linea_panic(i64, i64, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @"lin.;main"() -> i64 attributes {llvm.linkage = #llvm.linkage<internal>} {
    %rz0 = arith.constant 24 : i64
    %rs0 = llvm.alloca %rz0 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    cf.br ^b0
  ^b0:
    func.call @"lin.;make"(%rs0) : (!llvm.ptr) -> () loc("tests/codegen/an_aggregate_returned_by_return.lin":35:10)
    %v1 = func.call @"lin.;noise"() : () -> i64 loc("tests/codegen/an_aggregate_returned_by_return.lin":35:18)
    %v2 = func.call @"lin.;take"(%rs0, %v1) : (!llvm.ptr, i64) -> i64 loc("tests/codegen/an_aggregate_returned_by_return.lin":35:5)
    func.return %v2 : i64 loc("tests/codegen/an_aggregate_returned_by_return.lin":35:5)
  }
  func.func private @"lin.;make"(%sret: !llvm.ptr) attributes {llvm.linkage = #llvm.linkage<internal>} {
    %z0 = arith.constant 24 : i64
    %s0 = llvm.alloca %z0 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    cf.br ^b0
  ^b0:
    %v1 = arith.constant 0 : i64 loc("tests/codegen/an_aggregate_returned_by_return.lin":21:12)
    %v3 = arith.constant 1 : i64 loc("tests/codegen/an_aggregate_returned_by_return.lin":21:19)
    llvm.store %v3, %s0 : i64, !llvm.ptr loc("tests/codegen/an_aggregate_returned_by_return.lin":21:12)
    %v5 = arith.constant 8 : i64 loc("tests/codegen/an_aggregate_returned_by_return.lin":21:12)
    %v6 = llvm.getelementptr %s0[%v5] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("tests/codegen/an_aggregate_returned_by_return.lin":21:12)
    %v7 = arith.constant 2 : i64 loc("tests/codegen/an_aggregate_returned_by_return.lin":21:26)
    llvm.store %v7, %v6 : i64, !llvm.ptr loc("tests/codegen/an_aggregate_returned_by_return.lin":21:12)
    %v9 = arith.constant 16 : i64 loc("tests/codegen/an_aggregate_returned_by_return.lin":21:12)
    %v10 = llvm.getelementptr %s0[%v9] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("tests/codegen/an_aggregate_returned_by_return.lin":21:12)
    %v11 = arith.constant 3 : i64 loc("tests/codegen/an_aggregate_returned_by_return.lin":21:33)
    llvm.store %v11, %v10 : i64, !llvm.ptr loc("tests/codegen/an_aggregate_returned_by_return.lin":21:12)
    %rl13 = arith.constant 24 : i64 loc("tests/codegen/an_aggregate_returned_by_return.lin":21:5)
    "llvm.intr.memcpy"(%sret, %s0, %rl13) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("tests/codegen/an_aggregate_returned_by_return.lin":21:5)
    func.return loc("tests/codegen/an_aggregate_returned_by_return.lin":21:5)
  }
  func.func private @"lin.;noise"() -> i64 attributes {llvm.linkage = #llvm.linkage<internal>} {
    %z0 = arith.constant 24 : i64
    %s0 = llvm.alloca %z0 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    cf.br ^b0
  ^b0:
    %v1 = arith.constant 0 : i64 loc("tests/codegen/an_aggregate_returned_by_return.lin":25:18)
    %v3 = arith.constant 99 : i64 loc("tests/codegen/an_aggregate_returned_by_return.lin":25:25)
    llvm.store %v3, %s0 : i64, !llvm.ptr loc("tests/codegen/an_aggregate_returned_by_return.lin":25:18)
    %v5 = arith.constant 8 : i64 loc("tests/codegen/an_aggregate_returned_by_return.lin":25:18)
    %v6 = llvm.getelementptr %s0[%v5] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("tests/codegen/an_aggregate_returned_by_return.lin":25:18)
    %v7 = arith.constant 98 : i64 loc("tests/codegen/an_aggregate_returned_by_return.lin":25:33)
    llvm.store %v7, %v6 : i64, !llvm.ptr loc("tests/codegen/an_aggregate_returned_by_return.lin":25:18)
    %v9 = arith.constant 16 : i64 loc("tests/codegen/an_aggregate_returned_by_return.lin":25:18)
    %v10 = llvm.getelementptr %s0[%v9] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("tests/codegen/an_aggregate_returned_by_return.lin":25:18)
    %v11 = arith.constant 97 : i64 loc("tests/codegen/an_aggregate_returned_by_return.lin":25:41)
    llvm.store %v11, %v10 : i64, !llvm.ptr loc("tests/codegen/an_aggregate_returned_by_return.lin":25:18)
    %v14 = arith.constant 0 : i64 loc("tests/codegen/an_aggregate_returned_by_return.lin":26:11)
    %v16 = llvm.load %s0 : !llvm.ptr -> i64 loc("tests/codegen/an_aggregate_returned_by_return.lin":26:11)
    %k1m = arith.constant 255 : i64 loc("tests/codegen/an_aggregate_returned_by_return.lin":26:5)
    %k1 = arith.cmpi ugt, %v16, %k1m : i64 loc("tests/codegen/an_aggregate_returned_by_return.lin":26:5)
    cf.cond_br %k1, ^t1, ^c1 loc("tests/codegen/an_aggregate_returned_by_return.lin":26:5)
  ^t1:
    %tk1 = arith.constant 2 : i32 loc("tests/codegen/an_aggregate_returned_by_return.lin":26:5)
    %tf1 = llvm.mlir.addressof @linea_file0 : !llvm.ptr loc("tests/codegen/an_aggregate_returned_by_return.lin":26:5)
    %tl1 = arith.constant 26 : i32 loc("tests/codegen/an_aggregate_returned_by_return.lin":26:5)
    %tc1 = arith.constant 5 : i32 loc("tests/codegen/an_aggregate_returned_by_return.lin":26:5)
    func.call @linea_trap(%tk1, %tf1, %tl1, %tc1) : (i32, !llvm.ptr, i32, i32) -> () loc("tests/codegen/an_aggregate_returned_by_return.lin":26:5)
    llvm.unreachable loc("tests/codegen/an_aggregate_returned_by_return.lin":26:5)
  ^c1:
    %p17 = arith.constant 0 : i64 loc("tests/codegen/an_aggregate_returned_by_return.lin":26:5)
    %v17 = arith.addi %v16, %p17 : i64 loc("tests/codegen/an_aggregate_returned_by_return.lin":26:5)
    func.return %v17 : i64 loc("tests/codegen/an_aggregate_returned_by_return.lin":26:5)
  }
  func.func private @"lin.;take"(%a0: !llvm.ptr, %a1: i64) -> i64 attributes {llvm.linkage = #llvm.linkage<internal>} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x !llvm.ptr {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 1 : i64
    %s1 = llvm.alloca %z1 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z2 = arith.constant 1 : i64
    %s2 = llvm.alloca %z2 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    llvm.store %a0, %s0 : !llvm.ptr, !llvm.ptr
    %pw1 = arith.trunci %a1 : i64 to i8
    llvm.store %pw1, %s1 : i8, !llvm.ptr
    cf.br ^b0
  ^b0:
    %lw0 = llvm.load %s1 : !llvm.ptr -> i8 loc("tests/codegen/an_aggregate_returned_by_return.lin":30:13)
    %v0 = arith.extui %lw0 : i8 to i64 loc("tests/codegen/an_aggregate_returned_by_return.lin":30:13)
    %sw1 = arith.trunci %v0 : i64 to i8 loc("tests/codegen/an_aggregate_returned_by_return.lin":30:5)
    llvm.store %sw1, %s2 : i8, !llvm.ptr loc("tests/codegen/an_aggregate_returned_by_return.lin":30:5)
    %v2 = llvm.load %s0 : !llvm.ptr -> !llvm.ptr loc("tests/codegen/an_aggregate_returned_by_return.lin":31:11)
    %v3 = arith.constant 0 : i64 loc("tests/codegen/an_aggregate_returned_by_return.lin":31:11)
    %v5 = llvm.load %v2 : !llvm.ptr -> i64 loc("tests/codegen/an_aggregate_returned_by_return.lin":31:11)
    %k1m = arith.constant 255 : i64 loc("tests/codegen/an_aggregate_returned_by_return.lin":31:5)
    %k1 = arith.cmpi ugt, %v5, %k1m : i64 loc("tests/codegen/an_aggregate_returned_by_return.lin":31:5)
    cf.cond_br %k1, ^t1, ^c1 loc("tests/codegen/an_aggregate_returned_by_return.lin":31:5)
  ^t1:
    %tk1 = arith.constant 2 : i32 loc("tests/codegen/an_aggregate_returned_by_return.lin":31:5)
    %tf1 = llvm.mlir.addressof @linea_file0 : !llvm.ptr loc("tests/codegen/an_aggregate_returned_by_return.lin":31:5)
    %tl1 = arith.constant 31 : i32 loc("tests/codegen/an_aggregate_returned_by_return.lin":31:5)
    %tc1 = arith.constant 5 : i32 loc("tests/codegen/an_aggregate_returned_by_return.lin":31:5)
    func.call @linea_trap(%tk1, %tf1, %tl1, %tc1) : (i32, !llvm.ptr, i32, i32) -> () loc("tests/codegen/an_aggregate_returned_by_return.lin":31:5)
    llvm.unreachable loc("tests/codegen/an_aggregate_returned_by_return.lin":31:5)
  ^c1:
    %p6 = arith.constant 0 : i64 loc("tests/codegen/an_aggregate_returned_by_return.lin":31:5)
    %v6 = arith.addi %v5, %p6 : i64 loc("tests/codegen/an_aggregate_returned_by_return.lin":31:5)
    func.return %v6 : i64 loc("tests/codegen/an_aggregate_returned_by_return.lin":31:5)
  }
  func.func @main(%argc: i32, %argv: !llvm.ptr) -> i32 {
    func.call @linea_set_args(%argc, %argv) : (i32, !llvm.ptr) -> ()
    %status = func.call @"lin.;main"() : () -> i64
    %status32 = arith.trunci %status : i64 to i32
    func.return %status32 : i32
  }
}
