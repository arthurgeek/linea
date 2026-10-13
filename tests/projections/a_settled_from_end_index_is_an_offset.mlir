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
  llvm.mlir.global internal constant @linea_file0("tests/projections/a_settled_from_end_index_is_an_offset.lin\00") : !llvm.array<60 x i8>
  func.func private @linea_set_args(i32, !llvm.ptr)
  func.func private @linea_trap(i32, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @linea_panic(i64, i64, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @"lin.;main"() -> i64 attributes {llvm.linkage = #llvm.linkage<internal>} {
    %z0 = arith.constant 4 : i64
    %s0 = llvm.alloca %z0 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    cf.br ^b0
  ^b0:
    %v1 = arith.constant 0 : i64 loc("tests/projections/a_settled_from_end_index_is_an_offset.lin":6:25)
    %v3 = arith.constant 1 : i64 loc("tests/projections/a_settled_from_end_index_is_an_offset.lin":6:26)
    %iw4 = arith.trunci %v3 : i64 to i8 loc("tests/projections/a_settled_from_end_index_is_an_offset.lin":6:25)
    llvm.store %iw4, %s0 : i8, !llvm.ptr loc("tests/projections/a_settled_from_end_index_is_an_offset.lin":6:25)
    %v5 = arith.constant 1 : i64 loc("tests/projections/a_settled_from_end_index_is_an_offset.lin":6:25)
    %v6 = llvm.getelementptr %s0[%v5] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("tests/projections/a_settled_from_end_index_is_an_offset.lin":6:25)
    %v7 = arith.constant 2 : i64 loc("tests/projections/a_settled_from_end_index_is_an_offset.lin":6:29)
    %iw8 = arith.trunci %v7 : i64 to i8 loc("tests/projections/a_settled_from_end_index_is_an_offset.lin":6:25)
    llvm.store %iw8, %v6 : i8, !llvm.ptr loc("tests/projections/a_settled_from_end_index_is_an_offset.lin":6:25)
    %v9 = arith.constant 2 : i64 loc("tests/projections/a_settled_from_end_index_is_an_offset.lin":6:25)
    %v10 = llvm.getelementptr %s0[%v9] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("tests/projections/a_settled_from_end_index_is_an_offset.lin":6:25)
    %v11 = arith.constant 3 : i64 loc("tests/projections/a_settled_from_end_index_is_an_offset.lin":6:32)
    %iw12 = arith.trunci %v11 : i64 to i8 loc("tests/projections/a_settled_from_end_index_is_an_offset.lin":6:25)
    llvm.store %iw12, %v10 : i8, !llvm.ptr loc("tests/projections/a_settled_from_end_index_is_an_offset.lin":6:25)
    %v13 = arith.constant 3 : i64 loc("tests/projections/a_settled_from_end_index_is_an_offset.lin":6:25)
    %v14 = llvm.getelementptr %s0[%v13] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("tests/projections/a_settled_from_end_index_is_an_offset.lin":6:25)
    %v15 = arith.constant 4 : i64 loc("tests/projections/a_settled_from_end_index_is_an_offset.lin":6:35)
    %iw16 = arith.trunci %v15 : i64 to i8 loc("tests/projections/a_settled_from_end_index_is_an_offset.lin":6:25)
    llvm.store %iw16, %v14 : i8, !llvm.ptr loc("tests/projections/a_settled_from_end_index_is_an_offset.lin":6:25)
    %v18 = arith.constant 2 : i64 loc("tests/projections/a_settled_from_end_index_is_an_offset.lin":7:5)
    %v19 = llvm.getelementptr %s0[%v18] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("tests/projections/a_settled_from_end_index_is_an_offset.lin":7:5)
    %iw20 = llvm.load %v19 : !llvm.ptr -> i8 loc("tests/projections/a_settled_from_end_index_is_an_offset.lin":7:5)
    %v20 = arith.extui %iw20 : i8 to i64 loc("tests/projections/a_settled_from_end_index_is_an_offset.lin":7:5)
    func.return %v20 : i64 loc("tests/projections/a_settled_from_end_index_is_an_offset.lin":7:5)
  }
  func.func @main(%argc: i32, %argv: !llvm.ptr) -> i32 {
    func.call @linea_set_args(%argc, %argv) : (i32, !llvm.ptr) -> ()
    %status = func.call @"lin.;main"() : () -> i64
    %status32 = arith.trunci %status : i64 to i32
    func.return %status32 : i32
  }
}
