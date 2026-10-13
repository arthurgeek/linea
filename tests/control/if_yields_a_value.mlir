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
  llvm.mlir.global internal constant @linea_file0("tests/control/if_yields_a_value.lin\00") : !llvm.array<36 x i8>
  func.func private @linea_set_args(i32, !llvm.ptr)
  func.func private @linea_trap(i32, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @linea_panic(i64, i64, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @"lin.;main"() -> i64 attributes {llvm.linkage = #llvm.linkage<internal>} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 1 : i64
    %s1 = llvm.alloca %z1 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    cf.br ^b0
  ^b0:
    %v0 = arith.constant 7 : i64 loc("tests/control/if_yields_a_value.lin":2:20)
    %sw1 = arith.trunci %v0 : i64 to i8 loc("tests/control/if_yields_a_value.lin":2:5)
    llvm.store %sw1, %s0 : i8, !llvm.ptr loc("tests/control/if_yields_a_value.lin":2:5)
    %lw2 = llvm.load %s0 : !llvm.ptr -> i8 loc("tests/control/if_yields_a_value.lin":3:8)
    %v2 = arith.extui %lw2 : i8 to i64 loc("tests/control/if_yields_a_value.lin":3:8)
    %v3 = arith.constant 5 : i64 loc("tests/control/if_yields_a_value.lin":3:12)
    %v4 = arith.cmpi ugt, %v2, %v3 : i64 loc("tests/control/if_yields_a_value.lin":3:8)
    cf.cond_br %v4, ^b1, ^b2 loc("tests/control/if_yields_a_value.lin":3:5)
  ^b1:
    %v6 = arith.constant 1 : i64 loc("tests/control/if_yields_a_value.lin":4:9)
    %sw7 = arith.trunci %v6 : i64 to i8 loc("tests/control/if_yields_a_value.lin":3:5)
    llvm.store %sw7, %s1 : i8, !llvm.ptr loc("tests/control/if_yields_a_value.lin":3:5)
    cf.br ^b3 loc("tests/control/if_yields_a_value.lin":3:5)
  ^b2:
    %v9 = arith.constant 2 : i64 loc("tests/control/if_yields_a_value.lin":6:9)
    %sw10 = arith.trunci %v9 : i64 to i8 loc("tests/control/if_yields_a_value.lin":3:5)
    llvm.store %sw10, %s1 : i8, !llvm.ptr loc("tests/control/if_yields_a_value.lin":3:5)
    cf.br ^b3 loc("tests/control/if_yields_a_value.lin":3:5)
  ^b3:
    %lw12 = llvm.load %s1 : !llvm.ptr -> i8 loc("tests/control/if_yields_a_value.lin":3:5)
    %v12 = arith.extui %lw12 : i8 to i64 loc("tests/control/if_yields_a_value.lin":3:5)
    func.return %v12 : i64 loc("tests/control/if_yields_a_value.lin":3:5)
  }
  func.func @main(%argc: i32, %argv: !llvm.ptr) -> i32 {
    func.call @linea_set_args(%argc, %argv) : (i32, !llvm.ptr) -> ()
    %status = func.call @"lin.;main"() : () -> i64
    %status32 = arith.trunci %status : i64 to i32
    func.return %status32 : i32
  }
}
