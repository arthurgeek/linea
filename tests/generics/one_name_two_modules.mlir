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
  llvm.mlir.global internal constant @linea_file0("tests/generics/one_name_two_modules/main.lin\00") : !llvm.array<45 x i8>
  llvm.mlir.global internal constant @linea_file1("tests/generics/one_name_two_modules/a/a.lin\00") : !llvm.array<44 x i8>
  llvm.mlir.global internal constant @linea_file2("tests/generics/one_name_two_modules/b/b.lin\00") : !llvm.array<44 x i8>
  func.func private @linea_set_args(i32, !llvm.ptr)
  func.func private @linea_trap(i32, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @linea_panic(i64, i64, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @"lin.;main"() -> i64 attributes {llvm.linkage = #llvm.linkage<internal>} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 2 : i64
    %s1 = llvm.alloca %z1 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z2 = arith.constant 1 : i64
    %s2 = llvm.alloca %z2 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z3 = arith.constant 2 : i64
    %s3 = llvm.alloca %z3 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %rz1 = arith.constant 1 : i64
    %rs1 = llvm.alloca %rz1 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %rz4 = arith.constant 2 : i64
    %rs4 = llvm.alloca %rz4 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %rz8 = arith.constant 1 : i64
    %rs8 = llvm.alloca %rz8 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %rz12 = arith.constant 2 : i64
    %rs12 = llvm.alloca %rz12 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    cf.br ^b0
  ^b0:
    func.call @"lin.a;make"(%rs1) : (!llvm.ptr) -> () loc("tests/generics/one_name_two_modules/main.lin":13:15)
    %cl2 = arith.constant 1 : i64 loc("tests/generics/one_name_two_modules/main.lin":13:5)
    "llvm.intr.memcpy"(%s0, %rs1, %cl2) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("tests/generics/one_name_two_modules/main.lin":13:5)
    func.call @"lin.b;make"(%rs4) : (!llvm.ptr) -> () loc("tests/generics/one_name_two_modules/main.lin":14:15)
    %cl5 = arith.constant 2 : i64 loc("tests/generics/one_name_two_modules/main.lin":14:5)
    "llvm.intr.memcpy"(%s1, %rs4, %cl5) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("tests/generics/one_name_two_modules/main.lin":14:5)
    func.call @"lin.;ident[a.Thing]"(%rs8, %s0) : (!llvm.ptr, !llvm.ptr) -> () loc("tests/generics/one_name_two_modules/main.lin":15:14)
    %cl9 = arith.constant 1 : i64 loc("tests/generics/one_name_two_modules/main.lin":15:5)
    "llvm.intr.memcpy"(%s2, %rs8, %cl9) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("tests/generics/one_name_two_modules/main.lin":15:5)
    func.call @"lin.;ident[b.Thing]"(%rs12, %s1) : (!llvm.ptr, !llvm.ptr) -> () loc("tests/generics/one_name_two_modules/main.lin":16:14)
    %cl13 = arith.constant 2 : i64 loc("tests/generics/one_name_two_modules/main.lin":16:5)
    "llvm.intr.memcpy"(%s3, %rs12, %cl13) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("tests/generics/one_name_two_modules/main.lin":16:5)
    %v15 = arith.constant 0 : i64 loc("tests/generics/one_name_two_modules/main.lin":17:5)
    %iw17 = llvm.load %s2 : !llvm.ptr -> i8 loc("tests/generics/one_name_two_modules/main.lin":17:5)
    %v17 = arith.extui %iw17 : i8 to i64 loc("tests/generics/one_name_two_modules/main.lin":17:5)
    %v19 = arith.constant 1 : i64 loc("tests/generics/one_name_two_modules/main.lin":17:12)
    %v20 = llvm.getelementptr %s3[%v19] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("tests/generics/one_name_two_modules/main.lin":17:12)
    %iw21 = llvm.load %v20 : !llvm.ptr -> i8 loc("tests/generics/one_name_two_modules/main.lin":17:12)
    %v21 = arith.extui %iw21 : i8 to i64 loc("tests/generics/one_name_two_modules/main.lin":17:12)
    %v22 = arith.addi %v17, %v21 : i64 loc("tests/generics/one_name_two_modules/main.lin":17:5)
    %k1m = arith.constant 255 : i64 loc("tests/generics/one_name_two_modules/main.lin":17:10)
    %k1 = arith.cmpi ugt, %v22, %k1m : i64 loc("tests/generics/one_name_two_modules/main.lin":17:10)
    cf.cond_br %k1, ^t1, ^c1 loc("tests/generics/one_name_two_modules/main.lin":17:10)
  ^t1:
    %tk1 = arith.constant 0 : i32 loc("tests/generics/one_name_two_modules/main.lin":17:10)
    %tf1 = llvm.mlir.addressof @linea_file0 : !llvm.ptr loc("tests/generics/one_name_two_modules/main.lin":17:10)
    %tl1 = arith.constant 17 : i32 loc("tests/generics/one_name_two_modules/main.lin":17:10)
    %tc1 = arith.constant 10 : i32 loc("tests/generics/one_name_two_modules/main.lin":17:10)
    func.call @linea_trap(%tk1, %tf1, %tl1, %tc1) : (i32, !llvm.ptr, i32, i32) -> () loc("tests/generics/one_name_two_modules/main.lin":17:10)
    llvm.unreachable loc("tests/generics/one_name_two_modules/main.lin":17:10)
  ^c1:
    %p23 = arith.constant 0 : i64 loc("tests/generics/one_name_two_modules/main.lin":17:10)
    %v23 = arith.addi %v22, %p23 : i64 loc("tests/generics/one_name_two_modules/main.lin":17:10)
    func.return %v23 : i64 loc("tests/generics/one_name_two_modules/main.lin":17:5)
  }
  func.func private @"lin.a;make"(%sret: !llvm.ptr) attributes {llvm.linkage = #llvm.linkage<internal>} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    cf.br ^b0
  ^b0:
    %v1 = arith.constant 0 : i64 loc("tests/generics/one_name_two_modules/a/a.lin":7:5)
    %v3 = arith.constant 1 : i64 loc("tests/generics/one_name_two_modules/a/a.lin":7:12)
    %iw4 = arith.trunci %v3 : i64 to i8 loc("tests/generics/one_name_two_modules/a/a.lin":7:5)
    llvm.store %iw4, %s0 : i8, !llvm.ptr loc("tests/generics/one_name_two_modules/a/a.lin":7:5)
    %rl5 = arith.constant 1 : i64 loc("tests/generics/one_name_two_modules/a/a.lin":7:5)
    "llvm.intr.memcpy"(%sret, %s0, %rl5) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("tests/generics/one_name_two_modules/a/a.lin":7:5)
    func.return loc("tests/generics/one_name_two_modules/a/a.lin":7:5)
  }
  func.func private @"lin.b;make"(%sret: !llvm.ptr) attributes {llvm.linkage = #llvm.linkage<internal>} {
    %z0 = arith.constant 2 : i64
    %s0 = llvm.alloca %z0 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    cf.br ^b0
  ^b0:
    %v1 = arith.constant 0 : i64 loc("tests/generics/one_name_two_modules/b/b.lin":8:5)
    %v3 = arith.constant 2 : i64 loc("tests/generics/one_name_two_modules/b/b.lin":8:12)
    %iw4 = arith.trunci %v3 : i64 to i8 loc("tests/generics/one_name_two_modules/b/b.lin":8:5)
    llvm.store %iw4, %s0 : i8, !llvm.ptr loc("tests/generics/one_name_two_modules/b/b.lin":8:5)
    %v5 = arith.constant 1 : i64 loc("tests/generics/one_name_two_modules/b/b.lin":8:5)
    %v6 = llvm.getelementptr %s0[%v5] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("tests/generics/one_name_two_modules/b/b.lin":8:5)
    %v7 = arith.constant 3 : i64 loc("tests/generics/one_name_two_modules/b/b.lin":8:19)
    %iw8 = arith.trunci %v7 : i64 to i8 loc("tests/generics/one_name_two_modules/b/b.lin":8:5)
    llvm.store %iw8, %v6 : i8, !llvm.ptr loc("tests/generics/one_name_two_modules/b/b.lin":8:5)
    %rl9 = arith.constant 2 : i64 loc("tests/generics/one_name_two_modules/b/b.lin":8:5)
    "llvm.intr.memcpy"(%sret, %s0, %rl9) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("tests/generics/one_name_two_modules/b/b.lin":8:5)
    func.return loc("tests/generics/one_name_two_modules/b/b.lin":8:5)
  }
  func.func private @"lin.;ident[a.Thing]"(%sret: !llvm.ptr, %a0: !llvm.ptr) attributes {llvm.linkage = #llvm.linkage<internal>} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x !llvm.ptr {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 1 : i64
    %s1 = llvm.alloca %z1 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    llvm.store %a0, %s0 : !llvm.ptr, !llvm.ptr
    cf.br ^b0
  ^b0:
    %v0 = llvm.load %s0 : !llvm.ptr -> !llvm.ptr loc("tests/generics/one_name_two_modules/main.lin":9:10)
    %cl2 = arith.constant 1 : i64 loc("tests/generics/one_name_two_modules/main.lin":9:5)
    "llvm.intr.memcpy"(%s1, %v0, %cl2) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("tests/generics/one_name_two_modules/main.lin":9:5)
    %rl4 = arith.constant 1 : i64 loc("tests/generics/one_name_two_modules/main.lin":9:5)
    "llvm.intr.memcpy"(%sret, %s1, %rl4) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("tests/generics/one_name_two_modules/main.lin":9:5)
    func.return loc("tests/generics/one_name_two_modules/main.lin":9:5)
  }
  func.func private @"lin.;ident[b.Thing]"(%sret: !llvm.ptr, %a0: !llvm.ptr) attributes {llvm.linkage = #llvm.linkage<internal>} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x !llvm.ptr {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 2 : i64
    %s1 = llvm.alloca %z1 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    llvm.store %a0, %s0 : !llvm.ptr, !llvm.ptr
    cf.br ^b0
  ^b0:
    %v0 = llvm.load %s0 : !llvm.ptr -> !llvm.ptr loc("tests/generics/one_name_two_modules/main.lin":9:10)
    %cl2 = arith.constant 2 : i64 loc("tests/generics/one_name_two_modules/main.lin":9:5)
    "llvm.intr.memcpy"(%s1, %v0, %cl2) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("tests/generics/one_name_two_modules/main.lin":9:5)
    %rl4 = arith.constant 2 : i64 loc("tests/generics/one_name_two_modules/main.lin":9:5)
    "llvm.intr.memcpy"(%sret, %s1, %rl4) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("tests/generics/one_name_two_modules/main.lin":9:5)
    func.return loc("tests/generics/one_name_two_modules/main.lin":9:5)
  }
  func.func @main(%argc: i32, %argv: !llvm.ptr) -> i32 {
    func.call @linea_set_args(%argc, %argv) : (i32, !llvm.ptr) -> ()
    %status = func.call @"lin.;main"() : () -> i64
    %status32 = arith.trunci %status : i64 to i32
    func.return %status32 : i32
  }
}
