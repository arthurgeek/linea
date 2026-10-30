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
  llvm.mlir.global internal constant @linea_file0("tests/codegen/a_function_pointer_returns_an_aggregate.lin\00") : !llvm.array<58 x i8>
  func.func private @linea_set_args(i32, !llvm.ptr)
  func.func private @linea_trap(i32, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @linea_panic(i64, i64, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @"lin.;main"() -> i64 attributes {llvm.linkage = #llvm.linkage<internal>, passthrough = [["probe-stack", "inline-asm"]]} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x !llvm.ptr {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 2 : i64
    %s1 = llvm.alloca %z1 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %rz6 = arith.constant 2 : i64
    %rs6 = llvm.alloca %rz6 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    cf.br ^b0
  ^b0:
    %fa0 = func.constant @lin.closure.0 : (!llvm.ptr, i64, i64) -> () loc("tests/codegen/a_function_pointer_returns_an_aggregate.lin":7:67)
    %v0 = builtin.unrealized_conversion_cast %fa0 : (!llvm.ptr, i64, i64) -> () to !llvm.ptr loc("tests/codegen/a_function_pointer_returns_an_aggregate.lin":7:67)
    llvm.store %v0, %s0 : !llvm.ptr, !llvm.ptr loc("tests/codegen/a_function_pointer_returns_an_aggregate.lin":7:5)
    %v3 = llvm.load %s0 : !llvm.ptr -> !llvm.ptr loc("tests/codegen/a_function_pointer_returns_an_aggregate.lin":8:16)
    %v4 = arith.constant 4 : i64 loc("tests/codegen/a_function_pointer_returns_an_aggregate.lin":8:21)
    %v5 = arith.constant 5 : i64 loc("tests/codegen/a_function_pointer_returns_an_aggregate.lin":8:24)
    llvm.call %v3(%rs6, %v4, %v5) : !llvm.ptr, (!llvm.ptr, i64, i64) -> () loc("tests/codegen/a_function_pointer_returns_an_aggregate.lin":8:16)
    %cl7 = arith.constant 2 : i64 loc("tests/codegen/a_function_pointer_returns_an_aggregate.lin":8:5)
    "llvm.intr.memcpy"(%s1, %rs6, %cl7) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("tests/codegen/a_function_pointer_returns_an_aggregate.lin":8:5)
    %v9 = arith.constant 0 : i64 loc("tests/codegen/a_function_pointer_returns_an_aggregate.lin":9:5)
    %iw11 = llvm.load %s1 : !llvm.ptr -> i8 loc("tests/codegen/a_function_pointer_returns_an_aggregate.lin":9:5)
    %v11 = arith.extui %iw11 : i8 to i64 loc("tests/codegen/a_function_pointer_returns_an_aggregate.lin":9:5)
    %v13 = arith.constant 1 : i64 loc("tests/codegen/a_function_pointer_returns_an_aggregate.lin":9:18)
    %v14 = llvm.getelementptr %s1[%v13] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("tests/codegen/a_function_pointer_returns_an_aggregate.lin":9:18)
    %iw15 = llvm.load %v14 : !llvm.ptr -> i8 loc("tests/codegen/a_function_pointer_returns_an_aggregate.lin":9:18)
    %v15 = arith.extui %iw15 : i8 to i64 loc("tests/codegen/a_function_pointer_returns_an_aggregate.lin":9:18)
    %v16 = arith.addi %v11, %v15 : i64 loc("tests/codegen/a_function_pointer_returns_an_aggregate.lin":9:5)
    %k1m = arith.constant 255 : i64 loc("tests/codegen/a_function_pointer_returns_an_aggregate.lin":9:16)
    %k1 = arith.cmpi ugt, %v16, %k1m : i64 loc("tests/codegen/a_function_pointer_returns_an_aggregate.lin":9:16)
    cf.cond_br %k1, ^t1, ^c1 loc("tests/codegen/a_function_pointer_returns_an_aggregate.lin":9:16)
  ^t1:
    %tk1 = arith.constant 0 : i32 loc("tests/codegen/a_function_pointer_returns_an_aggregate.lin":9:16)
    %tf1 = llvm.mlir.addressof @linea_file0 : !llvm.ptr loc("tests/codegen/a_function_pointer_returns_an_aggregate.lin":9:16)
    %tl1 = arith.constant 9 : i32 loc("tests/codegen/a_function_pointer_returns_an_aggregate.lin":9:16)
    %tc1 = arith.constant 16 : i32 loc("tests/codegen/a_function_pointer_returns_an_aggregate.lin":9:16)
    func.call @linea_trap(%tk1, %tf1, %tl1, %tc1) : (i32, !llvm.ptr, i32, i32) -> () loc("tests/codegen/a_function_pointer_returns_an_aggregate.lin":9:16)
    llvm.unreachable loc("tests/codegen/a_function_pointer_returns_an_aggregate.lin":9:16)
  ^c1:
    %p17 = arith.constant 0 : i64 loc("tests/codegen/a_function_pointer_returns_an_aggregate.lin":9:16)
    %v17 = arith.addi %v16, %p17 : i64 loc("tests/codegen/a_function_pointer_returns_an_aggregate.lin":9:16)
    func.return %v17 : i64 loc("tests/codegen/a_function_pointer_returns_an_aggregate.lin":9:5)
  }
  func.func private @lin.closure.0(%sret: !llvm.ptr, %a0: i64, %a1: i64) attributes {llvm.linkage = #llvm.linkage<internal>, passthrough = [["probe-stack", "inline-asm"]]} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 1 : i64
    %s1 = llvm.alloca %z1 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z2 = arith.constant 2 : i64
    %s2 = llvm.alloca %z2 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %pw0 = arith.trunci %a0 : i64 to i8
    llvm.store %pw0, %s0 : i8, !llvm.ptr
    %pw1 = arith.trunci %a1 : i64 to i8
    llvm.store %pw1, %s1 : i8, !llvm.ptr
    cf.br ^b0
  ^b0:
    %v1 = arith.constant 0 : i64 loc("tests/codegen/a_function_pointer_returns_an_aggregate.lin":7:83)
    %lw3 = llvm.load %s0 : !llvm.ptr -> i8 loc("tests/codegen/a_function_pointer_returns_an_aggregate.lin":7:94)
    %v3 = arith.extui %lw3 : i8 to i64 loc("tests/codegen/a_function_pointer_returns_an_aggregate.lin":7:94)
    %iw4 = arith.trunci %v3 : i64 to i8 loc("tests/codegen/a_function_pointer_returns_an_aggregate.lin":7:83)
    llvm.store %iw4, %s2 : i8, !llvm.ptr loc("tests/codegen/a_function_pointer_returns_an_aggregate.lin":7:83)
    %v5 = arith.constant 1 : i64 loc("tests/codegen/a_function_pointer_returns_an_aggregate.lin":7:83)
    %v6 = llvm.getelementptr %s2[%v5] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("tests/codegen/a_function_pointer_returns_an_aggregate.lin":7:83)
    %lw7 = llvm.load %s1 : !llvm.ptr -> i8 loc("tests/codegen/a_function_pointer_returns_an_aggregate.lin":7:110)
    %v7 = arith.extui %lw7 : i8 to i64 loc("tests/codegen/a_function_pointer_returns_an_aggregate.lin":7:110)
    %iw8 = arith.trunci %v7 : i64 to i8 loc("tests/codegen/a_function_pointer_returns_an_aggregate.lin":7:83)
    llvm.store %iw8, %v6 : i8, !llvm.ptr loc("tests/codegen/a_function_pointer_returns_an_aggregate.lin":7:83)
    %rl9 = arith.constant 2 : i64 loc("tests/codegen/a_function_pointer_returns_an_aggregate.lin":7:83)
    "llvm.intr.memcpy"(%sret, %s2, %rl9) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("tests/codegen/a_function_pointer_returns_an_aggregate.lin":7:83)
    func.return loc("tests/codegen/a_function_pointer_returns_an_aggregate.lin":7:83)
  }
  func.func @main(%argc: i32, %argv: !llvm.ptr) -> i32 {
    func.call @linea_set_args(%argc, %argv) : (i32, !llvm.ptr) -> ()
    %status = func.call @"lin.;main"() : () -> i64
    %status32 = arith.trunci %status : i64 to i32
    func.return %status32 : i32
  }
}
