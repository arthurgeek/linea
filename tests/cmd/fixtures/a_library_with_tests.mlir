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
  llvm.mlir.global internal constant @linea_file0("tests/cmd/fixtures/a_library_with_tests/main.lin\00") : !llvm.array<49 x i8>
  func.func private @linea_set_args(i32, !llvm.ptr)
  func.func private @linea_trap(i32, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @linea_panic(i64, i64, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @"lin.;sum"() -> i64 attributes {llvm.linkage = #llvm.linkage<internal>} {
    %z0 = arith.constant 3 : i64
    %s0 = llvm.alloca %z0 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 1 : i64
    %s1 = llvm.alloca %z1 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z2 = arith.constant 1 : i64
    %s2 = llvm.alloca %z2 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    cf.br ^b0
  ^b0:
    %v1 = arith.constant 0 : i64 loc("tests/cmd/fixtures/a_library_with_tests/main.lin":4:26)
    %v3 = arith.constant 1 : i64 loc("tests/cmd/fixtures/a_library_with_tests/main.lin":4:27)
    %iw4 = arith.trunci %v3 : i64 to i8 loc("tests/cmd/fixtures/a_library_with_tests/main.lin":4:26)
    llvm.store %iw4, %s0 : i8, !llvm.ptr loc("tests/cmd/fixtures/a_library_with_tests/main.lin":4:26)
    %v5 = arith.constant 1 : i64 loc("tests/cmd/fixtures/a_library_with_tests/main.lin":4:26)
    %v6 = llvm.getelementptr %s0[%v5] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("tests/cmd/fixtures/a_library_with_tests/main.lin":4:26)
    %v7 = arith.constant 4 : i64 loc("tests/cmd/fixtures/a_library_with_tests/main.lin":4:30)
    %iw8 = arith.trunci %v7 : i64 to i8 loc("tests/cmd/fixtures/a_library_with_tests/main.lin":4:26)
    llvm.store %iw8, %v6 : i8, !llvm.ptr loc("tests/cmd/fixtures/a_library_with_tests/main.lin":4:26)
    %v9 = arith.constant 2 : i64 loc("tests/cmd/fixtures/a_library_with_tests/main.lin":4:26)
    %v10 = llvm.getelementptr %s0[%v9] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("tests/cmd/fixtures/a_library_with_tests/main.lin":4:26)
    %v11 = arith.constant 5 : i64 loc("tests/cmd/fixtures/a_library_with_tests/main.lin":4:33)
    %iw12 = arith.trunci %v11 : i64 to i8 loc("tests/cmd/fixtures/a_library_with_tests/main.lin":4:26)
    llvm.store %iw12, %v10 : i8, !llvm.ptr loc("tests/cmd/fixtures/a_library_with_tests/main.lin":4:26)
    %v13 = arith.constant 0 : i64 loc("tests/cmd/fixtures/a_library_with_tests/main.lin":5:24)
    %sw14 = arith.trunci %v13 : i64 to i8 loc("tests/cmd/fixtures/a_library_with_tests/main.lin":5:5)
    llvm.store %sw14, %s1 : i8, !llvm.ptr loc("tests/cmd/fixtures/a_library_with_tests/main.lin":5:5)
    %v16 = arith.constant 0 : i64 loc("tests/cmd/fixtures/a_library_with_tests/main.lin":6:5)
    llvm.store %v16, %s2 : i64, !llvm.ptr loc("tests/cmd/fixtures/a_library_with_tests/main.lin":6:5)
    cf.br ^b1 loc("tests/cmd/fixtures/a_library_with_tests/main.lin":6:5)
  ^b1:
    %v19 = llvm.load %s2 : !llvm.ptr -> i64 loc("tests/cmd/fixtures/a_library_with_tests/main.lin":6:5)
    %v20 = arith.constant 3 : i64 loc("tests/cmd/fixtures/a_library_with_tests/main.lin":6:5)
    %v21 = arith.cmpi ult, %v19, %v20 : i64 loc("tests/cmd/fixtures/a_library_with_tests/main.lin":6:5)
    cf.cond_br %v21, ^b5, ^b3 loc("tests/cmd/fixtures/a_library_with_tests/main.lin":6:5)
  ^b2:
    %v41 = llvm.load %s2 : !llvm.ptr -> i64 loc("tests/cmd/fixtures/a_library_with_tests/main.lin":6:5)
    %v42 = arith.constant 1 : i64 loc("tests/cmd/fixtures/a_library_with_tests/main.lin":6:5)
    %v43 = arith.addi %v41, %v42 : i64 loc("tests/cmd/fixtures/a_library_with_tests/main.lin":6:5)
    llvm.store %v43, %s2 : i64, !llvm.ptr loc("tests/cmd/fixtures/a_library_with_tests/main.lin":6:5)
    cf.br ^b1 loc("tests/cmd/fixtures/a_library_with_tests/main.lin":6:5)
  ^b3:
    cf.br ^b4 loc("tests/cmd/fixtures/a_library_with_tests/main.lin":6:5)
  ^b4:
    %v46 = arith.constant 0 : i64 loc("tests/cmd/fixtures/a_library_with_tests/main.lin":6:5)
    %lw47 = llvm.load %s1 : !llvm.ptr -> i8 loc("tests/cmd/fixtures/a_library_with_tests/main.lin":11:5)
    %v47 = arith.extui %lw47 : i8 to i64 loc("tests/cmd/fixtures/a_library_with_tests/main.lin":11:5)
    func.return %v47 : i64 loc("tests/cmd/fixtures/a_library_with_tests/main.lin":11:5)
  ^b5:
    %v24 = arith.constant 1 : i64 loc("tests/cmd/fixtures/a_library_with_tests/main.lin":6:5)
    %m25 = "llvm.intr.umul.with.overflow"(%v19, %v24) : (i64, i64) -> !llvm.struct<(i64, i1)> loc("tests/cmd/fixtures/a_library_with_tests/main.lin":6:5)
    %v25 = llvm.extractvalue %m25[0] : !llvm.struct<(i64, i1)> loc("tests/cmd/fixtures/a_library_with_tests/main.lin":6:5)
    %v26 = llvm.getelementptr %s0[%v25] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("tests/cmd/fixtures/a_library_with_tests/main.lin":6:5)
    %iw27 = llvm.load %v26 : !llvm.ptr -> i8 loc("tests/cmd/fixtures/a_library_with_tests/main.lin":7:12)
    %v27 = arith.extui %iw27 : i8 to i64 loc("tests/cmd/fixtures/a_library_with_tests/main.lin":7:12)
    %v28 = arith.constant 1 : i64 loc("tests/cmd/fixtures/a_library_with_tests/main.lin":7:16)
    %v29 = arith.cmpi ugt, %v27, %v28 : i64 loc("tests/cmd/fixtures/a_library_with_tests/main.lin":7:12)
    cf.cond_br %v29, ^b6, ^b7 loc("tests/cmd/fixtures/a_library_with_tests/main.lin":7:9)
  ^b6:
    %iw31 = llvm.load %v26 : !llvm.ptr -> i8 loc("tests/cmd/fixtures/a_library_with_tests/main.lin":8:22)
    %v31 = arith.extui %iw31 : i8 to i64 loc("tests/cmd/fixtures/a_library_with_tests/main.lin":8:22)
    %lw32 = llvm.load %s1 : !llvm.ptr -> i8 loc("tests/cmd/fixtures/a_library_with_tests/main.lin":8:13)
    %v32 = arith.extui %lw32 : i8 to i64 loc("tests/cmd/fixtures/a_library_with_tests/main.lin":8:13)
    %v33 = arith.addi %v32, %v31 : i64 loc("tests/cmd/fixtures/a_library_with_tests/main.lin":8:13)
    %k1m = arith.constant 255 : i64 loc("tests/cmd/fixtures/a_library_with_tests/main.lin":8:19)
    %k1 = arith.cmpi ugt, %v33, %k1m : i64 loc("tests/cmd/fixtures/a_library_with_tests/main.lin":8:19)
    cf.cond_br %k1, ^t1, ^c1 loc("tests/cmd/fixtures/a_library_with_tests/main.lin":8:19)
  ^t1:
    %tk1 = arith.constant 0 : i32 loc("tests/cmd/fixtures/a_library_with_tests/main.lin":8:19)
    %tf1 = llvm.mlir.addressof @linea_file0 : !llvm.ptr loc("tests/cmd/fixtures/a_library_with_tests/main.lin":8:19)
    %tl1 = arith.constant 8 : i32 loc("tests/cmd/fixtures/a_library_with_tests/main.lin":8:19)
    %tc1 = arith.constant 19 : i32 loc("tests/cmd/fixtures/a_library_with_tests/main.lin":8:19)
    func.call @linea_trap(%tk1, %tf1, %tl1, %tc1) : (i32, !llvm.ptr, i32, i32) -> () loc("tests/cmd/fixtures/a_library_with_tests/main.lin":8:19)
    llvm.unreachable loc("tests/cmd/fixtures/a_library_with_tests/main.lin":8:19)
  ^c1:
    %p34 = arith.constant 0 : i64 loc("tests/cmd/fixtures/a_library_with_tests/main.lin":8:19)
    %v34 = arith.addi %v33, %p34 : i64 loc("tests/cmd/fixtures/a_library_with_tests/main.lin":8:19)
    %sw35 = arith.trunci %v34 : i64 to i8 loc("tests/cmd/fixtures/a_library_with_tests/main.lin":8:13)
    llvm.store %sw35, %s1 : i8, !llvm.ptr loc("tests/cmd/fixtures/a_library_with_tests/main.lin":8:13)
    %v36 = arith.constant 0 : i64 loc("tests/cmd/fixtures/a_library_with_tests/main.lin":8:13)
    cf.br ^b8 loc("tests/cmd/fixtures/a_library_with_tests/main.lin":7:9)
  ^b7:
    cf.br ^b8 loc("tests/cmd/fixtures/a_library_with_tests/main.lin":7:9)
  ^b8:
    %v39 = arith.constant 0 : i64 loc("tests/cmd/fixtures/a_library_with_tests/main.lin":7:9)
    cf.br ^b2 loc("tests/cmd/fixtures/a_library_with_tests/main.lin":6:5)
  }
  func.func @sum() -> i8 {
    %answer = func.call @"lin.;sum"() : () -> i64
    %narrow = arith.trunci %answer : i64 to i8
    func.return %narrow : i8
  }
}
