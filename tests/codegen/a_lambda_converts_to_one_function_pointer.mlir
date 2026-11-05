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
  llvm.mlir.global internal constant @linea_file0("tests/codegen/a_lambda_converts_to_one_function_pointer.lin\00") : !llvm.array<60 x i8>
  func.func private @linea_set_args(i32, !llvm.ptr)
  func.func private @linea_trap(i32, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @linea_panic(i64, i64, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @"lin.;main"() -> i64 attributes {llvm.linkage = #llvm.linkage<internal>, passthrough = [["probe-stack", "inline-asm"]]} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x !llvm.ptr {alignment = 8 : i64} : (i64) -> !llvm.ptr
    cf.br ^b0
  ^b0:
    %fa0 = func.constant @lin.closure.0 : (i64) -> i64 loc("tests/codegen/a_lambda_converts_to_one_function_pointer.lin":2:53)
    %v0 = builtin.unrealized_conversion_cast %fa0 : (i64) -> i64 to !llvm.ptr loc("tests/codegen/a_lambda_converts_to_one_function_pointer.lin":2:53)
    llvm.store %v0, %s0 : !llvm.ptr, !llvm.ptr loc("tests/codegen/a_lambda_converts_to_one_function_pointer.lin":2:5)
    %v2 = llvm.load %s0 : !llvm.ptr -> !llvm.ptr loc("tests/codegen/a_lambda_converts_to_one_function_pointer.lin":3:5)
    %v3 = arith.constant 4 : i64 loc("tests/codegen/a_lambda_converts_to_one_function_pointer.lin":3:15)
    %v4 = llvm.call %v2(%v3) : !llvm.ptr, (i64) -> i64 loc("tests/codegen/a_lambda_converts_to_one_function_pointer.lin":3:5)
    func.return %v4 : i64 loc("tests/codegen/a_lambda_converts_to_one_function_pointer.lin":3:5)
  }
  func.func private @lin.closure.0(%a0: i64) -> i64 attributes {llvm.linkage = #llvm.linkage<internal>, passthrough = [["probe-stack", "inline-asm"]]} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %pw0 = arith.trunci %a0 : i64 to i8
    llvm.store %pw0, %s0 : i8, !llvm.ptr
    cf.br ^b0
  ^b0:
    %lw0 = llvm.load %s0 : !llvm.ptr -> i8 loc("tests/codegen/a_lambda_converts_to_one_function_pointer.lin":2:61)
    %v0 = arith.extui %lw0 : i8 to i64 loc("tests/codegen/a_lambda_converts_to_one_function_pointer.lin":2:61)
    %v1 = arith.constant 1 : i64 loc("tests/codegen/a_lambda_converts_to_one_function_pointer.lin":2:69)
    %v2 = arith.addi %v0, %v1 : i64 loc("tests/codegen/a_lambda_converts_to_one_function_pointer.lin":2:61)
    %k1m = arith.constant 255 : i64 loc("tests/codegen/a_lambda_converts_to_one_function_pointer.lin":2:67)
    %k1 = arith.cmpi ugt, %v2, %k1m : i64 loc("tests/codegen/a_lambda_converts_to_one_function_pointer.lin":2:67)
    cf.cond_br %k1, ^t1, ^c1 loc("tests/codegen/a_lambda_converts_to_one_function_pointer.lin":2:67)
  ^t1:
    %tk1 = arith.constant 0 : i32 loc("tests/codegen/a_lambda_converts_to_one_function_pointer.lin":2:67)
    %tf1 = llvm.mlir.addressof @linea_file0 : !llvm.ptr loc("tests/codegen/a_lambda_converts_to_one_function_pointer.lin":2:67)
    %tl1 = arith.constant 2 : i32 loc("tests/codegen/a_lambda_converts_to_one_function_pointer.lin":2:67)
    %tc1 = arith.constant 67 : i32 loc("tests/codegen/a_lambda_converts_to_one_function_pointer.lin":2:67)
    func.call @linea_trap(%tk1, %tf1, %tl1, %tc1) : (i32, !llvm.ptr, i32, i32) -> () loc("tests/codegen/a_lambda_converts_to_one_function_pointer.lin":2:67)
    llvm.unreachable loc("tests/codegen/a_lambda_converts_to_one_function_pointer.lin":2:67)
  ^c1:
    %p3 = arith.constant 0 : i64 loc("tests/codegen/a_lambda_converts_to_one_function_pointer.lin":2:67)
    %v3 = arith.addi %v2, %p3 : i64 loc("tests/codegen/a_lambda_converts_to_one_function_pointer.lin":2:67)
    func.return %v3 : i64 loc("tests/codegen/a_lambda_converts_to_one_function_pointer.lin":2:61)
  }
  func.func @main(%argc: i32, %argv: !llvm.ptr) -> i32 {
    func.call @linea_set_args(%argc, %argv) : (i32, !llvm.ptr) -> ()
    %status = func.call @"lin.;main"() : () -> i64
    %status32 = arith.trunci %status : i64 to i32
    func.return %status32 : i32
  }
}
