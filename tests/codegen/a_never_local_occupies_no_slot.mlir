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
  llvm.mlir.global internal constant @linea_file0("tests/codegen/a_never_local_occupies_no_slot.lin\00") : !llvm.array<49 x i8>
  llvm.mlir.global internal constant @linea_str0("stop") : !llvm.array<4 x i8>
  func.func private @linea_set_args(i32, !llvm.ptr)
  func.func private @linea_trap(i32, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @linea_panic(i64, i64, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @"lin.;main"() -> i64 attributes {llvm.linkage = #llvm.linkage<internal>} {
    %z0 = arith.constant 16 : i64
    %s0 = llvm.alloca %z0 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    cf.br ^b0
  ^b0:
    %ba1 = llvm.mlir.addressof @linea_str0 : !llvm.ptr loc("tests/codegen/a_never_local_occupies_no_slot.lin":2:31)
    %v1 = llvm.ptrtoint %ba1 : !llvm.ptr to i64 loc("tests/codegen/a_never_local_occupies_no_slot.lin":2:31)
    %v2 = arith.constant 0 : i64 loc("tests/codegen/a_never_local_occupies_no_slot.lin":2:31)
    llvm.store %v1, %s0 : i64, !llvm.ptr loc("tests/codegen/a_never_local_occupies_no_slot.lin":2:31)
    %v5 = arith.constant 4 : i64 loc("tests/codegen/a_never_local_occupies_no_slot.lin":2:31)
    %v6 = arith.constant 8 : i64 loc("tests/codegen/a_never_local_occupies_no_slot.lin":2:31)
    %v7 = llvm.getelementptr %s0[%v6] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("tests/codegen/a_never_local_occupies_no_slot.lin":2:31)
    llvm.store %v5, %v7 : i64, !llvm.ptr loc("tests/codegen/a_never_local_occupies_no_slot.lin":2:31)
    %poa1 = arith.constant 0 : i64 loc("tests/codegen/a_never_local_occupies_no_slot.lin":2:25)
    %ppa1 = llvm.getelementptr %s0[%poa1] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("tests/codegen/a_never_local_occupies_no_slot.lin":2:25)
    %pva1 = llvm.load %ppa1 : !llvm.ptr -> i64 loc("tests/codegen/a_never_local_occupies_no_slot.lin":2:25)
    %pol1 = arith.constant 8 : i64 loc("tests/codegen/a_never_local_occupies_no_slot.lin":2:25)
    %ppl1 = llvm.getelementptr %s0[%pol1] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("tests/codegen/a_never_local_occupies_no_slot.lin":2:25)
    %pvl1 = llvm.load %ppl1 : !llvm.ptr -> i64 loc("tests/codegen/a_never_local_occupies_no_slot.lin":2:25)
    %pf1 = llvm.mlir.addressof @linea_file0 : !llvm.ptr loc("tests/codegen/a_never_local_occupies_no_slot.lin":2:25)
    %tl1 = arith.constant 2 : i32 loc("tests/codegen/a_never_local_occupies_no_slot.lin":2:25)
    %tc1 = arith.constant 25 : i32 loc("tests/codegen/a_never_local_occupies_no_slot.lin":2:25)
    func.call @linea_panic(%pva1, %pvl1, %pf1, %tl1, %tc1) : (i64, i64, !llvm.ptr, i32, i32) -> () loc("tests/codegen/a_never_local_occupies_no_slot.lin":2:25)
    llvm.unreachable loc("tests/codegen/a_never_local_occupies_no_slot.lin":2:25)
  }
  func.func @main(%argc: i32, %argv: !llvm.ptr) -> i32 {
    func.call @linea_set_args(%argc, %argv) : (i32, !llvm.ptr) -> ()
    %status = func.call @"lin.;main"() : () -> i64
    %status32 = arith.trunci %status : i64 to i32
    func.return %status32 : i32
  }
}
