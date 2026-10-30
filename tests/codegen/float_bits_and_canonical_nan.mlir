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
  llvm.mlir.global internal constant @linea_file0("tests/codegen/float_bits_and_canonical_nan.lin\00") : !llvm.array<47 x i8>
  llvm.mlir.global internal constant @linea_file1("std/scalar/float.lin\00") : !llvm.array<21 x i8>
  llvm.mlir.global internal constant @linea_file2("std/mem/float.lin\00") : !llvm.array<18 x i8>
  func.func private @linea_set_args(i32, !llvm.ptr)
  func.func private @linea_trap(i32, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @linea_panic(i64, i64, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @"lin.;main"() -> i64 attributes {llvm.linkage = #llvm.linkage<internal>, passthrough = [["probe-stack", "inline-asm"]]} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    cf.br ^b0
  ^b0:
    %v0 = arith.constant 0x0 : f64 loc("tests/codegen/float_bits_and_canonical_nan.lin":10:25)
    %v1 = arith.constant 0x0 : f64 loc("tests/codegen/float_bits_and_canonical_nan.lin":10:30)
    %v2 = func.call @"lin.;quotient"(%v0, %v1) : (f64, f64) -> f64 loc("tests/codegen/float_bits_and_canonical_nan.lin":10:16)
    %v3 = func.call @"lin.;flipped"(%v2) : (f64) -> i64 loc("tests/codegen/float_bits_and_canonical_nan.lin":10:8)
    %v4 = arith.constant 0 : i64 loc("tests/codegen/float_bits_and_canonical_nan.lin":10:56)
    %v5 = func.call @"lin.std.scalar;Float64.from_bits"(%v4) : (i64) -> f64 loc("tests/codegen/float_bits_and_canonical_nan.lin":10:38)
    %v6 = func.call @"lin.std.scalar;Float64.to_bits"(%v5) : (f64) -> i64 loc("tests/codegen/float_bits_and_canonical_nan.lin":10:38)
    %v7 = arith.cmpi ugt, %v3, %v6 : i64 loc("tests/codegen/float_bits_and_canonical_nan.lin":10:8)
    cf.cond_br %v7, ^b1, ^b2 loc("tests/codegen/float_bits_and_canonical_nan.lin":10:5)
  ^b1:
    %v9 = arith.constant 0 : i64 loc("tests/codegen/float_bits_and_canonical_nan.lin":11:9)
    %sw10 = arith.trunci %v9 : i64 to i8 loc("tests/codegen/float_bits_and_canonical_nan.lin":10:5)
    llvm.store %sw10, %s0 : i8, !llvm.ptr loc("tests/codegen/float_bits_and_canonical_nan.lin":10:5)
    cf.br ^b3 loc("tests/codegen/float_bits_and_canonical_nan.lin":10:5)
  ^b2:
    %v12 = arith.constant 1 : i64 loc("tests/codegen/float_bits_and_canonical_nan.lin":13:9)
    %sw13 = arith.trunci %v12 : i64 to i8 loc("tests/codegen/float_bits_and_canonical_nan.lin":10:5)
    llvm.store %sw13, %s0 : i8, !llvm.ptr loc("tests/codegen/float_bits_and_canonical_nan.lin":10:5)
    cf.br ^b3 loc("tests/codegen/float_bits_and_canonical_nan.lin":10:5)
  ^b3:
    %lw15 = llvm.load %s0 : !llvm.ptr -> i8 loc("tests/codegen/float_bits_and_canonical_nan.lin":10:5)
    %v15 = arith.extui %lw15 : i8 to i64 loc("tests/codegen/float_bits_and_canonical_nan.lin":10:5)
    func.return %v15 : i64 loc("tests/codegen/float_bits_and_canonical_nan.lin":10:5)
  }
  func.func private @"lin.;quotient"(%a0: f64, %a1: f64) -> f64 attributes {llvm.linkage = #llvm.linkage<internal>, passthrough = [["probe-stack", "inline-asm"]]} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x f64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 1 : i64
    %s1 = llvm.alloca %z1 x f64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    llvm.store %a0, %s0 : f64, !llvm.ptr
    llvm.store %a1, %s1 : f64, !llvm.ptr
    cf.br ^b0
  ^b0:
    %v0 = llvm.load %s0 : !llvm.ptr -> f64 loc("tests/codegen/float_bits_and_canonical_nan.lin":2:5)
    %v1 = llvm.load %s1 : !llvm.ptr -> f64 loc("tests/codegen/float_bits_and_canonical_nan.lin":2:12)
    %nr2 = arith.divf %v0, %v1 : f64 loc("tests/codegen/float_bits_and_canonical_nan.lin":2:5)
    %nu2 = arith.cmpf uno, %nr2, %nr2 : f64 loc("tests/codegen/float_bits_and_canonical_nan.lin":2:5)
    %nq2 = arith.constant 0x7FF8000000000000 : f64 loc("tests/codegen/float_bits_and_canonical_nan.lin":2:5)
    %v2 = arith.select %nu2, %nq2, %nr2 : f64 loc("tests/codegen/float_bits_and_canonical_nan.lin":2:5)
    func.return %v2 : f64 loc("tests/codegen/float_bits_and_canonical_nan.lin":2:5)
  }
  func.func private @"lin.;flipped"(%a0: f64) -> i64 attributes {llvm.linkage = #llvm.linkage<internal>, passthrough = [["probe-stack", "inline-asm"]]} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x f64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    llvm.store %a0, %s0 : f64, !llvm.ptr
    cf.br ^b0
  ^b0:
    %v0 = llvm.load %s0 : !llvm.ptr -> f64 loc("tests/codegen/float_bits_and_canonical_nan.lin":6:7)
    %v1 = arith.negf %v0 : f64 loc("tests/codegen/float_bits_and_canonical_nan.lin":6:6)
    %v2 = func.call @"lin.std.scalar;Float64.to_bits"(%v1) : (f64) -> i64 loc("tests/codegen/float_bits_and_canonical_nan.lin":6:5)
    func.return %v2 : i64 loc("tests/codegen/float_bits_and_canonical_nan.lin":6:5)
  }
  func.func private @"lin.std.scalar;Float64.from_bits"(%a0: i64) -> f64 attributes {llvm.linkage = #llvm.linkage<internal>, passthrough = [["probe-stack", "inline-asm"]]} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    llvm.store %a0, %s0 : i64, !llvm.ptr
    cf.br ^b0
  ^b0:
    %v0 = llvm.load %s0 : !llvm.ptr -> i64 loc("std/scalar/float.lin":L:C)
    %v1 = func.call @"lin.std.mem;float64_from_bits"(%v0) : (i64) -> f64 loc("std/scalar/float.lin":L:C)
    func.return %v1 : f64 loc("std/scalar/float.lin":L:C)
  }
  func.func private @"lin.std.scalar;Float64.to_bits"(%a0: f64) -> i64 attributes {llvm.linkage = #llvm.linkage<internal>, passthrough = [["probe-stack", "inline-asm"]]} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x f64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    llvm.store %a0, %s0 : f64, !llvm.ptr
    cf.br ^b0
  ^b0:
    %v0 = llvm.load %s0 : !llvm.ptr -> f64 loc("std/scalar/float.lin":L:C)
    %v1 = func.call @"lin.std.mem;float64_to_bits"(%v0) : (f64) -> i64 loc("std/scalar/float.lin":L:C)
    func.return %v1 : i64 loc("std/scalar/float.lin":L:C)
  }
  func.func private @"lin.std.mem;float64_from_bits"(%a0: i64) -> f64 attributes {llvm.linkage = #llvm.linkage<internal>, passthrough = [["probe-stack", "inline-asm"]]} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    llvm.store %a0, %s0 : i64, !llvm.ptr
    cf.br ^b0
  ^b0:
    %v0 = llvm.load %s0 : !llvm.ptr -> i64 loc("std/mem/float.lin":L:C)
    %v1 = arith.bitcast %v0 : i64 to f64 loc("std/mem/float.lin":L:C)
    func.return %v1 : f64 loc("std/mem/float.lin":L:C)
  }
  func.func private @"lin.std.mem;float64_to_bits"(%a0: f64) -> i64 attributes {llvm.linkage = #llvm.linkage<internal>, passthrough = [["probe-stack", "inline-asm"]]} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x f64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    llvm.store %a0, %s0 : f64, !llvm.ptr
    cf.br ^b0
  ^b0:
    %v0 = llvm.load %s0 : !llvm.ptr -> f64 loc("std/mem/float.lin":L:C)
    %v1 = arith.bitcast %v0 : f64 to i64 loc("std/mem/float.lin":L:C)
    func.return %v1 : i64 loc("std/mem/float.lin":L:C)
  }
  func.func @main(%argc: i32, %argv: !llvm.ptr) -> i32 {
    func.call @linea_set_args(%argc, %argv) : (i32, !llvm.ptr) -> ()
    %status = func.call @"lin.;main"() : () -> i64
    %status32 = arith.trunci %status : i64 to i32
    func.return %status32 : i32
  }
}
