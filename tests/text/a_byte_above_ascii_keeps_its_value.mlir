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
  llvm.mlir.global internal constant @linea_file0("tests/text/a_byte_above_ascii_keeps_its_value.lin\00") : !llvm.array<50 x i8>
  llvm.mlir.global internal constant @linea_file1("std/text/str.lin\00") : !llvm.array<17 x i8>
  llvm.mlir.global internal constant @linea_file2("std/mem/slice.lin\00") : !llvm.array<18 x i8>
  llvm.mlir.global internal constant @linea_str0("\C3\A1") : !llvm.array<2 x i8>
  func.func private @linea_set_args(i32, !llvm.ptr)
  func.func private @linea_trap(i32, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @linea_panic(i64, i64, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @"lin.;main"() -> i64 attributes {llvm.linkage = #llvm.linkage<internal>} {
    %z0 = arith.constant 16 : i64
    %s0 = llvm.alloca %z0 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
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
    %z6 = arith.constant 1 : i64
    %s6 = llvm.alloca %z6 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %rz11 = arith.constant 16 : i64
    %rs11 = llvm.alloca %rz11 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz35 = arith.constant 16 : i64
    %rs35 = llvm.alloca %rz35 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    cf.br ^b0
  ^b0:
    %ba1 = llvm.mlir.addressof @linea_str0 : !llvm.ptr loc("tests/text/a_byte_above_ascii_keeps_its_value.lin":10:13)
    %v1 = llvm.ptrtoint %ba1 : !llvm.ptr to i64 loc("tests/text/a_byte_above_ascii_keeps_its_value.lin":10:13)
    %v2 = arith.constant 0 : i64 loc("tests/text/a_byte_above_ascii_keeps_its_value.lin":10:13)
    llvm.store %v1, %s0 : i64, !llvm.ptr loc("tests/text/a_byte_above_ascii_keeps_its_value.lin":10:13)
    %v5 = arith.constant 2 : i64 loc("tests/text/a_byte_above_ascii_keeps_its_value.lin":10:13)
    %v6 = arith.constant 8 : i64 loc("tests/text/a_byte_above_ascii_keeps_its_value.lin":10:13)
    %v7 = llvm.getelementptr %s0[%v6] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("tests/text/a_byte_above_ascii_keeps_its_value.lin":10:13)
    llvm.store %v5, %v7 : i64, !llvm.ptr loc("tests/text/a_byte_above_ascii_keeps_its_value.lin":10:13)
    %v10 = arith.constant 0 : i64 loc("tests/text/a_byte_above_ascii_keeps_its_value.lin":12:41)
    func.call @"lin.std.text;Str.byte"(%rs11, %s0, %v10) : (!llvm.ptr, !llvm.ptr, i64) -> () loc("tests/text/a_byte_above_ascii_keeps_its_value.lin":12:29)
    %v12 = llvm.load %rs11 : !llvm.ptr -> i64 loc("tests/text/a_byte_above_ascii_keeps_its_value.lin":12:23)
    %v13 = arith.constant 1 : i64 loc("tests/text/a_byte_above_ascii_keeps_its_value.lin":12:23)
    %v14 = arith.cmpi eq, %v12, %v13 : i64 loc("tests/text/a_byte_above_ascii_keeps_its_value.lin":12:23)
    cf.cond_br %v14, ^b3, ^b2 loc("tests/text/a_byte_above_ascii_keeps_its_value.lin":12:23)
  ^b1:
    %lw31 = llvm.load %s2 : !llvm.ptr -> i8 loc("tests/text/a_byte_above_ascii_keeps_its_value.lin":12:23)
    %v31 = arith.extui %lw31 : i8 to i64 loc("tests/text/a_byte_above_ascii_keeps_its_value.lin":12:23)
    %sw32 = arith.trunci %v31 : i64 to i8 loc("tests/text/a_byte_above_ascii_keeps_its_value.lin":12:5)
    llvm.store %sw32, %s1 : i8, !llvm.ptr loc("tests/text/a_byte_above_ascii_keeps_its_value.lin":12:5)
    %v34 = arith.constant 1 : i64 loc("tests/text/a_byte_above_ascii_keeps_its_value.lin":17:49)
    func.call @"lin.std.text;Str.byte"(%rs35, %s0, %v34) : (!llvm.ptr, !llvm.ptr, i64) -> () loc("tests/text/a_byte_above_ascii_keeps_its_value.lin":17:37)
    %v36 = llvm.load %rs35 : !llvm.ptr -> i64 loc("tests/text/a_byte_above_ascii_keeps_its_value.lin":17:31)
    %v37 = arith.constant 1 : i64 loc("tests/text/a_byte_above_ascii_keeps_its_value.lin":17:31)
    %v38 = arith.cmpi eq, %v36, %v37 : i64 loc("tests/text/a_byte_above_ascii_keeps_its_value.lin":17:31)
    cf.cond_br %v38, ^b8, ^b7 loc("tests/text/a_byte_above_ascii_keeps_its_value.lin":17:31)
  ^b2:
    %v23 = llvm.load %rs11 : !llvm.ptr -> i64 loc("tests/text/a_byte_above_ascii_keeps_its_value.lin":12:23)
    %v24 = arith.constant 0 : i64 loc("tests/text/a_byte_above_ascii_keeps_its_value.lin":12:23)
    %v25 = arith.cmpi eq, %v23, %v24 : i64 loc("tests/text/a_byte_above_ascii_keeps_its_value.lin":12:23)
    cf.cond_br %v25, ^b5, ^b4 loc("tests/text/a_byte_above_ascii_keeps_its_value.lin":12:23)
  ^b3:
    %v16 = arith.constant 8 : i64 loc("tests/text/a_byte_above_ascii_keeps_its_value.lin":12:23)
    %v17 = llvm.getelementptr %rs11[%v16] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("tests/text/a_byte_above_ascii_keeps_its_value.lin":12:23)
    %iw18 = llvm.load %v17 : !llvm.ptr -> i8 loc("tests/text/a_byte_above_ascii_keeps_its_value.lin":12:23)
    %v18 = arith.extui %iw18 : i8 to i64 loc("tests/text/a_byte_above_ascii_keeps_its_value.lin":12:23)
    %sw19 = arith.trunci %v18 : i64 to i8 loc("tests/text/a_byte_above_ascii_keeps_its_value.lin":12:23)
    llvm.store %sw19, %s3 : i8, !llvm.ptr loc("tests/text/a_byte_above_ascii_keeps_its_value.lin":12:23)
    %lw20 = llvm.load %s3 : !llvm.ptr -> i8 loc("tests/text/a_byte_above_ascii_keeps_its_value.lin":13:20)
    %v20 = arith.extui %lw20 : i8 to i64 loc("tests/text/a_byte_above_ascii_keeps_its_value.lin":13:20)
    %sw21 = arith.trunci %v20 : i64 to i8 loc("tests/text/a_byte_above_ascii_keeps_its_value.lin":12:23)
    llvm.store %sw21, %s2 : i8, !llvm.ptr loc("tests/text/a_byte_above_ascii_keeps_its_value.lin":12:23)
    cf.br ^b1 loc("tests/text/a_byte_above_ascii_keeps_its_value.lin":12:23)
  ^b4:
    %tk1 = arith.constant 3 : i32 loc("tests/text/a_byte_above_ascii_keeps_its_value.lin":12:23)
    %tf1 = llvm.mlir.addressof @linea_file0 : !llvm.ptr loc("tests/text/a_byte_above_ascii_keeps_its_value.lin":12:23)
    %tl1 = arith.constant 12 : i32 loc("tests/text/a_byte_above_ascii_keeps_its_value.lin":12:23)
    %tc1 = arith.constant 23 : i32 loc("tests/text/a_byte_above_ascii_keeps_its_value.lin":12:23)
    func.call @linea_trap(%tk1, %tf1, %tl1, %tc1) : (i32, !llvm.ptr, i32, i32) -> () loc("tests/text/a_byte_above_ascii_keeps_its_value.lin":12:23)
    llvm.unreachable loc("tests/text/a_byte_above_ascii_keeps_its_value.lin":12:23)
  ^b5:
    %v27 = arith.constant 0 : i64 loc("tests/text/a_byte_above_ascii_keeps_its_value.lin":14:17)
    %sw28 = arith.trunci %v27 : i64 to i8 loc("tests/text/a_byte_above_ascii_keeps_its_value.lin":12:23)
    llvm.store %sw28, %s2 : i8, !llvm.ptr loc("tests/text/a_byte_above_ascii_keeps_its_value.lin":12:23)
    cf.br ^b1 loc("tests/text/a_byte_above_ascii_keeps_its_value.lin":12:23)
  ^b6:
    %lw55 = llvm.load %s5 : !llvm.ptr -> i8 loc("tests/text/a_byte_above_ascii_keeps_its_value.lin":17:31)
    %v55 = arith.extui %lw55 : i8 to i64 loc("tests/text/a_byte_above_ascii_keeps_its_value.lin":17:31)
    %sw56 = arith.trunci %v55 : i64 to i8 loc("tests/text/a_byte_above_ascii_keeps_its_value.lin":17:5)
    llvm.store %sw56, %s4 : i8, !llvm.ptr loc("tests/text/a_byte_above_ascii_keeps_its_value.lin":17:5)
    %lw57 = llvm.load %s1 : !llvm.ptr -> i8 loc("tests/text/a_byte_above_ascii_keeps_its_value.lin":22:8)
    %v57 = arith.extui %lw57 : i8 to i64 loc("tests/text/a_byte_above_ascii_keeps_its_value.lin":22:8)
    %v58 = arith.constant 195 : i64 loc("tests/text/a_byte_above_ascii_keeps_its_value.lin":22:16)
    %v59 = arith.cmpi ne, %v57, %v58 : i64 loc("tests/text/a_byte_above_ascii_keeps_its_value.lin":22:8)
    cf.cond_br %v59, ^b11, ^b12 loc("tests/text/a_byte_above_ascii_keeps_its_value.lin":22:5)
  ^b7:
    %v47 = llvm.load %rs35 : !llvm.ptr -> i64 loc("tests/text/a_byte_above_ascii_keeps_its_value.lin":17:31)
    %v48 = arith.constant 0 : i64 loc("tests/text/a_byte_above_ascii_keeps_its_value.lin":17:31)
    %v49 = arith.cmpi eq, %v47, %v48 : i64 loc("tests/text/a_byte_above_ascii_keeps_its_value.lin":17:31)
    cf.cond_br %v49, ^b10, ^b9 loc("tests/text/a_byte_above_ascii_keeps_its_value.lin":17:31)
  ^b8:
    %v40 = arith.constant 8 : i64 loc("tests/text/a_byte_above_ascii_keeps_its_value.lin":17:31)
    %v41 = llvm.getelementptr %rs35[%v40] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("tests/text/a_byte_above_ascii_keeps_its_value.lin":17:31)
    %iw42 = llvm.load %v41 : !llvm.ptr -> i8 loc("tests/text/a_byte_above_ascii_keeps_its_value.lin":17:31)
    %v42 = arith.extui %iw42 : i8 to i64 loc("tests/text/a_byte_above_ascii_keeps_its_value.lin":17:31)
    %sw43 = arith.trunci %v42 : i64 to i8 loc("tests/text/a_byte_above_ascii_keeps_its_value.lin":17:31)
    llvm.store %sw43, %s6 : i8, !llvm.ptr loc("tests/text/a_byte_above_ascii_keeps_its_value.lin":17:31)
    %lw44 = llvm.load %s6 : !llvm.ptr -> i8 loc("tests/text/a_byte_above_ascii_keeps_its_value.lin":18:20)
    %v44 = arith.extui %lw44 : i8 to i64 loc("tests/text/a_byte_above_ascii_keeps_its_value.lin":18:20)
    %sw45 = arith.trunci %v44 : i64 to i8 loc("tests/text/a_byte_above_ascii_keeps_its_value.lin":17:31)
    llvm.store %sw45, %s5 : i8, !llvm.ptr loc("tests/text/a_byte_above_ascii_keeps_its_value.lin":17:31)
    cf.br ^b6 loc("tests/text/a_byte_above_ascii_keeps_its_value.lin":17:31)
  ^b9:
    %tk2 = arith.constant 3 : i32 loc("tests/text/a_byte_above_ascii_keeps_its_value.lin":17:31)
    %tf2 = llvm.mlir.addressof @linea_file0 : !llvm.ptr loc("tests/text/a_byte_above_ascii_keeps_its_value.lin":17:31)
    %tl2 = arith.constant 17 : i32 loc("tests/text/a_byte_above_ascii_keeps_its_value.lin":17:31)
    %tc2 = arith.constant 31 : i32 loc("tests/text/a_byte_above_ascii_keeps_its_value.lin":17:31)
    func.call @linea_trap(%tk2, %tf2, %tl2, %tc2) : (i32, !llvm.ptr, i32, i32) -> () loc("tests/text/a_byte_above_ascii_keeps_its_value.lin":17:31)
    llvm.unreachable loc("tests/text/a_byte_above_ascii_keeps_its_value.lin":17:31)
  ^b10:
    %v51 = arith.constant 0 : i64 loc("tests/text/a_byte_above_ascii_keeps_its_value.lin":19:17)
    %sw52 = arith.trunci %v51 : i64 to i8 loc("tests/text/a_byte_above_ascii_keeps_its_value.lin":17:31)
    llvm.store %sw52, %s5 : i8, !llvm.ptr loc("tests/text/a_byte_above_ascii_keeps_its_value.lin":17:31)
    cf.br ^b6 loc("tests/text/a_byte_above_ascii_keeps_its_value.lin":17:31)
  ^b11:
    %v61 = arith.constant 1 : i64 loc("tests/text/a_byte_above_ascii_keeps_its_value.lin":23:16)
    func.return %v61 : i64 loc("tests/text/a_byte_above_ascii_keeps_its_value.lin":23:9)
  ^b12:
    cf.br ^b13 loc("tests/text/a_byte_above_ascii_keeps_its_value.lin":22:5)
  ^b13:
    %v66 = arith.constant 0 : i64 loc("tests/text/a_byte_above_ascii_keeps_its_value.lin":22:5)
    %lw67 = llvm.load %s4 : !llvm.ptr -> i8 loc("tests/text/a_byte_above_ascii_keeps_its_value.lin":25:8)
    %v67 = arith.extui %lw67 : i8 to i64 loc("tests/text/a_byte_above_ascii_keeps_its_value.lin":25:8)
    %v68 = arith.constant 161 : i64 loc("tests/text/a_byte_above_ascii_keeps_its_value.lin":25:24)
    %v69 = arith.cmpi ne, %v67, %v68 : i64 loc("tests/text/a_byte_above_ascii_keeps_its_value.lin":25:8)
    cf.cond_br %v69, ^b15, ^b16 loc("tests/text/a_byte_above_ascii_keeps_its_value.lin":25:5)
  ^b15:
    %v71 = arith.constant 2 : i64 loc("tests/text/a_byte_above_ascii_keeps_its_value.lin":26:16)
    func.return %v71 : i64 loc("tests/text/a_byte_above_ascii_keeps_its_value.lin":26:9)
  ^b16:
    cf.br ^b17 loc("tests/text/a_byte_above_ascii_keeps_its_value.lin":25:5)
  ^b17:
    %v76 = arith.constant 0 : i64 loc("tests/text/a_byte_above_ascii_keeps_its_value.lin":25:5)
    %v77 = arith.constant 0 : i64 loc("tests/text/a_byte_above_ascii_keeps_its_value.lin":28:5)
    func.return %v77 : i64 loc("tests/text/a_byte_above_ascii_keeps_its_value.lin":28:5)
  }
  func.func private @"lin.std.text;Str.byte"(%sret: !llvm.ptr, %a0: !llvm.ptr, %a1: i64) attributes {llvm.linkage = #llvm.linkage<internal>} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x !llvm.ptr {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 1 : i64
    %s1 = llvm.alloca %z1 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z2 = arith.constant 16 : i64
    %s2 = llvm.alloca %z2 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    llvm.store %a0, %s0 : !llvm.ptr, !llvm.ptr
    llvm.store %a1, %s1 : i64, !llvm.ptr
    cf.br ^b0
  ^b0:
    %v0 = llvm.load %s1 : !llvm.ptr -> i64 loc("std/text/str.lin":L:C)
    %v1 = llvm.load %s0 : !llvm.ptr -> !llvm.ptr loc("std/text/str.lin":L:C)
    %v2 = func.call @"lin.std.text;Str.length"(%v1) : (!llvm.ptr) -> i64 loc("std/text/str.lin":L:C)
    %v3 = arith.cmpi uge, %v0, %v2 : i64 loc("std/text/str.lin":L:C)
    cf.cond_br %v3, ^b1, ^b2 loc("std/text/str.lin":L:C)
  ^b1:
    %v6 = arith.constant 0 : i64 loc("std/text/str.lin":L:C)
    llvm.store %v6, %s2 : i64, !llvm.ptr loc("std/text/str.lin":L:C)
    cf.br ^b3 loc("std/text/str.lin":L:C)
  ^b2:
    %v10 = arith.constant 1 : i64 loc("std/text/str.lin":L:C)
    llvm.store %v10, %s2 : i64, !llvm.ptr loc("std/text/str.lin":L:C)
    %v12 = arith.constant 8 : i64 loc("std/text/str.lin":L:C)
    %v13 = llvm.getelementptr %s2[%v12] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/text/str.lin":L:C)
    %v14 = llvm.load %s0 : !llvm.ptr -> !llvm.ptr loc("std/text/str.lin":L:C)
    %v15 = arith.constant 0 : i64 loc("std/text/str.lin":L:C)
    %v17 = llvm.load %s1 : !llvm.ptr -> i64 loc("std/text/str.lin":L:C)
    %v18 = arith.constant 1 : i64 loc("std/text/str.lin":L:C)
    %v19 = arith.constant 0 : i64 loc("std/text/str.lin":L:C)
    %v21 = llvm.load %v14 : !llvm.ptr -> i64 loc("std/text/str.lin":L:C)
    %v22 = arith.constant 8 : i64 loc("std/text/str.lin":L:C)
    %v23 = llvm.getelementptr %v14[%v22] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/text/str.lin":L:C)
    %v24 = llvm.load %v23 : !llvm.ptr -> i64 loc("std/text/str.lin":L:C)
    %v25 = arith.cmpi ult, %v17, %v24 : i64 loc("std/text/str.lin":L:C)
    %k1z = arith.constant true loc("std/text/str.lin":L:C)
    %k1 = arith.xori %v25, %k1z : i1 loc("std/text/str.lin":L:C)
    cf.cond_br %k1, ^t1, ^c1 loc("std/text/str.lin":L:C)
  ^t1:
    %tk1 = arith.constant 6 : i32 loc("std/text/str.lin":L:C)
    %tf1 = llvm.mlir.addressof @linea_file1 : !llvm.ptr loc("std/text/str.lin":L:C)
    %tl1 = arith.constant L : i32 loc("std/text/str.lin":L:C)
    %tc1 = arith.constant C : i32 loc("std/text/str.lin":L:C)
    func.call @linea_trap(%tk1, %tf1, %tl1, %tc1) : (i32, !llvm.ptr, i32, i32) -> () loc("std/text/str.lin":L:C)
    llvm.unreachable loc("std/text/str.lin":L:C)
  ^c1:
    %v26 = arith.ori %v25, %v25 : i1 loc("std/text/str.lin":L:C)
    %m27 = "llvm.intr.umul.with.overflow"(%v24, %v18) : (i64, i64) -> !llvm.struct<(i64, i1)> loc("std/text/str.lin":L:C)
    %v27 = llvm.extractvalue %m27[0] : !llvm.struct<(i64, i1)> loc("std/text/str.lin":L:C)
    %k2 = llvm.extractvalue %m27[1] : !llvm.struct<(i64, i1)> loc("std/text/str.lin":L:C)
    cf.cond_br %k2, ^t2, ^c2 loc("std/text/str.lin":L:C)
  ^t2:
    %tk2 = arith.constant 0 : i32 loc("std/text/str.lin":L:C)
    %tf2 = llvm.mlir.addressof @linea_file1 : !llvm.ptr loc("std/text/str.lin":L:C)
    %tl2 = arith.constant L : i32 loc("std/text/str.lin":L:C)
    %tc2 = arith.constant C : i32 loc("std/text/str.lin":L:C)
    func.call @linea_trap(%tk2, %tf2, %tl2, %tc2) : (i32, !llvm.ptr, i32, i32) -> () loc("std/text/str.lin":L:C)
    llvm.unreachable loc("std/text/str.lin":L:C)
  ^c2:
    %p28 = arith.constant 0 : i64 loc("std/text/str.lin":L:C)
    %v28 = arith.addi %v27, %p28 : i64 loc("std/text/str.lin":L:C)
    %m29 = "llvm.intr.umul.with.overflow"(%v17, %v18) : (i64, i64) -> !llvm.struct<(i64, i1)> loc("std/text/str.lin":L:C)
    %v29 = llvm.extractvalue %m29[0] : !llvm.struct<(i64, i1)> loc("std/text/str.lin":L:C)
    %k3 = llvm.extractvalue %m29[1] : !llvm.struct<(i64, i1)> loc("std/text/str.lin":L:C)
    cf.cond_br %k3, ^t3, ^c3 loc("std/text/str.lin":L:C)
  ^t3:
    %tk3 = arith.constant 0 : i32 loc("std/text/str.lin":L:C)
    %tf3 = llvm.mlir.addressof @linea_file1 : !llvm.ptr loc("std/text/str.lin":L:C)
    %tl3 = arith.constant L : i32 loc("std/text/str.lin":L:C)
    %tc3 = arith.constant C : i32 loc("std/text/str.lin":L:C)
    func.call @linea_trap(%tk3, %tf3, %tl3, %tc3) : (i32, !llvm.ptr, i32, i32) -> () loc("std/text/str.lin":L:C)
    llvm.unreachable loc("std/text/str.lin":L:C)
  ^c3:
    %p30 = arith.constant 0 : i64 loc("std/text/str.lin":L:C)
    %v30 = arith.addi %v29, %p30 : i64 loc("std/text/str.lin":L:C)
    %v31 = arith.constant 1 : i64 loc("std/text/str.lin":L:C)
    %v32 = arith.addi %v29, %v31 : i64 loc("std/text/str.lin":L:C)
    %k4 = arith.cmpi ult, %v32, %v29 : i64 loc("std/text/str.lin":L:C)
    cf.cond_br %k4, ^t4, ^c4 loc("std/text/str.lin":L:C)
  ^t4:
    %tk4 = arith.constant 0 : i32 loc("std/text/str.lin":L:C)
    %tf4 = llvm.mlir.addressof @linea_file1 : !llvm.ptr loc("std/text/str.lin":L:C)
    %tl4 = arith.constant L : i32 loc("std/text/str.lin":L:C)
    %tc4 = arith.constant C : i32 loc("std/text/str.lin":L:C)
    func.call @linea_trap(%tk4, %tf4, %tl4, %tc4) : (i32, !llvm.ptr, i32, i32) -> () loc("std/text/str.lin":L:C)
    llvm.unreachable loc("std/text/str.lin":L:C)
  ^c4:
    %p33 = arith.constant 0 : i64 loc("std/text/str.lin":L:C)
    %v33 = arith.addi %v32, %p33 : i64 loc("std/text/str.lin":L:C)
    %v34 = arith.cmpi ule, %v32, %v27 : i64 loc("std/text/str.lin":L:C)
    %k5z = arith.constant true loc("std/text/str.lin":L:C)
    %k5 = arith.xori %v34, %k5z : i1 loc("std/text/str.lin":L:C)
    cf.cond_br %k5, ^t5, ^c5 loc("std/text/str.lin":L:C)
  ^t5:
    %tk5 = arith.constant 6 : i32 loc("std/text/str.lin":L:C)
    %tf5 = llvm.mlir.addressof @linea_file1 : !llvm.ptr loc("std/text/str.lin":L:C)
    %tl5 = arith.constant L : i32 loc("std/text/str.lin":L:C)
    %tc5 = arith.constant C : i32 loc("std/text/str.lin":L:C)
    func.call @linea_trap(%tk5, %tf5, %tl5, %tc5) : (i32, !llvm.ptr, i32, i32) -> () loc("std/text/str.lin":L:C)
    llvm.unreachable loc("std/text/str.lin":L:C)
  ^c5:
    %v35 = arith.ori %v34, %v34 : i1 loc("std/text/str.lin":L:C)
    %v36 = arith.addi %v21, %v29 : i64 loc("std/text/str.lin":L:C)
    %v37 = llvm.inttoptr %v36 : i64 to !llvm.ptr loc("std/text/str.lin":L:C)
    %iw38 = llvm.load %v37 : !llvm.ptr -> i8 loc("std/text/str.lin":L:C)
    %v38 = arith.extui %iw38 : i8 to i64 loc("std/text/str.lin":L:C)
    %iw39 = arith.trunci %v38 : i64 to i8 loc("std/text/str.lin":L:C)
    llvm.store %iw39, %v13 : i8, !llvm.ptr loc("std/text/str.lin":L:C)
    cf.br ^b3 loc("std/text/str.lin":L:C)
  ^b3:
    %rl42 = arith.constant 16 : i64 loc("std/text/str.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s2, %rl42) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/text/str.lin":L:C)
    func.return loc("std/text/str.lin":L:C)
  }
  func.func private @"lin.std.text;Str.length"(%a0: !llvm.ptr) -> i64 attributes {llvm.linkage = #llvm.linkage<internal>} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x !llvm.ptr {alignment = 8 : i64} : (i64) -> !llvm.ptr
    llvm.store %a0, %s0 : !llvm.ptr, !llvm.ptr
    cf.br ^b0
  ^b0:
    %v0 = llvm.load %s0 : !llvm.ptr -> !llvm.ptr loc("std/text/str.lin":L:C)
    %v1 = arith.constant 0 : i64 loc("std/text/str.lin":L:C)
    %v3 = func.call @"lin.std.mem;Slice[UInt8].length"(%v0) : (!llvm.ptr) -> i64 loc("std/text/str.lin":L:C)
    func.return %v3 : i64 loc("std/text/str.lin":L:C)
  }
  func.func private @"lin.std.mem;Slice[UInt8].length"(%a0: !llvm.ptr) -> i64 attributes {llvm.linkage = #llvm.linkage<internal>} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x !llvm.ptr {alignment = 8 : i64} : (i64) -> !llvm.ptr
    llvm.store %a0, %s0 : !llvm.ptr, !llvm.ptr
    cf.br ^b0
  ^b0:
    %v0 = llvm.load %s0 : !llvm.ptr -> !llvm.ptr loc("std/mem/slice.lin":L:C)
    %v1 = arith.constant 8 : i64 loc("std/mem/slice.lin":L:C)
    %v2 = llvm.getelementptr %v0[%v1] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/mem/slice.lin":L:C)
    %v3 = llvm.load %v2 : !llvm.ptr -> i64 loc("std/mem/slice.lin":L:C)
    func.return %v3 : i64 loc("std/mem/slice.lin":L:C)
  }
  func.func @main(%argc: i32, %argv: !llvm.ptr) -> i32 {
    func.call @linea_set_args(%argc, %argv) : (i32, !llvm.ptr) -> ()
    %status = func.call @"lin.;main"() : () -> i64
    %status32 = arith.trunci %status : i64 to i32
    func.return %status32 : i32
  }
}
