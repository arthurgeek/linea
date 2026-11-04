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
  llvm.mlir.global internal constant @linea_file0("tests/projections/a_projection_is_the_path_it_names.lin\00") : !llvm.array<56 x i8>
  func.func private @linea_set_args(i32, !llvm.ptr)
  func.func private @linea_trap(i32, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @linea_panic(i64, i64, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @"lin.;main"() -> i64 attributes {llvm.linkage = #llvm.linkage<internal>, passthrough = [["probe-stack", "inline-asm"]]} {
    %z0 = arith.constant 4 : i64
    %s0 = llvm.alloca %z0 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    cf.br ^b0
  ^b0:
    %v1 = arith.constant 0 : i64 loc("tests/projections/a_projection_is_the_path_it_names.lin":18:19)
    %v3 = arith.constant 0 : i64 loc("tests/projections/a_projection_is_the_path_it_names.lin":18:30)
    %v5 = arith.constant 1 : i64 loc("tests/projections/a_projection_is_the_path_it_names.lin":18:31)
    %iw6 = arith.trunci %v5 : i64 to i8 loc("tests/projections/a_projection_is_the_path_it_names.lin":18:30)
    llvm.store %iw6, %s0 : i8, !llvm.ptr loc("tests/projections/a_projection_is_the_path_it_names.lin":18:30)
    %v7 = arith.constant 1 : i64 loc("tests/projections/a_projection_is_the_path_it_names.lin":18:30)
    %v8 = llvm.getelementptr %s0[%v7] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("tests/projections/a_projection_is_the_path_it_names.lin":18:30)
    %v9 = arith.constant 2 : i64 loc("tests/projections/a_projection_is_the_path_it_names.lin":18:34)
    %iw10 = arith.trunci %v9 : i64 to i8 loc("tests/projections/a_projection_is_the_path_it_names.lin":18:30)
    llvm.store %iw10, %v8 : i8, !llvm.ptr loc("tests/projections/a_projection_is_the_path_it_names.lin":18:30)
    %v11 = arith.constant 2 : i64 loc("tests/projections/a_projection_is_the_path_it_names.lin":18:30)
    %v12 = llvm.getelementptr %s0[%v11] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("tests/projections/a_projection_is_the_path_it_names.lin":18:30)
    %v13 = arith.constant 3 : i64 loc("tests/projections/a_projection_is_the_path_it_names.lin":18:37)
    %iw14 = arith.trunci %v13 : i64 to i8 loc("tests/projections/a_projection_is_the_path_it_names.lin":18:30)
    llvm.store %iw14, %v12 : i8, !llvm.ptr loc("tests/projections/a_projection_is_the_path_it_names.lin":18:30)
    %v15 = arith.constant 3 : i64 loc("tests/projections/a_projection_is_the_path_it_names.lin":18:30)
    %v16 = llvm.getelementptr %s0[%v15] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("tests/projections/a_projection_is_the_path_it_names.lin":18:30)
    %v17 = arith.constant 4 : i64 loc("tests/projections/a_projection_is_the_path_it_names.lin":18:40)
    %iw18 = arith.trunci %v17 : i64 to i8 loc("tests/projections/a_projection_is_the_path_it_names.lin":18:30)
    llvm.store %iw18, %v16 : i8, !llvm.ptr loc("tests/projections/a_projection_is_the_path_it_names.lin":18:30)
    %v20 = arith.constant 0 : i64 loc("tests/projections/a_projection_is_the_path_it_names.lin":19:5)
    %v22 = arith.constant 2 : i64 loc("tests/projections/a_projection_is_the_path_it_names.lin":19:5)
    %v23 = llvm.getelementptr %s0[%v22] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("tests/projections/a_projection_is_the_path_it_names.lin":19:5)
    %iw24 = llvm.load %v23 : !llvm.ptr -> i8 loc("tests/projections/a_projection_is_the_path_it_names.lin":19:5)
    %v24 = arith.extui %iw24 : i8 to i64 loc("tests/projections/a_projection_is_the_path_it_names.lin":19:5)
    func.return %v24 : i64 loc("tests/projections/a_projection_is_the_path_it_names.lin":19:5)
  }
  func.func @main(%argc: i32, %argv: !llvm.ptr) -> i32 {
    func.call @linea_set_args(%argc, %argv) : (i32, !llvm.ptr) -> ()
    %status = func.call @"lin.;main"() : () -> i64
    %status32 = arith.trunci %status : i64 to i32
    func.return %status32 : i32
  }
}
