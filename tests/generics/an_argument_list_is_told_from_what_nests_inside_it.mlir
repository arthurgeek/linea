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
  llvm.mlir.global internal constant @linea_file0("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin\00") : !llvm.array<70 x i8>
  func.func private @linea_set_args(i32, !llvm.ptr)
  func.func private @linea_trap(i32, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @linea_panic(i64, i64, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @"lin.;main"() -> i64 attributes {llvm.linkage = #llvm.linkage<internal>, passthrough = [["probe-stack", "inline-asm"]]} {
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
    %z6 = arith.constant 1 : i64
    %s6 = llvm.alloca %z6 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z7 = arith.constant 1 : i64
    %s7 = llvm.alloca %z7 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z8 = arith.constant 1 : i64
    %s8 = llvm.alloca %z8 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z9 = arith.constant 1 : i64
    %s9 = llvm.alloca %z9 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z10 = arith.constant 1 : i64
    %s10 = llvm.alloca %z10 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z11 = arith.constant 1 : i64
    %s11 = llvm.alloca %z11 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z12 = arith.constant 1 : i64
    %s12 = llvm.alloca %z12 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    cf.br ^b0
  ^b0:
    %v1 = arith.constant 0 : i64 loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":36:27)
    %v3 = arith.constant 2 : i64 loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":36:37)
    %iw4 = arith.trunci %v3 : i64 to i8 loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":36:27)
    llvm.store %iw4, %s0 : i8, !llvm.ptr loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":36:27)
    %v6 = arith.constant 0 : i64 loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":37:27)
    %v8 = arith.constant 3 : i64 loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":37:37)
    %iw9 = arith.trunci %v8 : i64 to i8 loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":37:27)
    llvm.store %iw9, %s1 : i8, !llvm.ptr loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":37:27)
    %v11 = arith.constant 0 : i64 loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":38:27)
    %v13 = arith.constant 5 : i64 loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":38:37)
    %iw14 = arith.trunci %v13 : i64 to i8 loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":38:27)
    llvm.store %iw14, %s2 : i8, !llvm.ptr loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":38:27)
    %v16 = arith.constant 0 : i64 loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":39:33)
    %v18 = arith.constant 0 : i64 loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":39:43)
    %v20 = arith.constant 6 : i64 loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":39:53)
    %iw21 = arith.trunci %v20 : i64 to i8 loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":39:43)
    llvm.store %iw21, %s3 : i8, !llvm.ptr loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":39:43)
    %v23 = arith.constant 0 : i64 loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":40:27)
    %v25 = arith.constant 7 : i64 loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":40:37)
    %iw26 = arith.trunci %v25 : i64 to i8 loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":40:27)
    llvm.store %iw26, %s4 : i8, !llvm.ptr loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":40:27)
    %v28 = arith.constant 0 : i64 loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":41:33)
    %v30 = arith.constant 0 : i64 loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":41:43)
    %v32 = arith.constant 9 : i64 loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":41:53)
    %iw33 = arith.trunci %v32 : i64 to i8 loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":41:43)
    llvm.store %iw33, %s5 : i8, !llvm.ptr loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":41:43)
    %v35 = arith.constant 0 : i64 loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":42:28)
    %v37 = arith.constant 10 : i64 loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":42:38)
    %iw38 = arith.trunci %v37 : i64 to i8 loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":42:28)
    llvm.store %iw38, %s6 : i8, !llvm.ptr loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":42:28)
    %v39 = arith.constant 1 : i64 loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":45:24)
    %v41 = func.call @"lin.;two[Int64,Wrap[UInt8]]"(%v39, %s0) : (i64, !llvm.ptr) -> i64 loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":45:20)
    %sw42 = arith.trunci %v41 : i64 to i8 loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":45:5)
    llvm.store %sw42, %s7 : i8, !llvm.ptr loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":45:5)
    %v44 = arith.constant 4 : i64 loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":46:28)
    %v45 = func.call @"lin.;two[Wrap[UInt8],Int64]"(%s1, %v44) : (!llvm.ptr, i64) -> i64 loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":46:20)
    %sw46 = arith.trunci %v45 : i64 to i8 loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":46:5)
    llvm.store %sw46, %s8 : i8, !llvm.ptr loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":46:5)
    %v48 = func.call @"lin.;one[Wrap[UInt8]]"(%s2) : (!llvm.ptr) -> i64 loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":49:20)
    %sw49 = arith.trunci %v48 : i64 to i8 loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":49:5)
    llvm.store %sw49, %s9 : i8, !llvm.ptr loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":49:5)
    %v51 = func.call @"lin.;one[Wrap[Wrap[UInt8]]]"(%s3) : (!llvm.ptr) -> i64 loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":50:20)
    %sw52 = arith.trunci %v51 : i64 to i8 loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":50:5)
    llvm.store %sw52, %s10 : i8, !llvm.ptr loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":50:5)
    %v54 = arith.constant 8 : i64 loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":53:33)
    %v55 = func.call @"lin.;Wrap[UInt8].mix[Int64]"(%s4, %v54) : (!llvm.ptr, i64) -> i64 loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":53:20)
    %sw56 = arith.trunci %v55 : i64 to i8 loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":53:5)
    llvm.store %sw56, %s11 : i8, !llvm.ptr loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":53:5)
    %v59 = func.call @"lin.;Wrap[Wrap[UInt8]].mix[Wrap[UInt8]]"(%s5, %s6) : (!llvm.ptr, !llvm.ptr) -> i64 loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":54:20)
    %sw60 = arith.trunci %v59 : i64 to i8 loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":54:5)
    llvm.store %sw60, %s12 : i8, !llvm.ptr loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":54:5)
    %lw61 = llvm.load %s7 : !llvm.ptr -> i8 loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":56:5)
    %v61 = arith.extui %lw61 : i8 to i64 loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":56:5)
    %lw62 = llvm.load %s8 : !llvm.ptr -> i8 loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":56:9)
    %v62 = arith.extui %lw62 : i8 to i64 loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":56:9)
    %v63 = arith.addi %v61, %v62 : i64 loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":56:5)
    %k1m = arith.constant 255 : i64 loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":56:7)
    %k1 = arith.cmpi ugt, %v63, %k1m : i64 loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":56:7)
    cf.cond_br %k1, ^t1, ^c1 loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":56:7)
  ^t1:
    %tk1 = arith.constant 0 : i32 loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":56:7)
    %tf1 = llvm.mlir.addressof @linea_file0 : !llvm.ptr loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":56:7)
    %tl1 = arith.constant 56 : i32 loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":56:7)
    %tc1 = arith.constant 7 : i32 loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":56:7)
    func.call @linea_trap(%tk1, %tf1, %tl1, %tc1) : (i32, !llvm.ptr, i32, i32) -> () loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":56:7)
    llvm.unreachable loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":56:7)
  ^c1:
    %p64 = arith.constant 0 : i64 loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":56:7)
    %v64 = arith.addi %v63, %p64 : i64 loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":56:7)
    %lw65 = llvm.load %s9 : !llvm.ptr -> i8 loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":56:13)
    %v65 = arith.extui %lw65 : i8 to i64 loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":56:13)
    %v66 = arith.addi %v64, %v65 : i64 loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":56:5)
    %k2m = arith.constant 255 : i64 loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":56:11)
    %k2 = arith.cmpi ugt, %v66, %k2m : i64 loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":56:11)
    cf.cond_br %k2, ^t2, ^c2 loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":56:11)
  ^t2:
    %tk2 = arith.constant 0 : i32 loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":56:11)
    %tf2 = llvm.mlir.addressof @linea_file0 : !llvm.ptr loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":56:11)
    %tl2 = arith.constant 56 : i32 loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":56:11)
    %tc2 = arith.constant 11 : i32 loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":56:11)
    func.call @linea_trap(%tk2, %tf2, %tl2, %tc2) : (i32, !llvm.ptr, i32, i32) -> () loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":56:11)
    llvm.unreachable loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":56:11)
  ^c2:
    %p67 = arith.constant 0 : i64 loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":56:11)
    %v67 = arith.addi %v66, %p67 : i64 loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":56:11)
    %lw68 = llvm.load %s10 : !llvm.ptr -> i8 loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":56:17)
    %v68 = arith.extui %lw68 : i8 to i64 loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":56:17)
    %v69 = arith.addi %v67, %v68 : i64 loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":56:5)
    %k3m = arith.constant 255 : i64 loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":56:15)
    %k3 = arith.cmpi ugt, %v69, %k3m : i64 loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":56:15)
    cf.cond_br %k3, ^t3, ^c3 loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":56:15)
  ^t3:
    %tk3 = arith.constant 0 : i32 loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":56:15)
    %tf3 = llvm.mlir.addressof @linea_file0 : !llvm.ptr loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":56:15)
    %tl3 = arith.constant 56 : i32 loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":56:15)
    %tc3 = arith.constant 15 : i32 loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":56:15)
    func.call @linea_trap(%tk3, %tf3, %tl3, %tc3) : (i32, !llvm.ptr, i32, i32) -> () loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":56:15)
    llvm.unreachable loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":56:15)
  ^c3:
    %p70 = arith.constant 0 : i64 loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":56:15)
    %v70 = arith.addi %v69, %p70 : i64 loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":56:15)
    %lw71 = llvm.load %s11 : !llvm.ptr -> i8 loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":56:21)
    %v71 = arith.extui %lw71 : i8 to i64 loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":56:21)
    %v72 = arith.addi %v70, %v71 : i64 loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":56:5)
    %k4m = arith.constant 255 : i64 loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":56:19)
    %k4 = arith.cmpi ugt, %v72, %k4m : i64 loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":56:19)
    cf.cond_br %k4, ^t4, ^c4 loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":56:19)
  ^t4:
    %tk4 = arith.constant 0 : i32 loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":56:19)
    %tf4 = llvm.mlir.addressof @linea_file0 : !llvm.ptr loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":56:19)
    %tl4 = arith.constant 56 : i32 loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":56:19)
    %tc4 = arith.constant 19 : i32 loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":56:19)
    func.call @linea_trap(%tk4, %tf4, %tl4, %tc4) : (i32, !llvm.ptr, i32, i32) -> () loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":56:19)
    llvm.unreachable loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":56:19)
  ^c4:
    %p73 = arith.constant 0 : i64 loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":56:19)
    %v73 = arith.addi %v72, %p73 : i64 loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":56:19)
    %lw74 = llvm.load %s12 : !llvm.ptr -> i8 loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":56:25)
    %v74 = arith.extui %lw74 : i8 to i64 loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":56:25)
    %v75 = arith.addi %v73, %v74 : i64 loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":56:5)
    %k5m = arith.constant 255 : i64 loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":56:23)
    %k5 = arith.cmpi ugt, %v75, %k5m : i64 loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":56:23)
    cf.cond_br %k5, ^t5, ^c5 loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":56:23)
  ^t5:
    %tk5 = arith.constant 0 : i32 loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":56:23)
    %tf5 = llvm.mlir.addressof @linea_file0 : !llvm.ptr loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":56:23)
    %tl5 = arith.constant 56 : i32 loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":56:23)
    %tc5 = arith.constant 23 : i32 loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":56:23)
    func.call @linea_trap(%tk5, %tf5, %tl5, %tc5) : (i32, !llvm.ptr, i32, i32) -> () loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":56:23)
    llvm.unreachable loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":56:23)
  ^c5:
    %p76 = arith.constant 0 : i64 loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":56:23)
    %v76 = arith.addi %v75, %p76 : i64 loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":56:23)
    func.return %v76 : i64 loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":56:5)
  }
  func.func private @"lin.;two[Int64,Wrap[UInt8]]"(%a0: i64, %a1: !llvm.ptr) -> i64 attributes {llvm.linkage = #llvm.linkage<internal>, passthrough = [["probe-stack", "inline-asm"]]} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 1 : i64
    %s1 = llvm.alloca %z1 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    llvm.store %a0, %s0 : i64, !llvm.ptr
    %pl1 = arith.constant 1 : i64
    "llvm.intr.memcpy"(%s1, %a1, %pl1) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> ()
    cf.br ^b0
  ^b0:
    %v0 = arith.constant 1 : i64 loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":19:5)
    func.return %v0 : i64 loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":19:5)
  }
  func.func private @"lin.;two[Wrap[UInt8],Int64]"(%a0: !llvm.ptr, %a1: i64) -> i64 attributes {llvm.linkage = #llvm.linkage<internal>, passthrough = [["probe-stack", "inline-asm"]]} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 1 : i64
    %s1 = llvm.alloca %z1 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %pl0 = arith.constant 1 : i64
    "llvm.intr.memcpy"(%s0, %a0, %pl0) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> ()
    llvm.store %a1, %s1 : i64, !llvm.ptr
    cf.br ^b0
  ^b0:
    %v0 = arith.constant 1 : i64 loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":19:5)
    func.return %v0 : i64 loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":19:5)
  }
  func.func private @"lin.;one[Wrap[UInt8]]"(%a0: !llvm.ptr) -> i64 attributes {llvm.linkage = #llvm.linkage<internal>, passthrough = [["probe-stack", "inline-asm"]]} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %pl0 = arith.constant 1 : i64
    "llvm.intr.memcpy"(%s0, %a0, %pl0) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> ()
    cf.br ^b0
  ^b0:
    %v0 = arith.constant 2 : i64 loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":23:5)
    func.return %v0 : i64 loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":23:5)
  }
  func.func private @"lin.;one[Wrap[Wrap[UInt8]]]"(%a0: !llvm.ptr) -> i64 attributes {llvm.linkage = #llvm.linkage<internal>, passthrough = [["probe-stack", "inline-asm"]]} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %pl0 = arith.constant 1 : i64
    "llvm.intr.memcpy"(%s0, %a0, %pl0) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> ()
    cf.br ^b0
  ^b0:
    %v0 = arith.constant 2 : i64 loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":23:5)
    func.return %v0 : i64 loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":23:5)
  }
  func.func private @"lin.;Wrap[UInt8].mix[Int64]"(%a0: !llvm.ptr, %a1: i64) -> i64 attributes {llvm.linkage = #llvm.linkage<internal>, passthrough = [["probe-stack", "inline-asm"]]} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 1 : i64
    %s1 = llvm.alloca %z1 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %pl0 = arith.constant 1 : i64
    "llvm.intr.memcpy"(%s0, %a0, %pl0) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> ()
    llvm.store %a1, %s1 : i64, !llvm.ptr
    cf.br ^b0
  ^b0:
    %v0 = arith.constant 4 : i64 loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":31:9)
    func.return %v0 : i64 loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":31:9)
  }
  func.func private @"lin.;Wrap[Wrap[UInt8]].mix[Wrap[UInt8]]"(%a0: !llvm.ptr, %a1: !llvm.ptr) -> i64 attributes {llvm.linkage = #llvm.linkage<internal>, passthrough = [["probe-stack", "inline-asm"]]} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 1 : i64
    %s1 = llvm.alloca %z1 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %pl0 = arith.constant 1 : i64
    "llvm.intr.memcpy"(%s0, %a0, %pl0) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> ()
    %pl1 = arith.constant 1 : i64
    "llvm.intr.memcpy"(%s1, %a1, %pl1) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> ()
    cf.br ^b0
  ^b0:
    %v0 = arith.constant 4 : i64 loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":31:9)
    func.return %v0 : i64 loc("tests/generics/an_argument_list_is_told_from_what_nests_inside_it.lin":31:9)
  }
  func.func @main(%argc: i32, %argv: !llvm.ptr) -> i32 {
    func.call @linea_set_args(%argc, %argv) : (i32, !llvm.ptr) -> ()
    %status = func.call @"lin.;main"() : () -> i64
    %status32 = arith.trunci %status : i64 to i32
    func.return %status32 : i32
  }
}
