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
  llvm.mlir.global internal constant @linea_file0("tests/library/an_export_reaches_its_private_implementation/main.lin\00") : !llvm.array<68 x i8>
  func.func private @linea_set_args(i32, !llvm.ptr)
  func.func private @linea_trap(i32, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @linea_panic(i64, i64, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @"lin.;api"(%a0: i64) -> i64 attributes {llvm.linkage = #llvm.linkage<internal>, passthrough = [["probe-stack", "inline-asm"]]} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x i32 {alignment = 4 : i64} : (i64) -> !llvm.ptr
    %pw0 = arith.trunci %a0 : i64 to i32
    llvm.store %pw0, %s0 : i32, !llvm.ptr
    cf.br ^b0
  ^b0:
    %lw0 = llvm.load %s0 : !llvm.ptr -> i32 loc("tests/library/an_export_reaches_its_private_implementation/main.lin":10:12)
    %v0 = arith.extsi %lw0 : i32 to i64 loc("tests/library/an_export_reaches_its_private_implementation/main.lin":10:12)
    %v1 = func.call @"lin.;helper"(%v0) : (i64) -> i64 loc("tests/library/an_export_reaches_its_private_implementation/main.lin":10:5)
    func.return %v1 : i64 loc("tests/library/an_export_reaches_its_private_implementation/main.lin":10:5)
  }
  func.func private @"lin.;helper"(%a0: i64) -> i64 attributes {llvm.linkage = #llvm.linkage<internal>, passthrough = [["probe-stack", "inline-asm"]]} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x i32 {alignment = 4 : i64} : (i64) -> !llvm.ptr
    %pw0 = arith.trunci %a0 : i64 to i32
    llvm.store %pw0, %s0 : i32, !llvm.ptr
    cf.br ^b0
  ^b0:
    %lw0 = llvm.load %s0 : !llvm.ptr -> i32 loc("tests/library/an_export_reaches_its_private_implementation/main.lin":2:5)
    %v0 = arith.extsi %lw0 : i32 to i64 loc("tests/library/an_export_reaches_its_private_implementation/main.lin":2:5)
    %v1 = arith.constant 1 : i64 loc("tests/library/an_export_reaches_its_private_implementation/main.lin":2:11)
    %v2 = arith.addi %v0, %v1 : i64 loc("tests/library/an_export_reaches_its_private_implementation/main.lin":2:5)
    %k1m = arith.constant 2147483647 : i64 loc("tests/library/an_export_reaches_its_private_implementation/main.lin":2:9)
    %k1 = arith.cmpi sgt, %v2, %k1m : i64 loc("tests/library/an_export_reaches_its_private_implementation/main.lin":2:9)
    cf.cond_br %k1, ^t1, ^c1 loc("tests/library/an_export_reaches_its_private_implementation/main.lin":2:9)
  ^t1:
    %tk1 = arith.constant 0 : i32 loc("tests/library/an_export_reaches_its_private_implementation/main.lin":2:9)
    %tf1 = llvm.mlir.addressof @linea_file0 : !llvm.ptr loc("tests/library/an_export_reaches_its_private_implementation/main.lin":2:9)
    %tl1 = arith.constant 2 : i32 loc("tests/library/an_export_reaches_its_private_implementation/main.lin":2:9)
    %tc1 = arith.constant 9 : i32 loc("tests/library/an_export_reaches_its_private_implementation/main.lin":2:9)
    func.call @linea_trap(%tk1, %tf1, %tl1, %tc1) : (i32, !llvm.ptr, i32, i32) -> () loc("tests/library/an_export_reaches_its_private_implementation/main.lin":2:9)
    llvm.unreachable loc("tests/library/an_export_reaches_its_private_implementation/main.lin":2:9)
  ^c1:
    %k2m = arith.constant -2147483648 : i64 loc("tests/library/an_export_reaches_its_private_implementation/main.lin":2:9)
    %k2 = arith.cmpi slt, %v2, %k2m : i64 loc("tests/library/an_export_reaches_its_private_implementation/main.lin":2:9)
    cf.cond_br %k2, ^t2, ^c2 loc("tests/library/an_export_reaches_its_private_implementation/main.lin":2:9)
  ^t2:
    %tk2 = arith.constant 0 : i32 loc("tests/library/an_export_reaches_its_private_implementation/main.lin":2:9)
    %tf2 = llvm.mlir.addressof @linea_file0 : !llvm.ptr loc("tests/library/an_export_reaches_its_private_implementation/main.lin":2:9)
    %tl2 = arith.constant 2 : i32 loc("tests/library/an_export_reaches_its_private_implementation/main.lin":2:9)
    %tc2 = arith.constant 9 : i32 loc("tests/library/an_export_reaches_its_private_implementation/main.lin":2:9)
    func.call @linea_trap(%tk2, %tf2, %tl2, %tc2) : (i32, !llvm.ptr, i32, i32) -> () loc("tests/library/an_export_reaches_its_private_implementation/main.lin":2:9)
    llvm.unreachable loc("tests/library/an_export_reaches_its_private_implementation/main.lin":2:9)
  ^c2:
    %p3 = arith.constant 0 : i64 loc("tests/library/an_export_reaches_its_private_implementation/main.lin":2:9)
    %v3 = arith.addi %v2, %p3 : i64 loc("tests/library/an_export_reaches_its_private_implementation/main.lin":2:9)
    func.return %v3 : i64 loc("tests/library/an_export_reaches_its_private_implementation/main.lin":2:5)
  }
  func.func @api(%p0: i32) -> i32 {
    %w0 = arith.extsi %p0 : i32 to i64
    %answer = func.call @"lin.;api"(%w0) : (i64) -> i64
    %narrow = arith.trunci %answer : i64 to i32
    func.return %narrow : i32
  }
}
