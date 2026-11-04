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
  llvm.mlir.global internal constant @linea_file0("tests/generics/a_variant_payload_of_unit.lin\00") : !llvm.array<45 x i8>
  func.func private @linea_set_args(i32, !llvm.ptr)
  func.func private @linea_trap(i32, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @linea_panic(i64, i64, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @"lin.;main"() -> i64 attributes {llvm.linkage = #llvm.linkage<internal>, passthrough = [["probe-stack", "inline-asm"]]} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 1 : i64
    %s1 = llvm.alloca %z1 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z2 = arith.constant 1 : i64
    %s2 = llvm.alloca %z2 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z3 = arith.constant 1 : i64
    %s3 = llvm.alloca %z3 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z4 = arith.constant 1 : i64
    %s4 = llvm.alloca %z4 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z5 = arith.constant 1 : i64
    %s5 = llvm.alloca %z5 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z6 = arith.constant 1 : i64
    %s6 = llvm.alloca %z6 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z7 = arith.constant 1 : i64
    %s7 = llvm.alloca %z7 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    cf.br ^b0
  ^b0:
    %v0 = arith.constant 7 : i64 loc("tests/generics/a_variant_payload_of_unit.lin":38:27)
    %v1 = func.call @"lin.;ident"(%v0) : (i64) -> i64 loc("tests/generics/a_variant_payload_of_unit.lin":38:21)
    llvm.store %v1, %s0 : i64, !llvm.ptr loc("tests/generics/a_variant_payload_of_unit.lin":38:5)
    %v3 = arith.constant 9 : i64 loc("tests/generics/a_variant_payload_of_unit.lin":39:27)
    %v4 = func.call @"lin.;ident"(%v3) : (i64) -> i64 loc("tests/generics/a_variant_payload_of_unit.lin":39:21)
    llvm.store %v4, %s1 : i64, !llvm.ptr loc("tests/generics/a_variant_payload_of_unit.lin":39:5)
    %v6 = arith.constant 11 : i64 loc("tests/generics/a_variant_payload_of_unit.lin":40:27)
    %v7 = func.call @"lin.;ident"(%v6) : (i64) -> i64 loc("tests/generics/a_variant_payload_of_unit.lin":40:21)
    llvm.store %v7, %s2 : i64, !llvm.ptr loc("tests/generics/a_variant_payload_of_unit.lin":40:5)
    %v9 = arith.constant 25 : i64 loc("tests/generics/a_variant_payload_of_unit.lin":41:31)
    %v10 = func.call @"lin.;holds"(%v9) : (i64) -> i64 loc("tests/generics/a_variant_payload_of_unit.lin":41:25)
    llvm.store %v10, %s3 : i64, !llvm.ptr loc("tests/generics/a_variant_payload_of_unit.lin":41:5)
    %v12 = llvm.load %s3 : !llvm.ptr -> i64 loc("tests/generics/a_variant_payload_of_unit.lin":43:8)
    %v13 = arith.constant 50 : i64 loc("tests/generics/a_variant_payload_of_unit.lin":43:17)
    %v14 = arith.cmpi ne, %v12, %v13 : i64 loc("tests/generics/a_variant_payload_of_unit.lin":43:8)
    cf.cond_br %v14, ^b1, ^b2 loc("tests/generics/a_variant_payload_of_unit.lin":43:5)
  ^b1:
    %v16 = arith.constant 1 : i64 loc("tests/generics/a_variant_payload_of_unit.lin":44:9)
    %sw17 = arith.trunci %v16 : i64 to i8 loc("tests/generics/a_variant_payload_of_unit.lin":43:5)
    llvm.store %sw17, %s4 : i8, !llvm.ptr loc("tests/generics/a_variant_payload_of_unit.lin":43:5)
    cf.br ^b3 loc("tests/generics/a_variant_payload_of_unit.lin":43:5)
  ^b2:
    %v19 = llvm.load %s0 : !llvm.ptr -> i64 loc("tests/generics/a_variant_payload_of_unit.lin":46:12)
    %v20 = arith.constant 7 : i64 loc("tests/generics/a_variant_payload_of_unit.lin":46:17)
    %v21 = arith.cmpi ne, %v19, %v20 : i64 loc("tests/generics/a_variant_payload_of_unit.lin":46:12)
    cf.cond_br %v21, ^b4, ^b5 loc("tests/generics/a_variant_payload_of_unit.lin":46:9)
  ^b3:
    %lw52 = llvm.load %s4 : !llvm.ptr -> i8 loc("tests/generics/a_variant_payload_of_unit.lin":43:5)
    %v52 = arith.extui %lw52 : i8 to i64 loc("tests/generics/a_variant_payload_of_unit.lin":43:5)
    func.return %v52 : i64 loc("tests/generics/a_variant_payload_of_unit.lin":43:5)
  ^b4:
    %v23 = arith.constant 2 : i64 loc("tests/generics/a_variant_payload_of_unit.lin":47:13)
    %sw24 = arith.trunci %v23 : i64 to i8 loc("tests/generics/a_variant_payload_of_unit.lin":46:9)
    llvm.store %sw24, %s5 : i8, !llvm.ptr loc("tests/generics/a_variant_payload_of_unit.lin":46:9)
    cf.br ^b6 loc("tests/generics/a_variant_payload_of_unit.lin":46:9)
  ^b5:
    %v26 = llvm.load %s1 : !llvm.ptr -> i64 loc("tests/generics/a_variant_payload_of_unit.lin":49:16)
    %v27 = arith.constant 9 : i64 loc("tests/generics/a_variant_payload_of_unit.lin":49:21)
    %v28 = arith.cmpi ne, %v26, %v27 : i64 loc("tests/generics/a_variant_payload_of_unit.lin":49:16)
    cf.cond_br %v28, ^b7, ^b8 loc("tests/generics/a_variant_payload_of_unit.lin":49:13)
  ^b6:
    %lw49 = llvm.load %s5 : !llvm.ptr -> i8 loc("tests/generics/a_variant_payload_of_unit.lin":46:9)
    %v49 = arith.extui %lw49 : i8 to i64 loc("tests/generics/a_variant_payload_of_unit.lin":46:9)
    %sw50 = arith.trunci %v49 : i64 to i8 loc("tests/generics/a_variant_payload_of_unit.lin":43:5)
    llvm.store %sw50, %s4 : i8, !llvm.ptr loc("tests/generics/a_variant_payload_of_unit.lin":43:5)
    cf.br ^b3 loc("tests/generics/a_variant_payload_of_unit.lin":43:5)
  ^b7:
    %v30 = arith.constant 3 : i64 loc("tests/generics/a_variant_payload_of_unit.lin":50:17)
    %sw31 = arith.trunci %v30 : i64 to i8 loc("tests/generics/a_variant_payload_of_unit.lin":49:13)
    llvm.store %sw31, %s6 : i8, !llvm.ptr loc("tests/generics/a_variant_payload_of_unit.lin":49:13)
    cf.br ^b9 loc("tests/generics/a_variant_payload_of_unit.lin":49:13)
  ^b8:
    %v33 = llvm.load %s2 : !llvm.ptr -> i64 loc("tests/generics/a_variant_payload_of_unit.lin":52:20)
    %v34 = arith.constant 11 : i64 loc("tests/generics/a_variant_payload_of_unit.lin":52:25)
    %v35 = arith.cmpi ne, %v33, %v34 : i64 loc("tests/generics/a_variant_payload_of_unit.lin":52:20)
    cf.cond_br %v35, ^b10, ^b11 loc("tests/generics/a_variant_payload_of_unit.lin":52:17)
  ^b9:
    %lw46 = llvm.load %s6 : !llvm.ptr -> i8 loc("tests/generics/a_variant_payload_of_unit.lin":49:13)
    %v46 = arith.extui %lw46 : i8 to i64 loc("tests/generics/a_variant_payload_of_unit.lin":49:13)
    %sw47 = arith.trunci %v46 : i64 to i8 loc("tests/generics/a_variant_payload_of_unit.lin":46:9)
    llvm.store %sw47, %s5 : i8, !llvm.ptr loc("tests/generics/a_variant_payload_of_unit.lin":46:9)
    cf.br ^b6 loc("tests/generics/a_variant_payload_of_unit.lin":46:9)
  ^b10:
    %v37 = arith.constant 4 : i64 loc("tests/generics/a_variant_payload_of_unit.lin":53:21)
    %sw38 = arith.trunci %v37 : i64 to i8 loc("tests/generics/a_variant_payload_of_unit.lin":52:17)
    llvm.store %sw38, %s7 : i8, !llvm.ptr loc("tests/generics/a_variant_payload_of_unit.lin":52:17)
    cf.br ^b12 loc("tests/generics/a_variant_payload_of_unit.lin":52:17)
  ^b11:
    %v40 = arith.constant 0 : i64 loc("tests/generics/a_variant_payload_of_unit.lin":55:21)
    %sw41 = arith.trunci %v40 : i64 to i8 loc("tests/generics/a_variant_payload_of_unit.lin":52:17)
    llvm.store %sw41, %s7 : i8, !llvm.ptr loc("tests/generics/a_variant_payload_of_unit.lin":52:17)
    cf.br ^b12 loc("tests/generics/a_variant_payload_of_unit.lin":52:17)
  ^b12:
    %lw43 = llvm.load %s7 : !llvm.ptr -> i8 loc("tests/generics/a_variant_payload_of_unit.lin":52:17)
    %v43 = arith.extui %lw43 : i8 to i64 loc("tests/generics/a_variant_payload_of_unit.lin":52:17)
    %sw44 = arith.trunci %v43 : i64 to i8 loc("tests/generics/a_variant_payload_of_unit.lin":49:13)
    llvm.store %sw44, %s6 : i8, !llvm.ptr loc("tests/generics/a_variant_payload_of_unit.lin":49:13)
    cf.br ^b9 loc("tests/generics/a_variant_payload_of_unit.lin":49:13)
  }
  func.func private @"lin.;ident"(%a0: i64) -> i64 attributes {llvm.linkage = #llvm.linkage<internal>, passthrough = [["probe-stack", "inline-asm"]]} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    llvm.store %a0, %s0 : i64, !llvm.ptr
    cf.br ^b0
  ^b0:
    %v0 = llvm.load %s0 : !llvm.ptr -> i64 loc("tests/generics/a_variant_payload_of_unit.lin":19:5)
    func.return %v0 : i64 loc("tests/generics/a_variant_payload_of_unit.lin":19:5)
  }
  func.func private @"lin.;holds"(%a0: i64) -> i64 attributes {llvm.linkage = #llvm.linkage<internal>, passthrough = [["probe-stack", "inline-asm"]]} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 1 : i64
    %s1 = llvm.alloca %z1 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z2 = arith.constant 8 : i64
    %s2 = llvm.alloca %z2 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z3 = arith.constant 8 : i64
    %s3 = llvm.alloca %z3 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z4 = arith.constant 1 : i64
    %s4 = llvm.alloca %z4 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z5 = arith.constant 1 : i64
    %s5 = llvm.alloca %z5 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z6 = arith.constant 1 : i64
    %s6 = llvm.alloca %z6 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z7 = arith.constant 1 : i64
    %s7 = llvm.alloca %z7 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    llvm.store %a0, %s0 : i64, !llvm.ptr
    cf.br ^b0
  ^b0:
    %v0 = llvm.load %s0 : !llvm.ptr -> i64 loc("tests/generics/a_variant_payload_of_unit.lin":23:31)
    %v1 = func.call @"lin.;ident"(%v0) : (i64) -> i64 loc("tests/generics/a_variant_payload_of_unit.lin":23:25)
    llvm.store %v1, %s1 : i64, !llvm.ptr loc("tests/generics/a_variant_payload_of_unit.lin":23:5)
    %v4 = llvm.load %s0 : !llvm.ptr -> i64 loc("tests/generics/a_variant_payload_of_unit.lin":24:20)
    %v5 = arith.constant 0 : i64 loc("tests/generics/a_variant_payload_of_unit.lin":24:24)
    %v6 = arith.cmpi ugt, %v4, %v5 : i64 loc("tests/generics/a_variant_payload_of_unit.lin":24:20)
    cf.cond_br %v6, ^b1, ^b2 loc("tests/generics/a_variant_payload_of_unit.lin":24:17)
  ^b1:
    %v9 = arith.constant 1 : i64 loc("tests/generics/a_variant_payload_of_unit.lin":25:9)
    llvm.store %v9, %s3 : i64, !llvm.ptr loc("tests/generics/a_variant_payload_of_unit.lin":25:9)
    %v11 = arith.constant 8 : i64 loc("tests/generics/a_variant_payload_of_unit.lin":25:9)
    %v12 = llvm.getelementptr %s3[%v11] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("tests/generics/a_variant_payload_of_unit.lin":25:9)
    %v13 = arith.constant 0 : i64 loc("tests/generics/a_variant_payload_of_unit.lin":25:18)
    cf.br ^b3 loc("tests/generics/a_variant_payload_of_unit.lin":24:17)
  ^b2:
    %v16 = arith.constant 0 : i64 loc("tests/generics/a_variant_payload_of_unit.lin":27:9)
    llvm.store %v16, %s3 : i64, !llvm.ptr loc("tests/generics/a_variant_payload_of_unit.lin":27:9)
    cf.br ^b3 loc("tests/generics/a_variant_payload_of_unit.lin":24:17)
  ^b3:
    %cl20 = arith.constant 8 : i64 loc("tests/generics/a_variant_payload_of_unit.lin":24:5)
    "llvm.intr.memcpy"(%s2, %s3, %cl20) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("tests/generics/a_variant_payload_of_unit.lin":24:5)
    %v21 = llvm.load %s0 : !llvm.ptr -> i64 loc("tests/generics/a_variant_payload_of_unit.lin":29:32)
    %v22 = func.call @"lin.;ident"(%v21) : (i64) -> i64 loc("tests/generics/a_variant_payload_of_unit.lin":29:26)
    llvm.store %v22, %s4 : i64, !llvm.ptr loc("tests/generics/a_variant_payload_of_unit.lin":29:5)
    %v25 = llvm.load %s2 : !llvm.ptr -> i64 loc("tests/generics/a_variant_payload_of_unit.lin":30:27)
    %v26 = arith.constant 0 : i64 loc("tests/generics/a_variant_payload_of_unit.lin":30:27)
    %v27 = arith.cmpi eq, %v25, %v26 : i64 loc("tests/generics/a_variant_payload_of_unit.lin":30:27)
    cf.cond_br %v27, ^b6, ^b5 loc("tests/generics/a_variant_payload_of_unit.lin":30:27)
  ^b4:
    %v44 = llvm.load %s6 : !llvm.ptr -> i64 loc("tests/generics/a_variant_payload_of_unit.lin":30:27)
    llvm.store %v44, %s5 : i64, !llvm.ptr loc("tests/generics/a_variant_payload_of_unit.lin":30:5)
    %v46 = llvm.load %s1 : !llvm.ptr -> i64 loc("tests/generics/a_variant_payload_of_unit.lin":34:5)
    %v47 = llvm.load %s4 : !llvm.ptr -> i64 loc("tests/generics/a_variant_payload_of_unit.lin":34:13)
    %v48 = arith.addi %v46, %v47 : i64 loc("tests/generics/a_variant_payload_of_unit.lin":34:5)
    %k1 = arith.cmpi ult, %v48, %v46 : i64 loc("tests/generics/a_variant_payload_of_unit.lin":34:11)
    cf.cond_br %k1, ^t1, ^c1 loc("tests/generics/a_variant_payload_of_unit.lin":34:11)
  ^t1:
    %tk1 = arith.constant 0 : i32 loc("tests/generics/a_variant_payload_of_unit.lin":34:11)
    %tf1 = llvm.mlir.addressof @linea_file0 : !llvm.ptr loc("tests/generics/a_variant_payload_of_unit.lin":34:11)
    %tl1 = arith.constant 34 : i32 loc("tests/generics/a_variant_payload_of_unit.lin":34:11)
    %tc1 = arith.constant 11 : i32 loc("tests/generics/a_variant_payload_of_unit.lin":34:11)
    func.call @linea_trap(%tk1, %tf1, %tl1, %tc1) : (i32, !llvm.ptr, i32, i32) -> () loc("tests/generics/a_variant_payload_of_unit.lin":34:11)
    llvm.unreachable loc("tests/generics/a_variant_payload_of_unit.lin":34:11)
  ^c1:
    %p49 = arith.constant 0 : i64 loc("tests/generics/a_variant_payload_of_unit.lin":34:11)
    %v49 = arith.addi %v48, %p49 : i64 loc("tests/generics/a_variant_payload_of_unit.lin":34:11)
    %v50 = llvm.load %s5 : !llvm.ptr -> i64 loc("tests/generics/a_variant_payload_of_unit.lin":34:22)
    %v51 = arith.addi %v49, %v50 : i64 loc("tests/generics/a_variant_payload_of_unit.lin":34:5)
    %k2 = arith.cmpi ult, %v51, %v49 : i64 loc("tests/generics/a_variant_payload_of_unit.lin":34:20)
    cf.cond_br %k2, ^t2, ^c2 loc("tests/generics/a_variant_payload_of_unit.lin":34:20)
  ^t2:
    %tk2 = arith.constant 0 : i32 loc("tests/generics/a_variant_payload_of_unit.lin":34:20)
    %tf2 = llvm.mlir.addressof @linea_file0 : !llvm.ptr loc("tests/generics/a_variant_payload_of_unit.lin":34:20)
    %tl2 = arith.constant 34 : i32 loc("tests/generics/a_variant_payload_of_unit.lin":34:20)
    %tc2 = arith.constant 20 : i32 loc("tests/generics/a_variant_payload_of_unit.lin":34:20)
    func.call @linea_trap(%tk2, %tf2, %tl2, %tc2) : (i32, !llvm.ptr, i32, i32) -> () loc("tests/generics/a_variant_payload_of_unit.lin":34:20)
    llvm.unreachable loc("tests/generics/a_variant_payload_of_unit.lin":34:20)
  ^c2:
    %p52 = arith.constant 0 : i64 loc("tests/generics/a_variant_payload_of_unit.lin":34:20)
    %v52 = arith.addi %v51, %p52 : i64 loc("tests/generics/a_variant_payload_of_unit.lin":34:20)
    func.return %v52 : i64 loc("tests/generics/a_variant_payload_of_unit.lin":34:5)
  ^b5:
    %v32 = llvm.load %s2 : !llvm.ptr -> i64 loc("tests/generics/a_variant_payload_of_unit.lin":30:27)
    %v33 = arith.constant 1 : i64 loc("tests/generics/a_variant_payload_of_unit.lin":30:27)
    %v34 = arith.cmpi eq, %v32, %v33 : i64 loc("tests/generics/a_variant_payload_of_unit.lin":30:27)
    cf.cond_br %v34, ^b8, ^b7 loc("tests/generics/a_variant_payload_of_unit.lin":30:27)
  ^b6:
    %v29 = arith.constant 0 : i64 loc("tests/generics/a_variant_payload_of_unit.lin":31:17)
    llvm.store %v29, %s6 : i64, !llvm.ptr loc("tests/generics/a_variant_payload_of_unit.lin":30:27)
    cf.br ^b4 loc("tests/generics/a_variant_payload_of_unit.lin":30:27)
  ^b7:
    %tk3 = arith.constant 3 : i32 loc("tests/generics/a_variant_payload_of_unit.lin":30:27)
    %tf3 = llvm.mlir.addressof @linea_file0 : !llvm.ptr loc("tests/generics/a_variant_payload_of_unit.lin":30:27)
    %tl3 = arith.constant 30 : i32 loc("tests/generics/a_variant_payload_of_unit.lin":30:27)
    %tc3 = arith.constant 27 : i32 loc("tests/generics/a_variant_payload_of_unit.lin":30:27)
    func.call @linea_trap(%tk3, %tf3, %tl3, %tc3) : (i32, !llvm.ptr, i32, i32) -> () loc("tests/generics/a_variant_payload_of_unit.lin":30:27)
    llvm.unreachable loc("tests/generics/a_variant_payload_of_unit.lin":30:27)
  ^b8:
    %v36 = arith.constant 8 : i64 loc("tests/generics/a_variant_payload_of_unit.lin":30:27)
    %v37 = llvm.getelementptr %s2[%v36] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("tests/generics/a_variant_payload_of_unit.lin":30:27)
    %v38 = arith.constant 0 : i64 loc("tests/generics/a_variant_payload_of_unit.lin":30:27)
    llvm.store %v38, %s7 : i64, !llvm.ptr loc("tests/generics/a_variant_payload_of_unit.lin":30:27)
    %v40 = arith.constant 0 : i64 loc("tests/generics/a_variant_payload_of_unit.lin":32:20)
    llvm.store %v40, %s6 : i64, !llvm.ptr loc("tests/generics/a_variant_payload_of_unit.lin":30:27)
    cf.br ^b4 loc("tests/generics/a_variant_payload_of_unit.lin":30:27)
  }
  func.func @main(%argc: i32, %argv: !llvm.ptr) -> i32 {
    func.call @linea_set_args(%argc, %argv) : (i32, !llvm.ptr) -> ()
    %status = func.call @"lin.;main"() : () -> i64
    %status32 = arith.trunci %status : i64 to i32
    func.return %status32 : i32
  }
}
