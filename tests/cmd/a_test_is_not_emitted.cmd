A test is not emitted.

  $ (cd "$LINEA_ROOT" && linea emit-mlir tests/decl/a_helper_only_a_test_calls_is_used.lin) > out
  $ cat out
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
    llvm.mlir.global internal constant @linea_file0("tests/decl/a_helper_only_a_test_calls_is_used.lin\00") : !llvm.array<50 x i8>
    func.func private @linea_set_args(i32, !llvm.ptr)
    func.func private @linea_trap(i32, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
    func.func private @linea_panic(i64, i64, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
    func.func private @"lin.;main"() -> i64 attributes {llvm.linkage = #llvm.linkage<internal>} {
      cf.br ^b0
    ^b0:
      %v0 = arith.constant 0 : i64 loc("tests/decl/a_helper_only_a_test_calls_is_used.lin":19:5)
      func.return %v0 : i64 loc("tests/decl/a_helper_only_a_test_calls_is_used.lin":19:5)
    }
    func.func @main(%argc: i32, %argv: !llvm.ptr) -> i32 {
      func.call @linea_set_args(%argc, %argv) : (i32, !llvm.ptr) -> ()
      %status = func.call @"lin.;main"() : () -> i64
      %status32 = arith.trunci %status : i64 to i32
      func.return %status32 : i32
    }
  }
