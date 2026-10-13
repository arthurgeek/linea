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
  llvm.mlir.global internal constant @linea_file0("tests/text/a_literal_holds_what_its_escapes_mean.lin\00") : !llvm.array<53 x i8>
  llvm.mlir.global internal constant @linea_file1("std/text/str.lin\00") : !llvm.array<17 x i8>
  llvm.mlir.global internal constant @linea_file2("std/mem/slice.lin\00") : !llvm.array<18 x i8>
  llvm.mlir.global internal constant @linea_str0("Ol\C3\A1") : !llvm.array<4 x i8>
  llvm.mlir.global internal constant @linea_str1("a\22b") : !llvm.array<3 x i8>
  func.func private @linea_set_args(i32, !llvm.ptr)
  func.func private @linea_trap(i32, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @linea_panic(i64, i64, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @"lin.;main"() -> i64 attributes {llvm.linkage = #llvm.linkage<internal>} {
    %z0 = arith.constant 16 : i64
    %s0 = llvm.alloca %z0 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 16 : i64
    %s1 = llvm.alloca %z1 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z2 = arith.constant 16 : i64
    %s2 = llvm.alloca %z2 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    cf.br ^b0
  ^b0:
    %ba1 = llvm.mlir.addressof @linea_str0 : !llvm.ptr loc("tests/text/a_literal_holds_what_its_escapes_mean.lin":7:24)
    %v1 = llvm.ptrtoint %ba1 : !llvm.ptr to i64 loc("tests/text/a_literal_holds_what_its_escapes_mean.lin":7:24)
    %v2 = arith.constant 0 : i64 loc("tests/text/a_literal_holds_what_its_escapes_mean.lin":7:24)
    llvm.store %v1, %s0 : i64, !llvm.ptr loc("tests/text/a_literal_holds_what_its_escapes_mean.lin":7:24)
    %v5 = arith.constant 4 : i64 loc("tests/text/a_literal_holds_what_its_escapes_mean.lin":7:24)
    %v6 = arith.constant 8 : i64 loc("tests/text/a_literal_holds_what_its_escapes_mean.lin":7:24)
    %v7 = llvm.getelementptr %s0[%v6] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("tests/text/a_literal_holds_what_its_escapes_mean.lin":7:24)
    llvm.store %v5, %v7 : i64, !llvm.ptr loc("tests/text/a_literal_holds_what_its_escapes_mean.lin":7:24)
    %ba10 = llvm.mlir.addressof @linea_str0 : !llvm.ptr loc("tests/text/a_literal_holds_what_its_escapes_mean.lin":8:24)
    %v10 = llvm.ptrtoint %ba10 : !llvm.ptr to i64 loc("tests/text/a_literal_holds_what_its_escapes_mean.lin":8:24)
    %v11 = arith.constant 0 : i64 loc("tests/text/a_literal_holds_what_its_escapes_mean.lin":8:24)
    llvm.store %v10, %s1 : i64, !llvm.ptr loc("tests/text/a_literal_holds_what_its_escapes_mean.lin":8:24)
    %v14 = arith.constant 4 : i64 loc("tests/text/a_literal_holds_what_its_escapes_mean.lin":8:24)
    %v15 = arith.constant 8 : i64 loc("tests/text/a_literal_holds_what_its_escapes_mean.lin":8:24)
    %v16 = llvm.getelementptr %s1[%v15] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("tests/text/a_literal_holds_what_its_escapes_mean.lin":8:24)
    llvm.store %v14, %v16 : i64, !llvm.ptr loc("tests/text/a_literal_holds_what_its_escapes_mean.lin":8:24)
    %ba19 = llvm.mlir.addressof @linea_str1 : !llvm.ptr loc("tests/text/a_literal_holds_what_its_escapes_mean.lin":9:23)
    %v19 = llvm.ptrtoint %ba19 : !llvm.ptr to i64 loc("tests/text/a_literal_holds_what_its_escapes_mean.lin":9:23)
    %v20 = arith.constant 0 : i64 loc("tests/text/a_literal_holds_what_its_escapes_mean.lin":9:23)
    llvm.store %v19, %s2 : i64, !llvm.ptr loc("tests/text/a_literal_holds_what_its_escapes_mean.lin":9:23)
    %v23 = arith.constant 3 : i64 loc("tests/text/a_literal_holds_what_its_escapes_mean.lin":9:23)
    %v24 = arith.constant 8 : i64 loc("tests/text/a_literal_holds_what_its_escapes_mean.lin":9:23)
    %v25 = llvm.getelementptr %s2[%v24] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("tests/text/a_literal_holds_what_its_escapes_mean.lin":9:23)
    llvm.store %v23, %v25 : i64, !llvm.ptr loc("tests/text/a_literal_holds_what_its_escapes_mean.lin":9:23)
    %v28 = func.call @"lin.std.text;Str.length"(%s0) : (!llvm.ptr) -> i64 loc("tests/text/a_literal_holds_what_its_escapes_mean.lin":10:11)
    %v30 = func.call @"lin.std.text;Str.length"(%s1) : (!llvm.ptr) -> i64 loc("tests/text/a_literal_holds_what_its_escapes_mean.lin":10:33)
    %v31 = arith.addi %v28, %v30 : i64 loc("tests/text/a_literal_holds_what_its_escapes_mean.lin":10:11)
    %k1 = arith.cmpi ult, %v31, %v28 : i64 loc("tests/text/a_literal_holds_what_its_escapes_mean.lin":10:31)
    cf.cond_br %k1, ^t1, ^c1 loc("tests/text/a_literal_holds_what_its_escapes_mean.lin":10:31)
  ^t1:
    %tk1 = arith.constant 0 : i32 loc("tests/text/a_literal_holds_what_its_escapes_mean.lin":10:31)
    %tf1 = llvm.mlir.addressof @linea_file0 : !llvm.ptr loc("tests/text/a_literal_holds_what_its_escapes_mean.lin":10:31)
    %tl1 = arith.constant 10 : i32 loc("tests/text/a_literal_holds_what_its_escapes_mean.lin":10:31)
    %tc1 = arith.constant 31 : i32 loc("tests/text/a_literal_holds_what_its_escapes_mean.lin":10:31)
    func.call @linea_trap(%tk1, %tf1, %tl1, %tc1) : (i32, !llvm.ptr, i32, i32) -> () loc("tests/text/a_literal_holds_what_its_escapes_mean.lin":10:31)
    llvm.unreachable loc("tests/text/a_literal_holds_what_its_escapes_mean.lin":10:31)
  ^c1:
    %p32 = arith.constant 0 : i64 loc("tests/text/a_literal_holds_what_its_escapes_mean.lin":10:31)
    %v32 = arith.addi %v31, %p32 : i64 loc("tests/text/a_literal_holds_what_its_escapes_mean.lin":10:31)
    %v34 = func.call @"lin.std.text;Str.length"(%s2) : (!llvm.ptr) -> i64 loc("tests/text/a_literal_holds_what_its_escapes_mean.lin":10:55)
    %v35 = arith.addi %v32, %v34 : i64 loc("tests/text/a_literal_holds_what_its_escapes_mean.lin":10:11)
    %k2 = arith.cmpi ult, %v35, %v32 : i64 loc("tests/text/a_literal_holds_what_its_escapes_mean.lin":10:53)
    cf.cond_br %k2, ^t2, ^c2 loc("tests/text/a_literal_holds_what_its_escapes_mean.lin":10:53)
  ^t2:
    %tk2 = arith.constant 0 : i32 loc("tests/text/a_literal_holds_what_its_escapes_mean.lin":10:53)
    %tf2 = llvm.mlir.addressof @linea_file0 : !llvm.ptr loc("tests/text/a_literal_holds_what_its_escapes_mean.lin":10:53)
    %tl2 = arith.constant 10 : i32 loc("tests/text/a_literal_holds_what_its_escapes_mean.lin":10:53)
    %tc2 = arith.constant 53 : i32 loc("tests/text/a_literal_holds_what_its_escapes_mean.lin":10:53)
    func.call @linea_trap(%tk2, %tf2, %tl2, %tc2) : (i32, !llvm.ptr, i32, i32) -> () loc("tests/text/a_literal_holds_what_its_escapes_mean.lin":10:53)
    llvm.unreachable loc("tests/text/a_literal_holds_what_its_escapes_mean.lin":10:53)
  ^c2:
    %p36 = arith.constant 0 : i64 loc("tests/text/a_literal_holds_what_its_escapes_mean.lin":10:53)
    %v36 = arith.addi %v35, %p36 : i64 loc("tests/text/a_literal_holds_what_its_escapes_mean.lin":10:53)
    %k3m = arith.constant 255 : i64 loc("tests/text/a_literal_holds_what_its_escapes_mean.lin":10:5)
    %k3 = arith.cmpi ugt, %v36, %k3m : i64 loc("tests/text/a_literal_holds_what_its_escapes_mean.lin":10:5)
    cf.cond_br %k3, ^t3, ^c3 loc("tests/text/a_literal_holds_what_its_escapes_mean.lin":10:5)
  ^t3:
    %tk3 = arith.constant 2 : i32 loc("tests/text/a_literal_holds_what_its_escapes_mean.lin":10:5)
    %tf3 = llvm.mlir.addressof @linea_file0 : !llvm.ptr loc("tests/text/a_literal_holds_what_its_escapes_mean.lin":10:5)
    %tl3 = arith.constant 10 : i32 loc("tests/text/a_literal_holds_what_its_escapes_mean.lin":10:5)
    %tc3 = arith.constant 5 : i32 loc("tests/text/a_literal_holds_what_its_escapes_mean.lin":10:5)
    func.call @linea_trap(%tk3, %tf3, %tl3, %tc3) : (i32, !llvm.ptr, i32, i32) -> () loc("tests/text/a_literal_holds_what_its_escapes_mean.lin":10:5)
    llvm.unreachable loc("tests/text/a_literal_holds_what_its_escapes_mean.lin":10:5)
  ^c3:
    %p37 = arith.constant 0 : i64 loc("tests/text/a_literal_holds_what_its_escapes_mean.lin":10:5)
    %v37 = arith.addi %v36, %p37 : i64 loc("tests/text/a_literal_holds_what_its_escapes_mean.lin":10:5)
    func.return %v37 : i64 loc("tests/text/a_literal_holds_what_its_escapes_mean.lin":10:5)
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
