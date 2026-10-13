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
  llvm.mlir.global internal constant @linea_file0("tests/tuples/two_tuple_nestings_are_two_symbols.lin\00") : !llvm.array<52 x i8>
  llvm.mlir.global internal constant @linea_str0("a") : !llvm.array<1 x i8>
  func.func private @linea_set_args(i32, !llvm.ptr)
  func.func private @linea_trap(i32, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @linea_panic(i64, i64, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @"lin.;main"() -> i64 attributes {llvm.linkage = #llvm.linkage<internal>} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 32 : i64
    %s1 = llvm.alloca %z1 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z2 = arith.constant 32 : i64
    %s2 = llvm.alloca %z2 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z3 = arith.constant 24 : i64
    %s3 = llvm.alloca %z3 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
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
    %v1 = arith.constant 0 : i64 loc("tests/tuples/two_tuple_nestings_are_two_symbols.lin":17:21)
    %v3 = arith.constant 7 : i64 loc("tests/tuples/two_tuple_nestings_are_two_symbols.lin":17:28)
    %iw4 = arith.trunci %v3 : i64 to i8 loc("tests/tuples/two_tuple_nestings_are_two_symbols.lin":17:21)
    llvm.store %iw4, %s0 : i8, !llvm.ptr loc("tests/tuples/two_tuple_nestings_are_two_symbols.lin":17:21)
    %v6 = arith.constant 0 : i64 loc("tests/tuples/two_tuple_nestings_are_two_symbols.lin":18:39)
    %v8 = arith.constant 1 : i64 loc("tests/tuples/two_tuple_nestings_are_two_symbols.lin":18:40)
    llvm.store %v8, %s1 : i64, !llvm.ptr loc("tests/tuples/two_tuple_nestings_are_two_symbols.lin":18:39)
    %v10 = arith.constant 8 : i64 loc("tests/tuples/two_tuple_nestings_are_two_symbols.lin":18:39)
    %v11 = llvm.getelementptr %s1[%v10] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("tests/tuples/two_tuple_nestings_are_two_symbols.lin":18:39)
    %v12 = arith.constant 0 : i64 loc("tests/tuples/two_tuple_nestings_are_two_symbols.lin":18:43)
    %ba14 = llvm.mlir.addressof @linea_str0 : !llvm.ptr loc("tests/tuples/two_tuple_nestings_are_two_symbols.lin":18:44)
    %v14 = llvm.ptrtoint %ba14 : !llvm.ptr to i64 loc("tests/tuples/two_tuple_nestings_are_two_symbols.lin":18:44)
    %v15 = arith.constant 0 : i64 loc("tests/tuples/two_tuple_nestings_are_two_symbols.lin":18:44)
    llvm.store %v14, %v11 : i64, !llvm.ptr loc("tests/tuples/two_tuple_nestings_are_two_symbols.lin":18:44)
    %v18 = arith.constant 1 : i64 loc("tests/tuples/two_tuple_nestings_are_two_symbols.lin":18:44)
    %v19 = arith.constant 8 : i64 loc("tests/tuples/two_tuple_nestings_are_two_symbols.lin":18:44)
    %v20 = llvm.getelementptr %v11[%v19] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("tests/tuples/two_tuple_nestings_are_two_symbols.lin":18:44)
    llvm.store %v18, %v20 : i64, !llvm.ptr loc("tests/tuples/two_tuple_nestings_are_two_symbols.lin":18:44)
    %v22 = arith.constant 16 : i64 loc("tests/tuples/two_tuple_nestings_are_two_symbols.lin":18:43)
    %v23 = llvm.getelementptr %v11[%v22] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("tests/tuples/two_tuple_nestings_are_two_symbols.lin":18:43)
    %v24 = arith.constant 1 : i1 loc("tests/tuples/two_tuple_nestings_are_two_symbols.lin":18:49)
    %iw25 = arith.extui %v24 : i1 to i8 loc("tests/tuples/two_tuple_nestings_are_two_symbols.lin":18:43)
    llvm.store %iw25, %v23 : i8, !llvm.ptr loc("tests/tuples/two_tuple_nestings_are_two_symbols.lin":18:43)
    %v27 = arith.constant 0 : i64 loc("tests/tuples/two_tuple_nestings_are_two_symbols.lin":19:38)
    %v29 = arith.constant 0 : i64 loc("tests/tuples/two_tuple_nestings_are_two_symbols.lin":19:39)
    %v31 = arith.constant 1 : i64 loc("tests/tuples/two_tuple_nestings_are_two_symbols.lin":19:40)
    llvm.store %v31, %s2 : i64, !llvm.ptr loc("tests/tuples/two_tuple_nestings_are_two_symbols.lin":19:39)
    %v33 = arith.constant 8 : i64 loc("tests/tuples/two_tuple_nestings_are_two_symbols.lin":19:39)
    %v34 = llvm.getelementptr %s2[%v33] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("tests/tuples/two_tuple_nestings_are_two_symbols.lin":19:39)
    %ba35 = llvm.mlir.addressof @linea_str0 : !llvm.ptr loc("tests/tuples/two_tuple_nestings_are_two_symbols.lin":19:43)
    %v35 = llvm.ptrtoint %ba35 : !llvm.ptr to i64 loc("tests/tuples/two_tuple_nestings_are_two_symbols.lin":19:43)
    %v36 = arith.constant 0 : i64 loc("tests/tuples/two_tuple_nestings_are_two_symbols.lin":19:43)
    llvm.store %v35, %v34 : i64, !llvm.ptr loc("tests/tuples/two_tuple_nestings_are_two_symbols.lin":19:43)
    %v39 = arith.constant 1 : i64 loc("tests/tuples/two_tuple_nestings_are_two_symbols.lin":19:43)
    %v40 = arith.constant 8 : i64 loc("tests/tuples/two_tuple_nestings_are_two_symbols.lin":19:43)
    %v41 = llvm.getelementptr %v34[%v40] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("tests/tuples/two_tuple_nestings_are_two_symbols.lin":19:43)
    llvm.store %v39, %v41 : i64, !llvm.ptr loc("tests/tuples/two_tuple_nestings_are_two_symbols.lin":19:43)
    %v43 = arith.constant 24 : i64 loc("tests/tuples/two_tuple_nestings_are_two_symbols.lin":19:38)
    %v44 = llvm.getelementptr %s2[%v43] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("tests/tuples/two_tuple_nestings_are_two_symbols.lin":19:38)
    %v45 = arith.constant 1 : i1 loc("tests/tuples/two_tuple_nestings_are_two_symbols.lin":19:49)
    %iw46 = arith.extui %v45 : i1 to i8 loc("tests/tuples/two_tuple_nestings_are_two_symbols.lin":19:38)
    llvm.store %iw46, %v44 : i8, !llvm.ptr loc("tests/tuples/two_tuple_nestings_are_two_symbols.lin":19:38)
    %v48 = arith.constant 0 : i64 loc("tests/tuples/two_tuple_nestings_are_two_symbols.lin":20:30)
    %v50 = arith.constant 1 : i64 loc("tests/tuples/two_tuple_nestings_are_two_symbols.lin":20:31)
    llvm.store %v50, %s3 : i64, !llvm.ptr loc("tests/tuples/two_tuple_nestings_are_two_symbols.lin":20:30)
    %v52 = arith.constant 8 : i64 loc("tests/tuples/two_tuple_nestings_are_two_symbols.lin":20:30)
    %v53 = llvm.getelementptr %s3[%v52] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("tests/tuples/two_tuple_nestings_are_two_symbols.lin":20:30)
    %ba54 = llvm.mlir.addressof @linea_str0 : !llvm.ptr loc("tests/tuples/two_tuple_nestings_are_two_symbols.lin":20:34)
    %v54 = llvm.ptrtoint %ba54 : !llvm.ptr to i64 loc("tests/tuples/two_tuple_nestings_are_two_symbols.lin":20:34)
    %v55 = arith.constant 0 : i64 loc("tests/tuples/two_tuple_nestings_are_two_symbols.lin":20:34)
    llvm.store %v54, %v53 : i64, !llvm.ptr loc("tests/tuples/two_tuple_nestings_are_two_symbols.lin":20:34)
    %v58 = arith.constant 1 : i64 loc("tests/tuples/two_tuple_nestings_are_two_symbols.lin":20:34)
    %v59 = arith.constant 8 : i64 loc("tests/tuples/two_tuple_nestings_are_two_symbols.lin":20:34)
    %v60 = llvm.getelementptr %v53[%v59] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("tests/tuples/two_tuple_nestings_are_two_symbols.lin":20:34)
    llvm.store %v58, %v60 : i64, !llvm.ptr loc("tests/tuples/two_tuple_nestings_are_two_symbols.lin":20:34)
    %v64 = func.call @"lin.;Holder.give[std.tuple.Tuple2[Int64,std.tuple.Tuple2[std.text.Str,Bool]]]"(%s0, %s1) : (!llvm.ptr, !llvm.ptr) -> i64 loc("tests/tuples/two_tuple_nestings_are_two_symbols.lin":21:13)
    %sw65 = arith.trunci %v64 : i64 to i8 loc("tests/tuples/two_tuple_nestings_are_two_symbols.lin":21:5)
    llvm.store %sw65, %s4 : i8, !llvm.ptr loc("tests/tuples/two_tuple_nestings_are_two_symbols.lin":21:5)
    %v68 = func.call @"lin.;Holder.give[std.tuple.Tuple2[std.tuple.Tuple2[Int64,std.text.Str],Bool]]"(%s0, %s2) : (!llvm.ptr, !llvm.ptr) -> i64 loc("tests/tuples/two_tuple_nestings_are_two_symbols.lin":22:13)
    %sw69 = arith.trunci %v68 : i64 to i8 loc("tests/tuples/two_tuple_nestings_are_two_symbols.lin":22:5)
    llvm.store %sw69, %s5 : i8, !llvm.ptr loc("tests/tuples/two_tuple_nestings_are_two_symbols.lin":22:5)
    %v72 = func.call @"lin.;Holder.give[std.tuple.Tuple2[Int64,std.text.Str]]"(%s0, %s3) : (!llvm.ptr, !llvm.ptr) -> i64 loc("tests/tuples/two_tuple_nestings_are_two_symbols.lin":23:13)
    %sw73 = arith.trunci %v72 : i64 to i8 loc("tests/tuples/two_tuple_nestings_are_two_symbols.lin":23:5)
    llvm.store %sw73, %s6 : i8, !llvm.ptr loc("tests/tuples/two_tuple_nestings_are_two_symbols.lin":23:5)
    %cl76 = arith.constant 1 : i64 loc("tests/tuples/two_tuple_nestings_are_two_symbols.lin":24:5)
    "llvm.intr.memcpy"(%s7, %s0, %cl76) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("tests/tuples/two_tuple_nestings_are_two_symbols.lin":24:5)
    %lw77 = llvm.load %s4 : !llvm.ptr -> i8 loc("tests/tuples/two_tuple_nestings_are_two_symbols.lin":25:5)
    %v77 = arith.extui %lw77 : i8 to i64 loc("tests/tuples/two_tuple_nestings_are_two_symbols.lin":25:5)
    %lw78 = llvm.load %s5 : !llvm.ptr -> i8 loc("tests/tuples/two_tuple_nestings_are_two_symbols.lin":25:9)
    %v78 = arith.extui %lw78 : i8 to i64 loc("tests/tuples/two_tuple_nestings_are_two_symbols.lin":25:9)
    %v79 = arith.addi %v77, %v78 : i64 loc("tests/tuples/two_tuple_nestings_are_two_symbols.lin":25:5)
    %k1m = arith.constant 255 : i64 loc("tests/tuples/two_tuple_nestings_are_two_symbols.lin":25:7)
    %k1 = arith.cmpi ugt, %v79, %k1m : i64 loc("tests/tuples/two_tuple_nestings_are_two_symbols.lin":25:7)
    cf.cond_br %k1, ^t1, ^c1 loc("tests/tuples/two_tuple_nestings_are_two_symbols.lin":25:7)
  ^t1:
    %tk1 = arith.constant 0 : i32 loc("tests/tuples/two_tuple_nestings_are_two_symbols.lin":25:7)
    %tf1 = llvm.mlir.addressof @linea_file0 : !llvm.ptr loc("tests/tuples/two_tuple_nestings_are_two_symbols.lin":25:7)
    %tl1 = arith.constant 25 : i32 loc("tests/tuples/two_tuple_nestings_are_two_symbols.lin":25:7)
    %tc1 = arith.constant 7 : i32 loc("tests/tuples/two_tuple_nestings_are_two_symbols.lin":25:7)
    func.call @linea_trap(%tk1, %tf1, %tl1, %tc1) : (i32, !llvm.ptr, i32, i32) -> () loc("tests/tuples/two_tuple_nestings_are_two_symbols.lin":25:7)
    llvm.unreachable loc("tests/tuples/two_tuple_nestings_are_two_symbols.lin":25:7)
  ^c1:
    %p80 = arith.constant 0 : i64 loc("tests/tuples/two_tuple_nestings_are_two_symbols.lin":25:7)
    %v80 = arith.addi %v79, %p80 : i64 loc("tests/tuples/two_tuple_nestings_are_two_symbols.lin":25:7)
    %lw81 = llvm.load %s6 : !llvm.ptr -> i8 loc("tests/tuples/two_tuple_nestings_are_two_symbols.lin":25:13)
    %v81 = arith.extui %lw81 : i8 to i64 loc("tests/tuples/two_tuple_nestings_are_two_symbols.lin":25:13)
    %v82 = arith.addi %v80, %v81 : i64 loc("tests/tuples/two_tuple_nestings_are_two_symbols.lin":25:5)
    %k2m = arith.constant 255 : i64 loc("tests/tuples/two_tuple_nestings_are_two_symbols.lin":25:11)
    %k2 = arith.cmpi ugt, %v82, %k2m : i64 loc("tests/tuples/two_tuple_nestings_are_two_symbols.lin":25:11)
    cf.cond_br %k2, ^t2, ^c2 loc("tests/tuples/two_tuple_nestings_are_two_symbols.lin":25:11)
  ^t2:
    %tk2 = arith.constant 0 : i32 loc("tests/tuples/two_tuple_nestings_are_two_symbols.lin":25:11)
    %tf2 = llvm.mlir.addressof @linea_file0 : !llvm.ptr loc("tests/tuples/two_tuple_nestings_are_two_symbols.lin":25:11)
    %tl2 = arith.constant 25 : i32 loc("tests/tuples/two_tuple_nestings_are_two_symbols.lin":25:11)
    %tc2 = arith.constant 11 : i32 loc("tests/tuples/two_tuple_nestings_are_two_symbols.lin":25:11)
    func.call @linea_trap(%tk2, %tf2, %tl2, %tc2) : (i32, !llvm.ptr, i32, i32) -> () loc("tests/tuples/two_tuple_nestings_are_two_symbols.lin":25:11)
    llvm.unreachable loc("tests/tuples/two_tuple_nestings_are_two_symbols.lin":25:11)
  ^c2:
    %p83 = arith.constant 0 : i64 loc("tests/tuples/two_tuple_nestings_are_two_symbols.lin":25:11)
    %v83 = arith.addi %v82, %p83 : i64 loc("tests/tuples/two_tuple_nestings_are_two_symbols.lin":25:11)
    func.return %v83 : i64 loc("tests/tuples/two_tuple_nestings_are_two_symbols.lin":25:5)
  }
  func.func private @"lin.;Holder.give[std.tuple.Tuple2[Int64,std.tuple.Tuple2[std.text.Str,Bool]]]"(%a0: !llvm.ptr, %a1: !llvm.ptr) -> i64 attributes {llvm.linkage = #llvm.linkage<internal>} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x !llvm.ptr {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 1 : i64
    %s1 = llvm.alloca %z1 x !llvm.ptr {alignment = 8 : i64} : (i64) -> !llvm.ptr
    llvm.store %a0, %s0 : !llvm.ptr, !llvm.ptr
    llvm.store %a1, %s1 : !llvm.ptr, !llvm.ptr
    cf.br ^b0
  ^b0:
    %v0 = llvm.load %s0 : !llvm.ptr -> !llvm.ptr loc("tests/tuples/two_tuple_nestings_are_two_symbols.lin":12:9)
    %v1 = arith.constant 0 : i64 loc("tests/tuples/two_tuple_nestings_are_two_symbols.lin":12:9)
    %iw3 = llvm.load %v0 : !llvm.ptr -> i8 loc("tests/tuples/two_tuple_nestings_are_two_symbols.lin":12:9)
    %v3 = arith.extui %iw3 : i8 to i64 loc("tests/tuples/two_tuple_nestings_are_two_symbols.lin":12:9)
    func.return %v3 : i64 loc("tests/tuples/two_tuple_nestings_are_two_symbols.lin":12:9)
  }
  func.func private @"lin.;Holder.give[std.tuple.Tuple2[std.tuple.Tuple2[Int64,std.text.Str],Bool]]"(%a0: !llvm.ptr, %a1: !llvm.ptr) -> i64 attributes {llvm.linkage = #llvm.linkage<internal>} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x !llvm.ptr {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 1 : i64
    %s1 = llvm.alloca %z1 x !llvm.ptr {alignment = 8 : i64} : (i64) -> !llvm.ptr
    llvm.store %a0, %s0 : !llvm.ptr, !llvm.ptr
    llvm.store %a1, %s1 : !llvm.ptr, !llvm.ptr
    cf.br ^b0
  ^b0:
    %v0 = llvm.load %s0 : !llvm.ptr -> !llvm.ptr loc("tests/tuples/two_tuple_nestings_are_two_symbols.lin":12:9)
    %v1 = arith.constant 0 : i64 loc("tests/tuples/two_tuple_nestings_are_two_symbols.lin":12:9)
    %iw3 = llvm.load %v0 : !llvm.ptr -> i8 loc("tests/tuples/two_tuple_nestings_are_two_symbols.lin":12:9)
    %v3 = arith.extui %iw3 : i8 to i64 loc("tests/tuples/two_tuple_nestings_are_two_symbols.lin":12:9)
    func.return %v3 : i64 loc("tests/tuples/two_tuple_nestings_are_two_symbols.lin":12:9)
  }
  func.func private @"lin.;Holder.give[std.tuple.Tuple2[Int64,std.text.Str]]"(%a0: !llvm.ptr, %a1: !llvm.ptr) -> i64 attributes {llvm.linkage = #llvm.linkage<internal>} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x !llvm.ptr {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 1 : i64
    %s1 = llvm.alloca %z1 x !llvm.ptr {alignment = 8 : i64} : (i64) -> !llvm.ptr
    llvm.store %a0, %s0 : !llvm.ptr, !llvm.ptr
    llvm.store %a1, %s1 : !llvm.ptr, !llvm.ptr
    cf.br ^b0
  ^b0:
    %v0 = llvm.load %s0 : !llvm.ptr -> !llvm.ptr loc("tests/tuples/two_tuple_nestings_are_two_symbols.lin":12:9)
    %v1 = arith.constant 0 : i64 loc("tests/tuples/two_tuple_nestings_are_two_symbols.lin":12:9)
    %iw3 = llvm.load %v0 : !llvm.ptr -> i8 loc("tests/tuples/two_tuple_nestings_are_two_symbols.lin":12:9)
    %v3 = arith.extui %iw3 : i8 to i64 loc("tests/tuples/two_tuple_nestings_are_two_symbols.lin":12:9)
    func.return %v3 : i64 loc("tests/tuples/two_tuple_nestings_are_two_symbols.lin":12:9)
  }
  func.func @main(%argc: i32, %argv: !llvm.ptr) -> i32 {
    func.call @linea_set_args(%argc, %argv) : (i32, !llvm.ptr) -> ()
    %status = func.call @"lin.;main"() : () -> i64
    %status32 = arith.trunci %status : i64 to i32
    func.return %status32 : i32
  }
}
