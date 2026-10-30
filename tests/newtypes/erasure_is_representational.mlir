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
  llvm.mlir.global internal constant @linea_file0("tests/newtypes/erasure_is_representational.lin\00") : !llvm.array<47 x i8>
  func.func private @linea_set_args(i32, !llvm.ptr)
  func.func private @linea_trap(i32, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @linea_panic(i64, i64, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @"lin.;main"() -> i64 attributes {llvm.linkage = #llvm.linkage<internal>, passthrough = [["probe-stack", "inline-asm"]]} {
    cf.br ^b0
  ^b0:
    %v0 = arith.constant 3 : i64 loc("tests/newtypes/erasure_is_representational.lin":23:28)
    %v1 = arith.constant 4 : i64 loc("tests/newtypes/erasure_is_representational.lin":23:39)
    %v2 = func.call @"lin.;addMeters"(%v0, %v1) : (i64, i64) -> i64 loc("tests/newtypes/erasure_is_representational.lin":23:11)
    %v3 = arith.constant 3 : i64 loc("tests/newtypes/erasure_is_representational.lin":23:55)
    %v4 = arith.constant 4 : i64 loc("tests/newtypes/erasure_is_representational.lin":23:58)
    %v5 = func.call @"lin.;addUInt64"(%v3, %v4) : (i64, i64) -> i64 loc("tests/newtypes/erasure_is_representational.lin":23:45)
    %v6 = arith.subi %v2, %v5 : i64 loc("tests/newtypes/erasure_is_representational.lin":23:11)
    %k1 = arith.cmpi ult, %v2, %v5 : i64 loc("tests/newtypes/erasure_is_representational.lin":23:43)
    cf.cond_br %k1, ^t1, ^c1 loc("tests/newtypes/erasure_is_representational.lin":23:43)
  ^t1:
    %tk1 = arith.constant 0 : i32 loc("tests/newtypes/erasure_is_representational.lin":23:43)
    %tf1 = llvm.mlir.addressof @linea_file0 : !llvm.ptr loc("tests/newtypes/erasure_is_representational.lin":23:43)
    %tl1 = arith.constant 23 : i32 loc("tests/newtypes/erasure_is_representational.lin":23:43)
    %tc1 = arith.constant 43 : i32 loc("tests/newtypes/erasure_is_representational.lin":23:43)
    func.call @linea_trap(%tk1, %tf1, %tl1, %tc1) : (i32, !llvm.ptr, i32, i32) -> () loc("tests/newtypes/erasure_is_representational.lin":23:43)
    llvm.unreachable loc("tests/newtypes/erasure_is_representational.lin":23:43)
  ^c1:
    %p7 = arith.constant 0 : i64 loc("tests/newtypes/erasure_is_representational.lin":23:43)
    %v7 = arith.addi %v6, %p7 : i64 loc("tests/newtypes/erasure_is_representational.lin":23:43)
    %k2m = arith.constant 255 : i64 loc("tests/newtypes/erasure_is_representational.lin":23:5)
    %k2 = arith.cmpi ugt, %v7, %k2m : i64 loc("tests/newtypes/erasure_is_representational.lin":23:5)
    cf.cond_br %k2, ^t2, ^c2 loc("tests/newtypes/erasure_is_representational.lin":23:5)
  ^t2:
    %tk2 = arith.constant 2 : i32 loc("tests/newtypes/erasure_is_representational.lin":23:5)
    %tf2 = llvm.mlir.addressof @linea_file0 : !llvm.ptr loc("tests/newtypes/erasure_is_representational.lin":23:5)
    %tl2 = arith.constant 23 : i32 loc("tests/newtypes/erasure_is_representational.lin":23:5)
    %tc2 = arith.constant 5 : i32 loc("tests/newtypes/erasure_is_representational.lin":23:5)
    func.call @linea_trap(%tk2, %tf2, %tl2, %tc2) : (i32, !llvm.ptr, i32, i32) -> () loc("tests/newtypes/erasure_is_representational.lin":23:5)
    llvm.unreachable loc("tests/newtypes/erasure_is_representational.lin":23:5)
  ^c2:
    %p8 = arith.constant 0 : i64 loc("tests/newtypes/erasure_is_representational.lin":23:5)
    %v8 = arith.addi %v7, %p8 : i64 loc("tests/newtypes/erasure_is_representational.lin":23:5)
    func.return %v8 : i64 loc("tests/newtypes/erasure_is_representational.lin":23:5)
  }
  func.func private @"lin.;addMeters"(%a0: i64, %a1: i64) -> i64 attributes {llvm.linkage = #llvm.linkage<internal>, passthrough = [["probe-stack", "inline-asm"]]} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 1 : i64
    %s1 = llvm.alloca %z1 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z2 = arith.constant 1 : i64
    %s2 = llvm.alloca %z2 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z3 = arith.constant 1 : i64
    %s3 = llvm.alloca %z3 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    llvm.store %a0, %s0 : i64, !llvm.ptr
    llvm.store %a1, %s1 : i64, !llvm.ptr
    cf.br ^b0
  ^b0:
    %v0 = llvm.load %s0 : !llvm.ptr -> i64 loc("tests/newtypes/erasure_is_representational.lin":11:21)
    llvm.store %v0, %s2 : i64, !llvm.ptr loc("tests/newtypes/erasure_is_representational.lin":11:5)
    %v2 = llvm.load %s1 : !llvm.ptr -> i64 loc("tests/newtypes/erasure_is_representational.lin":12:21)
    llvm.store %v2, %s3 : i64, !llvm.ptr loc("tests/newtypes/erasure_is_representational.lin":12:5)
    %v4 = llvm.load %s2 : !llvm.ptr -> i64 loc("tests/newtypes/erasure_is_representational.lin":13:5)
    %v5 = llvm.load %s3 : !llvm.ptr -> i64 loc("tests/newtypes/erasure_is_representational.lin":13:9)
    %v6 = arith.addi %v4, %v5 : i64 loc("tests/newtypes/erasure_is_representational.lin":13:5)
    %k1 = arith.cmpi ult, %v6, %v4 : i64 loc("tests/newtypes/erasure_is_representational.lin":13:7)
    cf.cond_br %k1, ^t1, ^c1 loc("tests/newtypes/erasure_is_representational.lin":13:7)
  ^t1:
    %tk1 = arith.constant 0 : i32 loc("tests/newtypes/erasure_is_representational.lin":13:7)
    %tf1 = llvm.mlir.addressof @linea_file0 : !llvm.ptr loc("tests/newtypes/erasure_is_representational.lin":13:7)
    %tl1 = arith.constant 13 : i32 loc("tests/newtypes/erasure_is_representational.lin":13:7)
    %tc1 = arith.constant 7 : i32 loc("tests/newtypes/erasure_is_representational.lin":13:7)
    func.call @linea_trap(%tk1, %tf1, %tl1, %tc1) : (i32, !llvm.ptr, i32, i32) -> () loc("tests/newtypes/erasure_is_representational.lin":13:7)
    llvm.unreachable loc("tests/newtypes/erasure_is_representational.lin":13:7)
  ^c1:
    %p7 = arith.constant 0 : i64 loc("tests/newtypes/erasure_is_representational.lin":13:7)
    %v7 = arith.addi %v6, %p7 : i64 loc("tests/newtypes/erasure_is_representational.lin":13:7)
    func.return %v7 : i64 loc("tests/newtypes/erasure_is_representational.lin":13:5)
  }
  func.func private @"lin.;addUInt64"(%a0: i64, %a1: i64) -> i64 attributes {llvm.linkage = #llvm.linkage<internal>, passthrough = [["probe-stack", "inline-asm"]]} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 1 : i64
    %s1 = llvm.alloca %z1 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z2 = arith.constant 1 : i64
    %s2 = llvm.alloca %z2 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z3 = arith.constant 1 : i64
    %s3 = llvm.alloca %z3 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    llvm.store %a0, %s0 : i64, !llvm.ptr
    llvm.store %a1, %s1 : i64, !llvm.ptr
    cf.br ^b0
  ^b0:
    %v0 = llvm.load %s0 : !llvm.ptr -> i64 loc("tests/newtypes/erasure_is_representational.lin":17:13)
    llvm.store %v0, %s2 : i64, !llvm.ptr loc("tests/newtypes/erasure_is_representational.lin":17:5)
    %v2 = llvm.load %s1 : !llvm.ptr -> i64 loc("tests/newtypes/erasure_is_representational.lin":18:13)
    llvm.store %v2, %s3 : i64, !llvm.ptr loc("tests/newtypes/erasure_is_representational.lin":18:5)
    %v4 = llvm.load %s2 : !llvm.ptr -> i64 loc("tests/newtypes/erasure_is_representational.lin":19:5)
    %v5 = llvm.load %s3 : !llvm.ptr -> i64 loc("tests/newtypes/erasure_is_representational.lin":19:9)
    %v6 = arith.addi %v4, %v5 : i64 loc("tests/newtypes/erasure_is_representational.lin":19:5)
    %k1 = arith.cmpi ult, %v6, %v4 : i64 loc("tests/newtypes/erasure_is_representational.lin":19:7)
    cf.cond_br %k1, ^t1, ^c1 loc("tests/newtypes/erasure_is_representational.lin":19:7)
  ^t1:
    %tk1 = arith.constant 0 : i32 loc("tests/newtypes/erasure_is_representational.lin":19:7)
    %tf1 = llvm.mlir.addressof @linea_file0 : !llvm.ptr loc("tests/newtypes/erasure_is_representational.lin":19:7)
    %tl1 = arith.constant 19 : i32 loc("tests/newtypes/erasure_is_representational.lin":19:7)
    %tc1 = arith.constant 7 : i32 loc("tests/newtypes/erasure_is_representational.lin":19:7)
    func.call @linea_trap(%tk1, %tf1, %tl1, %tc1) : (i32, !llvm.ptr, i32, i32) -> () loc("tests/newtypes/erasure_is_representational.lin":19:7)
    llvm.unreachable loc("tests/newtypes/erasure_is_representational.lin":19:7)
  ^c1:
    %p7 = arith.constant 0 : i64 loc("tests/newtypes/erasure_is_representational.lin":19:7)
    %v7 = arith.addi %v6, %p7 : i64 loc("tests/newtypes/erasure_is_representational.lin":19:7)
    func.return %v7 : i64 loc("tests/newtypes/erasure_is_representational.lin":19:5)
  }
  func.func @main(%argc: i32, %argv: !llvm.ptr) -> i32 {
    func.call @linea_set_args(%argc, %argv) : (i32, !llvm.ptr) -> ()
    %status = func.call @"lin.;main"() : () -> i64
    %status32 = arith.trunci %status : i64 to i32
    func.return %status32 : i32
  }
}
