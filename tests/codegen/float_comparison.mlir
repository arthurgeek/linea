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
  llvm.mlir.global internal constant @linea_file0("tests/codegen/float_comparison.lin\00") : !llvm.array<35 x i8>
  func.func private @linea_set_args(i32, !llvm.ptr)
  func.func private @linea_trap(i32, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @linea_panic(i64, i64, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @"lin.;main"() -> i64 attributes {llvm.linkage = #llvm.linkage<internal>, passthrough = [["probe-stack", "inline-asm"]]} {
    cf.br ^b0
  ^b0:
    %v0 = arith.constant 0x3FF0000000000000 : f64 loc("tests/codegen/float_comparison.lin":24:13)
    %v1 = arith.constant 0x4000000000000000 : f64 loc("tests/codegen/float_comparison.lin":24:18)
    %v2 = func.call @"lin.;compare"(%v0, %v1) : (f64, f64) -> i64 loc("tests/codegen/float_comparison.lin":24:5)
    %v3 = arith.constant 0x4000000000000000 : f64 loc("tests/codegen/float_comparison.lin":24:33)
    %v4 = arith.constant 0x3FF0000000000000 : f64 loc("tests/codegen/float_comparison.lin":24:38)
    %v5 = func.call @"lin.;compare"(%v3, %v4) : (f64, f64) -> i64 loc("tests/codegen/float_comparison.lin":24:25)
    %v6 = arith.addi %v2, %v5 : i64 loc("tests/codegen/float_comparison.lin":24:5)
    %k1m = arith.constant 255 : i64 loc("tests/codegen/float_comparison.lin":24:23)
    %k1 = arith.cmpi ugt, %v6, %k1m : i64 loc("tests/codegen/float_comparison.lin":24:23)
    cf.cond_br %k1, ^t1, ^c1 loc("tests/codegen/float_comparison.lin":24:23)
  ^t1:
    %tk1 = arith.constant 0 : i32 loc("tests/codegen/float_comparison.lin":24:23)
    %tf1 = llvm.mlir.addressof @linea_file0 : !llvm.ptr loc("tests/codegen/float_comparison.lin":24:23)
    %tl1 = arith.constant 24 : i32 loc("tests/codegen/float_comparison.lin":24:23)
    %tc1 = arith.constant 23 : i32 loc("tests/codegen/float_comparison.lin":24:23)
    func.call @linea_trap(%tk1, %tf1, %tl1, %tc1) : (i32, !llvm.ptr, i32, i32) -> () loc("tests/codegen/float_comparison.lin":24:23)
    llvm.unreachable loc("tests/codegen/float_comparison.lin":24:23)
  ^c1:
    %p7 = arith.constant 0 : i64 loc("tests/codegen/float_comparison.lin":24:23)
    %v7 = arith.addi %v6, %p7 : i64 loc("tests/codegen/float_comparison.lin":24:23)
    %v8 = arith.constant 0x3FF0000000000000 : f64 loc("tests/codegen/float_comparison.lin":24:53)
    %v9 = arith.constant 0x3FF0000000000000 : f64 loc("tests/codegen/float_comparison.lin":24:58)
    %v10 = func.call @"lin.;compare"(%v8, %v9) : (f64, f64) -> i64 loc("tests/codegen/float_comparison.lin":24:45)
    %v11 = arith.addi %v7, %v10 : i64 loc("tests/codegen/float_comparison.lin":24:5)
    %k2m = arith.constant 255 : i64 loc("tests/codegen/float_comparison.lin":24:43)
    %k2 = arith.cmpi ugt, %v11, %k2m : i64 loc("tests/codegen/float_comparison.lin":24:43)
    cf.cond_br %k2, ^t2, ^c2 loc("tests/codegen/float_comparison.lin":24:43)
  ^t2:
    %tk2 = arith.constant 0 : i32 loc("tests/codegen/float_comparison.lin":24:43)
    %tf2 = llvm.mlir.addressof @linea_file0 : !llvm.ptr loc("tests/codegen/float_comparison.lin":24:43)
    %tl2 = arith.constant 24 : i32 loc("tests/codegen/float_comparison.lin":24:43)
    %tc2 = arith.constant 43 : i32 loc("tests/codegen/float_comparison.lin":24:43)
    func.call @linea_trap(%tk2, %tf2, %tl2, %tc2) : (i32, !llvm.ptr, i32, i32) -> () loc("tests/codegen/float_comparison.lin":24:43)
    llvm.unreachable loc("tests/codegen/float_comparison.lin":24:43)
  ^c2:
    %p12 = arith.constant 0 : i64 loc("tests/codegen/float_comparison.lin":24:43)
    %v12 = arith.addi %v11, %p12 : i64 loc("tests/codegen/float_comparison.lin":24:43)
    func.return %v12 : i64 loc("tests/codegen/float_comparison.lin":24:5)
  }
  func.func private @"lin.;compare"(%a0: f64, %a1: f64) -> i64 attributes {llvm.linkage = #llvm.linkage<internal>, passthrough = [["probe-stack", "inline-asm"]]} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x f64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 1 : i64
    %s1 = llvm.alloca %z1 x f64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    llvm.store %a0, %s0 : f64, !llvm.ptr
    llvm.store %a1, %s1 : f64, !llvm.ptr
    cf.br ^b0
  ^b0:
    %v0 = llvm.load %s0 : !llvm.ptr -> f64 loc("tests/codegen/float_comparison.lin":2:8)
    %v1 = llvm.load %s1 : !llvm.ptr -> f64 loc("tests/codegen/float_comparison.lin":2:12)
    %v2 = arith.cmpf olt, %v0, %v1 : f64 loc("tests/codegen/float_comparison.lin":2:8)
    cf.cond_br %v2, ^b1, ^b2 loc("tests/codegen/float_comparison.lin":2:5)
  ^b1:
    %v4 = arith.constant 1 : i64 loc("tests/codegen/float_comparison.lin":3:16)
    func.return %v4 : i64 loc("tests/codegen/float_comparison.lin":3:9)
  ^b2:
    cf.br ^b3 loc("tests/codegen/float_comparison.lin":2:5)
  ^b3:
    %v9 = arith.constant 0 : i64 loc("tests/codegen/float_comparison.lin":2:5)
    %v10 = llvm.load %s0 : !llvm.ptr -> f64 loc("tests/codegen/float_comparison.lin":5:8)
    %v11 = llvm.load %s1 : !llvm.ptr -> f64 loc("tests/codegen/float_comparison.lin":5:13)
    %v12 = arith.cmpf ole, %v10, %v11 : f64 loc("tests/codegen/float_comparison.lin":5:8)
    cf.cond_br %v12, ^b5, ^b6 loc("tests/codegen/float_comparison.lin":5:5)
  ^b5:
    %v14 = arith.constant 2 : i64 loc("tests/codegen/float_comparison.lin":6:16)
    func.return %v14 : i64 loc("tests/codegen/float_comparison.lin":6:9)
  ^b6:
    cf.br ^b7 loc("tests/codegen/float_comparison.lin":5:5)
  ^b7:
    %v19 = arith.constant 0 : i64 loc("tests/codegen/float_comparison.lin":5:5)
    %v20 = llvm.load %s0 : !llvm.ptr -> f64 loc("tests/codegen/float_comparison.lin":8:8)
    %v21 = llvm.load %s1 : !llvm.ptr -> f64 loc("tests/codegen/float_comparison.lin":8:12)
    %v22 = arith.cmpf ogt, %v20, %v21 : f64 loc("tests/codegen/float_comparison.lin":8:8)
    cf.cond_br %v22, ^b9, ^b10 loc("tests/codegen/float_comparison.lin":8:5)
  ^b9:
    %v24 = arith.constant 3 : i64 loc("tests/codegen/float_comparison.lin":9:16)
    func.return %v24 : i64 loc("tests/codegen/float_comparison.lin":9:9)
  ^b10:
    cf.br ^b11 loc("tests/codegen/float_comparison.lin":8:5)
  ^b11:
    %v29 = arith.constant 0 : i64 loc("tests/codegen/float_comparison.lin":8:5)
    %v30 = llvm.load %s0 : !llvm.ptr -> f64 loc("tests/codegen/float_comparison.lin":11:8)
    %v31 = llvm.load %s1 : !llvm.ptr -> f64 loc("tests/codegen/float_comparison.lin":11:13)
    %v32 = arith.cmpf oge, %v30, %v31 : f64 loc("tests/codegen/float_comparison.lin":11:8)
    cf.cond_br %v32, ^b13, ^b14 loc("tests/codegen/float_comparison.lin":11:5)
  ^b13:
    %v34 = arith.constant 4 : i64 loc("tests/codegen/float_comparison.lin":12:16)
    func.return %v34 : i64 loc("tests/codegen/float_comparison.lin":12:9)
  ^b14:
    cf.br ^b15 loc("tests/codegen/float_comparison.lin":11:5)
  ^b15:
    %v39 = arith.constant 0 : i64 loc("tests/codegen/float_comparison.lin":11:5)
    %v40 = llvm.load %s0 : !llvm.ptr -> f64 loc("tests/codegen/float_comparison.lin":14:8)
    %v41 = llvm.load %s1 : !llvm.ptr -> f64 loc("tests/codegen/float_comparison.lin":14:13)
    %v42 = arith.cmpf oeq, %v40, %v41 : f64 loc("tests/codegen/float_comparison.lin":14:8)
    cf.cond_br %v42, ^b17, ^b18 loc("tests/codegen/float_comparison.lin":14:5)
  ^b17:
    %v44 = arith.constant 5 : i64 loc("tests/codegen/float_comparison.lin":15:16)
    func.return %v44 : i64 loc("tests/codegen/float_comparison.lin":15:9)
  ^b18:
    cf.br ^b19 loc("tests/codegen/float_comparison.lin":14:5)
  ^b19:
    %v49 = arith.constant 0 : i64 loc("tests/codegen/float_comparison.lin":14:5)
    %v50 = llvm.load %s0 : !llvm.ptr -> f64 loc("tests/codegen/float_comparison.lin":17:8)
    %v51 = llvm.load %s1 : !llvm.ptr -> f64 loc("tests/codegen/float_comparison.lin":17:13)
    %v52 = arith.cmpf une, %v50, %v51 : f64 loc("tests/codegen/float_comparison.lin":17:8)
    cf.cond_br %v52, ^b21, ^b22 loc("tests/codegen/float_comparison.lin":17:5)
  ^b21:
    %v54 = arith.constant 6 : i64 loc("tests/codegen/float_comparison.lin":18:16)
    func.return %v54 : i64 loc("tests/codegen/float_comparison.lin":18:9)
  ^b22:
    cf.br ^b23 loc("tests/codegen/float_comparison.lin":17:5)
  ^b23:
    %v59 = arith.constant 0 : i64 loc("tests/codegen/float_comparison.lin":17:5)
    %v60 = arith.constant 0 : i64 loc("tests/codegen/float_comparison.lin":20:5)
    func.return %v60 : i64 loc("tests/codegen/float_comparison.lin":20:5)
  }
  func.func @main(%argc: i32, %argv: !llvm.ptr) -> i32 {
    func.call @linea_set_args(%argc, %argv) : (i32, !llvm.ptr) -> ()
    %status = func.call @"lin.;main"() : () -> i64
    %status32 = arith.trunci %status : i64 to i32
    func.return %status32 : i32
  }
}
