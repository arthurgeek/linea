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
  llvm.mlir.global internal constant @linea_file0("tests/structs/inout_a_struct.lin\00") : !llvm.array<33 x i8>
  func.func private @linea_set_args(i32, !llvm.ptr)
  func.func private @linea_trap(i32, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @linea_panic(i64, i64, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @"lin.;main"() -> i64 attributes {llvm.linkage = #llvm.linkage<internal>, passthrough = [["probe-stack", "inline-asm"]]} {
    %z0 = arith.constant 2 : i64
    %s0 = llvm.alloca %z0 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    cf.br ^b0
  ^b0:
    %v1 = arith.constant 0 : i64 loc("tests/structs/inout_a_struct.lin":12:20)
    %v3 = arith.constant 1 : i64 loc("tests/structs/inout_a_struct.lin":12:27)
    %iw4 = arith.trunci %v3 : i64 to i8 loc("tests/structs/inout_a_struct.lin":12:20)
    llvm.store %iw4, %s0 : i8, !llvm.ptr loc("tests/structs/inout_a_struct.lin":12:20)
    %v5 = arith.constant 1 : i64 loc("tests/structs/inout_a_struct.lin":12:20)
    %v6 = llvm.getelementptr %s0[%v5] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("tests/structs/inout_a_struct.lin":12:20)
    %v7 = arith.constant 2 : i64 loc("tests/structs/inout_a_struct.lin":12:34)
    %iw8 = arith.trunci %v7 : i64 to i8 loc("tests/structs/inout_a_struct.lin":12:20)
    llvm.store %iw8, %v6 : i8, !llvm.ptr loc("tests/structs/inout_a_struct.lin":12:20)
    %v10 = func.call @"lin.;bump"(%s0) : (!llvm.ptr) -> i64 loc("tests/structs/inout_a_struct.lin":13:5)
    %v12 = func.call @"lin.;bump"(%s0) : (!llvm.ptr) -> i64 loc("tests/structs/inout_a_struct.lin":14:5)
    %v14 = arith.constant 0 : i64 loc("tests/structs/inout_a_struct.lin":19:5)
    %iw16 = llvm.load %s0 : !llvm.ptr -> i8 loc("tests/structs/inout_a_struct.lin":19:5)
    %v16 = arith.extui %iw16 : i8 to i64 loc("tests/structs/inout_a_struct.lin":19:5)
    %v18 = arith.constant 1 : i64 loc("tests/structs/inout_a_struct.lin":19:11)
    %v19 = llvm.getelementptr %s0[%v18] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("tests/structs/inout_a_struct.lin":19:11)
    %iw20 = llvm.load %v19 : !llvm.ptr -> i8 loc("tests/structs/inout_a_struct.lin":19:11)
    %v20 = arith.extui %iw20 : i8 to i64 loc("tests/structs/inout_a_struct.lin":19:11)
    %v21 = arith.addi %v16, %v20 : i64 loc("tests/structs/inout_a_struct.lin":19:5)
    %k1m = arith.constant 255 : i64 loc("tests/structs/inout_a_struct.lin":19:9)
    %k1 = arith.cmpi ugt, %v21, %k1m : i64 loc("tests/structs/inout_a_struct.lin":19:9)
    cf.cond_br %k1, ^t1, ^c1 loc("tests/structs/inout_a_struct.lin":19:9)
  ^t1:
    %tk1 = arith.constant 0 : i32 loc("tests/structs/inout_a_struct.lin":19:9)
    %tf1 = llvm.mlir.addressof @linea_file0 : !llvm.ptr loc("tests/structs/inout_a_struct.lin":19:9)
    %tl1 = arith.constant 19 : i32 loc("tests/structs/inout_a_struct.lin":19:9)
    %tc1 = arith.constant 9 : i32 loc("tests/structs/inout_a_struct.lin":19:9)
    func.call @linea_trap(%tk1, %tf1, %tl1, %tc1) : (i32, !llvm.ptr, i32, i32) -> () loc("tests/structs/inout_a_struct.lin":19:9)
    llvm.unreachable loc("tests/structs/inout_a_struct.lin":19:9)
  ^c1:
    %p22 = arith.constant 0 : i64 loc("tests/structs/inout_a_struct.lin":19:9)
    %v22 = arith.addi %v21, %p22 : i64 loc("tests/structs/inout_a_struct.lin":19:9)
    func.return %v22 : i64 loc("tests/structs/inout_a_struct.lin":19:5)
  }
  func.func private @"lin.;bump"(%a0: !llvm.ptr) -> i64 attributes {llvm.linkage = #llvm.linkage<internal>, passthrough = [["probe-stack", "inline-asm"]]} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x !llvm.ptr {alignment = 8 : i64} : (i64) -> !llvm.ptr
    llvm.store %a0, %s0 : !llvm.ptr, !llvm.ptr
    cf.br ^b0
  ^b0:
    %v0 = llvm.load %s0 : !llvm.ptr -> !llvm.ptr loc("tests/structs/inout_a_struct.lin":8:11)
    %v1 = arith.constant 0 : i64 loc("tests/structs/inout_a_struct.lin":8:11)
    %iw3 = llvm.load %v0 : !llvm.ptr -> i8 loc("tests/structs/inout_a_struct.lin":8:11)
    %v3 = arith.extui %iw3 : i8 to i64 loc("tests/structs/inout_a_struct.lin":8:11)
    %v4 = arith.constant 1 : i64 loc("tests/structs/inout_a_struct.lin":8:17)
    %v5 = arith.addi %v3, %v4 : i64 loc("tests/structs/inout_a_struct.lin":8:11)
    %k1m = arith.constant 255 : i64 loc("tests/structs/inout_a_struct.lin":8:15)
    %k1 = arith.cmpi ugt, %v5, %k1m : i64 loc("tests/structs/inout_a_struct.lin":8:15)
    cf.cond_br %k1, ^t1, ^c1 loc("tests/structs/inout_a_struct.lin":8:15)
  ^t1:
    %tk1 = arith.constant 0 : i32 loc("tests/structs/inout_a_struct.lin":8:15)
    %tf1 = llvm.mlir.addressof @linea_file0 : !llvm.ptr loc("tests/structs/inout_a_struct.lin":8:15)
    %tl1 = arith.constant 8 : i32 loc("tests/structs/inout_a_struct.lin":8:15)
    %tc1 = arith.constant 15 : i32 loc("tests/structs/inout_a_struct.lin":8:15)
    func.call @linea_trap(%tk1, %tf1, %tl1, %tc1) : (i32, !llvm.ptr, i32, i32) -> () loc("tests/structs/inout_a_struct.lin":8:15)
    llvm.unreachable loc("tests/structs/inout_a_struct.lin":8:15)
  ^c1:
    %p6 = arith.constant 0 : i64 loc("tests/structs/inout_a_struct.lin":8:15)
    %v6 = arith.addi %v5, %p6 : i64 loc("tests/structs/inout_a_struct.lin":8:15)
    %v7 = llvm.load %s0 : !llvm.ptr -> !llvm.ptr loc("tests/structs/inout_a_struct.lin":8:5)
    %v8 = arith.constant 0 : i64 loc("tests/structs/inout_a_struct.lin":8:5)
    %iw10 = arith.trunci %v6 : i64 to i8 loc("tests/structs/inout_a_struct.lin":8:5)
    llvm.store %iw10, %v7 : i8, !llvm.ptr loc("tests/structs/inout_a_struct.lin":8:5)
    %v11 = arith.constant 0 : i64 loc("tests/structs/inout_a_struct.lin":8:5)
    func.return %v11 : i64 loc("tests/structs/inout_a_struct.lin":8:5)
  }
  func.func @main(%argc: i32, %argv: !llvm.ptr) -> i32 {
    func.call @linea_set_args(%argc, %argv) : (i32, !llvm.ptr) -> ()
    %status = func.call @"lin.;main"() : () -> i64
    %status32 = arith.trunci %status : i64 to i32
    func.return %status32 : i32
  }
}
