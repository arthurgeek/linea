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
  llvm.mlir.global internal constant @linea_file0("tests/codegen/a_trap_in_an_aggregate_returning_function.lin\00") : !llvm.array<60 x i8>
  func.func private @linea_set_args(i32, !llvm.ptr)
  func.func private @linea_trap(i32, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @linea_panic(i64, i64, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @"lin.;main"() -> i64 attributes {llvm.linkage = #llvm.linkage<internal>} {
    %z0 = arith.constant 24 : i64
    %s0 = llvm.alloca %z0 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 1 : i64
    %s1 = llvm.alloca %z1 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z2 = arith.constant 1 : i64
    %s2 = llvm.alloca %z2 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z3 = arith.constant 1 : i64
    %s3 = llvm.alloca %z3 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %rz2 = arith.constant 24 : i64
    %rs2 = llvm.alloca %rz2 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    cf.br ^b0
  ^b0:
    %v1 = arith.constant 0 : i64 loc("tests/codegen/a_trap_in_an_aggregate_returning_function.lin":23:18)
    func.call @"lin.;grow"(%rs2, %v1) : (!llvm.ptr, i64) -> () loc("tests/codegen/a_trap_in_an_aggregate_returning_function.lin":23:13)
    %cl3 = arith.constant 24 : i64 loc("tests/codegen/a_trap_in_an_aggregate_returning_function.lin":23:5)
    "llvm.intr.memcpy"(%s0, %rs2, %cl3) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("tests/codegen/a_trap_in_an_aggregate_returning_function.lin":23:5)
    %v5 = arith.constant 0 : i64 loc("tests/codegen/a_trap_in_an_aggregate_returning_function.lin":25:8)
    %v7 = llvm.load %s0 : !llvm.ptr -> i64 loc("tests/codegen/a_trap_in_an_aggregate_returning_function.lin":25:8)
    %v8 = arith.constant 1 : i64 loc("tests/codegen/a_trap_in_an_aggregate_returning_function.lin":25:15)
    %v9 = arith.cmpi ne, %v7, %v8 : i64 loc("tests/codegen/a_trap_in_an_aggregate_returning_function.lin":25:8)
    cf.cond_br %v9, ^b1, ^b2 loc("tests/codegen/a_trap_in_an_aggregate_returning_function.lin":25:5)
  ^b1:
    %v11 = arith.constant 1 : i64 loc("tests/codegen/a_trap_in_an_aggregate_returning_function.lin":26:9)
    %sw12 = arith.trunci %v11 : i64 to i8 loc("tests/codegen/a_trap_in_an_aggregate_returning_function.lin":25:5)
    llvm.store %sw12, %s1 : i8, !llvm.ptr loc("tests/codegen/a_trap_in_an_aggregate_returning_function.lin":25:5)
    cf.br ^b3 loc("tests/codegen/a_trap_in_an_aggregate_returning_function.lin":25:5)
  ^b2:
    %v15 = arith.constant 8 : i64 loc("tests/codegen/a_trap_in_an_aggregate_returning_function.lin":28:12)
    %v16 = llvm.getelementptr %s0[%v15] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("tests/codegen/a_trap_in_an_aggregate_returning_function.lin":28:12)
    %v17 = llvm.load %v16 : !llvm.ptr -> i64 loc("tests/codegen/a_trap_in_an_aggregate_returning_function.lin":28:12)
    %v18 = arith.constant 2 : i64 loc("tests/codegen/a_trap_in_an_aggregate_returning_function.lin":28:19)
    %v19 = arith.cmpi ne, %v17, %v18 : i64 loc("tests/codegen/a_trap_in_an_aggregate_returning_function.lin":28:12)
    cf.cond_br %v19, ^b4, ^b5 loc("tests/codegen/a_trap_in_an_aggregate_returning_function.lin":28:9)
  ^b3:
    %lw43 = llvm.load %s1 : !llvm.ptr -> i8 loc("tests/codegen/a_trap_in_an_aggregate_returning_function.lin":25:5)
    %v43 = arith.extui %lw43 : i8 to i64 loc("tests/codegen/a_trap_in_an_aggregate_returning_function.lin":25:5)
    func.return %v43 : i64 loc("tests/codegen/a_trap_in_an_aggregate_returning_function.lin":25:5)
  ^b4:
    %v21 = arith.constant 2 : i64 loc("tests/codegen/a_trap_in_an_aggregate_returning_function.lin":29:13)
    %sw22 = arith.trunci %v21 : i64 to i8 loc("tests/codegen/a_trap_in_an_aggregate_returning_function.lin":28:9)
    llvm.store %sw22, %s2 : i8, !llvm.ptr loc("tests/codegen/a_trap_in_an_aggregate_returning_function.lin":28:9)
    cf.br ^b6 loc("tests/codegen/a_trap_in_an_aggregate_returning_function.lin":28:9)
  ^b5:
    %v25 = arith.constant 16 : i64 loc("tests/codegen/a_trap_in_an_aggregate_returning_function.lin":31:16)
    %v26 = llvm.getelementptr %s0[%v25] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("tests/codegen/a_trap_in_an_aggregate_returning_function.lin":31:16)
    %v27 = llvm.load %v26 : !llvm.ptr -> i64 loc("tests/codegen/a_trap_in_an_aggregate_returning_function.lin":31:16)
    %v28 = arith.constant 3 : i64 loc("tests/codegen/a_trap_in_an_aggregate_returning_function.lin":31:23)
    %v29 = arith.cmpi ne, %v27, %v28 : i64 loc("tests/codegen/a_trap_in_an_aggregate_returning_function.lin":31:16)
    cf.cond_br %v29, ^b7, ^b8 loc("tests/codegen/a_trap_in_an_aggregate_returning_function.lin":31:13)
  ^b6:
    %lw40 = llvm.load %s2 : !llvm.ptr -> i8 loc("tests/codegen/a_trap_in_an_aggregate_returning_function.lin":28:9)
    %v40 = arith.extui %lw40 : i8 to i64 loc("tests/codegen/a_trap_in_an_aggregate_returning_function.lin":28:9)
    %sw41 = arith.trunci %v40 : i64 to i8 loc("tests/codegen/a_trap_in_an_aggregate_returning_function.lin":25:5)
    llvm.store %sw41, %s1 : i8, !llvm.ptr loc("tests/codegen/a_trap_in_an_aggregate_returning_function.lin":25:5)
    cf.br ^b3 loc("tests/codegen/a_trap_in_an_aggregate_returning_function.lin":25:5)
  ^b7:
    %v31 = arith.constant 3 : i64 loc("tests/codegen/a_trap_in_an_aggregate_returning_function.lin":32:17)
    %sw32 = arith.trunci %v31 : i64 to i8 loc("tests/codegen/a_trap_in_an_aggregate_returning_function.lin":31:13)
    llvm.store %sw32, %s3 : i8, !llvm.ptr loc("tests/codegen/a_trap_in_an_aggregate_returning_function.lin":31:13)
    cf.br ^b9 loc("tests/codegen/a_trap_in_an_aggregate_returning_function.lin":31:13)
  ^b8:
    %v34 = arith.constant 0 : i64 loc("tests/codegen/a_trap_in_an_aggregate_returning_function.lin":34:17)
    %sw35 = arith.trunci %v34 : i64 to i8 loc("tests/codegen/a_trap_in_an_aggregate_returning_function.lin":31:13)
    llvm.store %sw35, %s3 : i8, !llvm.ptr loc("tests/codegen/a_trap_in_an_aggregate_returning_function.lin":31:13)
    cf.br ^b9 loc("tests/codegen/a_trap_in_an_aggregate_returning_function.lin":31:13)
  ^b9:
    %lw37 = llvm.load %s3 : !llvm.ptr -> i8 loc("tests/codegen/a_trap_in_an_aggregate_returning_function.lin":31:13)
    %v37 = arith.extui %lw37 : i8 to i64 loc("tests/codegen/a_trap_in_an_aggregate_returning_function.lin":31:13)
    %sw38 = arith.trunci %v37 : i64 to i8 loc("tests/codegen/a_trap_in_an_aggregate_returning_function.lin":28:9)
    llvm.store %sw38, %s2 : i8, !llvm.ptr loc("tests/codegen/a_trap_in_an_aggregate_returning_function.lin":28:9)
    cf.br ^b6 loc("tests/codegen/a_trap_in_an_aggregate_returning_function.lin":28:9)
  }
  func.func private @"lin.;grow"(%sret: !llvm.ptr, %a0: i64) attributes {llvm.linkage = #llvm.linkage<internal>} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 24 : i64
    %s1 = llvm.alloca %z1 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    llvm.store %a0, %s0 : i64, !llvm.ptr
    cf.br ^b0
  ^b0:
    %v1 = arith.constant 0 : i64 loc("tests/codegen/a_trap_in_an_aggregate_returning_function.lin":19:5)
    %v3 = llvm.load %s0 : !llvm.ptr -> i64 loc("tests/codegen/a_trap_in_an_aggregate_returning_function.lin":19:12)
    %v4 = arith.constant 1 : i64 loc("tests/codegen/a_trap_in_an_aggregate_returning_function.lin":19:16)
    %v5 = arith.addi %v3, %v4 : i64 loc("tests/codegen/a_trap_in_an_aggregate_returning_function.lin":19:12)
    %k1 = arith.cmpi ult, %v5, %v3 : i64 loc("tests/codegen/a_trap_in_an_aggregate_returning_function.lin":19:14)
    cf.cond_br %k1, ^t1, ^c1 loc("tests/codegen/a_trap_in_an_aggregate_returning_function.lin":19:14)
  ^t1:
    %tk1 = arith.constant 0 : i32 loc("tests/codegen/a_trap_in_an_aggregate_returning_function.lin":19:14)
    %tf1 = llvm.mlir.addressof @linea_file0 : !llvm.ptr loc("tests/codegen/a_trap_in_an_aggregate_returning_function.lin":19:14)
    %tl1 = arith.constant 19 : i32 loc("tests/codegen/a_trap_in_an_aggregate_returning_function.lin":19:14)
    %tc1 = arith.constant 14 : i32 loc("tests/codegen/a_trap_in_an_aggregate_returning_function.lin":19:14)
    func.call @linea_trap(%tk1, %tf1, %tl1, %tc1) : (i32, !llvm.ptr, i32, i32) -> () loc("tests/codegen/a_trap_in_an_aggregate_returning_function.lin":19:14)
    llvm.unreachable loc("tests/codegen/a_trap_in_an_aggregate_returning_function.lin":19:14)
  ^c1:
    %p6 = arith.constant 0 : i64 loc("tests/codegen/a_trap_in_an_aggregate_returning_function.lin":19:14)
    %v6 = arith.addi %v5, %p6 : i64 loc("tests/codegen/a_trap_in_an_aggregate_returning_function.lin":19:14)
    llvm.store %v6, %s1 : i64, !llvm.ptr loc("tests/codegen/a_trap_in_an_aggregate_returning_function.lin":19:5)
    %v8 = arith.constant 8 : i64 loc("tests/codegen/a_trap_in_an_aggregate_returning_function.lin":19:5)
    %v9 = llvm.getelementptr %s1[%v8] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("tests/codegen/a_trap_in_an_aggregate_returning_function.lin":19:5)
    %v10 = arith.constant 2 : i64 loc("tests/codegen/a_trap_in_an_aggregate_returning_function.lin":19:23)
    llvm.store %v10, %v9 : i64, !llvm.ptr loc("tests/codegen/a_trap_in_an_aggregate_returning_function.lin":19:5)
    %v12 = arith.constant 16 : i64 loc("tests/codegen/a_trap_in_an_aggregate_returning_function.lin":19:5)
    %v13 = llvm.getelementptr %s1[%v12] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("tests/codegen/a_trap_in_an_aggregate_returning_function.lin":19:5)
    %v14 = arith.constant 3 : i64 loc("tests/codegen/a_trap_in_an_aggregate_returning_function.lin":19:30)
    llvm.store %v14, %v13 : i64, !llvm.ptr loc("tests/codegen/a_trap_in_an_aggregate_returning_function.lin":19:5)
    %rl16 = arith.constant 24 : i64 loc("tests/codegen/a_trap_in_an_aggregate_returning_function.lin":19:5)
    "llvm.intr.memcpy"(%sret, %s1, %rl16) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("tests/codegen/a_trap_in_an_aggregate_returning_function.lin":19:5)
    func.return loc("tests/codegen/a_trap_in_an_aggregate_returning_function.lin":19:5)
  }
  func.func @main(%argc: i32, %argv: !llvm.ptr) -> i32 {
    func.call @linea_set_args(%argc, %argv) : (i32, !llvm.ptr) -> ()
    %status = func.call @"lin.;main"() : () -> i64
    %status32 = arith.trunci %status : i64 to i32
    func.return %status32 : i32
  }
}
