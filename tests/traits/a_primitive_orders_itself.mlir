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
  llvm.mlir.global internal constant @linea_file0("tests/traits/a_primitive_orders_itself.lin\00") : !llvm.array<43 x i8>
  func.func private @linea_set_args(i32, !llvm.ptr)
  func.func private @linea_trap(i32, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @linea_panic(i64, i64, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @"lin.;main"() -> i64 attributes {llvm.linkage = #llvm.linkage<internal>, passthrough = [["probe-stack", "inline-asm"]]} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 1 : i64
    %s1 = llvm.alloca %z1 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z2 = arith.constant 1 : i64
    %s2 = llvm.alloca %z2 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z3 = arith.constant 1 : i64
    %s3 = llvm.alloca %z3 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z4 = arith.constant 1 : i64
    %s4 = llvm.alloca %z4 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z5 = arith.constant 1 : i64
    %s5 = llvm.alloca %z5 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    cf.br ^b0
  ^b0:
    %v0 = arith.constant 2 : i64 loc("tests/traits/a_primitive_orders_itself.lin":12:23)
    llvm.store %v0, %s0 : i64, !llvm.ptr loc("tests/traits/a_primitive_orders_itself.lin":12:5)
    %v2 = arith.constant 9 : i64 loc("tests/traits/a_primitive_orders_itself.lin":13:24)
    llvm.store %v2, %s1 : i64, !llvm.ptr loc("tests/traits/a_primitive_orders_itself.lin":13:5)
    %v4 = arith.constant 3 : i64 loc("tests/traits/a_primitive_orders_itself.lin":14:25)
    %sw5 = arith.trunci %v4 : i64 to i8 loc("tests/traits/a_primitive_orders_itself.lin":14:5)
    llvm.store %sw5, %s2 : i8, !llvm.ptr loc("tests/traits/a_primitive_orders_itself.lin":14:5)
    %v6 = arith.constant 1 : i64 loc("tests/traits/a_primitive_orders_itself.lin":15:25)
    %sw7 = arith.trunci %v6 : i64 to i8 loc("tests/traits/a_primitive_orders_itself.lin":15:5)
    llvm.store %sw7, %s3 : i8, !llvm.ptr loc("tests/traits/a_primitive_orders_itself.lin":15:5)
    %v8 = llvm.load %s0 : !llvm.ptr -> i64 loc("tests/traits/a_primitive_orders_itself.lin":16:16)
    %v9 = llvm.load %s1 : !llvm.ptr -> i64 loc("tests/traits/a_primitive_orders_itself.lin":16:22)
    %v10 = func.call @"lin.;smaller[Int64]"(%v8, %v9) : (i64, i64) -> i1 loc("tests/traits/a_primitive_orders_itself.lin":16:8)
    cf.cond_br %v10, ^b1, ^b2 loc("tests/traits/a_primitive_orders_itself.lin":16:8)
  ^b1:
    %lw12 = llvm.load %s2 : !llvm.ptr -> i8 loc("tests/traits/a_primitive_orders_itself.lin":16:41)
    %v12 = arith.extui %lw12 : i8 to i64 loc("tests/traits/a_primitive_orders_itself.lin":16:41)
    %lw13 = llvm.load %s3 : !llvm.ptr -> i8 loc("tests/traits/a_primitive_orders_itself.lin":16:49)
    %v13 = arith.extui %lw13 : i8 to i64 loc("tests/traits/a_primitive_orders_itself.lin":16:49)
    %v14 = func.call @"lin.;smaller[UInt8]"(%v12, %v13) : (i64, i64) -> i1 loc("tests/traits/a_primitive_orders_itself.lin":16:33)
    %v15 = arith.constant 0 : i1 loc("tests/traits/a_primitive_orders_itself.lin":16:32)
    %v16 = arith.cmpi eq, %v14, %v15 : i1 loc("tests/traits/a_primitive_orders_itself.lin":16:32)
    %sw17 = arith.extui %v16 : i1 to i8 loc("tests/traits/a_primitive_orders_itself.lin":16:8)
    llvm.store %sw17, %s4 : i8, !llvm.ptr loc("tests/traits/a_primitive_orders_itself.lin":16:8)
    cf.br ^b3 loc("tests/traits/a_primitive_orders_itself.lin":16:8)
  ^b2:
    %v19 = arith.constant 0 : i1 loc("tests/traits/a_primitive_orders_itself.lin":16:8)
    %sw20 = arith.extui %v19 : i1 to i8 loc("tests/traits/a_primitive_orders_itself.lin":16:8)
    llvm.store %sw20, %s4 : i8, !llvm.ptr loc("tests/traits/a_primitive_orders_itself.lin":16:8)
    cf.br ^b3 loc("tests/traits/a_primitive_orders_itself.lin":16:8)
  ^b3:
    %lw22 = llvm.load %s4 : !llvm.ptr -> i8 loc("tests/traits/a_primitive_orders_itself.lin":16:8)
    %lz22 = arith.constant 0 : i8 loc("tests/traits/a_primitive_orders_itself.lin":16:8)
    %v22 = arith.cmpi ne, %lw22, %lz22 : i8 loc("tests/traits/a_primitive_orders_itself.lin":16:8)
    cf.cond_br %v22, ^b4, ^b5 loc("tests/traits/a_primitive_orders_itself.lin":16:5)
  ^b4:
    %v24 = arith.constant 6 : i64 loc("tests/traits/a_primitive_orders_itself.lin":17:9)
    %sw25 = arith.trunci %v24 : i64 to i8 loc("tests/traits/a_primitive_orders_itself.lin":16:5)
    llvm.store %sw25, %s5 : i8, !llvm.ptr loc("tests/traits/a_primitive_orders_itself.lin":16:5)
    cf.br ^b6 loc("tests/traits/a_primitive_orders_itself.lin":16:5)
  ^b5:
    %v27 = arith.constant 0 : i64 loc("tests/traits/a_primitive_orders_itself.lin":19:9)
    %sw28 = arith.trunci %v27 : i64 to i8 loc("tests/traits/a_primitive_orders_itself.lin":16:5)
    llvm.store %sw28, %s5 : i8, !llvm.ptr loc("tests/traits/a_primitive_orders_itself.lin":16:5)
    cf.br ^b6 loc("tests/traits/a_primitive_orders_itself.lin":16:5)
  ^b6:
    %lw30 = llvm.load %s5 : !llvm.ptr -> i8 loc("tests/traits/a_primitive_orders_itself.lin":16:5)
    %v30 = arith.extui %lw30 : i8 to i64 loc("tests/traits/a_primitive_orders_itself.lin":16:5)
    func.return %v30 : i64 loc("tests/traits/a_primitive_orders_itself.lin":16:5)
  }
  func.func private @"lin.;smaller[Int64]"(%a0: i64, %a1: i64) -> i1 attributes {llvm.linkage = #llvm.linkage<internal>, passthrough = [["probe-stack", "inline-asm"]]} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 1 : i64
    %s1 = llvm.alloca %z1 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    llvm.store %a0, %s0 : i64, !llvm.ptr
    llvm.store %a1, %s1 : i64, !llvm.ptr
    cf.br ^b0
  ^b0:
    %v0 = llvm.load %s0 : !llvm.ptr -> i64 loc("tests/traits/a_primitive_orders_itself.lin":8:21)
    %v1 = llvm.load %s1 : !llvm.ptr -> i64 loc("tests/traits/a_primitive_orders_itself.lin":8:24)
    %v2 = arith.cmpi slt, %v0, %v1 : i64 loc("tests/traits/a_primitive_orders_itself.lin":8:5)
    func.return %v2 : i1 loc("tests/traits/a_primitive_orders_itself.lin":8:5)
  }
  func.func private @"lin.;smaller[UInt8]"(%a0: i64, %a1: i64) -> i1 attributes {llvm.linkage = #llvm.linkage<internal>, passthrough = [["probe-stack", "inline-asm"]]} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 1 : i64
    %s1 = llvm.alloca %z1 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %pw0 = arith.trunci %a0 : i64 to i8
    llvm.store %pw0, %s0 : i8, !llvm.ptr
    %pw1 = arith.trunci %a1 : i64 to i8
    llvm.store %pw1, %s1 : i8, !llvm.ptr
    cf.br ^b0
  ^b0:
    %lw0 = llvm.load %s0 : !llvm.ptr -> i8 loc("tests/traits/a_primitive_orders_itself.lin":8:21)
    %v0 = arith.extui %lw0 : i8 to i64 loc("tests/traits/a_primitive_orders_itself.lin":8:21)
    %lw1 = llvm.load %s1 : !llvm.ptr -> i8 loc("tests/traits/a_primitive_orders_itself.lin":8:24)
    %v1 = arith.extui %lw1 : i8 to i64 loc("tests/traits/a_primitive_orders_itself.lin":8:24)
    %v2 = arith.cmpi ult, %v0, %v1 : i64 loc("tests/traits/a_primitive_orders_itself.lin":8:5)
    func.return %v2 : i1 loc("tests/traits/a_primitive_orders_itself.lin":8:5)
  }
  func.func @main(%argc: i32, %argv: !llvm.ptr) -> i32 {
    func.call @linea_set_args(%argc, %argv) : (i32, !llvm.ptr) -> ()
    %status = func.call @"lin.;main"() : () -> i64
    %status32 = arith.trunci %status : i64 to i32
    func.return %status32 : i32
  }
}
