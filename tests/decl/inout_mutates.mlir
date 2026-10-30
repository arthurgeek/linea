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
  llvm.mlir.global internal constant @linea_file0("tests/decl/inout_mutates.lin\00") : !llvm.array<29 x i8>
  func.func private @linea_set_args(i32, !llvm.ptr)
  func.func private @linea_trap(i32, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @linea_panic(i64, i64, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @"lin.;main"() -> i64 attributes {llvm.linkage = #llvm.linkage<internal>, passthrough = [["probe-stack", "inline-asm"]]} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    cf.br ^b0
  ^b0:
    %v0 = arith.constant 1 : i64 loc("tests/decl/inout_mutates.lin":6:20)
    %sw1 = arith.trunci %v0 : i64 to i8 loc("tests/decl/inout_mutates.lin":6:5)
    llvm.store %sw1, %s0 : i8, !llvm.ptr loc("tests/decl/inout_mutates.lin":6:5)
    %v3 = arith.constant 20 : i64 loc("tests/decl/inout_mutates.lin":7:14)
    %v4 = func.call @"lin.;bump"(%s0, %v3) : (!llvm.ptr, i64) -> i64 loc("tests/decl/inout_mutates.lin":7:5)
    %v6 = arith.constant 21 : i64 loc("tests/decl/inout_mutates.lin":8:14)
    %v7 = func.call @"lin.;bump"(%s0, %v6) : (!llvm.ptr, i64) -> i64 loc("tests/decl/inout_mutates.lin":8:5)
    %lw8 = llvm.load %s0 : !llvm.ptr -> i8 loc("tests/decl/inout_mutates.lin":9:5)
    %v8 = arith.extui %lw8 : i8 to i64 loc("tests/decl/inout_mutates.lin":9:5)
    func.return %v8 : i64 loc("tests/decl/inout_mutates.lin":9:5)
  }
  func.func private @"lin.;bump"(%a0: !llvm.ptr, %a1: i64) -> i64 attributes {llvm.linkage = #llvm.linkage<internal>, passthrough = [["probe-stack", "inline-asm"]]} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x !llvm.ptr {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 1 : i64
    %s1 = llvm.alloca %z1 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    llvm.store %a0, %s0 : !llvm.ptr, !llvm.ptr
    %pw1 = arith.trunci %a1 : i64 to i8
    llvm.store %pw1, %s1 : i8, !llvm.ptr
    cf.br ^b0
  ^b0:
    %v0 = llvm.load %s0 : !llvm.ptr -> !llvm.ptr loc("tests/decl/inout_mutates.lin":2:9)
    %iw1 = llvm.load %v0 : !llvm.ptr -> i8 loc("tests/decl/inout_mutates.lin":2:9)
    %v1 = arith.extui %iw1 : i8 to i64 loc("tests/decl/inout_mutates.lin":2:9)
    %lw2 = llvm.load %s1 : !llvm.ptr -> i8 loc("tests/decl/inout_mutates.lin":2:13)
    %v2 = arith.extui %lw2 : i8 to i64 loc("tests/decl/inout_mutates.lin":2:13)
    %v3 = arith.addi %v1, %v2 : i64 loc("tests/decl/inout_mutates.lin":2:9)
    %k1m = arith.constant 255 : i64 loc("tests/decl/inout_mutates.lin":2:11)
    %k1 = arith.cmpi ugt, %v3, %k1m : i64 loc("tests/decl/inout_mutates.lin":2:11)
    cf.cond_br %k1, ^t1, ^c1 loc("tests/decl/inout_mutates.lin":2:11)
  ^t1:
    %tk1 = arith.constant 0 : i32 loc("tests/decl/inout_mutates.lin":2:11)
    %tf1 = llvm.mlir.addressof @linea_file0 : !llvm.ptr loc("tests/decl/inout_mutates.lin":2:11)
    %tl1 = arith.constant 2 : i32 loc("tests/decl/inout_mutates.lin":2:11)
    %tc1 = arith.constant 11 : i32 loc("tests/decl/inout_mutates.lin":2:11)
    func.call @linea_trap(%tk1, %tf1, %tl1, %tc1) : (i32, !llvm.ptr, i32, i32) -> () loc("tests/decl/inout_mutates.lin":2:11)
    llvm.unreachable loc("tests/decl/inout_mutates.lin":2:11)
  ^c1:
    %p4 = arith.constant 0 : i64 loc("tests/decl/inout_mutates.lin":2:11)
    %v4 = arith.addi %v3, %p4 : i64 loc("tests/decl/inout_mutates.lin":2:11)
    %v5 = llvm.load %s0 : !llvm.ptr -> !llvm.ptr loc("tests/decl/inout_mutates.lin":2:5)
    %iw6 = arith.trunci %v4 : i64 to i8 loc("tests/decl/inout_mutates.lin":2:5)
    llvm.store %iw6, %v5 : i8, !llvm.ptr loc("tests/decl/inout_mutates.lin":2:5)
    %v7 = arith.constant 0 : i64 loc("tests/decl/inout_mutates.lin":2:5)
    func.return %v7 : i64 loc("tests/decl/inout_mutates.lin":2:5)
  }
  func.func @main(%argc: i32, %argv: !llvm.ptr) -> i32 {
    func.call @linea_set_args(%argc, %argv) : (i32, !llvm.ptr) -> ()
    %status = func.call @"lin.;main"() : () -> i64
    %status32 = arith.trunci %status : i64 to i32
    func.return %status32 : i32
  }
}
