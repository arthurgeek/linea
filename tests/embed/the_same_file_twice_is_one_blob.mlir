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
  llvm.mlir.global internal constant @linea_file0("tests/embed/the_same_file_twice_is_one_blob/main.lin\00") : !llvm.array<53 x i8>
  llvm.mlir.global internal constant @linea_file1("std/text/str.lin\00") : !llvm.array<17 x i8>
  llvm.mlir.global internal constant @linea_file2("std/mem/slice.lin\00") : !llvm.array<18 x i8>
  llvm.mlir.global internal constant @linea_str0("word") : !llvm.array<4 x i8>
  llvm.mlir.global internal constant @linea_static0() {addr_space = 0 : i32, alignment = 8 : i64} : !linea_static0 {
    %s0 = llvm.mlir.undef : !linea_static0
    %a0 = llvm.mlir.addressof @linea_str0 : !llvm.ptr
    %e0 = llvm.ptrtoint %a0 : !llvm.ptr to i64
    %s1 = llvm.insertvalue %e0, %s0[0] : !linea_static0
    %e1 = llvm.mlir.constant(4 : i64) : i64
    %s2 = llvm.insertvalue %e1, %s1[1] : !linea_static0
    llvm.return %s2 : !linea_static0
  }
  func.func private @linea_set_args(i32, !llvm.ptr)
  func.func private @linea_trap(i32, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @linea_panic(i64, i64, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @"lin.;main"() -> i64 attributes {llvm.linkage = #llvm.linkage<internal>, passthrough = [["probe-stack", "inline-asm"]]} {
    cf.br ^b0
  ^b0:
    %v0 = llvm.mlir.addressof @linea_static0 : !llvm.ptr loc("tests/embed/the_same_file_twice_is_one_blob/main.lin":8:11)
    %v1 = func.call @"lin.std.text;Str.length"(%v0) : (!llvm.ptr) -> i64 loc("tests/embed/the_same_file_twice_is_one_blob/main.lin":8:11)
    %v2 = llvm.mlir.addressof @linea_static0 : !llvm.ptr loc("tests/embed/the_same_file_twice_is_one_blob/main.lin":8:28)
    %v3 = func.call @"lin.std.text;Str.length"(%v2) : (!llvm.ptr) -> i64 loc("tests/embed/the_same_file_twice_is_one_blob/main.lin":8:28)
    %v4 = arith.addi %v1, %v3 : i64 loc("tests/embed/the_same_file_twice_is_one_blob/main.lin":8:11)
    %k1 = arith.cmpi ult, %v4, %v1 : i64 loc("tests/embed/the_same_file_twice_is_one_blob/main.lin":8:26)
    cf.cond_br %k1, ^t1, ^c1 loc("tests/embed/the_same_file_twice_is_one_blob/main.lin":8:26)
  ^t1:
    %tk1 = arith.constant 0 : i32 loc("tests/embed/the_same_file_twice_is_one_blob/main.lin":8:26)
    %tf1 = llvm.mlir.addressof @linea_file0 : !llvm.ptr loc("tests/embed/the_same_file_twice_is_one_blob/main.lin":8:26)
    %tl1 = arith.constant 8 : i32 loc("tests/embed/the_same_file_twice_is_one_blob/main.lin":8:26)
    %tc1 = arith.constant 26 : i32 loc("tests/embed/the_same_file_twice_is_one_blob/main.lin":8:26)
    func.call @linea_trap(%tk1, %tf1, %tl1, %tc1) : (i32, !llvm.ptr, i32, i32) -> () loc("tests/embed/the_same_file_twice_is_one_blob/main.lin":8:26)
    llvm.unreachable loc("tests/embed/the_same_file_twice_is_one_blob/main.lin":8:26)
  ^c1:
    %p5 = arith.constant 0 : i64 loc("tests/embed/the_same_file_twice_is_one_blob/main.lin":8:26)
    %v5 = arith.addi %v4, %p5 : i64 loc("tests/embed/the_same_file_twice_is_one_blob/main.lin":8:26)
    %v6 = llvm.mlir.addressof @linea_static0 : !llvm.ptr loc("tests/embed/the_same_file_twice_is_one_blob/main.lin":8:46)
    %v7 = func.call @"lin.std.text;Str.length"(%v6) : (!llvm.ptr) -> i64 loc("tests/embed/the_same_file_twice_is_one_blob/main.lin":8:46)
    %v8 = arith.addi %v5, %v7 : i64 loc("tests/embed/the_same_file_twice_is_one_blob/main.lin":8:11)
    %k2 = arith.cmpi ult, %v8, %v5 : i64 loc("tests/embed/the_same_file_twice_is_one_blob/main.lin":8:44)
    cf.cond_br %k2, ^t2, ^c2 loc("tests/embed/the_same_file_twice_is_one_blob/main.lin":8:44)
  ^t2:
    %tk2 = arith.constant 0 : i32 loc("tests/embed/the_same_file_twice_is_one_blob/main.lin":8:44)
    %tf2 = llvm.mlir.addressof @linea_file0 : !llvm.ptr loc("tests/embed/the_same_file_twice_is_one_blob/main.lin":8:44)
    %tl2 = arith.constant 8 : i32 loc("tests/embed/the_same_file_twice_is_one_blob/main.lin":8:44)
    %tc2 = arith.constant 44 : i32 loc("tests/embed/the_same_file_twice_is_one_blob/main.lin":8:44)
    func.call @linea_trap(%tk2, %tf2, %tl2, %tc2) : (i32, !llvm.ptr, i32, i32) -> () loc("tests/embed/the_same_file_twice_is_one_blob/main.lin":8:44)
    llvm.unreachable loc("tests/embed/the_same_file_twice_is_one_blob/main.lin":8:44)
  ^c2:
    %p9 = arith.constant 0 : i64 loc("tests/embed/the_same_file_twice_is_one_blob/main.lin":8:44)
    %v9 = arith.addi %v8, %p9 : i64 loc("tests/embed/the_same_file_twice_is_one_blob/main.lin":8:44)
    %k3m = arith.constant 255 : i64 loc("tests/embed/the_same_file_twice_is_one_blob/main.lin":8:5)
    %k3 = arith.cmpi ugt, %v9, %k3m : i64 loc("tests/embed/the_same_file_twice_is_one_blob/main.lin":8:5)
    cf.cond_br %k3, ^t3, ^c3 loc("tests/embed/the_same_file_twice_is_one_blob/main.lin":8:5)
  ^t3:
    %tk3 = arith.constant 2 : i32 loc("tests/embed/the_same_file_twice_is_one_blob/main.lin":8:5)
    %tf3 = llvm.mlir.addressof @linea_file0 : !llvm.ptr loc("tests/embed/the_same_file_twice_is_one_blob/main.lin":8:5)
    %tl3 = arith.constant 8 : i32 loc("tests/embed/the_same_file_twice_is_one_blob/main.lin":8:5)
    %tc3 = arith.constant 5 : i32 loc("tests/embed/the_same_file_twice_is_one_blob/main.lin":8:5)
    func.call @linea_trap(%tk3, %tf3, %tl3, %tc3) : (i32, !llvm.ptr, i32, i32) -> () loc("tests/embed/the_same_file_twice_is_one_blob/main.lin":8:5)
    llvm.unreachable loc("tests/embed/the_same_file_twice_is_one_blob/main.lin":8:5)
  ^c3:
    %p10 = arith.constant 0 : i64 loc("tests/embed/the_same_file_twice_is_one_blob/main.lin":8:5)
    %v10 = arith.addi %v9, %p10 : i64 loc("tests/embed/the_same_file_twice_is_one_blob/main.lin":8:5)
    func.return %v10 : i64 loc("tests/embed/the_same_file_twice_is_one_blob/main.lin":8:5)
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
