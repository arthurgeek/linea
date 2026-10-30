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
  llvm.mlir.global internal constant @linea_file0("tests/text/a_byte_past_the_end_is_absent.lin\00") : !llvm.array<45 x i8>
  llvm.mlir.global internal constant @linea_file1("std/text/str.lin\00") : !llvm.array<17 x i8>
  llvm.mlir.global internal constant @linea_file2("std/mem/slice.lin\00") : !llvm.array<18 x i8>
  llvm.mlir.global internal constant @linea_str0("AB") : !llvm.array<2 x i8>
  func.func private @linea_set_args(i32, !llvm.ptr)
  func.func private @linea_trap(i32, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @linea_panic(i64, i64, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @"lin.;main"() -> i64 attributes {llvm.linkage = #llvm.linkage<internal>, passthrough = [["probe-stack", "inline-asm"]]} {
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
    %z7 = arith.constant 1 : i64
    %s7 = llvm.alloca %z7 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z8 = arith.constant 1 : i64
    %s8 = llvm.alloca %z8 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z9 = arith.constant 1 : i64
    %s9 = llvm.alloca %z9 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %rz11 = arith.constant 16 : i64
    %rs11 = llvm.alloca %rz11 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz38 = arith.constant 16 : i64
    %rs38 = llvm.alloca %rz38 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz65 = arith.constant 16 : i64
    %rs65 = llvm.alloca %rz65 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    cf.br ^b0
  ^b0:
    %ba1 = llvm.mlir.addressof @linea_str0 : !llvm.ptr loc("tests/text/a_byte_past_the_end_is_absent.lin":11:13)
    %v1 = llvm.ptrtoint %ba1 : !llvm.ptr to i64 loc("tests/text/a_byte_past_the_end_is_absent.lin":11:13)
    %v2 = arith.constant 0 : i64 loc("tests/text/a_byte_past_the_end_is_absent.lin":11:13)
    llvm.store %v1, %s0 : i64, !llvm.ptr loc("tests/text/a_byte_past_the_end_is_absent.lin":11:13)
    %v5 = arith.constant 2 : i64 loc("tests/text/a_byte_past_the_end_is_absent.lin":11:13)
    %v6 = arith.constant 8 : i64 loc("tests/text/a_byte_past_the_end_is_absent.lin":11:13)
    %v7 = llvm.getelementptr %s0[%v6] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("tests/text/a_byte_past_the_end_is_absent.lin":11:13)
    llvm.store %v5, %v7 : i64, !llvm.ptr loc("tests/text/a_byte_past_the_end_is_absent.lin":11:13)
    %v10 = arith.constant 0 : i64 loc("tests/text/a_byte_past_the_end_is_absent.lin":13:42)
    func.call @"lin.std.text;Str.byte"(%rs11, %s0, %v10) : (!llvm.ptr, !llvm.ptr, i64) -> () loc("tests/text/a_byte_past_the_end_is_absent.lin":13:30)
    %v12 = llvm.load %rs11 : !llvm.ptr -> i64 loc("tests/text/a_byte_past_the_end_is_absent.lin":13:24)
    %v13 = arith.constant 1 : i64 loc("tests/text/a_byte_past_the_end_is_absent.lin":13:24)
    %v14 = arith.cmpi eq, %v12, %v13 : i64 loc("tests/text/a_byte_past_the_end_is_absent.lin":13:24)
    cf.cond_br %v14, ^b3, ^b2 loc("tests/text/a_byte_past_the_end_is_absent.lin":13:24)
  ^b1:
    %lw34 = llvm.load %s2 : !llvm.ptr -> i8 loc("tests/text/a_byte_past_the_end_is_absent.lin":13:24)
    %v34 = arith.extui %lw34 : i8 to i64 loc("tests/text/a_byte_past_the_end_is_absent.lin":13:24)
    %sw35 = arith.trunci %v34 : i64 to i8 loc("tests/text/a_byte_past_the_end_is_absent.lin":13:5)
    llvm.store %sw35, %s1 : i8, !llvm.ptr loc("tests/text/a_byte_past_the_end_is_absent.lin":13:5)
    %v37 = arith.constant 1 : i64 loc("tests/text/a_byte_past_the_end_is_absent.lin":18:43)
    func.call @"lin.std.text;Str.byte"(%rs38, %s0, %v37) : (!llvm.ptr, !llvm.ptr, i64) -> () loc("tests/text/a_byte_past_the_end_is_absent.lin":18:31)
    %v39 = llvm.load %rs38 : !llvm.ptr -> i64 loc("tests/text/a_byte_past_the_end_is_absent.lin":18:25)
    %v40 = arith.constant 1 : i64 loc("tests/text/a_byte_past_the_end_is_absent.lin":18:25)
    %v41 = arith.cmpi eq, %v39, %v40 : i64 loc("tests/text/a_byte_past_the_end_is_absent.lin":18:25)
    cf.cond_br %v41, ^b8, ^b7 loc("tests/text/a_byte_past_the_end_is_absent.lin":18:25)
  ^b2:
    %v26 = llvm.load %rs11 : !llvm.ptr -> i64 loc("tests/text/a_byte_past_the_end_is_absent.lin":13:24)
    %v27 = arith.constant 0 : i64 loc("tests/text/a_byte_past_the_end_is_absent.lin":13:24)
    %v28 = arith.cmpi eq, %v26, %v27 : i64 loc("tests/text/a_byte_past_the_end_is_absent.lin":13:24)
    cf.cond_br %v28, ^b5, ^b4 loc("tests/text/a_byte_past_the_end_is_absent.lin":13:24)
  ^b3:
    %v16 = arith.constant 8 : i64 loc("tests/text/a_byte_past_the_end_is_absent.lin":13:24)
    %v17 = llvm.getelementptr %rs11[%v16] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("tests/text/a_byte_past_the_end_is_absent.lin":13:24)
    %iw18 = llvm.load %v17 : !llvm.ptr -> i8 loc("tests/text/a_byte_past_the_end_is_absent.lin":13:24)
    %v18 = arith.extui %iw18 : i8 to i64 loc("tests/text/a_byte_past_the_end_is_absent.lin":13:24)
    %sw19 = arith.trunci %v18 : i64 to i8 loc("tests/text/a_byte_past_the_end_is_absent.lin":13:24)
    llvm.store %sw19, %s3 : i8, !llvm.ptr loc("tests/text/a_byte_past_the_end_is_absent.lin":13:24)
    %lw20 = llvm.load %s3 : !llvm.ptr -> i8 loc("tests/text/a_byte_past_the_end_is_absent.lin":14:20)
    %v20 = arith.extui %lw20 : i8 to i64 loc("tests/text/a_byte_past_the_end_is_absent.lin":14:20)
    %v21 = arith.constant 64 : i64 loc("tests/text/a_byte_past_the_end_is_absent.lin":14:24)
    %v22 = arith.subi %v20, %v21 : i64 loc("tests/text/a_byte_past_the_end_is_absent.lin":14:20)
    %k1m = arith.constant 255 : i64 loc("tests/text/a_byte_past_the_end_is_absent.lin":14:22)
    %k1 = arith.cmpi ugt, %v22, %k1m : i64 loc("tests/text/a_byte_past_the_end_is_absent.lin":14:22)
    cf.cond_br %k1, ^t1, ^c1 loc("tests/text/a_byte_past_the_end_is_absent.lin":14:22)
  ^t1:
    %tk1 = arith.constant 0 : i32 loc("tests/text/a_byte_past_the_end_is_absent.lin":14:22)
    %tf1 = llvm.mlir.addressof @linea_file0 : !llvm.ptr loc("tests/text/a_byte_past_the_end_is_absent.lin":14:22)
    %tl1 = arith.constant 14 : i32 loc("tests/text/a_byte_past_the_end_is_absent.lin":14:22)
    %tc1 = arith.constant 22 : i32 loc("tests/text/a_byte_past_the_end_is_absent.lin":14:22)
    func.call @linea_trap(%tk1, %tf1, %tl1, %tc1) : (i32, !llvm.ptr, i32, i32) -> () loc("tests/text/a_byte_past_the_end_is_absent.lin":14:22)
    llvm.unreachable loc("tests/text/a_byte_past_the_end_is_absent.lin":14:22)
  ^c1:
    %p23 = arith.constant 0 : i64 loc("tests/text/a_byte_past_the_end_is_absent.lin":14:22)
    %v23 = arith.addi %v22, %p23 : i64 loc("tests/text/a_byte_past_the_end_is_absent.lin":14:22)
    %sw24 = arith.trunci %v23 : i64 to i8 loc("tests/text/a_byte_past_the_end_is_absent.lin":13:24)
    llvm.store %sw24, %s2 : i8, !llvm.ptr loc("tests/text/a_byte_past_the_end_is_absent.lin":13:24)
    cf.br ^b1 loc("tests/text/a_byte_past_the_end_is_absent.lin":13:24)
  ^b4:
    %tk2 = arith.constant 3 : i32 loc("tests/text/a_byte_past_the_end_is_absent.lin":13:24)
    %tf2 = llvm.mlir.addressof @linea_file0 : !llvm.ptr loc("tests/text/a_byte_past_the_end_is_absent.lin":13:24)
    %tl2 = arith.constant 13 : i32 loc("tests/text/a_byte_past_the_end_is_absent.lin":13:24)
    %tc2 = arith.constant 24 : i32 loc("tests/text/a_byte_past_the_end_is_absent.lin":13:24)
    func.call @linea_trap(%tk2, %tf2, %tl2, %tc2) : (i32, !llvm.ptr, i32, i32) -> () loc("tests/text/a_byte_past_the_end_is_absent.lin":13:24)
    llvm.unreachable loc("tests/text/a_byte_past_the_end_is_absent.lin":13:24)
  ^b5:
    %v30 = arith.constant 0 : i64 loc("tests/text/a_byte_past_the_end_is_absent.lin":15:17)
    %sw31 = arith.trunci %v30 : i64 to i8 loc("tests/text/a_byte_past_the_end_is_absent.lin":13:24)
    llvm.store %sw31, %s2 : i8, !llvm.ptr loc("tests/text/a_byte_past_the_end_is_absent.lin":13:24)
    cf.br ^b1 loc("tests/text/a_byte_past_the_end_is_absent.lin":13:24)
  ^b6:
    %lw61 = llvm.load %s5 : !llvm.ptr -> i8 loc("tests/text/a_byte_past_the_end_is_absent.lin":18:25)
    %v61 = arith.extui %lw61 : i8 to i64 loc("tests/text/a_byte_past_the_end_is_absent.lin":18:25)
    %sw62 = arith.trunci %v61 : i64 to i8 loc("tests/text/a_byte_past_the_end_is_absent.lin":18:5)
    llvm.store %sw62, %s4 : i8, !llvm.ptr loc("tests/text/a_byte_past_the_end_is_absent.lin":18:5)
    %v64 = arith.constant 2 : i64 loc("tests/text/a_byte_past_the_end_is_absent.lin":25:41)
    func.call @"lin.std.text;Str.byte"(%rs65, %s0, %v64) : (!llvm.ptr, !llvm.ptr, i64) -> () loc("tests/text/a_byte_past_the_end_is_absent.lin":25:29)
    %v66 = llvm.load %rs65 : !llvm.ptr -> i64 loc("tests/text/a_byte_past_the_end_is_absent.lin":25:23)
    %v67 = arith.constant 1 : i64 loc("tests/text/a_byte_past_the_end_is_absent.lin":25:23)
    %v68 = arith.cmpi eq, %v66, %v67 : i64 loc("tests/text/a_byte_past_the_end_is_absent.lin":25:23)
    cf.cond_br %v68, ^b13, ^b12 loc("tests/text/a_byte_past_the_end_is_absent.lin":25:23)
  ^b7:
    %v53 = llvm.load %rs38 : !llvm.ptr -> i64 loc("tests/text/a_byte_past_the_end_is_absent.lin":18:25)
    %v54 = arith.constant 0 : i64 loc("tests/text/a_byte_past_the_end_is_absent.lin":18:25)
    %v55 = arith.cmpi eq, %v53, %v54 : i64 loc("tests/text/a_byte_past_the_end_is_absent.lin":18:25)
    cf.cond_br %v55, ^b10, ^b9 loc("tests/text/a_byte_past_the_end_is_absent.lin":18:25)
  ^b8:
    %v43 = arith.constant 8 : i64 loc("tests/text/a_byte_past_the_end_is_absent.lin":18:25)
    %v44 = llvm.getelementptr %rs38[%v43] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("tests/text/a_byte_past_the_end_is_absent.lin":18:25)
    %iw45 = llvm.load %v44 : !llvm.ptr -> i8 loc("tests/text/a_byte_past_the_end_is_absent.lin":18:25)
    %v45 = arith.extui %iw45 : i8 to i64 loc("tests/text/a_byte_past_the_end_is_absent.lin":18:25)
    %sw46 = arith.trunci %v45 : i64 to i8 loc("tests/text/a_byte_past_the_end_is_absent.lin":18:25)
    llvm.store %sw46, %s6 : i8, !llvm.ptr loc("tests/text/a_byte_past_the_end_is_absent.lin":18:25)
    %lw47 = llvm.load %s6 : !llvm.ptr -> i8 loc("tests/text/a_byte_past_the_end_is_absent.lin":19:20)
    %v47 = arith.extui %lw47 : i8 to i64 loc("tests/text/a_byte_past_the_end_is_absent.lin":19:20)
    %v48 = arith.constant 64 : i64 loc("tests/text/a_byte_past_the_end_is_absent.lin":19:24)
    %v49 = arith.subi %v47, %v48 : i64 loc("tests/text/a_byte_past_the_end_is_absent.lin":19:20)
    %k3m = arith.constant 255 : i64 loc("tests/text/a_byte_past_the_end_is_absent.lin":19:22)
    %k3 = arith.cmpi ugt, %v49, %k3m : i64 loc("tests/text/a_byte_past_the_end_is_absent.lin":19:22)
    cf.cond_br %k3, ^t3, ^c3 loc("tests/text/a_byte_past_the_end_is_absent.lin":19:22)
  ^t3:
    %tk3 = arith.constant 0 : i32 loc("tests/text/a_byte_past_the_end_is_absent.lin":19:22)
    %tf3 = llvm.mlir.addressof @linea_file0 : !llvm.ptr loc("tests/text/a_byte_past_the_end_is_absent.lin":19:22)
    %tl3 = arith.constant 19 : i32 loc("tests/text/a_byte_past_the_end_is_absent.lin":19:22)
    %tc3 = arith.constant 22 : i32 loc("tests/text/a_byte_past_the_end_is_absent.lin":19:22)
    func.call @linea_trap(%tk3, %tf3, %tl3, %tc3) : (i32, !llvm.ptr, i32, i32) -> () loc("tests/text/a_byte_past_the_end_is_absent.lin":19:22)
    llvm.unreachable loc("tests/text/a_byte_past_the_end_is_absent.lin":19:22)
  ^c3:
    %p50 = arith.constant 0 : i64 loc("tests/text/a_byte_past_the_end_is_absent.lin":19:22)
    %v50 = arith.addi %v49, %p50 : i64 loc("tests/text/a_byte_past_the_end_is_absent.lin":19:22)
    %sw51 = arith.trunci %v50 : i64 to i8 loc("tests/text/a_byte_past_the_end_is_absent.lin":18:25)
    llvm.store %sw51, %s5 : i8, !llvm.ptr loc("tests/text/a_byte_past_the_end_is_absent.lin":18:25)
    cf.br ^b6 loc("tests/text/a_byte_past_the_end_is_absent.lin":18:25)
  ^b9:
    %tk4 = arith.constant 3 : i32 loc("tests/text/a_byte_past_the_end_is_absent.lin":18:25)
    %tf4 = llvm.mlir.addressof @linea_file0 : !llvm.ptr loc("tests/text/a_byte_past_the_end_is_absent.lin":18:25)
    %tl4 = arith.constant 18 : i32 loc("tests/text/a_byte_past_the_end_is_absent.lin":18:25)
    %tc4 = arith.constant 25 : i32 loc("tests/text/a_byte_past_the_end_is_absent.lin":18:25)
    func.call @linea_trap(%tk4, %tf4, %tl4, %tc4) : (i32, !llvm.ptr, i32, i32) -> () loc("tests/text/a_byte_past_the_end_is_absent.lin":18:25)
    llvm.unreachable loc("tests/text/a_byte_past_the_end_is_absent.lin":18:25)
  ^b10:
    %v57 = arith.constant 0 : i64 loc("tests/text/a_byte_past_the_end_is_absent.lin":20:17)
    %sw58 = arith.trunci %v57 : i64 to i8 loc("tests/text/a_byte_past_the_end_is_absent.lin":18:25)
    llvm.store %sw58, %s5 : i8, !llvm.ptr loc("tests/text/a_byte_past_the_end_is_absent.lin":18:25)
    cf.br ^b6 loc("tests/text/a_byte_past_the_end_is_absent.lin":18:25)
  ^b11:
    %lw85 = llvm.load %s8 : !llvm.ptr -> i8 loc("tests/text/a_byte_past_the_end_is_absent.lin":25:23)
    %v85 = arith.extui %lw85 : i8 to i64 loc("tests/text/a_byte_past_the_end_is_absent.lin":25:23)
    %sw86 = arith.trunci %v85 : i64 to i8 loc("tests/text/a_byte_past_the_end_is_absent.lin":25:5)
    llvm.store %sw86, %s7 : i8, !llvm.ptr loc("tests/text/a_byte_past_the_end_is_absent.lin":25:5)
    %lw87 = llvm.load %s1 : !llvm.ptr -> i8 loc("tests/text/a_byte_past_the_end_is_absent.lin":31:5)
    %v87 = arith.extui %lw87 : i8 to i64 loc("tests/text/a_byte_past_the_end_is_absent.lin":31:5)
    %lw88 = llvm.load %s4 : !llvm.ptr -> i8 loc("tests/text/a_byte_past_the_end_is_absent.lin":31:13)
    %v88 = arith.extui %lw88 : i8 to i64 loc("tests/text/a_byte_past_the_end_is_absent.lin":31:13)
    %v89 = arith.addi %v87, %v88 : i64 loc("tests/text/a_byte_past_the_end_is_absent.lin":31:5)
    %k5m = arith.constant 255 : i64 loc("tests/text/a_byte_past_the_end_is_absent.lin":31:11)
    %k5 = arith.cmpi ugt, %v89, %k5m : i64 loc("tests/text/a_byte_past_the_end_is_absent.lin":31:11)
    cf.cond_br %k5, ^t5, ^c5 loc("tests/text/a_byte_past_the_end_is_absent.lin":31:11)
  ^t5:
    %tk5 = arith.constant 0 : i32 loc("tests/text/a_byte_past_the_end_is_absent.lin":31:11)
    %tf5 = llvm.mlir.addressof @linea_file0 : !llvm.ptr loc("tests/text/a_byte_past_the_end_is_absent.lin":31:11)
    %tl5 = arith.constant 31 : i32 loc("tests/text/a_byte_past_the_end_is_absent.lin":31:11)
    %tc5 = arith.constant 11 : i32 loc("tests/text/a_byte_past_the_end_is_absent.lin":31:11)
    func.call @linea_trap(%tk5, %tf5, %tl5, %tc5) : (i32, !llvm.ptr, i32, i32) -> () loc("tests/text/a_byte_past_the_end_is_absent.lin":31:11)
    llvm.unreachable loc("tests/text/a_byte_past_the_end_is_absent.lin":31:11)
  ^c5:
    %p90 = arith.constant 0 : i64 loc("tests/text/a_byte_past_the_end_is_absent.lin":31:11)
    %v90 = arith.addi %v89, %p90 : i64 loc("tests/text/a_byte_past_the_end_is_absent.lin":31:11)
    %lw91 = llvm.load %s7 : !llvm.ptr -> i8 loc("tests/text/a_byte_past_the_end_is_absent.lin":31:22)
    %v91 = arith.extui %lw91 : i8 to i64 loc("tests/text/a_byte_past_the_end_is_absent.lin":31:22)
    %v92 = arith.addi %v90, %v91 : i64 loc("tests/text/a_byte_past_the_end_is_absent.lin":31:5)
    %k6m = arith.constant 255 : i64 loc("tests/text/a_byte_past_the_end_is_absent.lin":31:20)
    %k6 = arith.cmpi ugt, %v92, %k6m : i64 loc("tests/text/a_byte_past_the_end_is_absent.lin":31:20)
    cf.cond_br %k6, ^t6, ^c6 loc("tests/text/a_byte_past_the_end_is_absent.lin":31:20)
  ^t6:
    %tk6 = arith.constant 0 : i32 loc("tests/text/a_byte_past_the_end_is_absent.lin":31:20)
    %tf6 = llvm.mlir.addressof @linea_file0 : !llvm.ptr loc("tests/text/a_byte_past_the_end_is_absent.lin":31:20)
    %tl6 = arith.constant 31 : i32 loc("tests/text/a_byte_past_the_end_is_absent.lin":31:20)
    %tc6 = arith.constant 20 : i32 loc("tests/text/a_byte_past_the_end_is_absent.lin":31:20)
    func.call @linea_trap(%tk6, %tf6, %tl6, %tc6) : (i32, !llvm.ptr, i32, i32) -> () loc("tests/text/a_byte_past_the_end_is_absent.lin":31:20)
    llvm.unreachable loc("tests/text/a_byte_past_the_end_is_absent.lin":31:20)
  ^c6:
    %p93 = arith.constant 0 : i64 loc("tests/text/a_byte_past_the_end_is_absent.lin":31:20)
    %v93 = arith.addi %v92, %p93 : i64 loc("tests/text/a_byte_past_the_end_is_absent.lin":31:20)
    func.return %v93 : i64 loc("tests/text/a_byte_past_the_end_is_absent.lin":31:5)
  ^b12:
    %v77 = llvm.load %rs65 : !llvm.ptr -> i64 loc("tests/text/a_byte_past_the_end_is_absent.lin":25:23)
    %v78 = arith.constant 0 : i64 loc("tests/text/a_byte_past_the_end_is_absent.lin":25:23)
    %v79 = arith.cmpi eq, %v77, %v78 : i64 loc("tests/text/a_byte_past_the_end_is_absent.lin":25:23)
    cf.cond_br %v79, ^b15, ^b14 loc("tests/text/a_byte_past_the_end_is_absent.lin":25:23)
  ^b13:
    %v70 = arith.constant 8 : i64 loc("tests/text/a_byte_past_the_end_is_absent.lin":25:23)
    %v71 = llvm.getelementptr %rs65[%v70] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("tests/text/a_byte_past_the_end_is_absent.lin":25:23)
    %iw72 = llvm.load %v71 : !llvm.ptr -> i8 loc("tests/text/a_byte_past_the_end_is_absent.lin":25:23)
    %v72 = arith.extui %iw72 : i8 to i64 loc("tests/text/a_byte_past_the_end_is_absent.lin":25:23)
    %sw73 = arith.trunci %v72 : i64 to i8 loc("tests/text/a_byte_past_the_end_is_absent.lin":25:23)
    llvm.store %sw73, %s9 : i8, !llvm.ptr loc("tests/text/a_byte_past_the_end_is_absent.lin":25:23)
    %v74 = arith.constant 100 : i64 loc("tests/text/a_byte_past_the_end_is_absent.lin":26:20)
    %sw75 = arith.trunci %v74 : i64 to i8 loc("tests/text/a_byte_past_the_end_is_absent.lin":25:23)
    llvm.store %sw75, %s8 : i8, !llvm.ptr loc("tests/text/a_byte_past_the_end_is_absent.lin":25:23)
    cf.br ^b11 loc("tests/text/a_byte_past_the_end_is_absent.lin":25:23)
  ^b14:
    %tk7 = arith.constant 3 : i32 loc("tests/text/a_byte_past_the_end_is_absent.lin":25:23)
    %tf7 = llvm.mlir.addressof @linea_file0 : !llvm.ptr loc("tests/text/a_byte_past_the_end_is_absent.lin":25:23)
    %tl7 = arith.constant 25 : i32 loc("tests/text/a_byte_past_the_end_is_absent.lin":25:23)
    %tc7 = arith.constant 23 : i32 loc("tests/text/a_byte_past_the_end_is_absent.lin":25:23)
    func.call @linea_trap(%tk7, %tf7, %tl7, %tc7) : (i32, !llvm.ptr, i32, i32) -> () loc("tests/text/a_byte_past_the_end_is_absent.lin":25:23)
    llvm.unreachable loc("tests/text/a_byte_past_the_end_is_absent.lin":25:23)
  ^b15:
    %v81 = arith.constant 4 : i64 loc("tests/text/a_byte_past_the_end_is_absent.lin":27:17)
    %sw82 = arith.trunci %v81 : i64 to i8 loc("tests/text/a_byte_past_the_end_is_absent.lin":25:23)
    llvm.store %sw82, %s8 : i8, !llvm.ptr loc("tests/text/a_byte_past_the_end_is_absent.lin":25:23)
    cf.br ^b11 loc("tests/text/a_byte_past_the_end_is_absent.lin":25:23)
  }
  func.func private @"lin.std.text;Str.byte"(%sret: !llvm.ptr, %a0: !llvm.ptr, %a1: i64) attributes {llvm.linkage = #llvm.linkage<internal>, passthrough = [["probe-stack", "inline-asm"]]} {
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
  func.func private @"lin.std.text;Str.length"(%a0: !llvm.ptr) -> i64 attributes {llvm.linkage = #llvm.linkage<internal>, passthrough = [["probe-stack", "inline-asm"]]} {
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
  func.func private @"lin.std.mem;Slice[UInt8].length"(%a0: !llvm.ptr) -> i64 attributes {llvm.linkage = #llvm.linkage<internal>, passthrough = [["probe-stack", "inline-asm"]]} {
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
