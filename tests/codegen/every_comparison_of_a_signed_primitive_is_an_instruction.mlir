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
  llvm.mlir.global internal constant @linea_file0("tests/codegen/every_comparison_of_a_signed_primitive_is_an_instruction.lin\00") : !llvm.array<75 x i8>
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
    %z3 = arith.constant 1 : i64
    %s3 = llvm.alloca %z3 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z4 = arith.constant 1 : i64
    %s4 = llvm.alloca %z4 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z5 = arith.constant 1 : i64
    %s5 = llvm.alloca %z5 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    cf.br ^b0
  ^b0:
    %v0 = arith.constant -1 : i64 loc("tests/codegen/every_comparison_of_a_signed_primitive_is_an_instruction.lin":30:11)
    %v1 = arith.constant -1 : i64 loc("tests/codegen/every_comparison_of_a_signed_primitive_is_an_instruction.lin":30:15)
    %v2 = func.call @"lin.;eq"(%v0, %v1) : (i64, i64) -> i1 loc("tests/codegen/every_comparison_of_a_signed_primitive_is_an_instruction.lin":30:8)
    cf.cond_br %v2, ^b1, ^b2 loc("tests/codegen/every_comparison_of_a_signed_primitive_is_an_instruction.lin":30:8)
  ^b1:
    %v4 = arith.constant -1 : i64 loc("tests/codegen/every_comparison_of_a_signed_primitive_is_an_instruction.lin":30:26)
    %v5 = arith.constant -1 : i64 loc("tests/codegen/every_comparison_of_a_signed_primitive_is_an_instruction.lin":30:30)
    %v6 = func.call @"lin.;ne"(%v4, %v5) : (i64, i64) -> i1 loc("tests/codegen/every_comparison_of_a_signed_primitive_is_an_instruction.lin":30:23)
    %v7 = arith.constant 0 : i1 loc("tests/codegen/every_comparison_of_a_signed_primitive_is_an_instruction.lin":30:22)
    %v8 = arith.cmpi eq, %v6, %v7 : i1 loc("tests/codegen/every_comparison_of_a_signed_primitive_is_an_instruction.lin":30:22)
    %sw9 = arith.extui %v8 : i1 to i8 loc("tests/codegen/every_comparison_of_a_signed_primitive_is_an_instruction.lin":30:8)
    llvm.store %sw9, %s0 : i8, !llvm.ptr loc("tests/codegen/every_comparison_of_a_signed_primitive_is_an_instruction.lin":30:8)
    cf.br ^b3 loc("tests/codegen/every_comparison_of_a_signed_primitive_is_an_instruction.lin":30:8)
  ^b2:
    %v11 = arith.constant 0 : i1 loc("tests/codegen/every_comparison_of_a_signed_primitive_is_an_instruction.lin":30:8)
    %sw12 = arith.extui %v11 : i1 to i8 loc("tests/codegen/every_comparison_of_a_signed_primitive_is_an_instruction.lin":30:8)
    llvm.store %sw12, %s0 : i8, !llvm.ptr loc("tests/codegen/every_comparison_of_a_signed_primitive_is_an_instruction.lin":30:8)
    cf.br ^b3 loc("tests/codegen/every_comparison_of_a_signed_primitive_is_an_instruction.lin":30:8)
  ^b3:
    %lw14 = llvm.load %s0 : !llvm.ptr -> i8 loc("tests/codegen/every_comparison_of_a_signed_primitive_is_an_instruction.lin":30:8)
    %lz14 = arith.constant 0 : i8 loc("tests/codegen/every_comparison_of_a_signed_primitive_is_an_instruction.lin":30:8)
    %v14 = arith.cmpi ne, %lw14, %lz14 : i8 loc("tests/codegen/every_comparison_of_a_signed_primitive_is_an_instruction.lin":30:8)
    cf.cond_br %v14, ^b4, ^b5 loc("tests/codegen/every_comparison_of_a_signed_primitive_is_an_instruction.lin":30:8)
  ^b4:
    %v16 = arith.constant -2 : i64 loc("tests/codegen/every_comparison_of_a_signed_primitive_is_an_instruction.lin":30:40)
    %v17 = arith.constant -1 : i64 loc("tests/codegen/every_comparison_of_a_signed_primitive_is_an_instruction.lin":30:44)
    %v18 = func.call @"lin.;lt"(%v16, %v17) : (i64, i64) -> i1 loc("tests/codegen/every_comparison_of_a_signed_primitive_is_an_instruction.lin":30:37)
    %sw19 = arith.extui %v18 : i1 to i8 loc("tests/codegen/every_comparison_of_a_signed_primitive_is_an_instruction.lin":30:8)
    llvm.store %sw19, %s1 : i8, !llvm.ptr loc("tests/codegen/every_comparison_of_a_signed_primitive_is_an_instruction.lin":30:8)
    cf.br ^b6 loc("tests/codegen/every_comparison_of_a_signed_primitive_is_an_instruction.lin":30:8)
  ^b5:
    %v21 = arith.constant 0 : i1 loc("tests/codegen/every_comparison_of_a_signed_primitive_is_an_instruction.lin":30:8)
    %sw22 = arith.extui %v21 : i1 to i8 loc("tests/codegen/every_comparison_of_a_signed_primitive_is_an_instruction.lin":30:8)
    llvm.store %sw22, %s1 : i8, !llvm.ptr loc("tests/codegen/every_comparison_of_a_signed_primitive_is_an_instruction.lin":30:8)
    cf.br ^b6 loc("tests/codegen/every_comparison_of_a_signed_primitive_is_an_instruction.lin":30:8)
  ^b6:
    %lw24 = llvm.load %s1 : !llvm.ptr -> i8 loc("tests/codegen/every_comparison_of_a_signed_primitive_is_an_instruction.lin":30:8)
    %lz24 = arith.constant 0 : i8 loc("tests/codegen/every_comparison_of_a_signed_primitive_is_an_instruction.lin":30:8)
    %v24 = arith.cmpi ne, %lw24, %lz24 : i8 loc("tests/codegen/every_comparison_of_a_signed_primitive_is_an_instruction.lin":30:8)
    cf.cond_br %v24, ^b7, ^b8 loc("tests/codegen/every_comparison_of_a_signed_primitive_is_an_instruction.lin":30:8)
  ^b7:
    %v26 = arith.constant -2 : i64 loc("tests/codegen/every_comparison_of_a_signed_primitive_is_an_instruction.lin":30:54)
    %v27 = arith.constant -2 : i64 loc("tests/codegen/every_comparison_of_a_signed_primitive_is_an_instruction.lin":30:58)
    %v28 = func.call @"lin.;le"(%v26, %v27) : (i64, i64) -> i1 loc("tests/codegen/every_comparison_of_a_signed_primitive_is_an_instruction.lin":30:51)
    %sw29 = arith.extui %v28 : i1 to i8 loc("tests/codegen/every_comparison_of_a_signed_primitive_is_an_instruction.lin":30:8)
    llvm.store %sw29, %s2 : i8, !llvm.ptr loc("tests/codegen/every_comparison_of_a_signed_primitive_is_an_instruction.lin":30:8)
    cf.br ^b9 loc("tests/codegen/every_comparison_of_a_signed_primitive_is_an_instruction.lin":30:8)
  ^b8:
    %v31 = arith.constant 0 : i1 loc("tests/codegen/every_comparison_of_a_signed_primitive_is_an_instruction.lin":30:8)
    %sw32 = arith.extui %v31 : i1 to i8 loc("tests/codegen/every_comparison_of_a_signed_primitive_is_an_instruction.lin":30:8)
    llvm.store %sw32, %s2 : i8, !llvm.ptr loc("tests/codegen/every_comparison_of_a_signed_primitive_is_an_instruction.lin":30:8)
    cf.br ^b9 loc("tests/codegen/every_comparison_of_a_signed_primitive_is_an_instruction.lin":30:8)
  ^b9:
    %lw34 = llvm.load %s2 : !llvm.ptr -> i8 loc("tests/codegen/every_comparison_of_a_signed_primitive_is_an_instruction.lin":30:8)
    %lz34 = arith.constant 0 : i8 loc("tests/codegen/every_comparison_of_a_signed_primitive_is_an_instruction.lin":30:8)
    %v34 = arith.cmpi ne, %lw34, %lz34 : i8 loc("tests/codegen/every_comparison_of_a_signed_primitive_is_an_instruction.lin":30:8)
    cf.cond_br %v34, ^b10, ^b11 loc("tests/codegen/every_comparison_of_a_signed_primitive_is_an_instruction.lin":30:8)
  ^b10:
    %v36 = arith.constant -1 : i64 loc("tests/codegen/every_comparison_of_a_signed_primitive_is_an_instruction.lin":30:68)
    %v37 = arith.constant -2 : i64 loc("tests/codegen/every_comparison_of_a_signed_primitive_is_an_instruction.lin":30:72)
    %v38 = func.call @"lin.;gt"(%v36, %v37) : (i64, i64) -> i1 loc("tests/codegen/every_comparison_of_a_signed_primitive_is_an_instruction.lin":30:65)
    %sw39 = arith.extui %v38 : i1 to i8 loc("tests/codegen/every_comparison_of_a_signed_primitive_is_an_instruction.lin":30:8)
    llvm.store %sw39, %s3 : i8, !llvm.ptr loc("tests/codegen/every_comparison_of_a_signed_primitive_is_an_instruction.lin":30:8)
    cf.br ^b12 loc("tests/codegen/every_comparison_of_a_signed_primitive_is_an_instruction.lin":30:8)
  ^b11:
    %v41 = arith.constant 0 : i1 loc("tests/codegen/every_comparison_of_a_signed_primitive_is_an_instruction.lin":30:8)
    %sw42 = arith.extui %v41 : i1 to i8 loc("tests/codegen/every_comparison_of_a_signed_primitive_is_an_instruction.lin":30:8)
    llvm.store %sw42, %s3 : i8, !llvm.ptr loc("tests/codegen/every_comparison_of_a_signed_primitive_is_an_instruction.lin":30:8)
    cf.br ^b12 loc("tests/codegen/every_comparison_of_a_signed_primitive_is_an_instruction.lin":30:8)
  ^b12:
    %lw44 = llvm.load %s3 : !llvm.ptr -> i8 loc("tests/codegen/every_comparison_of_a_signed_primitive_is_an_instruction.lin":30:8)
    %lz44 = arith.constant 0 : i8 loc("tests/codegen/every_comparison_of_a_signed_primitive_is_an_instruction.lin":30:8)
    %v44 = arith.cmpi ne, %lw44, %lz44 : i8 loc("tests/codegen/every_comparison_of_a_signed_primitive_is_an_instruction.lin":30:8)
    cf.cond_br %v44, ^b13, ^b14 loc("tests/codegen/every_comparison_of_a_signed_primitive_is_an_instruction.lin":30:8)
  ^b13:
    %v46 = arith.constant -1 : i64 loc("tests/codegen/every_comparison_of_a_signed_primitive_is_an_instruction.lin":30:82)
    %v47 = arith.constant -1 : i64 loc("tests/codegen/every_comparison_of_a_signed_primitive_is_an_instruction.lin":30:86)
    %v48 = func.call @"lin.;ge"(%v46, %v47) : (i64, i64) -> i1 loc("tests/codegen/every_comparison_of_a_signed_primitive_is_an_instruction.lin":30:79)
    %sw49 = arith.extui %v48 : i1 to i8 loc("tests/codegen/every_comparison_of_a_signed_primitive_is_an_instruction.lin":30:8)
    llvm.store %sw49, %s4 : i8, !llvm.ptr loc("tests/codegen/every_comparison_of_a_signed_primitive_is_an_instruction.lin":30:8)
    cf.br ^b15 loc("tests/codegen/every_comparison_of_a_signed_primitive_is_an_instruction.lin":30:8)
  ^b14:
    %v51 = arith.constant 0 : i1 loc("tests/codegen/every_comparison_of_a_signed_primitive_is_an_instruction.lin":30:8)
    %sw52 = arith.extui %v51 : i1 to i8 loc("tests/codegen/every_comparison_of_a_signed_primitive_is_an_instruction.lin":30:8)
    llvm.store %sw52, %s4 : i8, !llvm.ptr loc("tests/codegen/every_comparison_of_a_signed_primitive_is_an_instruction.lin":30:8)
    cf.br ^b15 loc("tests/codegen/every_comparison_of_a_signed_primitive_is_an_instruction.lin":30:8)
  ^b15:
    %lw54 = llvm.load %s4 : !llvm.ptr -> i8 loc("tests/codegen/every_comparison_of_a_signed_primitive_is_an_instruction.lin":30:8)
    %lz54 = arith.constant 0 : i8 loc("tests/codegen/every_comparison_of_a_signed_primitive_is_an_instruction.lin":30:8)
    %v54 = arith.cmpi ne, %lw54, %lz54 : i8 loc("tests/codegen/every_comparison_of_a_signed_primitive_is_an_instruction.lin":30:8)
    cf.cond_br %v54, ^b16, ^b17 loc("tests/codegen/every_comparison_of_a_signed_primitive_is_an_instruction.lin":30:5)
  ^b16:
    %v56 = arith.constant 5 : i64 loc("tests/codegen/every_comparison_of_a_signed_primitive_is_an_instruction.lin":31:9)
    %sw57 = arith.trunci %v56 : i64 to i8 loc("tests/codegen/every_comparison_of_a_signed_primitive_is_an_instruction.lin":30:5)
    llvm.store %sw57, %s5 : i8, !llvm.ptr loc("tests/codegen/every_comparison_of_a_signed_primitive_is_an_instruction.lin":30:5)
    cf.br ^b18 loc("tests/codegen/every_comparison_of_a_signed_primitive_is_an_instruction.lin":30:5)
  ^b17:
    %v59 = arith.constant 0 : i64 loc("tests/codegen/every_comparison_of_a_signed_primitive_is_an_instruction.lin":33:9)
    %sw60 = arith.trunci %v59 : i64 to i8 loc("tests/codegen/every_comparison_of_a_signed_primitive_is_an_instruction.lin":30:5)
    llvm.store %sw60, %s5 : i8, !llvm.ptr loc("tests/codegen/every_comparison_of_a_signed_primitive_is_an_instruction.lin":30:5)
    cf.br ^b18 loc("tests/codegen/every_comparison_of_a_signed_primitive_is_an_instruction.lin":30:5)
  ^b18:
    %lw62 = llvm.load %s5 : !llvm.ptr -> i8 loc("tests/codegen/every_comparison_of_a_signed_primitive_is_an_instruction.lin":30:5)
    %v62 = arith.extui %lw62 : i8 to i64 loc("tests/codegen/every_comparison_of_a_signed_primitive_is_an_instruction.lin":30:5)
    func.return %v62 : i64 loc("tests/codegen/every_comparison_of_a_signed_primitive_is_an_instruction.lin":30:5)
  }
  func.func private @"lin.;eq"(%a0: i64, %a1: i64) -> i1 attributes {llvm.linkage = #llvm.linkage<internal>} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 1 : i64
    %s1 = llvm.alloca %z1 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %pw0 = arith.trunci %a0 : i64 to i8
    llvm.store %pw0, %s0 : i8, !llvm.ptr
    %pw1 = arith.trunci %a1 : i64 to i8
    llvm.store %pw1, %s1 : i8, !llvm.ptr
    cf.br ^b0
  ^b0:
    %lw0 = llvm.load %s0 : !llvm.ptr -> i8 loc("tests/codegen/every_comparison_of_a_signed_primitive_is_an_instruction.lin":6:5)
    %v0 = arith.extsi %lw0 : i8 to i64 loc("tests/codegen/every_comparison_of_a_signed_primitive_is_an_instruction.lin":6:5)
    %lw1 = llvm.load %s1 : !llvm.ptr -> i8 loc("tests/codegen/every_comparison_of_a_signed_primitive_is_an_instruction.lin":6:10)
    %v1 = arith.extsi %lw1 : i8 to i64 loc("tests/codegen/every_comparison_of_a_signed_primitive_is_an_instruction.lin":6:10)
    %v2 = arith.cmpi eq, %v0, %v1 : i64 loc("tests/codegen/every_comparison_of_a_signed_primitive_is_an_instruction.lin":6:5)
    func.return %v2 : i1 loc("tests/codegen/every_comparison_of_a_signed_primitive_is_an_instruction.lin":6:5)
  }
  func.func private @"lin.;ne"(%a0: i64, %a1: i64) -> i1 attributes {llvm.linkage = #llvm.linkage<internal>} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 1 : i64
    %s1 = llvm.alloca %z1 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %pw0 = arith.trunci %a0 : i64 to i8
    llvm.store %pw0, %s0 : i8, !llvm.ptr
    %pw1 = arith.trunci %a1 : i64 to i8
    llvm.store %pw1, %s1 : i8, !llvm.ptr
    cf.br ^b0
  ^b0:
    %lw0 = llvm.load %s0 : !llvm.ptr -> i8 loc("tests/codegen/every_comparison_of_a_signed_primitive_is_an_instruction.lin":10:5)
    %v0 = arith.extsi %lw0 : i8 to i64 loc("tests/codegen/every_comparison_of_a_signed_primitive_is_an_instruction.lin":10:5)
    %lw1 = llvm.load %s1 : !llvm.ptr -> i8 loc("tests/codegen/every_comparison_of_a_signed_primitive_is_an_instruction.lin":10:10)
    %v1 = arith.extsi %lw1 : i8 to i64 loc("tests/codegen/every_comparison_of_a_signed_primitive_is_an_instruction.lin":10:10)
    %v2 = arith.cmpi ne, %v0, %v1 : i64 loc("tests/codegen/every_comparison_of_a_signed_primitive_is_an_instruction.lin":10:5)
    func.return %v2 : i1 loc("tests/codegen/every_comparison_of_a_signed_primitive_is_an_instruction.lin":10:5)
  }
  func.func private @"lin.;lt"(%a0: i64, %a1: i64) -> i1 attributes {llvm.linkage = #llvm.linkage<internal>} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 1 : i64
    %s1 = llvm.alloca %z1 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %pw0 = arith.trunci %a0 : i64 to i8
    llvm.store %pw0, %s0 : i8, !llvm.ptr
    %pw1 = arith.trunci %a1 : i64 to i8
    llvm.store %pw1, %s1 : i8, !llvm.ptr
    cf.br ^b0
  ^b0:
    %lw0 = llvm.load %s0 : !llvm.ptr -> i8 loc("tests/codegen/every_comparison_of_a_signed_primitive_is_an_instruction.lin":14:5)
    %v0 = arith.extsi %lw0 : i8 to i64 loc("tests/codegen/every_comparison_of_a_signed_primitive_is_an_instruction.lin":14:5)
    %lw1 = llvm.load %s1 : !llvm.ptr -> i8 loc("tests/codegen/every_comparison_of_a_signed_primitive_is_an_instruction.lin":14:9)
    %v1 = arith.extsi %lw1 : i8 to i64 loc("tests/codegen/every_comparison_of_a_signed_primitive_is_an_instruction.lin":14:9)
    %v2 = arith.cmpi slt, %v0, %v1 : i64 loc("tests/codegen/every_comparison_of_a_signed_primitive_is_an_instruction.lin":14:5)
    func.return %v2 : i1 loc("tests/codegen/every_comparison_of_a_signed_primitive_is_an_instruction.lin":14:5)
  }
  func.func private @"lin.;le"(%a0: i64, %a1: i64) -> i1 attributes {llvm.linkage = #llvm.linkage<internal>} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 1 : i64
    %s1 = llvm.alloca %z1 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %pw0 = arith.trunci %a0 : i64 to i8
    llvm.store %pw0, %s0 : i8, !llvm.ptr
    %pw1 = arith.trunci %a1 : i64 to i8
    llvm.store %pw1, %s1 : i8, !llvm.ptr
    cf.br ^b0
  ^b0:
    %lw0 = llvm.load %s0 : !llvm.ptr -> i8 loc("tests/codegen/every_comparison_of_a_signed_primitive_is_an_instruction.lin":18:5)
    %v0 = arith.extsi %lw0 : i8 to i64 loc("tests/codegen/every_comparison_of_a_signed_primitive_is_an_instruction.lin":18:5)
    %lw1 = llvm.load %s1 : !llvm.ptr -> i8 loc("tests/codegen/every_comparison_of_a_signed_primitive_is_an_instruction.lin":18:10)
    %v1 = arith.extsi %lw1 : i8 to i64 loc("tests/codegen/every_comparison_of_a_signed_primitive_is_an_instruction.lin":18:10)
    %v2 = arith.cmpi sle, %v0, %v1 : i64 loc("tests/codegen/every_comparison_of_a_signed_primitive_is_an_instruction.lin":18:5)
    func.return %v2 : i1 loc("tests/codegen/every_comparison_of_a_signed_primitive_is_an_instruction.lin":18:5)
  }
  func.func private @"lin.;gt"(%a0: i64, %a1: i64) -> i1 attributes {llvm.linkage = #llvm.linkage<internal>} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 1 : i64
    %s1 = llvm.alloca %z1 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %pw0 = arith.trunci %a0 : i64 to i8
    llvm.store %pw0, %s0 : i8, !llvm.ptr
    %pw1 = arith.trunci %a1 : i64 to i8
    llvm.store %pw1, %s1 : i8, !llvm.ptr
    cf.br ^b0
  ^b0:
    %lw0 = llvm.load %s0 : !llvm.ptr -> i8 loc("tests/codegen/every_comparison_of_a_signed_primitive_is_an_instruction.lin":22:5)
    %v0 = arith.extsi %lw0 : i8 to i64 loc("tests/codegen/every_comparison_of_a_signed_primitive_is_an_instruction.lin":22:5)
    %lw1 = llvm.load %s1 : !llvm.ptr -> i8 loc("tests/codegen/every_comparison_of_a_signed_primitive_is_an_instruction.lin":22:9)
    %v1 = arith.extsi %lw1 : i8 to i64 loc("tests/codegen/every_comparison_of_a_signed_primitive_is_an_instruction.lin":22:9)
    %v2 = arith.cmpi sgt, %v0, %v1 : i64 loc("tests/codegen/every_comparison_of_a_signed_primitive_is_an_instruction.lin":22:5)
    func.return %v2 : i1 loc("tests/codegen/every_comparison_of_a_signed_primitive_is_an_instruction.lin":22:5)
  }
  func.func private @"lin.;ge"(%a0: i64, %a1: i64) -> i1 attributes {llvm.linkage = #llvm.linkage<internal>} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 1 : i64
    %s1 = llvm.alloca %z1 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %pw0 = arith.trunci %a0 : i64 to i8
    llvm.store %pw0, %s0 : i8, !llvm.ptr
    %pw1 = arith.trunci %a1 : i64 to i8
    llvm.store %pw1, %s1 : i8, !llvm.ptr
    cf.br ^b0
  ^b0:
    %lw0 = llvm.load %s0 : !llvm.ptr -> i8 loc("tests/codegen/every_comparison_of_a_signed_primitive_is_an_instruction.lin":26:5)
    %v0 = arith.extsi %lw0 : i8 to i64 loc("tests/codegen/every_comparison_of_a_signed_primitive_is_an_instruction.lin":26:5)
    %lw1 = llvm.load %s1 : !llvm.ptr -> i8 loc("tests/codegen/every_comparison_of_a_signed_primitive_is_an_instruction.lin":26:10)
    %v1 = arith.extsi %lw1 : i8 to i64 loc("tests/codegen/every_comparison_of_a_signed_primitive_is_an_instruction.lin":26:10)
    %v2 = arith.cmpi sge, %v0, %v1 : i64 loc("tests/codegen/every_comparison_of_a_signed_primitive_is_an_instruction.lin":26:5)
    func.return %v2 : i1 loc("tests/codegen/every_comparison_of_a_signed_primitive_is_an_instruction.lin":26:5)
  }
  func.func @main(%argc: i32, %argv: !llvm.ptr) -> i32 {
    func.call @linea_set_args(%argc, %argv) : (i32, !llvm.ptr) -> ()
    %status = func.call @"lin.;main"() : () -> i64
    %status32 = arith.trunci %status : i64 to i32
    func.return %status32 : i32
  }
}
