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
  llvm.mlir.global internal constant @linea_file0("tests/generics/two_brands_are_one_layout.lin\00") : !llvm.array<45 x i8>
  func.func private @linea_set_args(i32, !llvm.ptr)
  func.func private @linea_trap(i32, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @linea_panic(i64, i64, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @"lin.;main"() -> i64 attributes {llvm.linkage = #llvm.linkage<internal>} {
    %z0 = arith.constant 16 : i64
    %s0 = llvm.alloca %z0 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 16 : i64
    %s1 = llvm.alloca %z1 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    cf.br ^b0
  ^b0:
    %v1 = arith.constant 0 : i64 loc("tests/generics/two_brands_are_one_layout.lin":14:24)
    %v3 = arith.constant 1 : i64 loc("tests/generics/two_brands_are_one_layout.lin":14:34)
    llvm.store %v3, %s0 : i64, !llvm.ptr loc("tests/generics/two_brands_are_one_layout.lin":14:24)
    %v5 = arith.constant 8 : i64 loc("tests/generics/two_brands_are_one_layout.lin":14:24)
    %v6 = llvm.getelementptr %s0[%v5] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("tests/generics/two_brands_are_one_layout.lin":14:24)
    %v7 = arith.constant 2 : i64 loc("tests/generics/two_brands_are_one_layout.lin":14:43)
    llvm.store %v7, %v6 : i64, !llvm.ptr loc("tests/generics/two_brands_are_one_layout.lin":14:24)
    %v10 = arith.constant 0 : i64 loc("tests/generics/two_brands_are_one_layout.lin":15:24)
    %v12 = arith.constant 3 : i64 loc("tests/generics/two_brands_are_one_layout.lin":15:34)
    llvm.store %v12, %s1 : i64, !llvm.ptr loc("tests/generics/two_brands_are_one_layout.lin":15:24)
    %v14 = arith.constant 8 : i64 loc("tests/generics/two_brands_are_one_layout.lin":15:24)
    %v15 = llvm.getelementptr %s1[%v14] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("tests/generics/two_brands_are_one_layout.lin":15:24)
    %v16 = arith.constant 4 : i64 loc("tests/generics/two_brands_are_one_layout.lin":15:43)
    llvm.store %v16, %v15 : i64, !llvm.ptr loc("tests/generics/two_brands_are_one_layout.lin":15:24)
    %v19 = arith.constant 0 : i64 loc("tests/generics/two_brands_are_one_layout.lin":16:11)
    %v21 = llvm.load %s0 : !llvm.ptr -> i64 loc("tests/generics/two_brands_are_one_layout.lin":16:11)
    %v23 = arith.constant 8 : i64 loc("tests/generics/two_brands_are_one_layout.lin":16:20)
    %v24 = llvm.getelementptr %s1[%v23] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("tests/generics/two_brands_are_one_layout.lin":16:20)
    %v25 = llvm.load %v24 : !llvm.ptr -> i64 loc("tests/generics/two_brands_are_one_layout.lin":16:20)
    %v26 = arith.addi %v21, %v25 : i64 loc("tests/generics/two_brands_are_one_layout.lin":16:11)
    %k1 = arith.cmpi ult, %v26, %v21 : i64 loc("tests/generics/two_brands_are_one_layout.lin":16:18)
    cf.cond_br %k1, ^t1, ^c1 loc("tests/generics/two_brands_are_one_layout.lin":16:18)
  ^t1:
    %tk1 = arith.constant 0 : i32 loc("tests/generics/two_brands_are_one_layout.lin":16:18)
    %tf1 = llvm.mlir.addressof @linea_file0 : !llvm.ptr loc("tests/generics/two_brands_are_one_layout.lin":16:18)
    %tl1 = arith.constant 16 : i32 loc("tests/generics/two_brands_are_one_layout.lin":16:18)
    %tc1 = arith.constant 18 : i32 loc("tests/generics/two_brands_are_one_layout.lin":16:18)
    func.call @linea_trap(%tk1, %tf1, %tl1, %tc1) : (i32, !llvm.ptr, i32, i32) -> () loc("tests/generics/two_brands_are_one_layout.lin":16:18)
    llvm.unreachable loc("tests/generics/two_brands_are_one_layout.lin":16:18)
  ^c1:
    %p27 = arith.constant 0 : i64 loc("tests/generics/two_brands_are_one_layout.lin":16:18)
    %v27 = arith.addi %v26, %p27 : i64 loc("tests/generics/two_brands_are_one_layout.lin":16:18)
    %k2m = arith.constant 255 : i64 loc("tests/generics/two_brands_are_one_layout.lin":16:5)
    %k2 = arith.cmpi ugt, %v27, %k2m : i64 loc("tests/generics/two_brands_are_one_layout.lin":16:5)
    cf.cond_br %k2, ^t2, ^c2 loc("tests/generics/two_brands_are_one_layout.lin":16:5)
  ^t2:
    %tk2 = arith.constant 2 : i32 loc("tests/generics/two_brands_are_one_layout.lin":16:5)
    %tf2 = llvm.mlir.addressof @linea_file0 : !llvm.ptr loc("tests/generics/two_brands_are_one_layout.lin":16:5)
    %tl2 = arith.constant 16 : i32 loc("tests/generics/two_brands_are_one_layout.lin":16:5)
    %tc2 = arith.constant 5 : i32 loc("tests/generics/two_brands_are_one_layout.lin":16:5)
    func.call @linea_trap(%tk2, %tf2, %tl2, %tc2) : (i32, !llvm.ptr, i32, i32) -> () loc("tests/generics/two_brands_are_one_layout.lin":16:5)
    llvm.unreachable loc("tests/generics/two_brands_are_one_layout.lin":16:5)
  ^c2:
    %p28 = arith.constant 0 : i64 loc("tests/generics/two_brands_are_one_layout.lin":16:5)
    %v28 = arith.addi %v27, %p28 : i64 loc("tests/generics/two_brands_are_one_layout.lin":16:5)
    func.return %v28 : i64 loc("tests/generics/two_brands_are_one_layout.lin":16:5)
  }
  func.func @main(%argc: i32, %argv: !llvm.ptr) -> i32 {
    func.call @linea_set_args(%argc, %argv) : (i32, !llvm.ptr) -> ()
    %status = func.call @"lin.;main"() : () -> i64
    %status32 = arith.trunci %status : i64 to i32
    func.return %status32 : i32
  }
}
