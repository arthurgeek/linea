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
  llvm.mlir.global internal constant @linea_file0("tests/traits/a_callable_bound_specialises_a_lambda.lin\00") : !llvm.array<55 x i8>
  func.func private @linea_set_args(i32, !llvm.ptr)
  func.func private @linea_trap(i32, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @linea_panic(i64, i64, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @"lin.;main"() -> i64 attributes {llvm.linkage = #llvm.linkage<internal>, passthrough = [["probe-stack", "inline-asm"]]} {
    cf.br ^b0
  ^b0:
    %v0 = arith.constant 2 : i64 loc("tests/traits/a_callable_bound_specialises_a_lambda.lin":6:13)
    %v1 = arith.constant 3 : i64 loc("tests/traits/a_callable_bound_specialises_a_lambda.lin":6:16)
    %v2 = arith.constant 0 : i64 loc("tests/traits/a_callable_bound_specialises_a_lambda.lin":6:19)
    %v3 = func.call @"lin.;reduce2[UInt8,closure0[]]"(%v0, %v1, %v2) : (i64, i64, i64) -> i64 loc("tests/traits/a_callable_bound_specialises_a_lambda.lin":6:5)
    func.return %v3 : i64 loc("tests/traits/a_callable_bound_specialises_a_lambda.lin":6:5)
  }
  func.func private @"lin.;reduce2[UInt8,closure0[]]"(%a0: i64, %a1: i64, %a2: i64) -> i64 attributes {llvm.linkage = #llvm.linkage<internal>, passthrough = [["probe-stack", "inline-asm"]]} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 1 : i64
    %s1 = llvm.alloca %z1 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z2 = arith.constant 1 : i64
    %s2 = llvm.alloca %z2 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %pw0 = arith.trunci %a0 : i64 to i8
    llvm.store %pw0, %s0 : i8, !llvm.ptr
    %pw1 = arith.trunci %a1 : i64 to i8
    llvm.store %pw1, %s1 : i8, !llvm.ptr
    llvm.store %a2, %s2 : i64, !llvm.ptr
    cf.br ^b0
  ^b0:
    %v0 = arith.constant 0 : i64 loc("tests/traits/a_callable_bound_specialises_a_lambda.lin":2:5)
    %lw1 = llvm.load %s0 : !llvm.ptr -> i8 loc("tests/traits/a_callable_bound_specialises_a_lambda.lin":2:13)
    %v1 = arith.extui %lw1 : i8 to i64 loc("tests/traits/a_callable_bound_specialises_a_lambda.lin":2:13)
    %lw2 = llvm.load %s1 : !llvm.ptr -> i8 loc("tests/traits/a_callable_bound_specialises_a_lambda.lin":2:18)
    %v2 = arith.extui %lw2 : i8 to i64 loc("tests/traits/a_callable_bound_specialises_a_lambda.lin":2:18)
    %v3 = func.call @lin.closure.0(%v1, %v2) : (i64, i64) -> i64 loc("tests/traits/a_callable_bound_specialises_a_lambda.lin":2:5)
    func.return %v3 : i64 loc("tests/traits/a_callable_bound_specialises_a_lambda.lin":2:5)
  }
  func.func private @lin.closure.0(%a0: i64, %a1: i64) -> i64 attributes {llvm.linkage = #llvm.linkage<internal>, passthrough = [["probe-stack", "inline-asm"]]} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 1 : i64
    %s1 = llvm.alloca %z1 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %pw0 = arith.trunci %a0 : i64 to i8
    llvm.store %pw0, %s0 : i8, !llvm.ptr
    %pw1 = arith.trunci %a1 : i64 to i8
    llvm.store %pw1, %s1 : i8, !llvm.ptr
    cf.br ^b0
  ^b0:
    %lw0 = llvm.load %s0 : !llvm.ptr -> i8 loc("tests/traits/a_callable_bound_specialises_a_lambda.lin":6:30)
    %v0 = arith.extui %lw0 : i8 to i64 loc("tests/traits/a_callable_bound_specialises_a_lambda.lin":6:30)
    %lw1 = llvm.load %s1 : !llvm.ptr -> i8 loc("tests/traits/a_callable_bound_specialises_a_lambda.lin":6:36)
    %v1 = arith.extui %lw1 : i8 to i64 loc("tests/traits/a_callable_bound_specialises_a_lambda.lin":6:36)
    %v2 = arith.addi %v0, %v1 : i64 loc("tests/traits/a_callable_bound_specialises_a_lambda.lin":6:30)
    %k1m = arith.constant 255 : i64 loc("tests/traits/a_callable_bound_specialises_a_lambda.lin":6:34)
    %k1 = arith.cmpi ugt, %v2, %k1m : i64 loc("tests/traits/a_callable_bound_specialises_a_lambda.lin":6:34)
    cf.cond_br %k1, ^t1, ^c1 loc("tests/traits/a_callable_bound_specialises_a_lambda.lin":6:34)
  ^t1:
    %tk1 = arith.constant 0 : i32 loc("tests/traits/a_callable_bound_specialises_a_lambda.lin":6:34)
    %tf1 = llvm.mlir.addressof @linea_file0 : !llvm.ptr loc("tests/traits/a_callable_bound_specialises_a_lambda.lin":6:34)
    %tl1 = arith.constant 6 : i32 loc("tests/traits/a_callable_bound_specialises_a_lambda.lin":6:34)
    %tc1 = arith.constant 34 : i32 loc("tests/traits/a_callable_bound_specialises_a_lambda.lin":6:34)
    func.call @linea_trap(%tk1, %tf1, %tl1, %tc1) : (i32, !llvm.ptr, i32, i32) -> () loc("tests/traits/a_callable_bound_specialises_a_lambda.lin":6:34)
    llvm.unreachable loc("tests/traits/a_callable_bound_specialises_a_lambda.lin":6:34)
  ^c1:
    %p3 = arith.constant 0 : i64 loc("tests/traits/a_callable_bound_specialises_a_lambda.lin":6:34)
    %v3 = arith.addi %v2, %p3 : i64 loc("tests/traits/a_callable_bound_specialises_a_lambda.lin":6:34)
    func.return %v3 : i64 loc("tests/traits/a_callable_bound_specialises_a_lambda.lin":6:30)
  }
  func.func @main(%argc: i32, %argv: !llvm.ptr) -> i32 {
    func.call @linea_set_args(%argc, %argv) : (i32, !llvm.ptr) -> ()
    %status = func.call @"lin.;main"() : () -> i64
    %status32 = arith.trunci %status : i64 to i32
    func.return %status32 : i32
  }
}
