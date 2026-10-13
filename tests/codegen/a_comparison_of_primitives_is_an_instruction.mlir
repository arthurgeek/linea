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
  llvm.mlir.global internal constant @linea_file0("tests/codegen/a_comparison_of_primitives_is_an_instruction.lin\00") : !llvm.array<63 x i8>
  func.func private @linea_set_args(i32, !llvm.ptr)
  func.func private @linea_trap(i32, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @linea_panic(i64, i64, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @"lin.;main"() -> i64 attributes {llvm.linkage = #llvm.linkage<internal>} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 1 : i64
    %s1 = llvm.alloca %z1 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    cf.br ^b0
  ^b0:
    %v0 = arith.constant 0 : i64 loc("tests/codegen/a_comparison_of_primitives_is_an_instruction.lin":5:20)
    %sw1 = arith.trunci %v0 : i64 to i8 loc("tests/codegen/a_comparison_of_primitives_is_an_instruction.lin":5:5)
    llvm.store %sw1, %s0 : i8, !llvm.ptr loc("tests/codegen/a_comparison_of_primitives_is_an_instruction.lin":5:5)
    %v2 = arith.constant 0 : i64 loc("tests/codegen/a_comparison_of_primitives_is_an_instruction.lin":6:24)
    %sw3 = arith.trunci %v2 : i64 to i8 loc("tests/codegen/a_comparison_of_primitives_is_an_instruction.lin":6:5)
    llvm.store %sw3, %s1 : i8, !llvm.ptr loc("tests/codegen/a_comparison_of_primitives_is_an_instruction.lin":6:5)
    cf.br ^b1 loc("tests/codegen/a_comparison_of_primitives_is_an_instruction.lin":7:5)
  ^b1:
    %lw5 = llvm.load %s0 : !llvm.ptr -> i8 loc("tests/codegen/a_comparison_of_primitives_is_an_instruction.lin":7:11)
    %v5 = arith.extui %lw5 : i8 to i64 loc("tests/codegen/a_comparison_of_primitives_is_an_instruction.lin":7:11)
    %v6 = arith.constant 5 : i64 loc("tests/codegen/a_comparison_of_primitives_is_an_instruction.lin":7:15)
    %v7 = arith.cmpi ult, %v5, %v6 : i64 loc("tests/codegen/a_comparison_of_primitives_is_an_instruction.lin":7:11)
    cf.cond_br %v7, ^b2, ^b3 loc("tests/codegen/a_comparison_of_primitives_is_an_instruction.lin":7:5)
  ^b2:
    %lw9 = llvm.load %s0 : !llvm.ptr -> i8 loc("tests/codegen/a_comparison_of_primitives_is_an_instruction.lin":8:12)
    %v9 = arith.extui %lw9 : i8 to i64 loc("tests/codegen/a_comparison_of_primitives_is_an_instruction.lin":8:12)
    %v10 = arith.constant 2 : i64 loc("tests/codegen/a_comparison_of_primitives_is_an_instruction.lin":8:17)
    %v11 = arith.cmpi ule, %v9, %v10 : i64 loc("tests/codegen/a_comparison_of_primitives_is_an_instruction.lin":8:12)
    cf.cond_br %v11, ^b4, ^b5 loc("tests/codegen/a_comparison_of_primitives_is_an_instruction.lin":8:9)
  ^b3:
    %v29 = arith.constant 0 : i64 loc("tests/codegen/a_comparison_of_primitives_is_an_instruction.lin":7:5)
    %lw30 = llvm.load %s1 : !llvm.ptr -> i8 loc("tests/codegen/a_comparison_of_primitives_is_an_instruction.lin":13:5)
    %v30 = arith.extui %lw30 : i8 to i64 loc("tests/codegen/a_comparison_of_primitives_is_an_instruction.lin":13:5)
    func.return %v30 : i64 loc("tests/codegen/a_comparison_of_primitives_is_an_instruction.lin":13:5)
  ^b4:
    %lw13 = llvm.load %s1 : !llvm.ptr -> i8 loc("tests/codegen/a_comparison_of_primitives_is_an_instruction.lin":9:21)
    %v13 = arith.extui %lw13 : i8 to i64 loc("tests/codegen/a_comparison_of_primitives_is_an_instruction.lin":9:21)
    %v14 = arith.constant 1 : i64 loc("tests/codegen/a_comparison_of_primitives_is_an_instruction.lin":9:29)
    %v15 = arith.addi %v13, %v14 : i64 loc("tests/codegen/a_comparison_of_primitives_is_an_instruction.lin":9:21)
    %k1m = arith.constant 255 : i64 loc("tests/codegen/a_comparison_of_primitives_is_an_instruction.lin":9:27)
    %k1 = arith.cmpi ugt, %v15, %k1m : i64 loc("tests/codegen/a_comparison_of_primitives_is_an_instruction.lin":9:27)
    cf.cond_br %k1, ^t1, ^c1 loc("tests/codegen/a_comparison_of_primitives_is_an_instruction.lin":9:27)
  ^t1:
    %tk1 = arith.constant 0 : i32 loc("tests/codegen/a_comparison_of_primitives_is_an_instruction.lin":9:27)
    %tf1 = llvm.mlir.addressof @linea_file0 : !llvm.ptr loc("tests/codegen/a_comparison_of_primitives_is_an_instruction.lin":9:27)
    %tl1 = arith.constant 9 : i32 loc("tests/codegen/a_comparison_of_primitives_is_an_instruction.lin":9:27)
    %tc1 = arith.constant 27 : i32 loc("tests/codegen/a_comparison_of_primitives_is_an_instruction.lin":9:27)
    func.call @linea_trap(%tk1, %tf1, %tl1, %tc1) : (i32, !llvm.ptr, i32, i32) -> () loc("tests/codegen/a_comparison_of_primitives_is_an_instruction.lin":9:27)
    llvm.unreachable loc("tests/codegen/a_comparison_of_primitives_is_an_instruction.lin":9:27)
  ^c1:
    %p16 = arith.constant 0 : i64 loc("tests/codegen/a_comparison_of_primitives_is_an_instruction.lin":9:27)
    %v16 = arith.addi %v15, %p16 : i64 loc("tests/codegen/a_comparison_of_primitives_is_an_instruction.lin":9:27)
    %sw17 = arith.trunci %v16 : i64 to i8 loc("tests/codegen/a_comparison_of_primitives_is_an_instruction.lin":9:13)
    llvm.store %sw17, %s1 : i8, !llvm.ptr loc("tests/codegen/a_comparison_of_primitives_is_an_instruction.lin":9:13)
    %v18 = arith.constant 0 : i64 loc("tests/codegen/a_comparison_of_primitives_is_an_instruction.lin":9:13)
    cf.br ^b6 loc("tests/codegen/a_comparison_of_primitives_is_an_instruction.lin":8:9)
  ^b5:
    cf.br ^b6 loc("tests/codegen/a_comparison_of_primitives_is_an_instruction.lin":8:9)
  ^b6:
    %v21 = arith.constant 0 : i64 loc("tests/codegen/a_comparison_of_primitives_is_an_instruction.lin":8:9)
    %lw22 = llvm.load %s0 : !llvm.ptr -> i8 loc("tests/codegen/a_comparison_of_primitives_is_an_instruction.lin":11:13)
    %v22 = arith.extui %lw22 : i8 to i64 loc("tests/codegen/a_comparison_of_primitives_is_an_instruction.lin":11:13)
    %v23 = arith.constant 1 : i64 loc("tests/codegen/a_comparison_of_primitives_is_an_instruction.lin":11:17)
    %v24 = arith.addi %v22, %v23 : i64 loc("tests/codegen/a_comparison_of_primitives_is_an_instruction.lin":11:13)
    %k2m = arith.constant 255 : i64 loc("tests/codegen/a_comparison_of_primitives_is_an_instruction.lin":11:15)
    %k2 = arith.cmpi ugt, %v24, %k2m : i64 loc("tests/codegen/a_comparison_of_primitives_is_an_instruction.lin":11:15)
    cf.cond_br %k2, ^t2, ^c2 loc("tests/codegen/a_comparison_of_primitives_is_an_instruction.lin":11:15)
  ^t2:
    %tk2 = arith.constant 0 : i32 loc("tests/codegen/a_comparison_of_primitives_is_an_instruction.lin":11:15)
    %tf2 = llvm.mlir.addressof @linea_file0 : !llvm.ptr loc("tests/codegen/a_comparison_of_primitives_is_an_instruction.lin":11:15)
    %tl2 = arith.constant 11 : i32 loc("tests/codegen/a_comparison_of_primitives_is_an_instruction.lin":11:15)
    %tc2 = arith.constant 15 : i32 loc("tests/codegen/a_comparison_of_primitives_is_an_instruction.lin":11:15)
    func.call @linea_trap(%tk2, %tf2, %tl2, %tc2) : (i32, !llvm.ptr, i32, i32) -> () loc("tests/codegen/a_comparison_of_primitives_is_an_instruction.lin":11:15)
    llvm.unreachable loc("tests/codegen/a_comparison_of_primitives_is_an_instruction.lin":11:15)
  ^c2:
    %p25 = arith.constant 0 : i64 loc("tests/codegen/a_comparison_of_primitives_is_an_instruction.lin":11:15)
    %v25 = arith.addi %v24, %p25 : i64 loc("tests/codegen/a_comparison_of_primitives_is_an_instruction.lin":11:15)
    %sw26 = arith.trunci %v25 : i64 to i8 loc("tests/codegen/a_comparison_of_primitives_is_an_instruction.lin":11:9)
    llvm.store %sw26, %s0 : i8, !llvm.ptr loc("tests/codegen/a_comparison_of_primitives_is_an_instruction.lin":11:9)
    %v27 = arith.constant 0 : i64 loc("tests/codegen/a_comparison_of_primitives_is_an_instruction.lin":11:9)
    cf.br ^b1 loc("tests/codegen/a_comparison_of_primitives_is_an_instruction.lin":7:5)
  }
  func.func @main(%argc: i32, %argv: !llvm.ptr) -> i32 {
    func.call @linea_set_args(%argc, %argv) : (i32, !llvm.ptr) -> ()
    %status = func.call @"lin.;main"() : () -> i64
    %status32 = arith.trunci %status : i64 to i32
    func.return %status32 : i32
  }
}
