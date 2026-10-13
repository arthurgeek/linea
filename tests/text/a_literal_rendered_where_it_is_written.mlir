!linea_static0 = !llvm.struct<packed (i64, i64)>
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
  llvm.mlir.global internal constant @linea_file0("tests/text/a_literal_rendered_where_it_is_written.lin\00") : !llvm.array<54 x i8>
  llvm.mlir.global internal constant @linea_file1("std/fmt/render.lin\00") : !llvm.array<19 x i8>
  llvm.mlir.global internal constant @linea_file2("std/fmt/decimal.lin\00") : !llvm.array<20 x i8>
  llvm.mlir.global internal constant @linea_file3("std/text/str.lin\00") : !llvm.array<17 x i8>
  llvm.mlir.global internal constant @linea_file4("std/mem/slice.lin\00") : !llvm.array<18 x i8>
  llvm.mlir.global internal constant @linea_file5("std/option/option.lin\00") : !llvm.array<22 x i8>
  llvm.mlir.global internal constant @linea_str0("answer ") : !llvm.array<7 x i8>
  llvm.mlir.global internal constant @linea_str1("") : !llvm.array<0 x i8>
  llvm.mlir.global internal constant @linea_str2("-") : !llvm.array<1 x i8>
  llvm.mlir.global internal constant @linea_str3("00010203040506070809101112131415161718192021222324252627282930313233343536373839404142434445464748495051525354555657585960616263646566676869707172737475767778798081828384858687888990919293949596979899") : !llvm.array<200 x i8>
  llvm.mlir.global internal constant @linea_str4("0") : !llvm.array<1 x i8>
  llvm.mlir.global internal constant @linea_str5("called Option.unwrap on None") : !llvm.array<28 x i8>
  llvm.mlir.global internal constant @linea_static0() {addr_space = 0 : i32, alignment = 8 : i64} : !linea_static0 {
    %s0 = llvm.mlir.undef : !linea_static0
    %a0 = llvm.mlir.addressof @linea_str3 : !llvm.ptr
    %e0 = llvm.ptrtoint %a0 : !llvm.ptr to i64
    %s1 = llvm.insertvalue %e0, %s0[0] : !linea_static0
    %e1 = llvm.mlir.constant(200 : i64) : i64
    %s2 = llvm.insertvalue %e1, %s1[1] : !linea_static0
    llvm.return %s2 : !linea_static0
  }
  func.func private @linea_set_args(i32, !llvm.ptr)
  func.func private @linea_trap(i32, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @linea_panic(i64, i64, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @"lin.;main"() -> i64 attributes {llvm.linkage = #llvm.linkage<internal>} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 8 : i64
    %s1 = llvm.alloca %z1 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z2 = arith.constant 40 : i64
    %s2 = llvm.alloca %z2 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z3 = arith.constant 8 : i64
    %s3 = llvm.alloca %z3 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z4 = arith.constant 8 : i64
    %s4 = llvm.alloca %z4 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z5 = arith.constant 1 : i64
    %s5 = llvm.alloca %z5 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z6 = arith.constant 1 : i64
    %s6 = llvm.alloca %z6 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz35 = arith.constant 8 : i64
    %rs35 = llvm.alloca %rz35 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz46 = arith.constant 8 : i64
    %rs46 = llvm.alloca %rz46 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz56 = arith.constant 8 : i64
    %rs56 = llvm.alloca %rz56 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    cf.br ^b0
  ^b0:
    %v0 = arith.constant 6 : i64 loc("tests/text/a_literal_rendered_where_it_is_written.lin":26:25)
    %sw1 = arith.trunci %v0 : i64 to i8 loc("tests/text/a_literal_rendered_where_it_is_written.lin":26:5)
    llvm.store %sw1, %s0 : i8, !llvm.ptr loc("tests/text/a_literal_rendered_where_it_is_written.lin":26:5)
    %v3 = arith.constant 0 : i64 loc("tests/text/a_literal_rendered_where_it_is_written.lin":27:17)
    %v5 = arith.constant 0 : i64 loc("tests/text/a_literal_rendered_where_it_is_written.lin":27:33)
    llvm.store %v5, %s1 : i64, !llvm.ptr loc("tests/text/a_literal_rendered_where_it_is_written.lin":27:17)
    %v8 = arith.constant 0 : i64 loc("tests/text/a_literal_rendered_where_it_is_written.lin":29:23)
    %ba10 = llvm.mlir.addressof @linea_str0 : !llvm.ptr loc("tests/text/a_literal_rendered_where_it_is_written.lin":29:23)
    %v10 = llvm.ptrtoint %ba10 : !llvm.ptr to i64 loc("tests/text/a_literal_rendered_where_it_is_written.lin":29:23)
    %v11 = arith.constant 0 : i64 loc("tests/text/a_literal_rendered_where_it_is_written.lin":29:23)
    llvm.store %v10, %s2 : i64, !llvm.ptr loc("tests/text/a_literal_rendered_where_it_is_written.lin":29:23)
    %v14 = arith.constant 7 : i64 loc("tests/text/a_literal_rendered_where_it_is_written.lin":29:23)
    %v15 = arith.constant 8 : i64 loc("tests/text/a_literal_rendered_where_it_is_written.lin":29:23)
    %v16 = llvm.getelementptr %s2[%v15] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("tests/text/a_literal_rendered_where_it_is_written.lin":29:23)
    llvm.store %v14, %v16 : i64, !llvm.ptr loc("tests/text/a_literal_rendered_where_it_is_written.lin":29:23)
    %v18 = arith.constant 16 : i64 loc("tests/text/a_literal_rendered_where_it_is_written.lin":29:23)
    %v19 = llvm.getelementptr %s2[%v18] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("tests/text/a_literal_rendered_where_it_is_written.lin":29:23)
    %lw20 = llvm.load %s0 : !llvm.ptr -> i8 loc("tests/text/a_literal_rendered_where_it_is_written.lin":29:32)
    %v20 = arith.extui %lw20 : i8 to i64 loc("tests/text/a_literal_rendered_where_it_is_written.lin":29:32)
    %iw21 = arith.trunci %v20 : i64 to i8 loc("tests/text/a_literal_rendered_where_it_is_written.lin":29:23)
    llvm.store %iw21, %v19 : i8, !llvm.ptr loc("tests/text/a_literal_rendered_where_it_is_written.lin":29:23)
    %v22 = arith.constant 24 : i64 loc("tests/text/a_literal_rendered_where_it_is_written.lin":29:23)
    %v23 = llvm.getelementptr %s2[%v22] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("tests/text/a_literal_rendered_where_it_is_written.lin":29:23)
    %ba24 = llvm.mlir.addressof @linea_str1 : !llvm.ptr loc("tests/text/a_literal_rendered_where_it_is_written.lin":29:38)
    %v24 = llvm.ptrtoint %ba24 : !llvm.ptr to i64 loc("tests/text/a_literal_rendered_where_it_is_written.lin":29:38)
    %v25 = arith.constant 0 : i64 loc("tests/text/a_literal_rendered_where_it_is_written.lin":29:38)
    llvm.store %v24, %v23 : i64, !llvm.ptr loc("tests/text/a_literal_rendered_where_it_is_written.lin":29:38)
    %v28 = arith.constant 0 : i64 loc("tests/text/a_literal_rendered_where_it_is_written.lin":29:38)
    %v29 = arith.constant 8 : i64 loc("tests/text/a_literal_rendered_where_it_is_written.lin":29:38)
    %v30 = llvm.getelementptr %v23[%v29] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("tests/text/a_literal_rendered_where_it_is_written.lin":29:38)
    llvm.store %v28, %v30 : i64, !llvm.ptr loc("tests/text/a_literal_rendered_where_it_is_written.lin":29:38)
    %v33 = arith.constant 0 : i64 loc("tests/text/a_literal_rendered_where_it_is_written.lin":29:11)
    func.call @"lin.std.text.Str;std.fmt;Display.fmt[Tally]"(%rs35, %s2, %s1) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("tests/text/a_literal_rendered_where_it_is_written.lin":29:11)
    %v36 = llvm.load %rs35 : !llvm.ptr -> i64 loc("tests/text/a_literal_rendered_where_it_is_written.lin":29:11)
    %v37 = arith.constant 0 : i64 loc("tests/text/a_literal_rendered_where_it_is_written.lin":29:11)
    %v38 = arith.cmpi eq, %v36, %v37 : i64 loc("tests/text/a_literal_rendered_where_it_is_written.lin":29:11)
    cf.cond_br %v38, ^b2, ^b3 loc("tests/text/a_literal_rendered_where_it_is_written.lin":29:11)
  ^b1:
    %v71 = llvm.load %s3 : !llvm.ptr -> i64 loc("tests/text/a_literal_rendered_where_it_is_written.lin":29:5)
    %v72 = arith.constant 0 : i64 loc("tests/text/a_literal_rendered_where_it_is_written.lin":29:5)
    %v73 = arith.cmpi eq, %v71, %v72 : i64 loc("tests/text/a_literal_rendered_where_it_is_written.lin":29:5)
    cf.cond_br %v73, ^b9, ^b10 loc("tests/text/a_literal_rendered_where_it_is_written.lin":29:5)
  ^b2:
    %v43 = arith.constant 16 : i64 loc("tests/text/a_literal_rendered_where_it_is_written.lin":29:11)
    %v44 = llvm.getelementptr %s2[%v43] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("tests/text/a_literal_rendered_where_it_is_written.lin":29:11)
    %iw45 = llvm.load %v44 : !llvm.ptr -> i8 loc("tests/text/a_literal_rendered_where_it_is_written.lin":29:11)
    %v45 = arith.extui %iw45 : i8 to i64 loc("tests/text/a_literal_rendered_where_it_is_written.lin":29:11)
    func.call @"lin.UInt8;std.fmt;Display.fmt[Tally]"(%rs46, %v45, %s1) : (!llvm.ptr, i64, !llvm.ptr) -> () loc("tests/text/a_literal_rendered_where_it_is_written.lin":29:11)
    %v47 = llvm.load %rs46 : !llvm.ptr -> i64 loc("tests/text/a_literal_rendered_where_it_is_written.lin":29:11)
    %v48 = arith.constant 0 : i64 loc("tests/text/a_literal_rendered_where_it_is_written.lin":29:11)
    %v49 = arith.cmpi eq, %v47, %v48 : i64 loc("tests/text/a_literal_rendered_where_it_is_written.lin":29:11)
    cf.cond_br %v49, ^b4, ^b5 loc("tests/text/a_literal_rendered_where_it_is_written.lin":29:11)
  ^b3:
    %cl41 = arith.constant 8 : i64 loc("tests/text/a_literal_rendered_where_it_is_written.lin":29:11)
    "llvm.intr.memcpy"(%s3, %rs35, %cl41) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("tests/text/a_literal_rendered_where_it_is_written.lin":29:11)
    cf.br ^b1 loc("tests/text/a_literal_rendered_where_it_is_written.lin":29:11)
  ^b4:
    %v54 = arith.constant 24 : i64 loc("tests/text/a_literal_rendered_where_it_is_written.lin":29:11)
    %v55 = llvm.getelementptr %s2[%v54] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("tests/text/a_literal_rendered_where_it_is_written.lin":29:11)
    func.call @"lin.std.text.Str;std.fmt;Display.fmt[Tally]"(%rs56, %v55, %s1) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("tests/text/a_literal_rendered_where_it_is_written.lin":29:11)
    %v57 = llvm.load %rs56 : !llvm.ptr -> i64 loc("tests/text/a_literal_rendered_where_it_is_written.lin":29:11)
    %v58 = arith.constant 0 : i64 loc("tests/text/a_literal_rendered_where_it_is_written.lin":29:11)
    %v59 = arith.cmpi eq, %v57, %v58 : i64 loc("tests/text/a_literal_rendered_where_it_is_written.lin":29:11)
    cf.cond_br %v59, ^b6, ^b7 loc("tests/text/a_literal_rendered_where_it_is_written.lin":29:11)
  ^b5:
    %cl52 = arith.constant 8 : i64 loc("tests/text/a_literal_rendered_where_it_is_written.lin":29:11)
    "llvm.intr.memcpy"(%s3, %rs46, %cl52) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("tests/text/a_literal_rendered_where_it_is_written.lin":29:11)
    cf.br ^b1 loc("tests/text/a_literal_rendered_where_it_is_written.lin":29:11)
  ^b6:
    %v64 = arith.constant 0 : i64 loc("tests/text/a_literal_rendered_where_it_is_written.lin":29:11)
    llvm.store %v64, %s4 : i64, !llvm.ptr loc("tests/text/a_literal_rendered_where_it_is_written.lin":29:11)
    %cl68 = arith.constant 8 : i64 loc("tests/text/a_literal_rendered_where_it_is_written.lin":29:11)
    "llvm.intr.memcpy"(%s3, %s4, %cl68) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("tests/text/a_literal_rendered_where_it_is_written.lin":29:11)
    cf.br ^b1 loc("tests/text/a_literal_rendered_where_it_is_written.lin":29:11)
  ^b7:
    %cl62 = arith.constant 8 : i64 loc("tests/text/a_literal_rendered_where_it_is_written.lin":29:11)
    "llvm.intr.memcpy"(%s3, %rs56, %cl62) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("tests/text/a_literal_rendered_where_it_is_written.lin":29:11)
    cf.br ^b1 loc("tests/text/a_literal_rendered_where_it_is_written.lin":29:11)
  ^b8:
    %lw91 = llvm.load %s5 : !llvm.ptr -> i8 loc("tests/text/a_literal_rendered_where_it_is_written.lin":29:5)
    %v91 = arith.extui %lw91 : i8 to i64 loc("tests/text/a_literal_rendered_where_it_is_written.lin":29:5)
    func.return %v91 : i64 loc("tests/text/a_literal_rendered_where_it_is_written.lin":29:5)
  ^b9:
    %v75 = arith.constant 8 : i64 loc("tests/text/a_literal_rendered_where_it_is_written.lin":29:5)
    %v76 = llvm.getelementptr %s3[%v75] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("tests/text/a_literal_rendered_where_it_is_written.lin":29:5)
    %v77 = arith.constant 0 : i64 loc("tests/text/a_literal_rendered_where_it_is_written.lin":29:5)
    llvm.store %v77, %s6 : i64, !llvm.ptr loc("tests/text/a_literal_rendered_where_it_is_written.lin":29:5)
    %v80 = arith.constant 0 : i64 loc("tests/text/a_literal_rendered_where_it_is_written.lin":30:24)
    %v82 = llvm.load %s1 : !llvm.ptr -> i64 loc("tests/text/a_literal_rendered_where_it_is_written.lin":30:24)
    %k1m = arith.constant 255 : i64 loc("tests/text/a_literal_rendered_where_it_is_written.lin":30:18)
    %k1 = arith.cmpi ugt, %v82, %k1m : i64 loc("tests/text/a_literal_rendered_where_it_is_written.lin":30:18)
    cf.cond_br %k1, ^t1, ^c1 loc("tests/text/a_literal_rendered_where_it_is_written.lin":30:18)
  ^t1:
    %tk1 = arith.constant 2 : i32 loc("tests/text/a_literal_rendered_where_it_is_written.lin":30:18)
    %tf1 = llvm.mlir.addressof @linea_file0 : !llvm.ptr loc("tests/text/a_literal_rendered_where_it_is_written.lin":30:18)
    %tl1 = arith.constant 30 : i32 loc("tests/text/a_literal_rendered_where_it_is_written.lin":30:18)
    %tc1 = arith.constant 18 : i32 loc("tests/text/a_literal_rendered_where_it_is_written.lin":30:18)
    func.call @linea_trap(%tk1, %tf1, %tl1, %tc1) : (i32, !llvm.ptr, i32, i32) -> () loc("tests/text/a_literal_rendered_where_it_is_written.lin":30:18)
    llvm.unreachable loc("tests/text/a_literal_rendered_where_it_is_written.lin":30:18)
  ^c1:
    %p83 = arith.constant 0 : i64 loc("tests/text/a_literal_rendered_where_it_is_written.lin":30:18)
    %v83 = arith.addi %v82, %p83 : i64 loc("tests/text/a_literal_rendered_where_it_is_written.lin":30:18)
    %sw84 = arith.trunci %v83 : i64 to i8 loc("tests/text/a_literal_rendered_where_it_is_written.lin":29:5)
    llvm.store %sw84, %s5 : i8, !llvm.ptr loc("tests/text/a_literal_rendered_where_it_is_written.lin":29:5)
    cf.br ^b8 loc("tests/text/a_literal_rendered_where_it_is_written.lin":29:5)
  ^b10:
    %v86 = arith.constant 1 : i64 loc("tests/text/a_literal_rendered_where_it_is_written.lin":29:5)
    %v87 = arith.cmpi eq, %v71, %v86 : i64 loc("tests/text/a_literal_rendered_where_it_is_written.lin":29:5)
    cf.cond_br %v87, ^b11, ^b12 loc("tests/text/a_literal_rendered_where_it_is_written.lin":29:5)
  ^b11:
    %tk2 = arith.constant 3 : i32 loc("tests/text/a_literal_rendered_where_it_is_written.lin":29:5)
    %tf2 = llvm.mlir.addressof @linea_file0 : !llvm.ptr loc("tests/text/a_literal_rendered_where_it_is_written.lin":29:5)
    %tl2 = arith.constant 29 : i32 loc("tests/text/a_literal_rendered_where_it_is_written.lin":29:5)
    %tc2 = arith.constant 5 : i32 loc("tests/text/a_literal_rendered_where_it_is_written.lin":29:5)
    func.call @linea_trap(%tk2, %tf2, %tl2, %tc2) : (i32, !llvm.ptr, i32, i32) -> () loc("tests/text/a_literal_rendered_where_it_is_written.lin":29:5)
    llvm.unreachable loc("tests/text/a_literal_rendered_where_it_is_written.lin":29:5)
  ^b12:
    %tk3 = arith.constant 3 : i32 loc("tests/text/a_literal_rendered_where_it_is_written.lin":29:5)
    %tf3 = llvm.mlir.addressof @linea_file0 : !llvm.ptr loc("tests/text/a_literal_rendered_where_it_is_written.lin":29:5)
    %tl3 = arith.constant 29 : i32 loc("tests/text/a_literal_rendered_where_it_is_written.lin":29:5)
    %tc3 = arith.constant 5 : i32 loc("tests/text/a_literal_rendered_where_it_is_written.lin":29:5)
    func.call @linea_trap(%tk3, %tf3, %tl3, %tc3) : (i32, !llvm.ptr, i32, i32) -> () loc("tests/text/a_literal_rendered_where_it_is_written.lin":29:5)
    llvm.unreachable loc("tests/text/a_literal_rendered_where_it_is_written.lin":29:5)
  }
  func.func private @"lin.std.text.Str;std.fmt;Display.fmt[Tally]"(%sret: !llvm.ptr, %a0: !llvm.ptr, %a1: !llvm.ptr) attributes {llvm.linkage = #llvm.linkage<internal>} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x !llvm.ptr {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 1 : i64
    %s1 = llvm.alloca %z1 x !llvm.ptr {alignment = 8 : i64} : (i64) -> !llvm.ptr
    llvm.store %a0, %s0 : !llvm.ptr, !llvm.ptr
    llvm.store %a1, %s1 : !llvm.ptr, !llvm.ptr
    cf.br ^b0
  ^b0:
    %v0 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/fmt/render.lin":L:C)
    %v1 = llvm.load %s0 : !llvm.ptr -> !llvm.ptr loc("std/fmt/render.lin":L:C)
    func.call @"lin.Tally;std.io.core;Writer.write_str"(%sret, %v0, %v1) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/fmt/render.lin":L:C)
    func.return loc("std/fmt/render.lin":L:C)
  }
  func.func private @"lin.UInt8;std.fmt;Display.fmt[Tally]"(%sret: !llvm.ptr, %a0: i64, %a1: !llvm.ptr) attributes {llvm.linkage = #llvm.linkage<internal>} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 1 : i64
    %s1 = llvm.alloca %z1 x !llvm.ptr {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z2 = arith.constant 8 : i64
    %s2 = llvm.alloca %z2 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %pw0 = arith.trunci %a0 : i64 to i8
    llvm.store %pw0, %s0 : i8, !llvm.ptr
    llvm.store %a1, %s1 : !llvm.ptr, !llvm.ptr
    cf.br ^b0
  ^b0:
    %lw0 = llvm.load %s0 : !llvm.ptr -> i8 loc("std/fmt/decimal.lin":L:C)
    %v0 = arith.extui %lw0 : i8 to i64 loc("std/fmt/decimal.lin":L:C)
    %v1 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %k1m = arith.constant 255 : i64 loc("std/fmt/decimal.lin":L:C)
    %k1 = arith.cmpi ugt, %v1, %k1m : i64 loc("std/fmt/decimal.lin":L:C)
    cf.cond_br %k1, ^t1, ^c1 loc("std/fmt/decimal.lin":L:C)
  ^t1:
    %tk1 = arith.constant 2 : i32 loc("std/fmt/decimal.lin":L:C)
    %tf1 = llvm.mlir.addressof @linea_file2 : !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    %tl1 = arith.constant L : i32 loc("std/fmt/decimal.lin":L:C)
    %tc1 = arith.constant C : i32 loc("std/fmt/decimal.lin":L:C)
    func.call @linea_trap(%tk1, %tf1, %tl1, %tc1) : (i32, !llvm.ptr, i32, i32) -> () loc("std/fmt/decimal.lin":L:C)
    llvm.unreachable loc("std/fmt/decimal.lin":L:C)
  ^c1:
    %p2 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %v2 = arith.addi %v1, %p2 : i64 loc("std/fmt/decimal.lin":L:C)
    %v3 = arith.cmpi ult, %v0, %v2 : i64 loc("std/fmt/decimal.lin":L:C)
    cf.cond_br %v3, ^b1, ^b2 loc("std/fmt/decimal.lin":L:C)
  ^b1:
    %lw6 = llvm.load %s0 : !llvm.ptr -> i8 loc("std/fmt/decimal.lin":L:C)
    %v6 = arith.extui %lw6 : i8 to i64 loc("std/fmt/decimal.lin":L:C)
    %p7 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %v7 = arith.addi %v6, %p7 : i64 loc("std/fmt/decimal.lin":L:C)
    %v8 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    func.call @"lin.std.fmt;format_signed[Tally]"(%sret, %v7, %v8) : (!llvm.ptr, i64, !llvm.ptr) -> () loc("std/fmt/decimal.lin":L:C)
    func.return loc("std/fmt/decimal.lin":L:C)
  ^b2:
    %lw13 = llvm.load %s0 : !llvm.ptr -> i8 loc("std/fmt/decimal.lin":L:C)
    %v13 = arith.extui %lw13 : i8 to i64 loc("std/fmt/decimal.lin":L:C)
    %p14 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %v14 = arith.addi %v13, %p14 : i64 loc("std/fmt/decimal.lin":L:C)
    %v15 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    func.call @"lin.std.fmt;format_unsigned[Tally]"(%sret, %v14, %v15) : (!llvm.ptr, i64, !llvm.ptr) -> () loc("std/fmt/decimal.lin":L:C)
    func.return loc("std/fmt/decimal.lin":L:C)
  }
  func.func private @"lin.Tally;std.io.core;Writer.write_str"(%sret: !llvm.ptr, %a0: !llvm.ptr, %a1: !llvm.ptr) attributes {llvm.linkage = #llvm.linkage<internal>} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x !llvm.ptr {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 1 : i64
    %s1 = llvm.alloca %z1 x !llvm.ptr {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z2 = arith.constant 8 : i64
    %s2 = llvm.alloca %z2 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    llvm.store %a0, %s0 : !llvm.ptr, !llvm.ptr
    llvm.store %a1, %s1 : !llvm.ptr, !llvm.ptr
    cf.br ^b0
  ^b0:
    %v0 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("tests/text/a_literal_rendered_where_it_is_written.lin":20:23)
    %v1 = func.call @"lin.std.text;Str.length"(%v0) : (!llvm.ptr) -> i64 loc("tests/text/a_literal_rendered_where_it_is_written.lin":20:23)
    %v2 = llvm.load %s0 : !llvm.ptr -> !llvm.ptr loc("tests/text/a_literal_rendered_where_it_is_written.lin":20:9)
    %v3 = arith.constant 0 : i64 loc("tests/text/a_literal_rendered_where_it_is_written.lin":20:9)
    %v5 = llvm.load %v2 : !llvm.ptr -> i64 loc("tests/text/a_literal_rendered_where_it_is_written.lin":20:9)
    %v6 = arith.addi %v5, %v1 : i64 loc("tests/text/a_literal_rendered_where_it_is_written.lin":20:9)
    %k1 = arith.cmpi ult, %v6, %v5 : i64 loc("tests/text/a_literal_rendered_where_it_is_written.lin":20:20)
    cf.cond_br %k1, ^t1, ^c1 loc("tests/text/a_literal_rendered_where_it_is_written.lin":20:20)
  ^t1:
    %tk1 = arith.constant 0 : i32 loc("tests/text/a_literal_rendered_where_it_is_written.lin":20:20)
    %tf1 = llvm.mlir.addressof @linea_file0 : !llvm.ptr loc("tests/text/a_literal_rendered_where_it_is_written.lin":20:20)
    %tl1 = arith.constant 20 : i32 loc("tests/text/a_literal_rendered_where_it_is_written.lin":20:20)
    %tc1 = arith.constant 20 : i32 loc("tests/text/a_literal_rendered_where_it_is_written.lin":20:20)
    func.call @linea_trap(%tk1, %tf1, %tl1, %tc1) : (i32, !llvm.ptr, i32, i32) -> () loc("tests/text/a_literal_rendered_where_it_is_written.lin":20:20)
    llvm.unreachable loc("tests/text/a_literal_rendered_where_it_is_written.lin":20:20)
  ^c1:
    %p7 = arith.constant 0 : i64 loc("tests/text/a_literal_rendered_where_it_is_written.lin":20:20)
    %v7 = arith.addi %v6, %p7 : i64 loc("tests/text/a_literal_rendered_where_it_is_written.lin":20:20)
    llvm.store %v7, %v2 : i64, !llvm.ptr loc("tests/text/a_literal_rendered_where_it_is_written.lin":20:9)
    %v9 = arith.constant 0 : i64 loc("tests/text/a_literal_rendered_where_it_is_written.lin":20:9)
    %v10 = arith.constant 0 : i64 loc("tests/text/a_literal_rendered_where_it_is_written.lin":21:16)
    llvm.store %v10, %s2 : i64, !llvm.ptr loc("tests/text/a_literal_rendered_where_it_is_written.lin":21:16)
    %v13 = arith.constant 8 : i64 loc("tests/text/a_literal_rendered_where_it_is_written.lin":21:16)
    %v14 = llvm.getelementptr %s2[%v13] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("tests/text/a_literal_rendered_where_it_is_written.lin":21:16)
    %v15 = arith.constant 0 : i64 loc("tests/text/a_literal_rendered_where_it_is_written.lin":21:20)
    %rl16 = arith.constant 8 : i64 loc("tests/text/a_literal_rendered_where_it_is_written.lin":21:9)
    "llvm.intr.memcpy"(%sret, %s2, %rl16) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("tests/text/a_literal_rendered_where_it_is_written.lin":21:9)
    func.return loc("tests/text/a_literal_rendered_where_it_is_written.lin":21:9)
  }
  func.func private @"lin.std.fmt;format_signed[Tally]"(%sret: !llvm.ptr, %a0: i64, %a1: !llvm.ptr) attributes {llvm.linkage = #llvm.linkage<internal>} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 1 : i64
    %s1 = llvm.alloca %z1 x !llvm.ptr {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z2 = arith.constant 16 : i64
    %s2 = llvm.alloca %z2 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z3 = arith.constant 1 : i64
    %s3 = llvm.alloca %z3 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z4 = arith.constant 1 : i64
    %s4 = llvm.alloca %z4 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z5 = arith.constant 1 : i64
    %s5 = llvm.alloca %z5 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z6 = arith.constant 1 : i64
    %s6 = llvm.alloca %z6 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z7 = arith.constant 1 : i64
    %s7 = llvm.alloca %z7 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z8 = arith.constant 1 : i64
    %s8 = llvm.alloca %z8 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z9 = arith.constant 8 : i64
    %s9 = llvm.alloca %z9 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    llvm.store %a0, %s0 : i64, !llvm.ptr
    llvm.store %a1, %s1 : !llvm.ptr, !llvm.ptr
    %rz14 = arith.constant 8 : i64
    %rs14 = llvm.alloca %rz14 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz66 = arith.constant 16 : i64
    %rs66 = llvm.alloca %rz66 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz67 = arith.constant 8 : i64
    %rs67 = llvm.alloca %rz67 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    cf.br ^b0
  ^b0:
    %v0 = llvm.load %s0 : !llvm.ptr -> i64 loc("std/fmt/decimal.lin":L:C)
    %v1 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %v2 = arith.cmpi slt, %v0, %v1 : i64 loc("std/fmt/decimal.lin":L:C)
    cf.cond_br %v2, ^b1, ^b2 loc("std/fmt/decimal.lin":L:C)
  ^b1:
    %v4 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    %ba6 = llvm.mlir.addressof @linea_str2 : !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    %v6 = llvm.ptrtoint %ba6 : !llvm.ptr to i64 loc("std/fmt/decimal.lin":L:C)
    %v7 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    llvm.store %v6, %s2 : i64, !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    %v10 = arith.constant 1 : i64 loc("std/fmt/decimal.lin":L:C)
    %v11 = arith.constant 8 : i64 loc("std/fmt/decimal.lin":L:C)
    %v12 = llvm.getelementptr %s2[%v11] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/fmt/decimal.lin":L:C)
    llvm.store %v10, %v12 : i64, !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    func.call @"lin.Tally;std.io.core;Writer.write_str"(%rs14, %v4, %s2) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/fmt/decimal.lin":L:C)
    %v15 = llvm.load %rs14 : !llvm.ptr -> i64 loc("std/fmt/decimal.lin":L:C)
    %v16 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %v17 = arith.cmpi eq, %v15, %v16 : i64 loc("std/fmt/decimal.lin":L:C)
    cf.cond_br %v17, ^b4, ^b5 loc("std/fmt/decimal.lin":L:C)
  ^b2:
    cf.br ^b3 loc("std/fmt/decimal.lin":L:C)
  ^b3:
    %v25 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %v26 = llvm.load %s0 : !llvm.ptr -> i64 loc("std/fmt/decimal.lin":L:C)
    %v27 = func.call @"lin.std.fmt;scale"(%v26) : (i64) -> i64 loc("std/fmt/decimal.lin":L:C)
    llvm.store %v27, %s3 : i64, !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    %v29 = arith.constant 1 : i1 loc("std/fmt/decimal.lin":L:C)
    %sw30 = arith.extui %v29 : i1 to i8 loc("std/fmt/decimal.lin":L:C)
    llvm.store %sw30, %s4 : i8, !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    cf.br ^b6 loc("std/fmt/decimal.lin":L:C)
  ^b4:
    %v20 = arith.constant 8 : i64 loc("std/fmt/decimal.lin":L:C)
    %v21 = llvm.getelementptr %rs14[%v20] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/fmt/decimal.lin":L:C)
    %v22 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    cf.br ^b3 loc("std/fmt/decimal.lin":L:C)
  ^b5:
    %tk1 = arith.constant 3 : i32 loc("std/fmt/decimal.lin":L:C)
    %tf1 = llvm.mlir.addressof @linea_file2 : !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    %tl1 = arith.constant L : i32 loc("std/fmt/decimal.lin":L:C)
    %tc1 = arith.constant C : i32 loc("std/fmt/decimal.lin":L:C)
    func.call @linea_trap(%tk1, %tf1, %tl1, %tc1) : (i32, !llvm.ptr, i32, i32) -> () loc("std/fmt/decimal.lin":L:C)
    llvm.unreachable loc("std/fmt/decimal.lin":L:C)
  ^b6:
    %v32 = llvm.load %s3 : !llvm.ptr -> i64 loc("std/fmt/decimal.lin":L:C)
    %v33 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %v34 = arith.cmpi sgt, %v32, %v33 : i64 loc("std/fmt/decimal.lin":L:C)
    cf.cond_br %v34, ^b7, ^b8 loc("std/fmt/decimal.lin":L:C)
  ^b7:
    %v36 = llvm.load %s0 : !llvm.ptr -> i64 loc("std/fmt/decimal.lin":L:C)
    %v37 = llvm.load %s3 : !llvm.ptr -> i64 loc("std/fmt/decimal.lin":L:C)
    %k2z = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %k2 = arith.cmpi eq, %v37, %k2z : i64 loc("std/fmt/decimal.lin":L:C)
    cf.cond_br %k2, ^t2, ^c2 loc("std/fmt/decimal.lin":L:C)
  ^t2:
    %tk2 = arith.constant 1 : i32 loc("std/fmt/decimal.lin":L:C)
    %tf2 = llvm.mlir.addressof @linea_file2 : !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    %tl2 = arith.constant L : i32 loc("std/fmt/decimal.lin":L:C)
    %tc2 = arith.constant C : i32 loc("std/fmt/decimal.lin":L:C)
    func.call @linea_trap(%tk2, %tf2, %tl2, %tc2) : (i32, !llvm.ptr, i32, i32) -> () loc("std/fmt/decimal.lin":L:C)
    llvm.unreachable loc("std/fmt/decimal.lin":L:C)
  ^c2:
    %p38 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %v38 = arith.addi %v37, %p38 : i64 loc("std/fmt/decimal.lin":L:C)
    %k3ca = arith.constant -9223372036854775808 : i64 loc("std/fmt/decimal.lin":L:C)
    %k3a = arith.cmpi eq, %v36, %k3ca : i64 loc("std/fmt/decimal.lin":L:C)
    %k3cb = arith.constant -1 : i64 loc("std/fmt/decimal.lin":L:C)
    %k3b = arith.cmpi eq, %v38, %k3cb : i64 loc("std/fmt/decimal.lin":L:C)
    %k3 = arith.andi %k3a, %k3b : i1 loc("std/fmt/decimal.lin":L:C)
    cf.cond_br %k3, ^t3, ^c3 loc("std/fmt/decimal.lin":L:C)
  ^t3:
    %tk3 = arith.constant 0 : i32 loc("std/fmt/decimal.lin":L:C)
    %tf3 = llvm.mlir.addressof @linea_file2 : !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    %tl3 = arith.constant L : i32 loc("std/fmt/decimal.lin":L:C)
    %tc3 = arith.constant C : i32 loc("std/fmt/decimal.lin":L:C)
    func.call @linea_trap(%tk3, %tf3, %tl3, %tc3) : (i32, !llvm.ptr, i32, i32) -> () loc("std/fmt/decimal.lin":L:C)
    llvm.unreachable loc("std/fmt/decimal.lin":L:C)
  ^c3:
    %v39 = arith.divsi %v36, %v38 : i64 loc("std/fmt/decimal.lin":L:C)
    %p40 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %v40 = arith.addi %v39, %p40 : i64 loc("std/fmt/decimal.lin":L:C)
    llvm.store %v40, %s5 : i64, !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    %v42 = llvm.load %s5 : !llvm.ptr -> i64 loc("std/fmt/decimal.lin":L:C)
    %v43 = arith.constant 100 : i64 loc("std/fmt/decimal.lin":L:C)
    %k4z = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %k4 = arith.cmpi eq, %v43, %k4z : i64 loc("std/fmt/decimal.lin":L:C)
    cf.cond_br %k4, ^t4, ^c4 loc("std/fmt/decimal.lin":L:C)
  ^t4:
    %tk4 = arith.constant 1 : i32 loc("std/fmt/decimal.lin":L:C)
    %tf4 = llvm.mlir.addressof @linea_file2 : !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    %tl4 = arith.constant L : i32 loc("std/fmt/decimal.lin":L:C)
    %tc4 = arith.constant C : i32 loc("std/fmt/decimal.lin":L:C)
    func.call @linea_trap(%tk4, %tf4, %tl4, %tc4) : (i32, !llvm.ptr, i32, i32) -> () loc("std/fmt/decimal.lin":L:C)
    llvm.unreachable loc("std/fmt/decimal.lin":L:C)
  ^c4:
    %p44 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %v44 = arith.addi %v43, %p44 : i64 loc("std/fmt/decimal.lin":L:C)
    %k5ca = arith.constant -9223372036854775808 : i64 loc("std/fmt/decimal.lin":L:C)
    %k5a = arith.cmpi eq, %v42, %k5ca : i64 loc("std/fmt/decimal.lin":L:C)
    %k5cb = arith.constant -1 : i64 loc("std/fmt/decimal.lin":L:C)
    %k5b = arith.cmpi eq, %v44, %k5cb : i64 loc("std/fmt/decimal.lin":L:C)
    %k5 = arith.andi %k5a, %k5b : i1 loc("std/fmt/decimal.lin":L:C)
    cf.cond_br %k5, ^t5, ^c5 loc("std/fmt/decimal.lin":L:C)
  ^t5:
    %tk5 = arith.constant 0 : i32 loc("std/fmt/decimal.lin":L:C)
    %tf5 = llvm.mlir.addressof @linea_file2 : !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    %tl5 = arith.constant L : i32 loc("std/fmt/decimal.lin":L:C)
    %tc5 = arith.constant C : i32 loc("std/fmt/decimal.lin":L:C)
    func.call @linea_trap(%tk5, %tf5, %tl5, %tc5) : (i32, !llvm.ptr, i32, i32) -> () loc("std/fmt/decimal.lin":L:C)
    llvm.unreachable loc("std/fmt/decimal.lin":L:C)
  ^c5:
    %v45 = arith.remsi %v42, %v44 : i64 loc("std/fmt/decimal.lin":L:C)
    %p46 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %v46 = arith.addi %v45, %p46 : i64 loc("std/fmt/decimal.lin":L:C)
    llvm.store %v46, %s6 : i64, !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    %v48 = llvm.load %s6 : !llvm.ptr -> i64 loc("std/fmt/decimal.lin":L:C)
    %v49 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %v50 = arith.cmpi slt, %v48, %v49 : i64 loc("std/fmt/decimal.lin":L:C)
    cf.cond_br %v50, ^b9, ^b10 loc("std/fmt/decimal.lin":L:C)
  ^b8:
    %v87 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %v88 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    llvm.store %v88, %s9 : i64, !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    %v91 = arith.constant 8 : i64 loc("std/fmt/decimal.lin":L:C)
    %v92 = llvm.getelementptr %s9[%v91] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/fmt/decimal.lin":L:C)
    %v93 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %rl94 = arith.constant 8 : i64 loc("std/fmt/decimal.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s9, %rl94) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/fmt/decimal.lin":L:C)
    func.return loc("std/fmt/decimal.lin":L:C)
  ^b9:
    %v52 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %v53 = llvm.load %s6 : !llvm.ptr -> i64 loc("std/fmt/decimal.lin":L:C)
    %v54 = arith.subi %v52, %v53 : i64 loc("std/fmt/decimal.lin":L:C)
    %k6a = arith.xori %v52, %v53 : i64 loc("std/fmt/decimal.lin":L:C)
    %k6b = arith.xori %v52, %v54 : i64 loc("std/fmt/decimal.lin":L:C)
    %k6c = arith.andi %k6a, %k6b : i64 loc("std/fmt/decimal.lin":L:C)
    %k6z = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %k6 = arith.cmpi slt, %k6c, %k6z : i64 loc("std/fmt/decimal.lin":L:C)
    cf.cond_br %k6, ^t6, ^c6 loc("std/fmt/decimal.lin":L:C)
  ^t6:
    %tk6 = arith.constant 0 : i32 loc("std/fmt/decimal.lin":L:C)
    %tf6 = llvm.mlir.addressof @linea_file2 : !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    %tl6 = arith.constant L : i32 loc("std/fmt/decimal.lin":L:C)
    %tc6 = arith.constant C : i32 loc("std/fmt/decimal.lin":L:C)
    func.call @linea_trap(%tk6, %tf6, %tl6, %tc6) : (i32, !llvm.ptr, i32, i32) -> () loc("std/fmt/decimal.lin":L:C)
    llvm.unreachable loc("std/fmt/decimal.lin":L:C)
  ^c6:
    %p55 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %v55 = arith.addi %v54, %p55 : i64 loc("std/fmt/decimal.lin":L:C)
    llvm.store %v55, %s8 : i64, !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    cf.br ^b11 loc("std/fmt/decimal.lin":L:C)
  ^b10:
    %v58 = llvm.load %s6 : !llvm.ptr -> i64 loc("std/fmt/decimal.lin":L:C)
    llvm.store %v58, %s8 : i64, !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    cf.br ^b11 loc("std/fmt/decimal.lin":L:C)
  ^b11:
    %v61 = llvm.load %s8 : !llvm.ptr -> i64 loc("std/fmt/decimal.lin":L:C)
    llvm.store %v61, %s7 : i64, !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    %v63 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    %v64 = llvm.load %s7 : !llvm.ptr -> i64 loc("std/fmt/decimal.lin":L:C)
    %lw65 = llvm.load %s4 : !llvm.ptr -> i8 loc("std/fmt/decimal.lin":L:C)
    %lz65 = arith.constant 0 : i8 loc("std/fmt/decimal.lin":L:C)
    %v65 = arith.cmpi ne, %lw65, %lz65 : i8 loc("std/fmt/decimal.lin":L:C)
    func.call @"lin.std.fmt;digits"(%rs66, %v64, %v65) : (!llvm.ptr, i64, i1) -> () loc("std/fmt/decimal.lin":L:C)
    func.call @"lin.Tally;std.io.core;Writer.write_str"(%rs67, %v63, %rs66) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/fmt/decimal.lin":L:C)
    %v68 = llvm.load %rs67 : !llvm.ptr -> i64 loc("std/fmt/decimal.lin":L:C)
    %v69 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %v70 = arith.cmpi eq, %v68, %v69 : i64 loc("std/fmt/decimal.lin":L:C)
    cf.cond_br %v70, ^b12, ^b13 loc("std/fmt/decimal.lin":L:C)
  ^b12:
    %v73 = arith.constant 8 : i64 loc("std/fmt/decimal.lin":L:C)
    %v74 = llvm.getelementptr %rs67[%v73] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/fmt/decimal.lin":L:C)
    %v75 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %v76 = arith.constant 0 : i1 loc("std/fmt/decimal.lin":L:C)
    %sw77 = arith.extui %v76 : i1 to i8 loc("std/fmt/decimal.lin":L:C)
    llvm.store %sw77, %s4 : i8, !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    %v78 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %v79 = llvm.load %s3 : !llvm.ptr -> i64 loc("std/fmt/decimal.lin":L:C)
    %v80 = arith.constant 100 : i64 loc("std/fmt/decimal.lin":L:C)
    %k7z = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %k7 = arith.cmpi eq, %v80, %k7z : i64 loc("std/fmt/decimal.lin":L:C)
    cf.cond_br %k7, ^t7, ^c7 loc("std/fmt/decimal.lin":L:C)
  ^t7:
    %tk7 = arith.constant 1 : i32 loc("std/fmt/decimal.lin":L:C)
    %tf7 = llvm.mlir.addressof @linea_file2 : !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    %tl7 = arith.constant L : i32 loc("std/fmt/decimal.lin":L:C)
    %tc7 = arith.constant C : i32 loc("std/fmt/decimal.lin":L:C)
    func.call @linea_trap(%tk7, %tf7, %tl7, %tc7) : (i32, !llvm.ptr, i32, i32) -> () loc("std/fmt/decimal.lin":L:C)
    llvm.unreachable loc("std/fmt/decimal.lin":L:C)
  ^c7:
    %p81 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %v81 = arith.addi %v80, %p81 : i64 loc("std/fmt/decimal.lin":L:C)
    %k8ca = arith.constant -9223372036854775808 : i64 loc("std/fmt/decimal.lin":L:C)
    %k8a = arith.cmpi eq, %v79, %k8ca : i64 loc("std/fmt/decimal.lin":L:C)
    %k8cb = arith.constant -1 : i64 loc("std/fmt/decimal.lin":L:C)
    %k8b = arith.cmpi eq, %v81, %k8cb : i64 loc("std/fmt/decimal.lin":L:C)
    %k8 = arith.andi %k8a, %k8b : i1 loc("std/fmt/decimal.lin":L:C)
    cf.cond_br %k8, ^t8, ^c8 loc("std/fmt/decimal.lin":L:C)
  ^t8:
    %tk8 = arith.constant 0 : i32 loc("std/fmt/decimal.lin":L:C)
    %tf8 = llvm.mlir.addressof @linea_file2 : !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    %tl8 = arith.constant L : i32 loc("std/fmt/decimal.lin":L:C)
    %tc8 = arith.constant C : i32 loc("std/fmt/decimal.lin":L:C)
    func.call @linea_trap(%tk8, %tf8, %tl8, %tc8) : (i32, !llvm.ptr, i32, i32) -> () loc("std/fmt/decimal.lin":L:C)
    llvm.unreachable loc("std/fmt/decimal.lin":L:C)
  ^c8:
    %v82 = arith.divsi %v79, %v81 : i64 loc("std/fmt/decimal.lin":L:C)
    %p83 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %v83 = arith.addi %v82, %p83 : i64 loc("std/fmt/decimal.lin":L:C)
    llvm.store %v83, %s3 : i64, !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    %v85 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    cf.br ^b6 loc("std/fmt/decimal.lin":L:C)
  ^b13:
    %tk9 = arith.constant 3 : i32 loc("std/fmt/decimal.lin":L:C)
    %tf9 = llvm.mlir.addressof @linea_file2 : !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    %tl9 = arith.constant L : i32 loc("std/fmt/decimal.lin":L:C)
    %tc9 = arith.constant C : i32 loc("std/fmt/decimal.lin":L:C)
    func.call @linea_trap(%tk9, %tf9, %tl9, %tc9) : (i32, !llvm.ptr, i32, i32) -> () loc("std/fmt/decimal.lin":L:C)
    llvm.unreachable loc("std/fmt/decimal.lin":L:C)
  }
  func.func private @"lin.std.fmt;format_unsigned[Tally]"(%sret: !llvm.ptr, %a0: i64, %a1: !llvm.ptr) attributes {llvm.linkage = #llvm.linkage<internal>} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 1 : i64
    %s1 = llvm.alloca %z1 x !llvm.ptr {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z2 = arith.constant 1 : i64
    %s2 = llvm.alloca %z2 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z3 = arith.constant 1 : i64
    %s3 = llvm.alloca %z3 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z4 = arith.constant 1 : i64
    %s4 = llvm.alloca %z4 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z5 = arith.constant 1 : i64
    %s5 = llvm.alloca %z5 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z6 = arith.constant 8 : i64
    %s6 = llvm.alloca %z6 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    llvm.store %a0, %s0 : i64, !llvm.ptr
    llvm.store %a1, %s1 : !llvm.ptr, !llvm.ptr
    %rz26 = arith.constant 16 : i64
    %rs26 = llvm.alloca %rz26 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz27 = arith.constant 8 : i64
    %rs27 = llvm.alloca %rz27 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    cf.br ^b0
  ^b0:
    %v0 = llvm.load %s0 : !llvm.ptr -> i64 loc("std/fmt/decimal.lin":L:C)
    %v1 = func.call @"lin.std.fmt;scale_unsigned"(%v0) : (i64) -> i64 loc("std/fmt/decimal.lin":L:C)
    llvm.store %v1, %s2 : i64, !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    %v3 = arith.constant 1 : i1 loc("std/fmt/decimal.lin":L:C)
    %sw4 = arith.extui %v3 : i1 to i8 loc("std/fmt/decimal.lin":L:C)
    llvm.store %sw4, %s3 : i8, !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    cf.br ^b1 loc("std/fmt/decimal.lin":L:C)
  ^b1:
    %v6 = llvm.load %s2 : !llvm.ptr -> i64 loc("std/fmt/decimal.lin":L:C)
    %v7 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %v8 = arith.cmpi ugt, %v6, %v7 : i64 loc("std/fmt/decimal.lin":L:C)
    cf.cond_br %v8, ^b2, ^b3 loc("std/fmt/decimal.lin":L:C)
  ^b2:
    %v10 = llvm.load %s0 : !llvm.ptr -> i64 loc("std/fmt/decimal.lin":L:C)
    %v11 = llvm.load %s2 : !llvm.ptr -> i64 loc("std/fmt/decimal.lin":L:C)
    %k1z = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %k1 = arith.cmpi eq, %v11, %k1z : i64 loc("std/fmt/decimal.lin":L:C)
    cf.cond_br %k1, ^t1, ^c1 loc("std/fmt/decimal.lin":L:C)
  ^t1:
    %tk1 = arith.constant 1 : i32 loc("std/fmt/decimal.lin":L:C)
    %tf1 = llvm.mlir.addressof @linea_file2 : !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    %tl1 = arith.constant L : i32 loc("std/fmt/decimal.lin":L:C)
    %tc1 = arith.constant C : i32 loc("std/fmt/decimal.lin":L:C)
    func.call @linea_trap(%tk1, %tf1, %tl1, %tc1) : (i32, !llvm.ptr, i32, i32) -> () loc("std/fmt/decimal.lin":L:C)
    llvm.unreachable loc("std/fmt/decimal.lin":L:C)
  ^c1:
    %p12 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %v12 = arith.addi %v11, %p12 : i64 loc("std/fmt/decimal.lin":L:C)
    %v13 = arith.divui %v10, %v12 : i64 loc("std/fmt/decimal.lin":L:C)
    %p14 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %v14 = arith.addi %v13, %p14 : i64 loc("std/fmt/decimal.lin":L:C)
    llvm.store %v14, %s4 : i64, !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    %v16 = llvm.load %s4 : !llvm.ptr -> i64 loc("std/fmt/decimal.lin":L:C)
    %v17 = arith.constant 100 : i64 loc("std/fmt/decimal.lin":L:C)
    %k2z = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %k2 = arith.cmpi eq, %v17, %k2z : i64 loc("std/fmt/decimal.lin":L:C)
    cf.cond_br %k2, ^t2, ^c2 loc("std/fmt/decimal.lin":L:C)
  ^t2:
    %tk2 = arith.constant 1 : i32 loc("std/fmt/decimal.lin":L:C)
    %tf2 = llvm.mlir.addressof @linea_file2 : !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    %tl2 = arith.constant L : i32 loc("std/fmt/decimal.lin":L:C)
    %tc2 = arith.constant C : i32 loc("std/fmt/decimal.lin":L:C)
    func.call @linea_trap(%tk2, %tf2, %tl2, %tc2) : (i32, !llvm.ptr, i32, i32) -> () loc("std/fmt/decimal.lin":L:C)
    llvm.unreachable loc("std/fmt/decimal.lin":L:C)
  ^c2:
    %p18 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %v18 = arith.addi %v17, %p18 : i64 loc("std/fmt/decimal.lin":L:C)
    %v19 = arith.remui %v16, %v18 : i64 loc("std/fmt/decimal.lin":L:C)
    %p20 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %v20 = arith.addi %v19, %p20 : i64 loc("std/fmt/decimal.lin":L:C)
    llvm.store %v20, %s5 : i64, !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    %v22 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    %v23 = llvm.load %s5 : !llvm.ptr -> i64 loc("std/fmt/decimal.lin":L:C)
    %k3z = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %k3 = arith.cmpi slt, %v23, %k3z : i64 loc("std/fmt/decimal.lin":L:C)
    cf.cond_br %k3, ^t3, ^c3 loc("std/fmt/decimal.lin":L:C)
  ^t3:
    %tk3 = arith.constant 2 : i32 loc("std/fmt/decimal.lin":L:C)
    %tf3 = llvm.mlir.addressof @linea_file2 : !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    %tl3 = arith.constant L : i32 loc("std/fmt/decimal.lin":L:C)
    %tc3 = arith.constant C : i32 loc("std/fmt/decimal.lin":L:C)
    func.call @linea_trap(%tk3, %tf3, %tl3, %tc3) : (i32, !llvm.ptr, i32, i32) -> () loc("std/fmt/decimal.lin":L:C)
    llvm.unreachable loc("std/fmt/decimal.lin":L:C)
  ^c3:
    %p24 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %v24 = arith.addi %v23, %p24 : i64 loc("std/fmt/decimal.lin":L:C)
    %lw25 = llvm.load %s3 : !llvm.ptr -> i8 loc("std/fmt/decimal.lin":L:C)
    %lz25 = arith.constant 0 : i8 loc("std/fmt/decimal.lin":L:C)
    %v25 = arith.cmpi ne, %lw25, %lz25 : i8 loc("std/fmt/decimal.lin":L:C)
    func.call @"lin.std.fmt;digits"(%rs26, %v24, %v25) : (!llvm.ptr, i64, i1) -> () loc("std/fmt/decimal.lin":L:C)
    func.call @"lin.Tally;std.io.core;Writer.write_str"(%rs27, %v22, %rs26) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/fmt/decimal.lin":L:C)
    %v28 = llvm.load %rs27 : !llvm.ptr -> i64 loc("std/fmt/decimal.lin":L:C)
    %v29 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %v30 = arith.cmpi eq, %v28, %v29 : i64 loc("std/fmt/decimal.lin":L:C)
    cf.cond_br %v30, ^b4, ^b5 loc("std/fmt/decimal.lin":L:C)
  ^b3:
    %v47 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %v48 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    llvm.store %v48, %s6 : i64, !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    %v51 = arith.constant 8 : i64 loc("std/fmt/decimal.lin":L:C)
    %v52 = llvm.getelementptr %s6[%v51] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/fmt/decimal.lin":L:C)
    %v53 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %rl54 = arith.constant 8 : i64 loc("std/fmt/decimal.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s6, %rl54) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/fmt/decimal.lin":L:C)
    func.return loc("std/fmt/decimal.lin":L:C)
  ^b4:
    %v33 = arith.constant 8 : i64 loc("std/fmt/decimal.lin":L:C)
    %v34 = llvm.getelementptr %rs27[%v33] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/fmt/decimal.lin":L:C)
    %v35 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %v36 = arith.constant 0 : i1 loc("std/fmt/decimal.lin":L:C)
    %sw37 = arith.extui %v36 : i1 to i8 loc("std/fmt/decimal.lin":L:C)
    llvm.store %sw37, %s3 : i8, !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    %v38 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %v39 = llvm.load %s2 : !llvm.ptr -> i64 loc("std/fmt/decimal.lin":L:C)
    %v40 = arith.constant 100 : i64 loc("std/fmt/decimal.lin":L:C)
    %k4z = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %k4 = arith.cmpi eq, %v40, %k4z : i64 loc("std/fmt/decimal.lin":L:C)
    cf.cond_br %k4, ^t4, ^c4 loc("std/fmt/decimal.lin":L:C)
  ^t4:
    %tk4 = arith.constant 1 : i32 loc("std/fmt/decimal.lin":L:C)
    %tf4 = llvm.mlir.addressof @linea_file2 : !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    %tl4 = arith.constant L : i32 loc("std/fmt/decimal.lin":L:C)
    %tc4 = arith.constant C : i32 loc("std/fmt/decimal.lin":L:C)
    func.call @linea_trap(%tk4, %tf4, %tl4, %tc4) : (i32, !llvm.ptr, i32, i32) -> () loc("std/fmt/decimal.lin":L:C)
    llvm.unreachable loc("std/fmt/decimal.lin":L:C)
  ^c4:
    %p41 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %v41 = arith.addi %v40, %p41 : i64 loc("std/fmt/decimal.lin":L:C)
    %v42 = arith.divui %v39, %v41 : i64 loc("std/fmt/decimal.lin":L:C)
    %p43 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %v43 = arith.addi %v42, %p43 : i64 loc("std/fmt/decimal.lin":L:C)
    llvm.store %v43, %s2 : i64, !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    %v45 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    cf.br ^b1 loc("std/fmt/decimal.lin":L:C)
  ^b5:
    %tk5 = arith.constant 3 : i32 loc("std/fmt/decimal.lin":L:C)
    %tf5 = llvm.mlir.addressof @linea_file2 : !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    %tl5 = arith.constant L : i32 loc("std/fmt/decimal.lin":L:C)
    %tc5 = arith.constant C : i32 loc("std/fmt/decimal.lin":L:C)
    func.call @linea_trap(%tk5, %tf5, %tl5, %tc5) : (i32, !llvm.ptr, i32, i32) -> () loc("std/fmt/decimal.lin":L:C)
    llvm.unreachable loc("std/fmt/decimal.lin":L:C)
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
  func.func private @"lin.std.fmt;scale"(%a0: i64) -> i64 attributes {llvm.linkage = #llvm.linkage<internal>} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 1 : i64
    %s1 = llvm.alloca %z1 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    llvm.store %a0, %s0 : i64, !llvm.ptr
    cf.br ^b0
  ^b0:
    %v0 = arith.constant 1 : i64 loc("std/fmt/decimal.lin":L:C)
    llvm.store %v0, %s1 : i64, !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    cf.br ^b1 loc("std/fmt/decimal.lin":L:C)
  ^b1:
    %v3 = llvm.load %s0 : !llvm.ptr -> i64 loc("std/fmt/decimal.lin":L:C)
    %v4 = llvm.load %s1 : !llvm.ptr -> i64 loc("std/fmt/decimal.lin":L:C)
    %k1z = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %k1 = arith.cmpi eq, %v4, %k1z : i64 loc("std/fmt/decimal.lin":L:C)
    cf.cond_br %k1, ^t1, ^c1 loc("std/fmt/decimal.lin":L:C)
  ^t1:
    %tk1 = arith.constant 1 : i32 loc("std/fmt/decimal.lin":L:C)
    %tf1 = llvm.mlir.addressof @linea_file2 : !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    %tl1 = arith.constant L : i32 loc("std/fmt/decimal.lin":L:C)
    %tc1 = arith.constant C : i32 loc("std/fmt/decimal.lin":L:C)
    func.call @linea_trap(%tk1, %tf1, %tl1, %tc1) : (i32, !llvm.ptr, i32, i32) -> () loc("std/fmt/decimal.lin":L:C)
    llvm.unreachable loc("std/fmt/decimal.lin":L:C)
  ^c1:
    %p5 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %v5 = arith.addi %v4, %p5 : i64 loc("std/fmt/decimal.lin":L:C)
    %k2ca = arith.constant -9223372036854775808 : i64 loc("std/fmt/decimal.lin":L:C)
    %k2a = arith.cmpi eq, %v3, %k2ca : i64 loc("std/fmt/decimal.lin":L:C)
    %k2cb = arith.constant -1 : i64 loc("std/fmt/decimal.lin":L:C)
    %k2b = arith.cmpi eq, %v5, %k2cb : i64 loc("std/fmt/decimal.lin":L:C)
    %k2 = arith.andi %k2a, %k2b : i1 loc("std/fmt/decimal.lin":L:C)
    cf.cond_br %k2, ^t2, ^c2 loc("std/fmt/decimal.lin":L:C)
  ^t2:
    %tk2 = arith.constant 0 : i32 loc("std/fmt/decimal.lin":L:C)
    %tf2 = llvm.mlir.addressof @linea_file2 : !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    %tl2 = arith.constant L : i32 loc("std/fmt/decimal.lin":L:C)
    %tc2 = arith.constant C : i32 loc("std/fmt/decimal.lin":L:C)
    func.call @linea_trap(%tk2, %tf2, %tl2, %tc2) : (i32, !llvm.ptr, i32, i32) -> () loc("std/fmt/decimal.lin":L:C)
    llvm.unreachable loc("std/fmt/decimal.lin":L:C)
  ^c2:
    %v6 = arith.divsi %v3, %v5 : i64 loc("std/fmt/decimal.lin":L:C)
    %p7 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %v7 = arith.addi %v6, %p7 : i64 loc("std/fmt/decimal.lin":L:C)
    %v8 = arith.constant 100 : i64 loc("std/fmt/decimal.lin":L:C)
    %k3z = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %k3 = arith.cmpi eq, %v8, %k3z : i64 loc("std/fmt/decimal.lin":L:C)
    cf.cond_br %k3, ^t3, ^c3 loc("std/fmt/decimal.lin":L:C)
  ^t3:
    %tk3 = arith.constant 1 : i32 loc("std/fmt/decimal.lin":L:C)
    %tf3 = llvm.mlir.addressof @linea_file2 : !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    %tl3 = arith.constant L : i32 loc("std/fmt/decimal.lin":L:C)
    %tc3 = arith.constant C : i32 loc("std/fmt/decimal.lin":L:C)
    func.call @linea_trap(%tk3, %tf3, %tl3, %tc3) : (i32, !llvm.ptr, i32, i32) -> () loc("std/fmt/decimal.lin":L:C)
    llvm.unreachable loc("std/fmt/decimal.lin":L:C)
  ^c3:
    %p9 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %v9 = arith.addi %v8, %p9 : i64 loc("std/fmt/decimal.lin":L:C)
    %k4ca = arith.constant -9223372036854775808 : i64 loc("std/fmt/decimal.lin":L:C)
    %k4a = arith.cmpi eq, %v7, %k4ca : i64 loc("std/fmt/decimal.lin":L:C)
    %k4cb = arith.constant -1 : i64 loc("std/fmt/decimal.lin":L:C)
    %k4b = arith.cmpi eq, %v9, %k4cb : i64 loc("std/fmt/decimal.lin":L:C)
    %k4 = arith.andi %k4a, %k4b : i1 loc("std/fmt/decimal.lin":L:C)
    cf.cond_br %k4, ^t4, ^c4 loc("std/fmt/decimal.lin":L:C)
  ^t4:
    %tk4 = arith.constant 0 : i32 loc("std/fmt/decimal.lin":L:C)
    %tf4 = llvm.mlir.addressof @linea_file2 : !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    %tl4 = arith.constant L : i32 loc("std/fmt/decimal.lin":L:C)
    %tc4 = arith.constant C : i32 loc("std/fmt/decimal.lin":L:C)
    func.call @linea_trap(%tk4, %tf4, %tl4, %tc4) : (i32, !llvm.ptr, i32, i32) -> () loc("std/fmt/decimal.lin":L:C)
    llvm.unreachable loc("std/fmt/decimal.lin":L:C)
  ^c4:
    %v10 = arith.divsi %v7, %v9 : i64 loc("std/fmt/decimal.lin":L:C)
    %p11 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %v11 = arith.addi %v10, %p11 : i64 loc("std/fmt/decimal.lin":L:C)
    %v12 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %v13 = arith.cmpi ne, %v11, %v12 : i64 loc("std/fmt/decimal.lin":L:C)
    cf.cond_br %v13, ^b2, ^b3 loc("std/fmt/decimal.lin":L:C)
  ^b2:
    %v15 = llvm.load %s1 : !llvm.ptr -> i64 loc("std/fmt/decimal.lin":L:C)
    %v16 = arith.constant 100 : i64 loc("std/fmt/decimal.lin":L:C)
    %m17 = "llvm.intr.smul.with.overflow"(%v15, %v16) : (i64, i64) -> !llvm.struct<(i64, i1)> loc("std/fmt/decimal.lin":L:C)
    %v17 = llvm.extractvalue %m17[0] : !llvm.struct<(i64, i1)> loc("std/fmt/decimal.lin":L:C)
    %k5 = llvm.extractvalue %m17[1] : !llvm.struct<(i64, i1)> loc("std/fmt/decimal.lin":L:C)
    cf.cond_br %k5, ^t5, ^c5 loc("std/fmt/decimal.lin":L:C)
  ^t5:
    %tk5 = arith.constant 0 : i32 loc("std/fmt/decimal.lin":L:C)
    %tf5 = llvm.mlir.addressof @linea_file2 : !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    %tl5 = arith.constant L : i32 loc("std/fmt/decimal.lin":L:C)
    %tc5 = arith.constant C : i32 loc("std/fmt/decimal.lin":L:C)
    func.call @linea_trap(%tk5, %tf5, %tl5, %tc5) : (i32, !llvm.ptr, i32, i32) -> () loc("std/fmt/decimal.lin":L:C)
    llvm.unreachable loc("std/fmt/decimal.lin":L:C)
  ^c5:
    %p18 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %v18 = arith.addi %v17, %p18 : i64 loc("std/fmt/decimal.lin":L:C)
    llvm.store %v18, %s1 : i64, !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    %v20 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    cf.br ^b1 loc("std/fmt/decimal.lin":L:C)
  ^b3:
    %v22 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %v23 = llvm.load %s1 : !llvm.ptr -> i64 loc("std/fmt/decimal.lin":L:C)
    func.return %v23 : i64 loc("std/fmt/decimal.lin":L:C)
  }
  func.func private @"lin.std.fmt;digits"(%sret: !llvm.ptr, %a0: i64, %a1: i1) attributes {llvm.linkage = #llvm.linkage<internal>} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 1 : i64
    %s1 = llvm.alloca %z1 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z2 = arith.constant 1 : i64
    %s2 = llvm.alloca %z2 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z3 = arith.constant 1 : i64
    %s3 = llvm.alloca %z3 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z4 = arith.constant 1 : i64
    %s4 = llvm.alloca %z4 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z5 = arith.constant 1 : i64
    %s5 = llvm.alloca %z5 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z6 = arith.constant 16 : i64
    %s6 = llvm.alloca %z6 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    llvm.store %a0, %s0 : i64, !llvm.ptr
    %pw1 = arith.extui %a1 : i1 to i8
    llvm.store %pw1, %s1 : i8, !llvm.ptr
    %rz35 = arith.constant 24 : i64
    %rs35 = llvm.alloca %rz35 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    cf.br ^b0
  ^b0:
    %v0 = llvm.load %s0 : !llvm.ptr -> i64 loc("std/fmt/decimal.lin":L:C)
    %k1z = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %k1 = arith.cmpi slt, %v0, %k1z : i64 loc("std/fmt/decimal.lin":L:C)
    cf.cond_br %k1, ^t1, ^c1 loc("std/fmt/decimal.lin":L:C)
  ^t1:
    %tk1 = arith.constant 2 : i32 loc("std/fmt/decimal.lin":L:C)
    %tf1 = llvm.mlir.addressof @linea_file2 : !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    %tl1 = arith.constant L : i32 loc("std/fmt/decimal.lin":L:C)
    %tc1 = arith.constant C : i32 loc("std/fmt/decimal.lin":L:C)
    func.call @linea_trap(%tk1, %tf1, %tl1, %tc1) : (i32, !llvm.ptr, i32, i32) -> () loc("std/fmt/decimal.lin":L:C)
    llvm.unreachable loc("std/fmt/decimal.lin":L:C)
  ^c1:
    %p1 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %v1 = arith.addi %v0, %p1 : i64 loc("std/fmt/decimal.lin":L:C)
    %v2 = arith.constant 2 : i64 loc("std/fmt/decimal.lin":L:C)
    %m3 = "llvm.intr.umul.with.overflow"(%v1, %v2) : (i64, i64) -> !llvm.struct<(i64, i1)> loc("std/fmt/decimal.lin":L:C)
    %v3 = llvm.extractvalue %m3[0] : !llvm.struct<(i64, i1)> loc("std/fmt/decimal.lin":L:C)
    %k2 = llvm.extractvalue %m3[1] : !llvm.struct<(i64, i1)> loc("std/fmt/decimal.lin":L:C)
    cf.cond_br %k2, ^t2, ^c2 loc("std/fmt/decimal.lin":L:C)
  ^t2:
    %tk2 = arith.constant 0 : i32 loc("std/fmt/decimal.lin":L:C)
    %tf2 = llvm.mlir.addressof @linea_file2 : !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    %tl2 = arith.constant L : i32 loc("std/fmt/decimal.lin":L:C)
    %tc2 = arith.constant C : i32 loc("std/fmt/decimal.lin":L:C)
    func.call @linea_trap(%tk2, %tf2, %tl2, %tc2) : (i32, !llvm.ptr, i32, i32) -> () loc("std/fmt/decimal.lin":L:C)
    llvm.unreachable loc("std/fmt/decimal.lin":L:C)
  ^c2:
    %p4 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %v4 = arith.addi %v3, %p4 : i64 loc("std/fmt/decimal.lin":L:C)
    llvm.store %v4, %s2 : i64, !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    %lw6 = llvm.load %s1 : !llvm.ptr -> i8 loc("std/fmt/decimal.lin":L:C)
    %lz6 = arith.constant 0 : i8 loc("std/fmt/decimal.lin":L:C)
    %v6 = arith.cmpi ne, %lw6, %lz6 : i8 loc("std/fmt/decimal.lin":L:C)
    cf.cond_br %v6, ^b1, ^b2 loc("std/fmt/decimal.lin":L:C)
  ^b1:
    %v8 = llvm.load %s0 : !llvm.ptr -> i64 loc("std/fmt/decimal.lin":L:C)
    %v9 = arith.constant 10 : i64 loc("std/fmt/decimal.lin":L:C)
    %v10 = arith.cmpi slt, %v8, %v9 : i64 loc("std/fmt/decimal.lin":L:C)
    %sw11 = arith.extui %v10 : i1 to i8 loc("std/fmt/decimal.lin":L:C)
    llvm.store %sw11, %s4 : i8, !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    cf.br ^b3 loc("std/fmt/decimal.lin":L:C)
  ^b2:
    %v13 = arith.constant 0 : i1 loc("std/fmt/decimal.lin":L:C)
    %sw14 = arith.extui %v13 : i1 to i8 loc("std/fmt/decimal.lin":L:C)
    llvm.store %sw14, %s4 : i8, !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    cf.br ^b3 loc("std/fmt/decimal.lin":L:C)
  ^b3:
    %lw16 = llvm.load %s4 : !llvm.ptr -> i8 loc("std/fmt/decimal.lin":L:C)
    %lz16 = arith.constant 0 : i8 loc("std/fmt/decimal.lin":L:C)
    %v16 = arith.cmpi ne, %lw16, %lz16 : i8 loc("std/fmt/decimal.lin":L:C)
    cf.cond_br %v16, ^b4, ^b5 loc("std/fmt/decimal.lin":L:C)
  ^b4:
    %v18 = llvm.load %s2 : !llvm.ptr -> i64 loc("std/fmt/decimal.lin":L:C)
    %v19 = arith.constant 1 : i64 loc("std/fmt/decimal.lin":L:C)
    %v20 = arith.addi %v18, %v19 : i64 loc("std/fmt/decimal.lin":L:C)
    %k3 = arith.cmpi ult, %v20, %v18 : i64 loc("std/fmt/decimal.lin":L:C)
    cf.cond_br %k3, ^t3, ^c3 loc("std/fmt/decimal.lin":L:C)
  ^t3:
    %tk3 = arith.constant 0 : i32 loc("std/fmt/decimal.lin":L:C)
    %tf3 = llvm.mlir.addressof @linea_file2 : !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    %tl3 = arith.constant L : i32 loc("std/fmt/decimal.lin":L:C)
    %tc3 = arith.constant C : i32 loc("std/fmt/decimal.lin":L:C)
    func.call @linea_trap(%tk3, %tf3, %tl3, %tc3) : (i32, !llvm.ptr, i32, i32) -> () loc("std/fmt/decimal.lin":L:C)
    llvm.unreachable loc("std/fmt/decimal.lin":L:C)
  ^c3:
    %p21 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %v21 = arith.addi %v20, %p21 : i64 loc("std/fmt/decimal.lin":L:C)
    llvm.store %v21, %s5 : i64, !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    cf.br ^b6 loc("std/fmt/decimal.lin":L:C)
  ^b5:
    %v24 = llvm.load %s2 : !llvm.ptr -> i64 loc("std/fmt/decimal.lin":L:C)
    llvm.store %v24, %s5 : i64, !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    cf.br ^b6 loc("std/fmt/decimal.lin":L:C)
  ^b6:
    %v27 = llvm.load %s5 : !llvm.ptr -> i64 loc("std/fmt/decimal.lin":L:C)
    llvm.store %v27, %s3 : i64, !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    %v29 = llvm.mlir.addressof @linea_static0 : !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    %v30 = llvm.load %s3 : !llvm.ptr -> i64 loc("std/fmt/decimal.lin":L:C)
    %v31 = llvm.load %s2 : !llvm.ptr -> i64 loc("std/fmt/decimal.lin":L:C)
    %v32 = arith.constant 2 : i64 loc("std/fmt/decimal.lin":L:C)
    %v33 = arith.addi %v31, %v32 : i64 loc("std/fmt/decimal.lin":L:C)
    %k4 = arith.cmpi ult, %v33, %v31 : i64 loc("std/fmt/decimal.lin":L:C)
    cf.cond_br %k4, ^t4, ^c4 loc("std/fmt/decimal.lin":L:C)
  ^t4:
    %tk4 = arith.constant 0 : i32 loc("std/fmt/decimal.lin":L:C)
    %tf4 = llvm.mlir.addressof @linea_file2 : !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    %tl4 = arith.constant L : i32 loc("std/fmt/decimal.lin":L:C)
    %tc4 = arith.constant C : i32 loc("std/fmt/decimal.lin":L:C)
    func.call @linea_trap(%tk4, %tf4, %tl4, %tc4) : (i32, !llvm.ptr, i32, i32) -> () loc("std/fmt/decimal.lin":L:C)
    llvm.unreachable loc("std/fmt/decimal.lin":L:C)
  ^c4:
    %p34 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %v34 = arith.addi %v33, %p34 : i64 loc("std/fmt/decimal.lin":L:C)
    func.call @"lin.std.text;Str.slice"(%rs35, %v29, %v30, %v34) : (!llvm.ptr, !llvm.ptr, i64, i64) -> () loc("std/fmt/decimal.lin":L:C)
    %ba37 = llvm.mlir.addressof @linea_str4 : !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    %v37 = llvm.ptrtoint %ba37 : !llvm.ptr to i64 loc("std/fmt/decimal.lin":L:C)
    %v38 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    llvm.store %v37, %s6 : i64, !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    %v41 = arith.constant 1 : i64 loc("std/fmt/decimal.lin":L:C)
    %v42 = arith.constant 8 : i64 loc("std/fmt/decimal.lin":L:C)
    %v43 = llvm.getelementptr %s6[%v42] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/fmt/decimal.lin":L:C)
    llvm.store %v41, %v43 : i64, !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    func.call @"lin.std.option;Option[std.text.Str].unwrap_or"(%sret, %rs35, %s6) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/fmt/decimal.lin":L:C)
    func.return loc("std/fmt/decimal.lin":L:C)
  }
  func.func private @"lin.std.fmt;scale_unsigned"(%a0: i64) -> i64 attributes {llvm.linkage = #llvm.linkage<internal>} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 1 : i64
    %s1 = llvm.alloca %z1 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    llvm.store %a0, %s0 : i64, !llvm.ptr
    cf.br ^b0
  ^b0:
    %v0 = arith.constant 1 : i64 loc("std/fmt/decimal.lin":L:C)
    llvm.store %v0, %s1 : i64, !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    cf.br ^b1 loc("std/fmt/decimal.lin":L:C)
  ^b1:
    %v3 = llvm.load %s0 : !llvm.ptr -> i64 loc("std/fmt/decimal.lin":L:C)
    %v4 = llvm.load %s1 : !llvm.ptr -> i64 loc("std/fmt/decimal.lin":L:C)
    %k1z = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %k1 = arith.cmpi eq, %v4, %k1z : i64 loc("std/fmt/decimal.lin":L:C)
    cf.cond_br %k1, ^t1, ^c1 loc("std/fmt/decimal.lin":L:C)
  ^t1:
    %tk1 = arith.constant 1 : i32 loc("std/fmt/decimal.lin":L:C)
    %tf1 = llvm.mlir.addressof @linea_file2 : !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    %tl1 = arith.constant L : i32 loc("std/fmt/decimal.lin":L:C)
    %tc1 = arith.constant C : i32 loc("std/fmt/decimal.lin":L:C)
    func.call @linea_trap(%tk1, %tf1, %tl1, %tc1) : (i32, !llvm.ptr, i32, i32) -> () loc("std/fmt/decimal.lin":L:C)
    llvm.unreachable loc("std/fmt/decimal.lin":L:C)
  ^c1:
    %p5 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %v5 = arith.addi %v4, %p5 : i64 loc("std/fmt/decimal.lin":L:C)
    %v6 = arith.divui %v3, %v5 : i64 loc("std/fmt/decimal.lin":L:C)
    %p7 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %v7 = arith.addi %v6, %p7 : i64 loc("std/fmt/decimal.lin":L:C)
    %v8 = arith.constant 100 : i64 loc("std/fmt/decimal.lin":L:C)
    %k2z = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %k2 = arith.cmpi eq, %v8, %k2z : i64 loc("std/fmt/decimal.lin":L:C)
    cf.cond_br %k2, ^t2, ^c2 loc("std/fmt/decimal.lin":L:C)
  ^t2:
    %tk2 = arith.constant 1 : i32 loc("std/fmt/decimal.lin":L:C)
    %tf2 = llvm.mlir.addressof @linea_file2 : !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    %tl2 = arith.constant L : i32 loc("std/fmt/decimal.lin":L:C)
    %tc2 = arith.constant C : i32 loc("std/fmt/decimal.lin":L:C)
    func.call @linea_trap(%tk2, %tf2, %tl2, %tc2) : (i32, !llvm.ptr, i32, i32) -> () loc("std/fmt/decimal.lin":L:C)
    llvm.unreachable loc("std/fmt/decimal.lin":L:C)
  ^c2:
    %p9 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %v9 = arith.addi %v8, %p9 : i64 loc("std/fmt/decimal.lin":L:C)
    %v10 = arith.divui %v7, %v9 : i64 loc("std/fmt/decimal.lin":L:C)
    %p11 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %v11 = arith.addi %v10, %p11 : i64 loc("std/fmt/decimal.lin":L:C)
    %v12 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %v13 = arith.cmpi ne, %v11, %v12 : i64 loc("std/fmt/decimal.lin":L:C)
    cf.cond_br %v13, ^b2, ^b3 loc("std/fmt/decimal.lin":L:C)
  ^b2:
    %v15 = llvm.load %s1 : !llvm.ptr -> i64 loc("std/fmt/decimal.lin":L:C)
    %v16 = arith.constant 100 : i64 loc("std/fmt/decimal.lin":L:C)
    %m17 = "llvm.intr.umul.with.overflow"(%v15, %v16) : (i64, i64) -> !llvm.struct<(i64, i1)> loc("std/fmt/decimal.lin":L:C)
    %v17 = llvm.extractvalue %m17[0] : !llvm.struct<(i64, i1)> loc("std/fmt/decimal.lin":L:C)
    %k3 = llvm.extractvalue %m17[1] : !llvm.struct<(i64, i1)> loc("std/fmt/decimal.lin":L:C)
    cf.cond_br %k3, ^t3, ^c3 loc("std/fmt/decimal.lin":L:C)
  ^t3:
    %tk3 = arith.constant 0 : i32 loc("std/fmt/decimal.lin":L:C)
    %tf3 = llvm.mlir.addressof @linea_file2 : !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    %tl3 = arith.constant L : i32 loc("std/fmt/decimal.lin":L:C)
    %tc3 = arith.constant C : i32 loc("std/fmt/decimal.lin":L:C)
    func.call @linea_trap(%tk3, %tf3, %tl3, %tc3) : (i32, !llvm.ptr, i32, i32) -> () loc("std/fmt/decimal.lin":L:C)
    llvm.unreachable loc("std/fmt/decimal.lin":L:C)
  ^c3:
    %p18 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %v18 = arith.addi %v17, %p18 : i64 loc("std/fmt/decimal.lin":L:C)
    llvm.store %v18, %s1 : i64, !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    %v20 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    cf.br ^b1 loc("std/fmt/decimal.lin":L:C)
  ^b3:
    %v22 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %v23 = llvm.load %s1 : !llvm.ptr -> i64 loc("std/fmt/decimal.lin":L:C)
    func.return %v23 : i64 loc("std/fmt/decimal.lin":L:C)
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
  func.func private @"lin.std.text;Str.slice"(%sret: !llvm.ptr, %a0: !llvm.ptr, %a1: i64, %a2: i64) attributes {llvm.linkage = #llvm.linkage<internal>} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x !llvm.ptr {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 1 : i64
    %s1 = llvm.alloca %z1 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z2 = arith.constant 1 : i64
    %s2 = llvm.alloca %z2 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z3 = arith.constant 1 : i64
    %s3 = llvm.alloca %z3 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z4 = arith.constant 24 : i64
    %s4 = llvm.alloca %z4 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z5 = arith.constant 1 : i64
    %s5 = llvm.alloca %z5 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z6 = arith.constant 24 : i64
    %s6 = llvm.alloca %z6 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    llvm.store %a0, %s0 : !llvm.ptr, !llvm.ptr
    llvm.store %a1, %s1 : i64, !llvm.ptr
    llvm.store %a2, %s2 : i64, !llvm.ptr
    %rz57 = arith.constant 24 : i64
    %rs57 = llvm.alloca %rz57 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz58 = arith.constant 16 : i64
    %rs58 = llvm.alloca %rz58 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    cf.br ^b0
  ^b0:
    %v0 = llvm.load %s1 : !llvm.ptr -> i64 loc("std/text/str.lin":L:C)
    %v1 = llvm.load %s2 : !llvm.ptr -> i64 loc("std/text/str.lin":L:C)
    %v2 = arith.cmpi ugt, %v0, %v1 : i64 loc("std/text/str.lin":L:C)
    cf.cond_br %v2, ^b1, ^b2 loc("std/text/str.lin":L:C)
  ^b1:
    %v4 = arith.constant 1 : i1 loc("std/text/str.lin":L:C)
    %sw5 = arith.extui %v4 : i1 to i8 loc("std/text/str.lin":L:C)
    llvm.store %sw5, %s3 : i8, !llvm.ptr loc("std/text/str.lin":L:C)
    cf.br ^b3 loc("std/text/str.lin":L:C)
  ^b2:
    %v7 = llvm.load %s2 : !llvm.ptr -> i64 loc("std/text/str.lin":L:C)
    %v8 = llvm.load %s0 : !llvm.ptr -> !llvm.ptr loc("std/text/str.lin":L:C)
    %v9 = func.call @"lin.std.text;Str.length"(%v8) : (!llvm.ptr) -> i64 loc("std/text/str.lin":L:C)
    %v10 = arith.cmpi ugt, %v7, %v9 : i64 loc("std/text/str.lin":L:C)
    %sw11 = arith.extui %v10 : i1 to i8 loc("std/text/str.lin":L:C)
    llvm.store %sw11, %s3 : i8, !llvm.ptr loc("std/text/str.lin":L:C)
    cf.br ^b3 loc("std/text/str.lin":L:C)
  ^b3:
    %lw13 = llvm.load %s3 : !llvm.ptr -> i8 loc("std/text/str.lin":L:C)
    %lz13 = arith.constant 0 : i8 loc("std/text/str.lin":L:C)
    %v13 = arith.cmpi ne, %lw13, %lz13 : i8 loc("std/text/str.lin":L:C)
    cf.cond_br %v13, ^b4, ^b5 loc("std/text/str.lin":L:C)
  ^b4:
    %v16 = arith.constant 0 : i64 loc("std/text/str.lin":L:C)
    llvm.store %v16, %s4 : i64, !llvm.ptr loc("std/text/str.lin":L:C)
    cf.br ^b6 loc("std/text/str.lin":L:C)
  ^b5:
    %v20 = llvm.load %s0 : !llvm.ptr -> !llvm.ptr loc("std/text/str.lin":L:C)
    %v21 = llvm.load %s1 : !llvm.ptr -> i64 loc("std/text/str.lin":L:C)
    %v22 = func.call @"lin.std.text;starts_a_character"(%v20, %v21) : (!llvm.ptr, i64) -> i1 loc("std/text/str.lin":L:C)
    %v23 = arith.constant 0 : i1 loc("std/text/str.lin":L:C)
    %v24 = arith.cmpi eq, %v22, %v23 : i1 loc("std/text/str.lin":L:C)
    cf.cond_br %v24, ^b7, ^b8 loc("std/text/str.lin":L:C)
  ^b6:
    %rl65 = arith.constant 24 : i64 loc("std/text/str.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s4, %rl65) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/text/str.lin":L:C)
    func.return loc("std/text/str.lin":L:C)
  ^b7:
    %v26 = arith.constant 1 : i1 loc("std/text/str.lin":L:C)
    %sw27 = arith.extui %v26 : i1 to i8 loc("std/text/str.lin":L:C)
    llvm.store %sw27, %s5 : i8, !llvm.ptr loc("std/text/str.lin":L:C)
    cf.br ^b9 loc("std/text/str.lin":L:C)
  ^b8:
    %v29 = llvm.load %s0 : !llvm.ptr -> !llvm.ptr loc("std/text/str.lin":L:C)
    %v30 = llvm.load %s2 : !llvm.ptr -> i64 loc("std/text/str.lin":L:C)
    %v31 = func.call @"lin.std.text;starts_a_character"(%v29, %v30) : (!llvm.ptr, i64) -> i1 loc("std/text/str.lin":L:C)
    %v32 = arith.constant 0 : i1 loc("std/text/str.lin":L:C)
    %v33 = arith.cmpi eq, %v31, %v32 : i1 loc("std/text/str.lin":L:C)
    %sw34 = arith.extui %v33 : i1 to i8 loc("std/text/str.lin":L:C)
    llvm.store %sw34, %s5 : i8, !llvm.ptr loc("std/text/str.lin":L:C)
    cf.br ^b9 loc("std/text/str.lin":L:C)
  ^b9:
    %lw36 = llvm.load %s5 : !llvm.ptr -> i8 loc("std/text/str.lin":L:C)
    %lz36 = arith.constant 0 : i8 loc("std/text/str.lin":L:C)
    %v36 = arith.cmpi ne, %lw36, %lz36 : i8 loc("std/text/str.lin":L:C)
    cf.cond_br %v36, ^b10, ^b11 loc("std/text/str.lin":L:C)
  ^b10:
    %v39 = arith.constant 0 : i64 loc("std/text/str.lin":L:C)
    llvm.store %v39, %s6 : i64, !llvm.ptr loc("std/text/str.lin":L:C)
    cf.br ^b12 loc("std/text/str.lin":L:C)
  ^b11:
    %v43 = arith.constant 1 : i64 loc("std/text/str.lin":L:C)
    llvm.store %v43, %s6 : i64, !llvm.ptr loc("std/text/str.lin":L:C)
    %v45 = arith.constant 8 : i64 loc("std/text/str.lin":L:C)
    %v46 = llvm.getelementptr %s6[%v45] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/text/str.lin":L:C)
    %v47 = arith.constant 0 : i64 loc("std/text/str.lin":L:C)
    %v49 = llvm.load %s0 : !llvm.ptr -> !llvm.ptr loc("std/text/str.lin":L:C)
    %v50 = arith.constant 0 : i64 loc("std/text/str.lin":L:C)
    %v52 = llvm.load %s1 : !llvm.ptr -> i64 loc("std/text/str.lin":L:C)
    %v53 = llvm.load %s2 : !llvm.ptr -> i64 loc("std/text/str.lin":L:C)
    %v54 = llvm.load %s1 : !llvm.ptr -> i64 loc("std/text/str.lin":L:C)
    %v55 = arith.subi %v53, %v54 : i64 loc("std/text/str.lin":L:C)
    %k1 = arith.cmpi ult, %v53, %v54 : i64 loc("std/text/str.lin":L:C)
    cf.cond_br %k1, ^t1, ^c1 loc("std/text/str.lin":L:C)
  ^t1:
    %tk1 = arith.constant 0 : i32 loc("std/text/str.lin":L:C)
    %tf1 = llvm.mlir.addressof @linea_file3 : !llvm.ptr loc("std/text/str.lin":L:C)
    %tl1 = arith.constant L : i32 loc("std/text/str.lin":L:C)
    %tc1 = arith.constant C : i32 loc("std/text/str.lin":L:C)
    func.call @linea_trap(%tk1, %tf1, %tl1, %tc1) : (i32, !llvm.ptr, i32, i32) -> () loc("std/text/str.lin":L:C)
    llvm.unreachable loc("std/text/str.lin":L:C)
  ^c1:
    %p56 = arith.constant 0 : i64 loc("std/text/str.lin":L:C)
    %v56 = arith.addi %v55, %p56 : i64 loc("std/text/str.lin":L:C)
    func.call @"lin.std.mem;Slice[UInt8].subspan"(%rs57, %v49, %v52, %v56) : (!llvm.ptr, !llvm.ptr, i64, i64) -> () loc("std/text/str.lin":L:C)
    func.call @"lin.std.option;Option[std.mem.Slice[UInt8]].unwrap"(%rs58, %rs57) : (!llvm.ptr, !llvm.ptr) -> () loc("std/text/str.lin":L:C)
    %cl59 = arith.constant 16 : i64 loc("std/text/str.lin":L:C)
    "llvm.intr.memcpy"(%v46, %rs58, %cl59) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/text/str.lin":L:C)
    cf.br ^b12 loc("std/text/str.lin":L:C)
  ^b12:
    %cl62 = arith.constant 24 : i64 loc("std/text/str.lin":L:C)
    "llvm.intr.memcpy"(%s4, %s6, %cl62) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/text/str.lin":L:C)
    cf.br ^b6 loc("std/text/str.lin":L:C)
  }
  func.func private @"lin.std.option;Option[std.text.Str].unwrap_or"(%sret: !llvm.ptr, %a0: !llvm.ptr, %a1: !llvm.ptr) attributes {llvm.linkage = #llvm.linkage<internal>} {
    %z0 = arith.constant 24 : i64
    %s0 = llvm.alloca %z0 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 16 : i64
    %s1 = llvm.alloca %z1 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z2 = arith.constant 16 : i64
    %s2 = llvm.alloca %z2 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z3 = arith.constant 16 : i64
    %s3 = llvm.alloca %z3 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %pl0 = arith.constant 24 : i64
    "llvm.intr.memcpy"(%s0, %a0, %pl0) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> ()
    %pl1 = arith.constant 16 : i64
    "llvm.intr.memcpy"(%s1, %a1, %pl1) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> ()
    cf.br ^b0
  ^b0:
    %v1 = llvm.load %s0 : !llvm.ptr -> i64 loc("std/option/option.lin":L:C)
    %v2 = arith.constant 1 : i64 loc("std/option/option.lin":L:C)
    %v3 = arith.cmpi eq, %v1, %v2 : i64 loc("std/option/option.lin":L:C)
    cf.cond_br %v3, ^b2, ^b3 loc("std/option/option.lin":L:C)
  ^b1:
    %rl22 = arith.constant 16 : i64 loc("std/option/option.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s2, %rl22) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/option/option.lin":L:C)
    func.return loc("std/option/option.lin":L:C)
  ^b2:
    %v5 = arith.constant 8 : i64 loc("std/option/option.lin":L:C)
    %v6 = llvm.getelementptr %s0[%v5] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/option/option.lin":L:C)
    %cl8 = arith.constant 16 : i64 loc("std/option/option.lin":L:C)
    "llvm.intr.memcpy"(%s3, %v6, %cl8) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/option/option.lin":L:C)
    %cl11 = arith.constant 16 : i64 loc("std/option/option.lin":L:C)
    "llvm.intr.memcpy"(%s2, %s3, %cl11) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/option/option.lin":L:C)
    cf.br ^b1 loc("std/option/option.lin":L:C)
  ^b3:
    %v13 = arith.constant 0 : i64 loc("std/option/option.lin":L:C)
    %v14 = arith.cmpi eq, %v1, %v13 : i64 loc("std/option/option.lin":L:C)
    cf.cond_br %v14, ^b4, ^b5 loc("std/option/option.lin":L:C)
  ^b4:
    %cl18 = arith.constant 16 : i64 loc("std/option/option.lin":L:C)
    "llvm.intr.memcpy"(%s2, %s1, %cl18) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/option/option.lin":L:C)
    cf.br ^b1 loc("std/option/option.lin":L:C)
  ^b5:
    %tk1 = arith.constant 3 : i32 loc("std/option/option.lin":L:C)
    %tf1 = llvm.mlir.addressof @linea_file5 : !llvm.ptr loc("std/option/option.lin":L:C)
    %tl1 = arith.constant L : i32 loc("std/option/option.lin":L:C)
    %tc1 = arith.constant C : i32 loc("std/option/option.lin":L:C)
    func.call @linea_trap(%tk1, %tf1, %tl1, %tc1) : (i32, !llvm.ptr, i32, i32) -> () loc("std/option/option.lin":L:C)
    llvm.unreachable loc("std/option/option.lin":L:C)
  }
  func.func private @"lin.std.text;starts_a_character"(%a0: !llvm.ptr, %a1: i64) -> i1 attributes {llvm.linkage = #llvm.linkage<internal>} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x !llvm.ptr {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 1 : i64
    %s1 = llvm.alloca %z1 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z2 = arith.constant 1 : i64
    %s2 = llvm.alloca %z2 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z3 = arith.constant 1 : i64
    %s3 = llvm.alloca %z3 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z4 = arith.constant 1 : i64
    %s4 = llvm.alloca %z4 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z5 = arith.constant 1 : i64
    %s5 = llvm.alloca %z5 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    llvm.store %a0, %s0 : !llvm.ptr, !llvm.ptr
    llvm.store %a1, %s1 : i64, !llvm.ptr
    %rz13 = arith.constant 16 : i64
    %rs13 = llvm.alloca %rz13 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    cf.br ^b0
  ^b0:
    %v0 = llvm.load %s1 : !llvm.ptr -> i64 loc("std/text/str.lin":L:C)
    %v1 = llvm.load %s0 : !llvm.ptr -> !llvm.ptr loc("std/text/str.lin":L:C)
    %v2 = func.call @"lin.std.text;Str.length"(%v1) : (!llvm.ptr) -> i64 loc("std/text/str.lin":L:C)
    %v3 = arith.cmpi uge, %v0, %v2 : i64 loc("std/text/str.lin":L:C)
    cf.cond_br %v3, ^b1, ^b2 loc("std/text/str.lin":L:C)
  ^b1:
    %v5 = llvm.load %s1 : !llvm.ptr -> i64 loc("std/text/str.lin":L:C)
    %v6 = llvm.load %s0 : !llvm.ptr -> !llvm.ptr loc("std/text/str.lin":L:C)
    %v7 = func.call @"lin.std.text;Str.length"(%v6) : (!llvm.ptr) -> i64 loc("std/text/str.lin":L:C)
    %v8 = arith.cmpi eq, %v5, %v7 : i64 loc("std/text/str.lin":L:C)
    %sw9 = arith.extui %v8 : i1 to i8 loc("std/text/str.lin":L:C)
    llvm.store %sw9, %s2 : i8, !llvm.ptr loc("std/text/str.lin":L:C)
    cf.br ^b3 loc("std/text/str.lin":L:C)
  ^b2:
    %v11 = llvm.load %s0 : !llvm.ptr -> !llvm.ptr loc("std/text/str.lin":L:C)
    %v12 = llvm.load %s1 : !llvm.ptr -> i64 loc("std/text/str.lin":L:C)
    func.call @"lin.std.text;Str.byte"(%rs13, %v11, %v12) : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/text/str.lin":L:C)
    %v14 = llvm.load %rs13 : !llvm.ptr -> i64 loc("std/text/str.lin":L:C)
    %v15 = arith.constant 1 : i64 loc("std/text/str.lin":L:C)
    %v16 = arith.cmpi eq, %v14, %v15 : i64 loc("std/text/str.lin":L:C)
    cf.cond_br %v16, ^b5, ^b6 loc("std/text/str.lin":L:C)
  ^b3:
    %lw47 = llvm.load %s2 : !llvm.ptr -> i8 loc("std/text/str.lin":L:C)
    %lz47 = arith.constant 0 : i8 loc("std/text/str.lin":L:C)
    %v47 = arith.cmpi ne, %lw47, %lz47 : i8 loc("std/text/str.lin":L:C)
    func.return %v47 : i1 loc("std/text/str.lin":L:C)
  ^b4:
    %lw44 = llvm.load %s3 : !llvm.ptr -> i8 loc("std/text/str.lin":L:C)
    %lz44 = arith.constant 0 : i8 loc("std/text/str.lin":L:C)
    %v44 = arith.cmpi ne, %lw44, %lz44 : i8 loc("std/text/str.lin":L:C)
    %sw45 = arith.extui %v44 : i1 to i8 loc("std/text/str.lin":L:C)
    llvm.store %sw45, %s2 : i8, !llvm.ptr loc("std/text/str.lin":L:C)
    cf.br ^b3 loc("std/text/str.lin":L:C)
  ^b5:
    %v18 = arith.constant 8 : i64 loc("std/text/str.lin":L:C)
    %v19 = llvm.getelementptr %rs13[%v18] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/text/str.lin":L:C)
    %iw20 = llvm.load %v19 : !llvm.ptr -> i8 loc("std/text/str.lin":L:C)
    %v20 = arith.extui %iw20 : i8 to i64 loc("std/text/str.lin":L:C)
    %sw21 = arith.trunci %v20 : i64 to i8 loc("std/text/str.lin":L:C)
    llvm.store %sw21, %s4 : i8, !llvm.ptr loc("std/text/str.lin":L:C)
    %lw22 = llvm.load %s4 : !llvm.ptr -> i8 loc("std/text/str.lin":L:C)
    %v22 = arith.extui %lw22 : i8 to i64 loc("std/text/str.lin":L:C)
    %v23 = arith.constant 128 : i64 loc("std/text/str.lin":L:C)
    %v24 = arith.cmpi ult, %v22, %v23 : i64 loc("std/text/str.lin":L:C)
    cf.cond_br %v24, ^b7, ^b8 loc("std/text/str.lin":L:C)
  ^b6:
    %v37 = arith.constant 0 : i64 loc("std/text/str.lin":L:C)
    %v38 = arith.cmpi eq, %v14, %v37 : i64 loc("std/text/str.lin":L:C)
    cf.cond_br %v38, ^b10, ^b11 loc("std/text/str.lin":L:C)
  ^b7:
    %v26 = arith.constant 1 : i1 loc("std/text/str.lin":L:C)
    %sw27 = arith.extui %v26 : i1 to i8 loc("std/text/str.lin":L:C)
    llvm.store %sw27, %s5 : i8, !llvm.ptr loc("std/text/str.lin":L:C)
    cf.br ^b9 loc("std/text/str.lin":L:C)
  ^b8:
    %lw29 = llvm.load %s4 : !llvm.ptr -> i8 loc("std/text/str.lin":L:C)
    %v29 = arith.extui %lw29 : i8 to i64 loc("std/text/str.lin":L:C)
    %v30 = arith.constant 191 : i64 loc("std/text/str.lin":L:C)
    %v31 = arith.cmpi ugt, %v29, %v30 : i64 loc("std/text/str.lin":L:C)
    %sw32 = arith.extui %v31 : i1 to i8 loc("std/text/str.lin":L:C)
    llvm.store %sw32, %s5 : i8, !llvm.ptr loc("std/text/str.lin":L:C)
    cf.br ^b9 loc("std/text/str.lin":L:C)
  ^b9:
    %lw34 = llvm.load %s5 : !llvm.ptr -> i8 loc("std/text/str.lin":L:C)
    %lz34 = arith.constant 0 : i8 loc("std/text/str.lin":L:C)
    %v34 = arith.cmpi ne, %lw34, %lz34 : i8 loc("std/text/str.lin":L:C)
    %sw35 = arith.extui %v34 : i1 to i8 loc("std/text/str.lin":L:C)
    llvm.store %sw35, %s3 : i8, !llvm.ptr loc("std/text/str.lin":L:C)
    cf.br ^b4 loc("std/text/str.lin":L:C)
  ^b10:
    %v40 = arith.constant 0 : i1 loc("std/text/str.lin":L:C)
    %sw41 = arith.extui %v40 : i1 to i8 loc("std/text/str.lin":L:C)
    llvm.store %sw41, %s3 : i8, !llvm.ptr loc("std/text/str.lin":L:C)
    cf.br ^b4 loc("std/text/str.lin":L:C)
  ^b11:
    %tk1 = arith.constant 3 : i32 loc("std/text/str.lin":L:C)
    %tf1 = llvm.mlir.addressof @linea_file3 : !llvm.ptr loc("std/text/str.lin":L:C)
    %tl1 = arith.constant L : i32 loc("std/text/str.lin":L:C)
    %tc1 = arith.constant C : i32 loc("std/text/str.lin":L:C)
    func.call @linea_trap(%tk1, %tf1, %tl1, %tc1) : (i32, !llvm.ptr, i32, i32) -> () loc("std/text/str.lin":L:C)
    llvm.unreachable loc("std/text/str.lin":L:C)
  }
  func.func private @"lin.std.mem;Slice[UInt8].subspan"(%sret: !llvm.ptr, %a0: !llvm.ptr, %a1: i64, %a2: i64) attributes {llvm.linkage = #llvm.linkage<internal>} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x !llvm.ptr {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 1 : i64
    %s1 = llvm.alloca %z1 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z2 = arith.constant 1 : i64
    %s2 = llvm.alloca %z2 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z3 = arith.constant 24 : i64
    %s3 = llvm.alloca %z3 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z4 = arith.constant 24 : i64
    %s4 = llvm.alloca %z4 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z5 = arith.constant 16 : i64
    %s5 = llvm.alloca %z5 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    llvm.store %a0, %s0 : !llvm.ptr, !llvm.ptr
    llvm.store %a1, %s1 : i64, !llvm.ptr
    llvm.store %a2, %s2 : i64, !llvm.ptr
    cf.br ^b0
  ^b0:
    %v0 = llvm.load %s1 : !llvm.ptr -> i64 loc("std/mem/slice.lin":L:C)
    %v1 = llvm.load %s0 : !llvm.ptr -> !llvm.ptr loc("std/mem/slice.lin":L:C)
    %v2 = arith.constant 8 : i64 loc("std/mem/slice.lin":L:C)
    %v3 = llvm.getelementptr %v1[%v2] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/mem/slice.lin":L:C)
    %v4 = llvm.load %v3 : !llvm.ptr -> i64 loc("std/mem/slice.lin":L:C)
    %v5 = arith.cmpi ugt, %v0, %v4 : i64 loc("std/mem/slice.lin":L:C)
    cf.cond_br %v5, ^b1, ^b2 loc("std/mem/slice.lin":L:C)
  ^b1:
    %v8 = arith.constant 0 : i64 loc("std/mem/slice.lin":L:C)
    llvm.store %v8, %s3 : i64, !llvm.ptr loc("std/mem/slice.lin":L:C)
    cf.br ^b3 loc("std/mem/slice.lin":L:C)
  ^b2:
    %v12 = llvm.load %s2 : !llvm.ptr -> i64 loc("std/mem/slice.lin":L:C)
    %v13 = llvm.load %s0 : !llvm.ptr -> !llvm.ptr loc("std/mem/slice.lin":L:C)
    %v14 = arith.constant 8 : i64 loc("std/mem/slice.lin":L:C)
    %v15 = llvm.getelementptr %v13[%v14] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/mem/slice.lin":L:C)
    %v16 = llvm.load %v15 : !llvm.ptr -> i64 loc("std/mem/slice.lin":L:C)
    %v17 = llvm.load %s1 : !llvm.ptr -> i64 loc("std/mem/slice.lin":L:C)
    %v18 = arith.subi %v16, %v17 : i64 loc("std/mem/slice.lin":L:C)
    %k1 = arith.cmpi ult, %v16, %v17 : i64 loc("std/mem/slice.lin":L:C)
    cf.cond_br %k1, ^t1, ^c1 loc("std/mem/slice.lin":L:C)
  ^t1:
    %tk1 = arith.constant 0 : i32 loc("std/mem/slice.lin":L:C)
    %tf1 = llvm.mlir.addressof @linea_file4 : !llvm.ptr loc("std/mem/slice.lin":L:C)
    %tl1 = arith.constant L : i32 loc("std/mem/slice.lin":L:C)
    %tc1 = arith.constant C : i32 loc("std/mem/slice.lin":L:C)
    func.call @linea_trap(%tk1, %tf1, %tl1, %tc1) : (i32, !llvm.ptr, i32, i32) -> () loc("std/mem/slice.lin":L:C)
    llvm.unreachable loc("std/mem/slice.lin":L:C)
  ^c1:
    %p19 = arith.constant 0 : i64 loc("std/mem/slice.lin":L:C)
    %v19 = arith.addi %v18, %p19 : i64 loc("std/mem/slice.lin":L:C)
    %v20 = arith.cmpi ugt, %v12, %v19 : i64 loc("std/mem/slice.lin":L:C)
    cf.cond_br %v20, ^b4, ^b5 loc("std/mem/slice.lin":L:C)
  ^b3:
    %rl63 = arith.constant 24 : i64 loc("std/mem/slice.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s3, %rl63) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/mem/slice.lin":L:C)
    func.return loc("std/mem/slice.lin":L:C)
  ^b4:
    %v23 = arith.constant 0 : i64 loc("std/mem/slice.lin":L:C)
    llvm.store %v23, %s4 : i64, !llvm.ptr loc("std/mem/slice.lin":L:C)
    cf.br ^b6 loc("std/mem/slice.lin":L:C)
  ^b5:
    %v27 = arith.constant 1 : i64 loc("std/mem/slice.lin":L:C)
    llvm.store %v27, %s4 : i64, !llvm.ptr loc("std/mem/slice.lin":L:C)
    %v29 = arith.constant 8 : i64 loc("std/mem/slice.lin":L:C)
    %v30 = llvm.getelementptr %s4[%v29] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/mem/slice.lin":L:C)
    %v31 = llvm.load %s0 : !llvm.ptr -> !llvm.ptr loc("std/mem/slice.lin":L:C)
    %v32 = llvm.load %s1 : !llvm.ptr -> i64 loc("std/mem/slice.lin":L:C)
    %v33 = llvm.load %s2 : !llvm.ptr -> i64 loc("std/mem/slice.lin":L:C)
    %v34 = arith.constant 1 : i64 loc("std/mem/slice.lin":L:C)
    %v35 = arith.constant 0 : i64 loc("std/mem/slice.lin":L:C)
    %v37 = llvm.load %v31 : !llvm.ptr -> i64 loc("std/mem/slice.lin":L:C)
    %v38 = arith.constant 8 : i64 loc("std/mem/slice.lin":L:C)
    %v39 = llvm.getelementptr %v31[%v38] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/mem/slice.lin":L:C)
    %v40 = llvm.load %v39 : !llvm.ptr -> i64 loc("std/mem/slice.lin":L:C)
    %v41 = arith.cmpi ule, %v32, %v40 : i64 loc("std/mem/slice.lin":L:C)
    %k2z = arith.constant true loc("std/mem/slice.lin":L:C)
    %k2 = arith.xori %v41, %k2z : i1 loc("std/mem/slice.lin":L:C)
    cf.cond_br %k2, ^t2, ^c2 loc("std/mem/slice.lin":L:C)
  ^t2:
    %tk2 = arith.constant 6 : i32 loc("std/mem/slice.lin":L:C)
    %tf2 = llvm.mlir.addressof @linea_file4 : !llvm.ptr loc("std/mem/slice.lin":L:C)
    %tl2 = arith.constant L : i32 loc("std/mem/slice.lin":L:C)
    %tc2 = arith.constant C : i32 loc("std/mem/slice.lin":L:C)
    func.call @linea_trap(%tk2, %tf2, %tl2, %tc2) : (i32, !llvm.ptr, i32, i32) -> () loc("std/mem/slice.lin":L:C)
    llvm.unreachable loc("std/mem/slice.lin":L:C)
  ^c2:
    %v42 = arith.ori %v41, %v41 : i1 loc("std/mem/slice.lin":L:C)
    %v43 = arith.subi %v40, %v32 : i64 loc("std/mem/slice.lin":L:C)
    %v44 = arith.cmpi ule, %v33, %v43 : i64 loc("std/mem/slice.lin":L:C)
    %k3z = arith.constant true loc("std/mem/slice.lin":L:C)
    %k3 = arith.xori %v44, %k3z : i1 loc("std/mem/slice.lin":L:C)
    cf.cond_br %k3, ^t3, ^c3 loc("std/mem/slice.lin":L:C)
  ^t3:
    %tk3 = arith.constant 6 : i32 loc("std/mem/slice.lin":L:C)
    %tf3 = llvm.mlir.addressof @linea_file4 : !llvm.ptr loc("std/mem/slice.lin":L:C)
    %tl3 = arith.constant L : i32 loc("std/mem/slice.lin":L:C)
    %tc3 = arith.constant C : i32 loc("std/mem/slice.lin":L:C)
    func.call @linea_trap(%tk3, %tf3, %tl3, %tc3) : (i32, !llvm.ptr, i32, i32) -> () loc("std/mem/slice.lin":L:C)
    llvm.unreachable loc("std/mem/slice.lin":L:C)
  ^c3:
    %v45 = arith.ori %v44, %v44 : i1 loc("std/mem/slice.lin":L:C)
    %m46 = "llvm.intr.umul.with.overflow"(%v32, %v34) : (i64, i64) -> !llvm.struct<(i64, i1)> loc("std/mem/slice.lin":L:C)
    %v46 = llvm.extractvalue %m46[0] : !llvm.struct<(i64, i1)> loc("std/mem/slice.lin":L:C)
    %k4 = llvm.extractvalue %m46[1] : !llvm.struct<(i64, i1)> loc("std/mem/slice.lin":L:C)
    cf.cond_br %k4, ^t4, ^c4 loc("std/mem/slice.lin":L:C)
  ^t4:
    %tk4 = arith.constant 0 : i32 loc("std/mem/slice.lin":L:C)
    %tf4 = llvm.mlir.addressof @linea_file4 : !llvm.ptr loc("std/mem/slice.lin":L:C)
    %tl4 = arith.constant L : i32 loc("std/mem/slice.lin":L:C)
    %tc4 = arith.constant C : i32 loc("std/mem/slice.lin":L:C)
    func.call @linea_trap(%tk4, %tf4, %tl4, %tc4) : (i32, !llvm.ptr, i32, i32) -> () loc("std/mem/slice.lin":L:C)
    llvm.unreachable loc("std/mem/slice.lin":L:C)
  ^c4:
    %p47 = arith.constant 0 : i64 loc("std/mem/slice.lin":L:C)
    %v47 = arith.addi %v46, %p47 : i64 loc("std/mem/slice.lin":L:C)
    %v48 = arith.addi %v37, %v46 : i64 loc("std/mem/slice.lin":L:C)
    %k5 = arith.cmpi ult, %v48, %v37 : i64 loc("std/mem/slice.lin":L:C)
    cf.cond_br %k5, ^t5, ^c5 loc("std/mem/slice.lin":L:C)
  ^t5:
    %tk5 = arith.constant 0 : i32 loc("std/mem/slice.lin":L:C)
    %tf5 = llvm.mlir.addressof @linea_file4 : !llvm.ptr loc("std/mem/slice.lin":L:C)
    %tl5 = arith.constant L : i32 loc("std/mem/slice.lin":L:C)
    %tc5 = arith.constant C : i32 loc("std/mem/slice.lin":L:C)
    func.call @linea_trap(%tk5, %tf5, %tl5, %tc5) : (i32, !llvm.ptr, i32, i32) -> () loc("std/mem/slice.lin":L:C)
    llvm.unreachable loc("std/mem/slice.lin":L:C)
  ^c5:
    %p49 = arith.constant 0 : i64 loc("std/mem/slice.lin":L:C)
    %v49 = arith.addi %v48, %p49 : i64 loc("std/mem/slice.lin":L:C)
    %v51 = arith.constant 0 : i64 loc("std/mem/slice.lin":L:C)
    llvm.store %v48, %s5 : i64, !llvm.ptr loc("std/mem/slice.lin":L:C)
    %v54 = arith.constant 8 : i64 loc("std/mem/slice.lin":L:C)
    %v55 = llvm.getelementptr %s5[%v54] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/mem/slice.lin":L:C)
    llvm.store %v33, %v55 : i64, !llvm.ptr loc("std/mem/slice.lin":L:C)
    %cl57 = arith.constant 16 : i64 loc("std/mem/slice.lin":L:C)
    "llvm.intr.memcpy"(%v30, %s5, %cl57) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/mem/slice.lin":L:C)
    cf.br ^b6 loc("std/mem/slice.lin":L:C)
  ^b6:
    %cl60 = arith.constant 24 : i64 loc("std/mem/slice.lin":L:C)
    "llvm.intr.memcpy"(%s3, %s4, %cl60) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/mem/slice.lin":L:C)
    cf.br ^b3 loc("std/mem/slice.lin":L:C)
  }
  func.func private @"lin.std.option;Option[std.mem.Slice[UInt8]].unwrap"(%sret: !llvm.ptr, %a0: !llvm.ptr) attributes {llvm.linkage = #llvm.linkage<internal>} {
    %z0 = arith.constant 24 : i64
    %s0 = llvm.alloca %z0 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 16 : i64
    %s1 = llvm.alloca %z1 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z2 = arith.constant 16 : i64
    %s2 = llvm.alloca %z2 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z3 = arith.constant 16 : i64
    %s3 = llvm.alloca %z3 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %pl0 = arith.constant 24 : i64
    "llvm.intr.memcpy"(%s0, %a0, %pl0) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> ()
    cf.br ^b0
  ^b0:
    %v1 = llvm.load %s0 : !llvm.ptr -> i64 loc("std/option/option.lin":L:C)
    %v2 = arith.constant 1 : i64 loc("std/option/option.lin":L:C)
    %v3 = arith.cmpi eq, %v1, %v2 : i64 loc("std/option/option.lin":L:C)
    cf.cond_br %v3, ^b2, ^b3 loc("std/option/option.lin":L:C)
  ^b1:
    %rl30 = arith.constant 16 : i64 loc("std/option/option.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s1, %rl30) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/option/option.lin":L:C)
    func.return loc("std/option/option.lin":L:C)
  ^b2:
    %v5 = arith.constant 8 : i64 loc("std/option/option.lin":L:C)
    %v6 = llvm.getelementptr %s0[%v5] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/option/option.lin":L:C)
    %cl8 = arith.constant 16 : i64 loc("std/option/option.lin":L:C)
    "llvm.intr.memcpy"(%s2, %v6, %cl8) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/option/option.lin":L:C)
    %cl11 = arith.constant 16 : i64 loc("std/option/option.lin":L:C)
    "llvm.intr.memcpy"(%s1, %s2, %cl11) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/option/option.lin":L:C)
    cf.br ^b1 loc("std/option/option.lin":L:C)
  ^b3:
    %v13 = arith.constant 0 : i64 loc("std/option/option.lin":L:C)
    %v14 = arith.cmpi eq, %v1, %v13 : i64 loc("std/option/option.lin":L:C)
    cf.cond_br %v14, ^b4, ^b5 loc("std/option/option.lin":L:C)
  ^b4:
    %ba17 = llvm.mlir.addressof @linea_str5 : !llvm.ptr loc("std/option/option.lin":L:C)
    %v17 = llvm.ptrtoint %ba17 : !llvm.ptr to i64 loc("std/option/option.lin":L:C)
    %v18 = arith.constant 0 : i64 loc("std/option/option.lin":L:C)
    llvm.store %v17, %s3 : i64, !llvm.ptr loc("std/option/option.lin":L:C)
    %v21 = arith.constant 28 : i64 loc("std/option/option.lin":L:C)
    %v22 = arith.constant 8 : i64 loc("std/option/option.lin":L:C)
    %v23 = llvm.getelementptr %s3[%v22] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/option/option.lin":L:C)
    llvm.store %v21, %v23 : i64, !llvm.ptr loc("std/option/option.lin":L:C)
    %poa1 = arith.constant 0 : i64 loc("std/option/option.lin":L:C)
    %ppa1 = llvm.getelementptr %s3[%poa1] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/option/option.lin":L:C)
    %pva1 = llvm.load %ppa1 : !llvm.ptr -> i64 loc("std/option/option.lin":L:C)
    %pol1 = arith.constant 8 : i64 loc("std/option/option.lin":L:C)
    %ppl1 = llvm.getelementptr %s3[%pol1] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/option/option.lin":L:C)
    %pvl1 = llvm.load %ppl1 : !llvm.ptr -> i64 loc("std/option/option.lin":L:C)
    %pf1 = llvm.mlir.addressof @linea_file5 : !llvm.ptr loc("std/option/option.lin":L:C)
    %tl1 = arith.constant L : i32 loc("std/option/option.lin":L:C)
    %tc1 = arith.constant C : i32 loc("std/option/option.lin":L:C)
    func.call @linea_panic(%pva1, %pvl1, %pf1, %tl1, %tc1) : (i64, i64, !llvm.ptr, i32, i32) -> () loc("std/option/option.lin":L:C)
    llvm.unreachable loc("std/option/option.lin":L:C)
  ^b5:
    %tk2 = arith.constant 3 : i32 loc("std/option/option.lin":L:C)
    %tf2 = llvm.mlir.addressof @linea_file5 : !llvm.ptr loc("std/option/option.lin":L:C)
    %tl2 = arith.constant L : i32 loc("std/option/option.lin":L:C)
    %tc2 = arith.constant C : i32 loc("std/option/option.lin":L:C)
    func.call @linea_trap(%tk2, %tf2, %tl2, %tc2) : (i32, !llvm.ptr, i32, i32) -> () loc("std/option/option.lin":L:C)
    llvm.unreachable loc("std/option/option.lin":L:C)
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
    %tf1 = llvm.mlir.addressof @linea_file3 : !llvm.ptr loc("std/text/str.lin":L:C)
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
    %tf2 = llvm.mlir.addressof @linea_file3 : !llvm.ptr loc("std/text/str.lin":L:C)
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
    %tf3 = llvm.mlir.addressof @linea_file3 : !llvm.ptr loc("std/text/str.lin":L:C)
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
    %tf4 = llvm.mlir.addressof @linea_file3 : !llvm.ptr loc("std/text/str.lin":L:C)
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
    %tf5 = llvm.mlir.addressof @linea_file3 : !llvm.ptr loc("std/text/str.lin":L:C)
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
  func.func @main(%argc: i32, %argv: !llvm.ptr) -> i32 {
    func.call @linea_set_args(%argc, %argv) : (i32, !llvm.ptr) -> ()
    %status = func.call @"lin.;main"() : () -> i64
    %status32 = arith.trunci %status : i64 to i32
    func.return %status32 : i32
  }
}
