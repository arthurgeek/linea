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
  llvm.mlir.global internal constant @linea_file0("tests/traits/a_trait_slot_is_not_an_argument_slot.lin\00") : !llvm.array<54 x i8>
  func.func private @linea_set_args(i32, !llvm.ptr)
  func.func private @linea_trap(i32, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @linea_panic(i64, i64, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @"lin.;main"() -> i64 attributes {llvm.linkage = #llvm.linkage<internal>, passthrough = [["probe-stack", "inline-asm"]]} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 1 : i64
    %s1 = llvm.alloca %z1 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    cf.br ^b0
  ^b0:
    %v1 = arith.constant 0 : i64 loc("tests/traits/a_trait_slot_is_not_an_argument_slot.lin":36:19)
    %v3 = arith.constant 1 : i64 loc("tests/traits/a_trait_slot_is_not_an_argument_slot.lin":36:26)
    %iw4 = arith.trunci %v3 : i64 to i8 loc("tests/traits/a_trait_slot_is_not_an_argument_slot.lin":36:19)
    llvm.store %iw4, %s0 : i8, !llvm.ptr loc("tests/traits/a_trait_slot_is_not_an_argument_slot.lin":36:19)
    %v6 = arith.constant 0 : i64 loc("tests/traits/a_trait_slot_is_not_an_argument_slot.lin":37:17)
    %v8 = arith.constant 2 : i64 loc("tests/traits/a_trait_slot_is_not_an_argument_slot.lin":37:24)
    %iw9 = arith.trunci %v8 : i64 to i8 loc("tests/traits/a_trait_slot_is_not_an_argument_slot.lin":37:17)
    llvm.store %iw9, %s1 : i8, !llvm.ptr loc("tests/traits/a_trait_slot_is_not_an_argument_slot.lin":37:17)
    %v12 = func.call @"lin.;Cell._1[_2]"(%s0, %s1) : (!llvm.ptr, !llvm.ptr) -> i64 loc("tests/traits/a_trait_slot_is_not_an_argument_slot.lin":38:5)
    %v14 = func.call @"lin.Cell;;_1._2"(%s0) : (!llvm.ptr) -> i64 loc("tests/traits/a_trait_slot_is_not_an_argument_slot.lin":38:21)
    %v15 = arith.addi %v12, %v14 : i64 loc("tests/traits/a_trait_slot_is_not_an_argument_slot.lin":38:5)
    %k1m = arith.constant 255 : i64 loc("tests/traits/a_trait_slot_is_not_an_argument_slot.lin":38:19)
    %k1 = arith.cmpi ugt, %v15, %k1m : i64 loc("tests/traits/a_trait_slot_is_not_an_argument_slot.lin":38:19)
    cf.cond_br %k1, ^t1, ^c1 loc("tests/traits/a_trait_slot_is_not_an_argument_slot.lin":38:19)
  ^t1:
    %tk1 = arith.constant 0 : i32 loc("tests/traits/a_trait_slot_is_not_an_argument_slot.lin":38:19)
    %tf1 = llvm.mlir.addressof @linea_file0 : !llvm.ptr loc("tests/traits/a_trait_slot_is_not_an_argument_slot.lin":38:19)
    %tl1 = arith.constant 38 : i32 loc("tests/traits/a_trait_slot_is_not_an_argument_slot.lin":38:19)
    %tc1 = arith.constant 19 : i32 loc("tests/traits/a_trait_slot_is_not_an_argument_slot.lin":38:19)
    func.call @linea_trap(%tk1, %tf1, %tl1, %tc1) : (i32, !llvm.ptr, i32, i32) -> () loc("tests/traits/a_trait_slot_is_not_an_argument_slot.lin":38:19)
    llvm.unreachable loc("tests/traits/a_trait_slot_is_not_an_argument_slot.lin":38:19)
  ^c1:
    %p16 = arith.constant 0 : i64 loc("tests/traits/a_trait_slot_is_not_an_argument_slot.lin":38:19)
    %v16 = arith.addi %v15, %p16 : i64 loc("tests/traits/a_trait_slot_is_not_an_argument_slot.lin":38:19)
    %v17 = arith.constant 2 : i64 loc("tests/traits/a_trait_slot_is_not_an_argument_slot.lin":38:32)
    %v18 = arith.subi %v16, %v17 : i64 loc("tests/traits/a_trait_slot_is_not_an_argument_slot.lin":38:5)
    %k2m = arith.constant 255 : i64 loc("tests/traits/a_trait_slot_is_not_an_argument_slot.lin":38:30)
    %k2 = arith.cmpi ugt, %v18, %k2m : i64 loc("tests/traits/a_trait_slot_is_not_an_argument_slot.lin":38:30)
    cf.cond_br %k2, ^t2, ^c2 loc("tests/traits/a_trait_slot_is_not_an_argument_slot.lin":38:30)
  ^t2:
    %tk2 = arith.constant 0 : i32 loc("tests/traits/a_trait_slot_is_not_an_argument_slot.lin":38:30)
    %tf2 = llvm.mlir.addressof @linea_file0 : !llvm.ptr loc("tests/traits/a_trait_slot_is_not_an_argument_slot.lin":38:30)
    %tl2 = arith.constant 38 : i32 loc("tests/traits/a_trait_slot_is_not_an_argument_slot.lin":38:30)
    %tc2 = arith.constant 30 : i32 loc("tests/traits/a_trait_slot_is_not_an_argument_slot.lin":38:30)
    func.call @linea_trap(%tk2, %tf2, %tl2, %tc2) : (i32, !llvm.ptr, i32, i32) -> () loc("tests/traits/a_trait_slot_is_not_an_argument_slot.lin":38:30)
    llvm.unreachable loc("tests/traits/a_trait_slot_is_not_an_argument_slot.lin":38:30)
  ^c2:
    %p19 = arith.constant 0 : i64 loc("tests/traits/a_trait_slot_is_not_an_argument_slot.lin":38:30)
    %v19 = arith.addi %v18, %p19 : i64 loc("tests/traits/a_trait_slot_is_not_an_argument_slot.lin":38:30)
    func.return %v19 : i64 loc("tests/traits/a_trait_slot_is_not_an_argument_slot.lin":38:5)
  }
  func.func private @"lin.;Cell._1[_2]"(%a0: !llvm.ptr, %a1: !llvm.ptr) -> i64 attributes {llvm.linkage = #llvm.linkage<internal>, passthrough = [["probe-stack", "inline-asm"]]} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x !llvm.ptr {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 1 : i64
    %s1 = llvm.alloca %z1 x !llvm.ptr {alignment = 8 : i64} : (i64) -> !llvm.ptr
    llvm.store %a0, %s0 : !llvm.ptr, !llvm.ptr
    llvm.store %a1, %s1 : !llvm.ptr, !llvm.ptr
    cf.br ^b0
  ^b0:
    %v0 = llvm.load %s0 : !llvm.ptr -> !llvm.ptr loc("tests/traits/a_trait_slot_is_not_an_argument_slot.lin":25:9)
    %v1 = arith.constant 0 : i64 loc("tests/traits/a_trait_slot_is_not_an_argument_slot.lin":25:9)
    %iw3 = llvm.load %v0 : !llvm.ptr -> i8 loc("tests/traits/a_trait_slot_is_not_an_argument_slot.lin":25:9)
    %v3 = arith.extui %iw3 : i8 to i64 loc("tests/traits/a_trait_slot_is_not_an_argument_slot.lin":25:9)
    func.return %v3 : i64 loc("tests/traits/a_trait_slot_is_not_an_argument_slot.lin":25:9)
  }
  func.func private @"lin.Cell;;_1._2"(%a0: !llvm.ptr) -> i64 attributes {llvm.linkage = #llvm.linkage<internal>, passthrough = [["probe-stack", "inline-asm"]]} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x !llvm.ptr {alignment = 8 : i64} : (i64) -> !llvm.ptr
    llvm.store %a0, %s0 : !llvm.ptr, !llvm.ptr
    cf.br ^b0
  ^b0:
    %v0 = llvm.load %s0 : !llvm.ptr -> !llvm.ptr loc("tests/traits/a_trait_slot_is_not_an_argument_slot.lin":31:9)
    %v1 = arith.constant 0 : i64 loc("tests/traits/a_trait_slot_is_not_an_argument_slot.lin":31:9)
    %iw3 = llvm.load %v0 : !llvm.ptr -> i8 loc("tests/traits/a_trait_slot_is_not_an_argument_slot.lin":31:9)
    %v3 = arith.extui %iw3 : i8 to i64 loc("tests/traits/a_trait_slot_is_not_an_argument_slot.lin":31:9)
    func.return %v3 : i64 loc("tests/traits/a_trait_slot_is_not_an_argument_slot.lin":31:9)
  }
  func.func @main(%argc: i32, %argv: !llvm.ptr) -> i32 {
    func.call @linea_set_args(%argc, %argv) : (i32, !llvm.ptr) -> ()
    %status = func.call @"lin.;main"() : () -> i64
    %status32 = arith.trunci %status : i64 to i32
    func.return %status32 : i32
  }
}
