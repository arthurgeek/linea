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
  llvm.mlir.global internal constant @linea_file0("tests/generics/a_module_prefix_is_not_a_name/main.lin\00") : !llvm.array<54 x i8>
  llvm.mlir.global internal constant @linea_file1("tests/generics/a_module_prefix_is_not_a_name/sub/sub.lin\00") : !llvm.array<57 x i8>
  func.func private @linea_set_args(i32, !llvm.ptr)
  func.func private @linea_trap(i32, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @linea_panic(i64, i64, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @"lin.;main"() -> i64 attributes {llvm.linkage = #llvm.linkage<internal>} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 1 : i64
    %s1 = llvm.alloca %z1 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z2 = arith.constant 1 : i64
    %s2 = llvm.alloca %z2 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %rz17 = arith.constant 1 : i64
    %rs17 = llvm.alloca %rz17 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    cf.br ^b0
  ^b0:
    %v1 = arith.constant 0 : i64 loc("tests/generics/a_module_prefix_is_not_a_name/main.lin":32:18)
    %v3 = arith.constant 1 : i64 loc("tests/generics/a_module_prefix_is_not_a_name/main.lin":32:25)
    %iw4 = arith.trunci %v3 : i64 to i8 loc("tests/generics/a_module_prefix_is_not_a_name/main.lin":32:18)
    llvm.store %iw4, %s0 : i8, !llvm.ptr loc("tests/generics/a_module_prefix_is_not_a_name/main.lin":32:18)
    %v6 = arith.constant 0 : i64 loc("tests/generics/a_module_prefix_is_not_a_name/main.lin":33:16)
    %v8 = arith.constant 2 : i64 loc("tests/generics/a_module_prefix_is_not_a_name/main.lin":33:23)
    %iw9 = arith.trunci %v8 : i64 to i8 loc("tests/generics/a_module_prefix_is_not_a_name/main.lin":33:16)
    llvm.store %iw9, %s1 : i8, !llvm.ptr loc("tests/generics/a_module_prefix_is_not_a_name/main.lin":33:16)
    %v11 = arith.constant 0 : i64 loc("tests/generics/a_module_prefix_is_not_a_name/main.lin":34:20)
    %v13 = arith.constant 0 : i64 loc("tests/generics/a_module_prefix_is_not_a_name/main.lin":34:27)
    %v15 = arith.constant 4 : i64 loc("tests/generics/a_module_prefix_is_not_a_name/main.lin":34:34)
    %iw16 = arith.trunci %v15 : i64 to i8 loc("tests/generics/a_module_prefix_is_not_a_name/main.lin":34:27)
    llvm.store %iw16, %s2 : i8, !llvm.ptr loc("tests/generics/a_module_prefix_is_not_a_name/main.lin":34:27)
    func.call @"lin.sub;mk"(%rs17) : (!llvm.ptr) -> () loc("tests/generics/a_module_prefix_is_not_a_name/main.lin":35:7)
    %v19 = func.call @"lin.;g[sub.X,Y]"(%rs17, %s1) : (!llvm.ptr, !llvm.ptr) -> i64 loc("tests/generics/a_module_prefix_is_not_a_name/main.lin":35:5)
    %v22 = func.call @"lin.;g[Sub,X[Y]]"(%s0, %s2) : (!llvm.ptr, !llvm.ptr) -> i64 loc("tests/generics/a_module_prefix_is_not_a_name/main.lin":35:22)
    %v23 = arith.addi %v19, %v22 : i64 loc("tests/generics/a_module_prefix_is_not_a_name/main.lin":35:5)
    %k1m = arith.constant 255 : i64 loc("tests/generics/a_module_prefix_is_not_a_name/main.lin":35:20)
    %k1 = arith.cmpi ugt, %v23, %k1m : i64 loc("tests/generics/a_module_prefix_is_not_a_name/main.lin":35:20)
    cf.cond_br %k1, ^t1, ^c1 loc("tests/generics/a_module_prefix_is_not_a_name/main.lin":35:20)
  ^t1:
    %tk1 = arith.constant 0 : i32 loc("tests/generics/a_module_prefix_is_not_a_name/main.lin":35:20)
    %tf1 = llvm.mlir.addressof @linea_file0 : !llvm.ptr loc("tests/generics/a_module_prefix_is_not_a_name/main.lin":35:20)
    %tl1 = arith.constant 35 : i32 loc("tests/generics/a_module_prefix_is_not_a_name/main.lin":35:20)
    %tc1 = arith.constant 20 : i32 loc("tests/generics/a_module_prefix_is_not_a_name/main.lin":35:20)
    func.call @linea_trap(%tk1, %tf1, %tl1, %tc1) : (i32, !llvm.ptr, i32, i32) -> () loc("tests/generics/a_module_prefix_is_not_a_name/main.lin":35:20)
    llvm.unreachable loc("tests/generics/a_module_prefix_is_not_a_name/main.lin":35:20)
  ^c1:
    %p24 = arith.constant 0 : i64 loc("tests/generics/a_module_prefix_is_not_a_name/main.lin":35:20)
    %v24 = arith.addi %v23, %p24 : i64 loc("tests/generics/a_module_prefix_is_not_a_name/main.lin":35:20)
    %v25 = func.call @"lin.;Sub.helper"() : () -> i64 loc("tests/generics/a_module_prefix_is_not_a_name/main.lin":35:33)
    %v26 = arith.addi %v24, %v25 : i64 loc("tests/generics/a_module_prefix_is_not_a_name/main.lin":35:5)
    %k2m = arith.constant 255 : i64 loc("tests/generics/a_module_prefix_is_not_a_name/main.lin":35:31)
    %k2 = arith.cmpi ugt, %v26, %k2m : i64 loc("tests/generics/a_module_prefix_is_not_a_name/main.lin":35:31)
    cf.cond_br %k2, ^t2, ^c2 loc("tests/generics/a_module_prefix_is_not_a_name/main.lin":35:31)
  ^t2:
    %tk2 = arith.constant 0 : i32 loc("tests/generics/a_module_prefix_is_not_a_name/main.lin":35:31)
    %tf2 = llvm.mlir.addressof @linea_file0 : !llvm.ptr loc("tests/generics/a_module_prefix_is_not_a_name/main.lin":35:31)
    %tl2 = arith.constant 35 : i32 loc("tests/generics/a_module_prefix_is_not_a_name/main.lin":35:31)
    %tc2 = arith.constant 31 : i32 loc("tests/generics/a_module_prefix_is_not_a_name/main.lin":35:31)
    func.call @linea_trap(%tk2, %tf2, %tl2, %tc2) : (i32, !llvm.ptr, i32, i32) -> () loc("tests/generics/a_module_prefix_is_not_a_name/main.lin":35:31)
    llvm.unreachable loc("tests/generics/a_module_prefix_is_not_a_name/main.lin":35:31)
  ^c2:
    %p27 = arith.constant 0 : i64 loc("tests/generics/a_module_prefix_is_not_a_name/main.lin":35:31)
    %v27 = arith.addi %v26, %p27 : i64 loc("tests/generics/a_module_prefix_is_not_a_name/main.lin":35:31)
    %v28 = func.call @"lin.sub;helper"() : () -> i64 loc("tests/generics/a_module_prefix_is_not_a_name/main.lin":35:48)
    %v29 = arith.addi %v27, %v28 : i64 loc("tests/generics/a_module_prefix_is_not_a_name/main.lin":35:5)
    %k3m = arith.constant 255 : i64 loc("tests/generics/a_module_prefix_is_not_a_name/main.lin":35:46)
    %k3 = arith.cmpi ugt, %v29, %k3m : i64 loc("tests/generics/a_module_prefix_is_not_a_name/main.lin":35:46)
    cf.cond_br %k3, ^t3, ^c3 loc("tests/generics/a_module_prefix_is_not_a_name/main.lin":35:46)
  ^t3:
    %tk3 = arith.constant 0 : i32 loc("tests/generics/a_module_prefix_is_not_a_name/main.lin":35:46)
    %tf3 = llvm.mlir.addressof @linea_file0 : !llvm.ptr loc("tests/generics/a_module_prefix_is_not_a_name/main.lin":35:46)
    %tl3 = arith.constant 35 : i32 loc("tests/generics/a_module_prefix_is_not_a_name/main.lin":35:46)
    %tc3 = arith.constant 46 : i32 loc("tests/generics/a_module_prefix_is_not_a_name/main.lin":35:46)
    func.call @linea_trap(%tk3, %tf3, %tl3, %tc3) : (i32, !llvm.ptr, i32, i32) -> () loc("tests/generics/a_module_prefix_is_not_a_name/main.lin":35:46)
    llvm.unreachable loc("tests/generics/a_module_prefix_is_not_a_name/main.lin":35:46)
  ^c3:
    %p30 = arith.constant 0 : i64 loc("tests/generics/a_module_prefix_is_not_a_name/main.lin":35:46)
    %v30 = arith.addi %v29, %p30 : i64 loc("tests/generics/a_module_prefix_is_not_a_name/main.lin":35:46)
    func.return %v30 : i64 loc("tests/generics/a_module_prefix_is_not_a_name/main.lin":35:5)
  }
  func.func private @"lin.sub;mk"(%sret: !llvm.ptr) attributes {llvm.linkage = #llvm.linkage<internal>} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    cf.br ^b0
  ^b0:
    %v1 = arith.constant 0 : i64 loc("tests/generics/a_module_prefix_is_not_a_name/sub/sub.lin":6:5)
    %v3 = arith.constant 1 : i64 loc("tests/generics/a_module_prefix_is_not_a_name/sub/sub.lin":6:12)
    %iw4 = arith.trunci %v3 : i64 to i8 loc("tests/generics/a_module_prefix_is_not_a_name/sub/sub.lin":6:5)
    llvm.store %iw4, %s0 : i8, !llvm.ptr loc("tests/generics/a_module_prefix_is_not_a_name/sub/sub.lin":6:5)
    %rl5 = arith.constant 1 : i64 loc("tests/generics/a_module_prefix_is_not_a_name/sub/sub.lin":6:5)
    "llvm.intr.memcpy"(%sret, %s0, %rl5) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("tests/generics/a_module_prefix_is_not_a_name/sub/sub.lin":6:5)
    func.return loc("tests/generics/a_module_prefix_is_not_a_name/sub/sub.lin":6:5)
  }
  func.func private @"lin.;g[sub.X,Y]"(%a0: !llvm.ptr, %a1: !llvm.ptr) -> i64 attributes {llvm.linkage = #llvm.linkage<internal>} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x !llvm.ptr {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 1 : i64
    %s1 = llvm.alloca %z1 x !llvm.ptr {alignment = 8 : i64} : (i64) -> !llvm.ptr
    llvm.store %a0, %s0 : !llvm.ptr, !llvm.ptr
    llvm.store %a1, %s1 : !llvm.ptr, !llvm.ptr
    cf.br ^b0
  ^b0:
    %v0 = arith.constant 1 : i64 loc("tests/generics/a_module_prefix_is_not_a_name/main.lin":22:5)
    func.return %v0 : i64 loc("tests/generics/a_module_prefix_is_not_a_name/main.lin":22:5)
  }
  func.func private @"lin.;g[Sub,X[Y]]"(%a0: !llvm.ptr, %a1: !llvm.ptr) -> i64 attributes {llvm.linkage = #llvm.linkage<internal>} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x !llvm.ptr {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 1 : i64
    %s1 = llvm.alloca %z1 x !llvm.ptr {alignment = 8 : i64} : (i64) -> !llvm.ptr
    llvm.store %a0, %s0 : !llvm.ptr, !llvm.ptr
    llvm.store %a1, %s1 : !llvm.ptr, !llvm.ptr
    cf.br ^b0
  ^b0:
    %v0 = arith.constant 1 : i64 loc("tests/generics/a_module_prefix_is_not_a_name/main.lin":22:5)
    func.return %v0 : i64 loc("tests/generics/a_module_prefix_is_not_a_name/main.lin":22:5)
  }
  func.func private @"lin.;Sub.helper"() -> i64 attributes {llvm.linkage = #llvm.linkage<internal>} {
    cf.br ^b0
  ^b0:
    %v0 = arith.constant 3 : i64 loc("tests/generics/a_module_prefix_is_not_a_name/main.lin":27:9)
    func.return %v0 : i64 loc("tests/generics/a_module_prefix_is_not_a_name/main.lin":27:9)
  }
  func.func private @"lin.sub;helper"() -> i64 attributes {llvm.linkage = #llvm.linkage<internal>} {
    cf.br ^b0
  ^b0:
    %v0 = arith.constant 5 : i64 loc("tests/generics/a_module_prefix_is_not_a_name/sub/sub.lin":10:5)
    func.return %v0 : i64 loc("tests/generics/a_module_prefix_is_not_a_name/sub/sub.lin":10:5)
  }
  func.func @main(%argc: i32, %argv: !llvm.ptr) -> i32 {
    func.call @linea_set_args(%argc, %argv) : (i32, !llvm.ptr) -> ()
    %status = func.call @"lin.;main"() : () -> i64
    %status32 = arith.trunci %status : i64 to i32
    func.return %status32 : i32
  }
}
