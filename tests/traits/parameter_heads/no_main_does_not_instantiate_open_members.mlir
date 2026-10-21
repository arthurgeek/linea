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
  llvm.mlir.global internal constant @linea_file0("tests/traits/parameter_heads/no_main_does_not_instantiate_open_members/main.lin\00") : !llvm.array<80 x i8>
  func.func private @linea_set_args(i32, !llvm.ptr)
  func.func private @linea_trap(i32, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @linea_panic(i64, i64, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @"lin.;retain"(%a0: i64) -> i64 attributes {llvm.linkage = #llvm.linkage<internal>} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %pw0 = arith.trunci %a0 : i64 to i8
    llvm.store %pw0, %s0 : i8, !llvm.ptr
    cf.br ^b0
  ^b0:
    %lw0 = llvm.load %s0 : !llvm.ptr -> i8 loc("tests/traits/parameter_heads/no_main_does_not_instantiate_open_members/main.lin":12:5)
    %v0 = arith.extui %lw0 : i8 to i64 loc("tests/traits/parameter_heads/no_main_does_not_instantiate_open_members/main.lin":12:5)
    %v1 = func.call @"lin.UInt8;;Identity.identity"(%v0) : (i64) -> i64 loc("tests/traits/parameter_heads/no_main_does_not_instantiate_open_members/main.lin":12:5)
    func.return %v1 : i64 loc("tests/traits/parameter_heads/no_main_does_not_instantiate_open_members/main.lin":12:5)
  }
  func.func private @"lin.UInt8;;Identity.identity"(%a0: i64) -> i64 attributes {llvm.linkage = #llvm.linkage<internal>} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %pw0 = arith.trunci %a0 : i64 to i8
    llvm.store %pw0, %s0 : i8, !llvm.ptr
    cf.br ^b0
  ^b0:
    %lw0 = llvm.load %s0 : !llvm.ptr -> i8 loc("tests/traits/parameter_heads/no_main_does_not_instantiate_open_members/main.lin":7:9)
    %v0 = arith.extui %lw0 : i8 to i64 loc("tests/traits/parameter_heads/no_main_does_not_instantiate_open_members/main.lin":7:9)
    func.return %v0 : i64 loc("tests/traits/parameter_heads/no_main_does_not_instantiate_open_members/main.lin":7:9)
  }
  func.func @retain(%p0: i8 {llvm.zeroext}) -> (i8 {llvm.zeroext}) {
    %w0 = arith.extui %p0 : i8 to i64
    %answer = func.call @"lin.;retain"(%w0) : (i64) -> i64
    %narrow = arith.trunci %answer : i64 to i8
    func.return %narrow : i8
  }
}
