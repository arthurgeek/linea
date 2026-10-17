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
  llvm.mlir.global internal constant @linea_file0("tests/codegen/float32_lowers_to_f32.lin\00") : !llvm.array<40 x i8>
  func.func private @linea_set_args(i32, !llvm.ptr)
  func.func private @linea_trap(i32, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @linea_panic(i64, i64, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @"lin.;main"() -> i64 attributes {llvm.linkage = #llvm.linkage<internal>} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x f32 {alignment = 4 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 1 : i64
    %s1 = llvm.alloca %z1 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z2 = arith.constant 1 : i64
    %s2 = llvm.alloca %z2 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    cf.br ^b0
  ^b0:
    %v0 = arith.constant 0x3F800000 : f32 loc("tests/codegen/float32_lowers_to_f32.lin":14:21)
    %v1 = arith.constant 0x40000000 : f32 loc("tests/codegen/float32_lowers_to_f32.lin":14:26)
    %v2 = func.call @"lin.;mix"(%v0, %v1) : (f32, f32) -> f32 loc("tests/codegen/float32_lowers_to_f32.lin":14:17)
    llvm.store %v2, %s0 : f32, !llvm.ptr loc("tests/codegen/float32_lowers_to_f32.lin":14:5)
    %v4 = llvm.load %s0 : !llvm.ptr -> f32 loc("tests/codegen/float32_lowers_to_f32.lin":15:14)
    %v5 = func.call @"lin.;widen"(%v4) : (f32) -> f64 loc("tests/codegen/float32_lowers_to_f32.lin":15:8)
    %v6 = arith.constant 0x4004000000000000 : f64 loc("tests/codegen/float32_lowers_to_f32.lin":15:24)
    %v7 = arith.cmpf oeq, %v5, %v6 : f64 loc("tests/codegen/float32_lowers_to_f32.lin":15:8)
    cf.cond_br %v7, ^b1, ^b2 loc("tests/codegen/float32_lowers_to_f32.lin":15:8)
  ^b1:
    %v9 = arith.constant 0x4004000000000000 : f64 loc("tests/codegen/float32_lowers_to_f32.lin":15:38)
    %v10 = func.call @"lin.;narrow"(%v9) : (f64) -> f32 loc("tests/codegen/float32_lowers_to_f32.lin":15:31)
    %v11 = llvm.load %s0 : !llvm.ptr -> f32 loc("tests/codegen/float32_lowers_to_f32.lin":15:46)
    %v12 = arith.cmpf oeq, %v10, %v11 : f32 loc("tests/codegen/float32_lowers_to_f32.lin":15:31)
    %sw13 = arith.extui %v12 : i1 to i8 loc("tests/codegen/float32_lowers_to_f32.lin":15:8)
    llvm.store %sw13, %s1 : i8, !llvm.ptr loc("tests/codegen/float32_lowers_to_f32.lin":15:8)
    cf.br ^b3 loc("tests/codegen/float32_lowers_to_f32.lin":15:8)
  ^b2:
    %v15 = arith.constant 0 : i1 loc("tests/codegen/float32_lowers_to_f32.lin":15:8)
    %sw16 = arith.extui %v15 : i1 to i8 loc("tests/codegen/float32_lowers_to_f32.lin":15:8)
    llvm.store %sw16, %s1 : i8, !llvm.ptr loc("tests/codegen/float32_lowers_to_f32.lin":15:8)
    cf.br ^b3 loc("tests/codegen/float32_lowers_to_f32.lin":15:8)
  ^b3:
    %lw18 = llvm.load %s1 : !llvm.ptr -> i8 loc("tests/codegen/float32_lowers_to_f32.lin":15:8)
    %lz18 = arith.constant 0 : i8 loc("tests/codegen/float32_lowers_to_f32.lin":15:8)
    %v18 = arith.cmpi ne, %lw18, %lz18 : i8 loc("tests/codegen/float32_lowers_to_f32.lin":15:8)
    cf.cond_br %v18, ^b4, ^b5 loc("tests/codegen/float32_lowers_to_f32.lin":15:5)
  ^b4:
    %v20 = arith.constant 0 : i64 loc("tests/codegen/float32_lowers_to_f32.lin":16:9)
    %sw21 = arith.trunci %v20 : i64 to i8 loc("tests/codegen/float32_lowers_to_f32.lin":15:5)
    llvm.store %sw21, %s2 : i8, !llvm.ptr loc("tests/codegen/float32_lowers_to_f32.lin":15:5)
    cf.br ^b6 loc("tests/codegen/float32_lowers_to_f32.lin":15:5)
  ^b5:
    %v23 = arith.constant 1 : i64 loc("tests/codegen/float32_lowers_to_f32.lin":18:9)
    %sw24 = arith.trunci %v23 : i64 to i8 loc("tests/codegen/float32_lowers_to_f32.lin":15:5)
    llvm.store %sw24, %s2 : i8, !llvm.ptr loc("tests/codegen/float32_lowers_to_f32.lin":15:5)
    cf.br ^b6 loc("tests/codegen/float32_lowers_to_f32.lin":15:5)
  ^b6:
    %lw26 = llvm.load %s2 : !llvm.ptr -> i8 loc("tests/codegen/float32_lowers_to_f32.lin":15:5)
    %v26 = arith.extui %lw26 : i8 to i64 loc("tests/codegen/float32_lowers_to_f32.lin":15:5)
    func.return %v26 : i64 loc("tests/codegen/float32_lowers_to_f32.lin":15:5)
  }
  func.func private @"lin.;mix"(%a0: f32, %a1: f32) -> f32 attributes {llvm.linkage = #llvm.linkage<internal>} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x f32 {alignment = 4 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 1 : i64
    %s1 = llvm.alloca %z1 x f32 {alignment = 4 : i64} : (i64) -> !llvm.ptr
    llvm.store %a0, %s0 : f32, !llvm.ptr
    llvm.store %a1, %s1 : f32, !llvm.ptr
    cf.br ^b0
  ^b0:
    %v0 = llvm.load %s0 : !llvm.ptr -> f32 loc("tests/codegen/float32_lowers_to_f32.lin":2:5)
    %v1 = arith.constant 0x3F000000 : f32 loc("tests/codegen/float32_lowers_to_f32.lin":2:12)
    %nr2 = arith.mulf %v0, %v1 : f32 loc("tests/codegen/float32_lowers_to_f32.lin":2:5)
    %nu2 = arith.cmpf uno, %nr2, %nr2 : f32 loc("tests/codegen/float32_lowers_to_f32.lin":2:5)
    %nq2 = arith.constant 0x7FC00000 : f32 loc("tests/codegen/float32_lowers_to_f32.lin":2:5)
    %v2 = arith.select %nu2, %nq2, %nr2 : f32 loc("tests/codegen/float32_lowers_to_f32.lin":2:5)
    %v3 = llvm.load %s1 : !llvm.ptr -> f32 loc("tests/codegen/float32_lowers_to_f32.lin":2:18)
    %nr4 = arith.addf %v2, %v3 : f32 loc("tests/codegen/float32_lowers_to_f32.lin":2:5)
    %nu4 = arith.cmpf uno, %nr4, %nr4 : f32 loc("tests/codegen/float32_lowers_to_f32.lin":2:5)
    %nq4 = arith.constant 0x7FC00000 : f32 loc("tests/codegen/float32_lowers_to_f32.lin":2:5)
    %v4 = arith.select %nu4, %nq4, %nr4 : f32 loc("tests/codegen/float32_lowers_to_f32.lin":2:5)
    func.return %v4 : f32 loc("tests/codegen/float32_lowers_to_f32.lin":2:5)
  }
  func.func private @"lin.;widen"(%a0: f32) -> f64 attributes {llvm.linkage = #llvm.linkage<internal>} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x f32 {alignment = 4 : i64} : (i64) -> !llvm.ptr
    llvm.store %a0, %s0 : f32, !llvm.ptr
    cf.br ^b0
  ^b0:
    %v0 = llvm.load %s0 : !llvm.ptr -> f32 loc("tests/codegen/float32_lowers_to_f32.lin":6:13)
    %nr1 = arith.extf %v0 : f32 to f64 loc("tests/codegen/float32_lowers_to_f32.lin":6:5)
    %nu1 = arith.cmpf uno, %nr1, %nr1 : f64 loc("tests/codegen/float32_lowers_to_f32.lin":6:5)
    %nq1 = arith.constant 0x7FF8000000000000 : f64 loc("tests/codegen/float32_lowers_to_f32.lin":6:5)
    %v1 = arith.select %nu1, %nq1, %nr1 : f64 loc("tests/codegen/float32_lowers_to_f32.lin":6:5)
    func.return %v1 : f64 loc("tests/codegen/float32_lowers_to_f32.lin":6:5)
  }
  func.func private @"lin.;narrow"(%a0: f64) -> f32 attributes {llvm.linkage = #llvm.linkage<internal>} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x f64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    llvm.store %a0, %s0 : f64, !llvm.ptr
    cf.br ^b0
  ^b0:
    %v0 = llvm.load %s0 : !llvm.ptr -> f64 loc("tests/codegen/float32_lowers_to_f32.lin":10:13)
    %nr1 = arith.truncf %v0 : f64 to f32 loc("tests/codegen/float32_lowers_to_f32.lin":10:5)
    %nu1 = arith.cmpf uno, %nr1, %nr1 : f32 loc("tests/codegen/float32_lowers_to_f32.lin":10:5)
    %nq1 = arith.constant 0x7FC00000 : f32 loc("tests/codegen/float32_lowers_to_f32.lin":10:5)
    %v1 = arith.select %nu1, %nq1, %nr1 : f32 loc("tests/codegen/float32_lowers_to_f32.lin":10:5)
    func.return %v1 : f32 loc("tests/codegen/float32_lowers_to_f32.lin":10:5)
  }
  func.func @main(%argc: i32, %argv: !llvm.ptr) -> i32 {
    func.call @linea_set_args(%argc, %argv) : (i32, !llvm.ptr) -> ()
    %status = func.call @"lin.;main"() : () -> i64
    %status32 = arith.trunci %status : i64 to i32
    func.return %status32 : i32
  }
}
