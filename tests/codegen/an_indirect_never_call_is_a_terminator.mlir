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
  llvm.mlir.global internal constant @linea_file0("tests/codegen/an_indirect_never_call_is_a_terminator.lin\00") : !llvm.array<57 x i8>
  func.func private @linea_set_args(i32, !llvm.ptr)
  func.func private @linea_trap(i32, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @linea_panic(i64, i64, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @"lin.;main"() -> i64 attributes {llvm.linkage = #llvm.linkage<internal>, passthrough = [["probe-stack", "inline-asm"]]} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x !llvm.ptr {alignment = 8 : i64} : (i64) -> !llvm.ptr
    cf.br ^b0
  ^b0:
    %fa0 = func.constant @"lin.;halt" : () -> () loc("tests/codegen/an_indirect_never_call_is_a_terminator.lin":6:31)
    %v0 = builtin.unrealized_conversion_cast %fa0 : () -> () to !llvm.ptr loc("tests/codegen/an_indirect_never_call_is_a_terminator.lin":6:31)
    llvm.store %v0, %s0 : !llvm.ptr, !llvm.ptr loc("tests/codegen/an_indirect_never_call_is_a_terminator.lin":6:5)
    %v2 = llvm.load %s0 : !llvm.ptr -> !llvm.ptr loc("tests/codegen/an_indirect_never_call_is_a_terminator.lin":7:5)
    llvm.call %v2() : !llvm.ptr, () -> () loc("tests/codegen/an_indirect_never_call_is_a_terminator.lin":7:5)
    llvm.unreachable loc("tests/codegen/an_indirect_never_call_is_a_terminator.lin":7:5)
  }
  func.func private @"lin.;halt"() attributes {llvm.linkage = #llvm.linkage<internal>, passthrough = ["noreturn", ["probe-stack", "inline-asm"]]} {
    cf.br ^b0
  ^b0:
    cf.br ^b1 loc("tests/codegen/an_indirect_never_call_is_a_terminator.lin":2:5)
  ^b1:
    %v1 = arith.constant 0 : i64 loc("tests/codegen/an_indirect_never_call_is_a_terminator.lin":2:10)
    cf.br ^b1 loc("tests/codegen/an_indirect_never_call_is_a_terminator.lin":2:5)
  }
  func.func @main(%argc: i32, %argv: !llvm.ptr) -> i32 {
    func.call @linea_set_args(%argc, %argv) : (i32, !llvm.ptr) -> ()
    %status = func.call @"lin.;main"() : () -> i64
    %status32 = arith.trunci %status : i64 to i32
    func.return %status32 : i32
  }
}
