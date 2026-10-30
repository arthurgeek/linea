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
  llvm.mlir.global internal constant @linea_file0("tests/codegen/a_closure_result_freezes_at_first_expected_call.lin\00") : !llvm.array<66 x i8>
  func.func private @linea_set_args(i32, !llvm.ptr)
  func.func private @linea_trap(i32, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @linea_panic(i64, i64, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @"lin.;main"() -> i64 attributes {llvm.linkage = #llvm.linkage<internal>, passthrough = [["probe-stack", "inline-asm"]]} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 1 : i64
    %s1 = llvm.alloca %z1 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z2 = arith.constant 1 : i64
    %s2 = llvm.alloca %z2 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    cf.br ^b0
  ^b0:
    %v0 = arith.constant 0 : i64 loc("tests/codegen/a_closure_result_freezes_at_first_expected_call.lin":2:20)
    llvm.store %v0, %s0 : i64, !llvm.ptr loc("tests/codegen/a_closure_result_freezes_at_first_expected_call.lin":2:5)
    %v2 = arith.constant 0 : i64 loc("tests/codegen/a_closure_result_freezes_at_first_expected_call.lin":3:24)
    %v3 = func.call @lin.closure.0() : () -> i64 loc("tests/codegen/a_closure_result_freezes_at_first_expected_call.lin":3:24)
    %sw4 = arith.trunci %v3 : i64 to i8 loc("tests/codegen/a_closure_result_freezes_at_first_expected_call.lin":3:5)
    llvm.store %sw4, %s1 : i8, !llvm.ptr loc("tests/codegen/a_closure_result_freezes_at_first_expected_call.lin":3:5)
    %v5 = arith.constant 0 : i64 loc("tests/codegen/a_closure_result_freezes_at_first_expected_call.lin":4:18)
    %v6 = func.call @lin.closure.0() : () -> i64 loc("tests/codegen/a_closure_result_freezes_at_first_expected_call.lin":4:18)
    %sw7 = arith.trunci %v6 : i64 to i8 loc("tests/codegen/a_closure_result_freezes_at_first_expected_call.lin":4:5)
    llvm.store %sw7, %s2 : i8, !llvm.ptr loc("tests/codegen/a_closure_result_freezes_at_first_expected_call.lin":4:5)
    %lw8 = llvm.load %s1 : !llvm.ptr -> i8 loc("tests/codegen/a_closure_result_freezes_at_first_expected_call.lin":5:5)
    %v8 = arith.extui %lw8 : i8 to i64 loc("tests/codegen/a_closure_result_freezes_at_first_expected_call.lin":5:5)
    %lw9 = llvm.load %s2 : !llvm.ptr -> i8 loc("tests/codegen/a_closure_result_freezes_at_first_expected_call.lin":5:13)
    %v9 = arith.extui %lw9 : i8 to i64 loc("tests/codegen/a_closure_result_freezes_at_first_expected_call.lin":5:13)
    %v10 = arith.addi %v8, %v9 : i64 loc("tests/codegen/a_closure_result_freezes_at_first_expected_call.lin":5:5)
    %k1m = arith.constant 255 : i64 loc("tests/codegen/a_closure_result_freezes_at_first_expected_call.lin":5:11)
    %k1 = arith.cmpi ugt, %v10, %k1m : i64 loc("tests/codegen/a_closure_result_freezes_at_first_expected_call.lin":5:11)
    cf.cond_br %k1, ^t1, ^c1 loc("tests/codegen/a_closure_result_freezes_at_first_expected_call.lin":5:11)
  ^t1:
    %tk1 = arith.constant 0 : i32 loc("tests/codegen/a_closure_result_freezes_at_first_expected_call.lin":5:11)
    %tf1 = llvm.mlir.addressof @linea_file0 : !llvm.ptr loc("tests/codegen/a_closure_result_freezes_at_first_expected_call.lin":5:11)
    %tl1 = arith.constant 5 : i32 loc("tests/codegen/a_closure_result_freezes_at_first_expected_call.lin":5:11)
    %tc1 = arith.constant 11 : i32 loc("tests/codegen/a_closure_result_freezes_at_first_expected_call.lin":5:11)
    func.call @linea_trap(%tk1, %tf1, %tl1, %tc1) : (i32, !llvm.ptr, i32, i32) -> () loc("tests/codegen/a_closure_result_freezes_at_first_expected_call.lin":5:11)
    llvm.unreachable loc("tests/codegen/a_closure_result_freezes_at_first_expected_call.lin":5:11)
  ^c1:
    %p11 = arith.constant 0 : i64 loc("tests/codegen/a_closure_result_freezes_at_first_expected_call.lin":5:11)
    %v11 = arith.addi %v10, %p11 : i64 loc("tests/codegen/a_closure_result_freezes_at_first_expected_call.lin":5:11)
    func.return %v11 : i64 loc("tests/codegen/a_closure_result_freezes_at_first_expected_call.lin":5:5)
  }
  func.func private @lin.closure.0() -> i64 attributes {llvm.linkage = #llvm.linkage<internal>, passthrough = [["probe-stack", "inline-asm"]]} {
    cf.br ^b0
  ^b0:
    %v0 = arith.constant 7 : i64 loc("tests/codegen/a_closure_result_freezes_at_first_expected_call.lin":2:23)
    func.return %v0 : i64 loc("tests/codegen/a_closure_result_freezes_at_first_expected_call.lin":2:23)
  }
  func.func @main(%argc: i32, %argv: !llvm.ptr) -> i32 {
    func.call @linea_set_args(%argc, %argv) : (i32, !llvm.ptr) -> ()
    %status = func.call @"lin.;main"() : () -> i64
    %status32 = arith.trunci %status : i64 to i32
    func.return %status32 : i32
  }
}
