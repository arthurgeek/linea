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
  llvm.mlir.global internal constant @linea_file0("tests/codegen/a_marker_emits_nothing.lin\00") : !llvm.array<41 x i8>
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
    cf.br ^b0
  ^b0:
    %v1 = arith.constant 0 : i64 loc("tests/codegen/a_marker_emits_nothing.lin":22:18)
    %v3 = arith.constant 1 : i64 loc("tests/codegen/a_marker_emits_nothing.lin":22:29)
    %iw4 = arith.trunci %v3 : i64 to i8 loc("tests/codegen/a_marker_emits_nothing.lin":22:18)
    llvm.store %iw4, %s0 : i8, !llvm.ptr loc("tests/codegen/a_marker_emits_nothing.lin":22:18)
    %v6 = arith.constant 0 : i64 loc("tests/codegen/a_marker_emits_nothing.lin":23:18)
    %v8 = arith.constant 1 : i64 loc("tests/codegen/a_marker_emits_nothing.lin":23:29)
    %iw9 = arith.trunci %v8 : i64 to i8 loc("tests/codegen/a_marker_emits_nothing.lin":23:18)
    llvm.store %iw9, %s1 : i8, !llvm.ptr loc("tests/codegen/a_marker_emits_nothing.lin":23:18)
    %v12 = func.call @"lin.Tag;;Same.alike"(%s0, %s1) : (!llvm.ptr, !llvm.ptr) -> i1 loc("tests/codegen/a_marker_emits_nothing.lin":24:8)
    cf.cond_br %v12, ^b1, ^b2 loc("tests/codegen/a_marker_emits_nothing.lin":24:5)
  ^b1:
    %v14 = arith.constant 0 : i64 loc("tests/codegen/a_marker_emits_nothing.lin":25:9)
    %sw15 = arith.trunci %v14 : i64 to i8 loc("tests/codegen/a_marker_emits_nothing.lin":24:5)
    llvm.store %sw15, %s2 : i8, !llvm.ptr loc("tests/codegen/a_marker_emits_nothing.lin":24:5)
    cf.br ^b3 loc("tests/codegen/a_marker_emits_nothing.lin":24:5)
  ^b2:
    %v17 = arith.constant 1 : i64 loc("tests/codegen/a_marker_emits_nothing.lin":27:9)
    %sw18 = arith.trunci %v17 : i64 to i8 loc("tests/codegen/a_marker_emits_nothing.lin":24:5)
    llvm.store %sw18, %s2 : i8, !llvm.ptr loc("tests/codegen/a_marker_emits_nothing.lin":24:5)
    cf.br ^b3 loc("tests/codegen/a_marker_emits_nothing.lin":24:5)
  ^b3:
    %lw20 = llvm.load %s2 : !llvm.ptr -> i8 loc("tests/codegen/a_marker_emits_nothing.lin":24:5)
    %v20 = arith.extui %lw20 : i8 to i64 loc("tests/codegen/a_marker_emits_nothing.lin":24:5)
    func.return %v20 : i64 loc("tests/codegen/a_marker_emits_nothing.lin":24:5)
  }
  func.func private @"lin.Tag;;Same.alike"(%a0: !llvm.ptr, %a1: !llvm.ptr) -> i1 attributes {llvm.linkage = #llvm.linkage<internal>} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x !llvm.ptr {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 1 : i64
    %s1 = llvm.alloca %z1 x !llvm.ptr {alignment = 8 : i64} : (i64) -> !llvm.ptr
    llvm.store %a0, %s0 : !llvm.ptr, !llvm.ptr
    llvm.store %a1, %s1 : !llvm.ptr, !llvm.ptr
    cf.br ^b0
  ^b0:
    %v0 = llvm.load %s0 : !llvm.ptr -> !llvm.ptr loc("tests/codegen/a_marker_emits_nothing.lin":15:9)
    %v1 = arith.constant 0 : i64 loc("tests/codegen/a_marker_emits_nothing.lin":15:9)
    %iw3 = llvm.load %v0 : !llvm.ptr -> i8 loc("tests/codegen/a_marker_emits_nothing.lin":15:9)
    %v3 = arith.extui %iw3 : i8 to i64 loc("tests/codegen/a_marker_emits_nothing.lin":15:9)
    %v4 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("tests/codegen/a_marker_emits_nothing.lin":15:23)
    %v5 = arith.constant 0 : i64 loc("tests/codegen/a_marker_emits_nothing.lin":15:23)
    %iw7 = llvm.load %v4 : !llvm.ptr -> i8 loc("tests/codegen/a_marker_emits_nothing.lin":15:23)
    %v7 = arith.extui %iw7 : i8 to i64 loc("tests/codegen/a_marker_emits_nothing.lin":15:23)
    %v8 = arith.cmpi eq, %v3, %v7 : i64 loc("tests/codegen/a_marker_emits_nothing.lin":15:9)
    func.return %v8 : i1 loc("tests/codegen/a_marker_emits_nothing.lin":15:9)
  }
  func.func @main(%argc: i32, %argv: !llvm.ptr) -> i32 {
    func.call @linea_set_args(%argc, %argv) : (i32, !llvm.ptr) -> ()
    %status = func.call @"lin.;main"() : () -> i64
    %status32 = arith.trunci %status : i64 to i32
    func.return %status32 : i32
  }
}
