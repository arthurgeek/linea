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
  llvm.mlir.global internal constant @linea_file0("tests/codegen/a_slot_holds_what_the_binding_was_recorded_as.lin\00") : !llvm.array<64 x i8>
  func.func private @linea_set_args(i32, !llvm.ptr)
  func.func private @linea_trap(i32, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @linea_panic(i64, i64, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @"lin.;main"() -> i64 attributes {llvm.linkage = #llvm.linkage<internal>} {
    %z0 = arith.constant 24 : i64
    %s0 = llvm.alloca %z0 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 24 : i64
    %s1 = llvm.alloca %z1 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz15 = arith.constant 24 : i64
    %rs15 = llvm.alloca %rz15 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    cf.br ^b0
  ^b0:
    %v1 = arith.constant 0 : i64 loc("tests/codegen/a_slot_holds_what_the_binding_was_recorded_as.lin":19:18)
    %v3 = arith.constant 7 : i64 loc("tests/codegen/a_slot_holds_what_the_binding_was_recorded_as.lin":19:25)
    %iw4 = arith.trunci %v3 : i64 to i8 loc("tests/codegen/a_slot_holds_what_the_binding_was_recorded_as.lin":19:18)
    llvm.store %iw4, %s0 : i8, !llvm.ptr loc("tests/codegen/a_slot_holds_what_the_binding_was_recorded_as.lin":19:18)
    %v5 = arith.constant 8 : i64 loc("tests/codegen/a_slot_holds_what_the_binding_was_recorded_as.lin":19:18)
    %v6 = llvm.getelementptr %s0[%v5] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("tests/codegen/a_slot_holds_what_the_binding_was_recorded_as.lin":19:18)
    %v7 = arith.constant 1 : i64 loc("tests/codegen/a_slot_holds_what_the_binding_was_recorded_as.lin":19:32)
    llvm.store %v7, %v6 : i64, !llvm.ptr loc("tests/codegen/a_slot_holds_what_the_binding_was_recorded_as.lin":19:18)
    %v9 = arith.constant 16 : i64 loc("tests/codegen/a_slot_holds_what_the_binding_was_recorded_as.lin":19:18)
    %v10 = llvm.getelementptr %s0[%v9] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("tests/codegen/a_slot_holds_what_the_binding_was_recorded_as.lin":19:18)
    %v11 = arith.constant 2 : i64 loc("tests/codegen/a_slot_holds_what_the_binding_was_recorded_as.lin":19:39)
    llvm.store %v11, %v10 : i64, !llvm.ptr loc("tests/codegen/a_slot_holds_what_the_binding_was_recorded_as.lin":19:18)
    func.call @"lin.;f"(%rs15, %s0) : (!llvm.ptr, !llvm.ptr) -> () loc("tests/codegen/a_slot_holds_what_the_binding_was_recorded_as.lin":20:18)
    %cl16 = arith.constant 24 : i64 loc("tests/codegen/a_slot_holds_what_the_binding_was_recorded_as.lin":20:5)
    "llvm.intr.memcpy"(%s1, %rs15, %cl16) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("tests/codegen/a_slot_holds_what_the_binding_was_recorded_as.lin":20:5)
    %v18 = arith.constant 0 : i64 loc("tests/codegen/a_slot_holds_what_the_binding_was_recorded_as.lin":21:5)
    %iw20 = llvm.load %s1 : !llvm.ptr -> i8 loc("tests/codegen/a_slot_holds_what_the_binding_was_recorded_as.lin":21:5)
    %v20 = arith.extui %iw20 : i8 to i64 loc("tests/codegen/a_slot_holds_what_the_binding_was_recorded_as.lin":21:5)
    func.return %v20 : i64 loc("tests/codegen/a_slot_holds_what_the_binding_was_recorded_as.lin":21:5)
  }
  func.func private @"lin.;f"(%sret: !llvm.ptr, %a0: !llvm.ptr) attributes {llvm.linkage = #llvm.linkage<internal>} {
    %z0 = arith.constant 24 : i64
    %s0 = llvm.alloca %z0 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 24 : i64
    %s1 = llvm.alloca %z1 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %pl0 = arith.constant 24 : i64
    "llvm.intr.memcpy"(%s0, %a0, %pl0) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> ()
    cf.br ^b0
  ^b0:
    %rl1 = arith.constant 24 : i64 loc("tests/codegen/a_slot_holds_what_the_binding_was_recorded_as.lin":14:19)
    "llvm.intr.memcpy"(%sret, %s0, %rl1) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("tests/codegen/a_slot_holds_what_the_binding_was_recorded_as.lin":14:19)
    func.return loc("tests/codegen/a_slot_holds_what_the_binding_was_recorded_as.lin":14:19)
  }
  func.func @main(%argc: i32, %argv: !llvm.ptr) -> i32 {
    func.call @linea_set_args(%argc, %argv) : (i32, !llvm.ptr) -> ()
    %status = func.call @"lin.;main"() : () -> i64
    %status32 = arith.trunci %status : i64 to i32
    func.return %status32 : i32
  }
}
