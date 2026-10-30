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
  llvm.mlir.global internal constant @linea_file0("tests/generics/a_field_of_unit.lin\00") : !llvm.array<35 x i8>
  func.func private @linea_set_args(i32, !llvm.ptr)
  func.func private @linea_trap(i32, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @linea_panic(i64, i64, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @"lin.;main"() -> i64 attributes {llvm.linkage = #llvm.linkage<internal>, passthrough = [["probe-stack", "inline-asm"]]} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 1 : i64
    %s1 = llvm.alloca %z1 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z2 = arith.constant 1 : i64
    %s2 = llvm.alloca %z2 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z3 = arith.constant 1 : i64
    %s3 = llvm.alloca %z3 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z4 = arith.constant 1 : i64
    %s4 = llvm.alloca %z4 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %rz7 = arith.constant 1 : i64
    %rs7 = llvm.alloca %rz7 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    cf.br ^b0
  ^b0:
    %v0 = arith.constant -81985529216486896 : i64 loc("tests/generics/a_field_of_unit.lin":14:25)
    llvm.store %v0, %s0 : i64, !llvm.ptr loc("tests/generics/a_field_of_unit.lin":14:5)
    %v2 = arith.constant 7 : i64 loc("tests/generics/a_field_of_unit.lin":15:20)
    %sw3 = arith.trunci %v2 : i64 to i8 loc("tests/generics/a_field_of_unit.lin":15:5)
    llvm.store %sw3, %s1 : i8, !llvm.ptr loc("tests/generics/a_field_of_unit.lin":15:5)
    %lw5 = llvm.load %s1 : !llvm.ptr -> i8 loc("tests/generics/a_field_of_unit.lin":16:18)
    %v5 = arith.extui %lw5 : i8 to i64 loc("tests/generics/a_field_of_unit.lin":16:18)
    %v6 = arith.constant 0 : i64 loc("tests/generics/a_field_of_unit.lin":16:21)
    func.call @"lin.;both[UInt8,$28$29]"(%rs7, %v5, %v6) : (!llvm.ptr, i64, i64) -> () loc("tests/generics/a_field_of_unit.lin":16:13)
    %cl8 = arith.constant 1 : i64 loc("tests/generics/a_field_of_unit.lin":16:5)
    "llvm.intr.memcpy"(%s2, %rs7, %cl8) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("tests/generics/a_field_of_unit.lin":16:5)
    %v10 = arith.constant 1 : i64 loc("tests/generics/a_field_of_unit.lin":17:25)
    %v11 = llvm.getelementptr %s2[%v10] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("tests/generics/a_field_of_unit.lin":17:25)
    %v12 = arith.constant 0 : i64 loc("tests/generics/a_field_of_unit.lin":17:25)
    llvm.store %v12, %s3 : i64, !llvm.ptr loc("tests/generics/a_field_of_unit.lin":17:5)
    %v14 = llvm.load %s0 : !llvm.ptr -> i64 loc("tests/generics/a_field_of_unit.lin":19:8)
    %v15 = arith.constant -81985529216486896 : i64 loc("tests/generics/a_field_of_unit.lin":19:17)
    %v16 = arith.cmpi ne, %v14, %v15 : i64 loc("tests/generics/a_field_of_unit.lin":19:8)
    cf.cond_br %v16, ^b1, ^b2 loc("tests/generics/a_field_of_unit.lin":19:5)
  ^b1:
    %v18 = arith.constant 1 : i64 loc("tests/generics/a_field_of_unit.lin":20:9)
    %sw19 = arith.trunci %v18 : i64 to i8 loc("tests/generics/a_field_of_unit.lin":19:5)
    llvm.store %sw19, %s4 : i8, !llvm.ptr loc("tests/generics/a_field_of_unit.lin":19:5)
    cf.br ^b3 loc("tests/generics/a_field_of_unit.lin":19:5)
  ^b2:
    %v22 = arith.constant 0 : i64 loc("tests/generics/a_field_of_unit.lin":22:9)
    %iw24 = llvm.load %s2 : !llvm.ptr -> i8 loc("tests/generics/a_field_of_unit.lin":22:9)
    %v24 = arith.extui %iw24 : i8 to i64 loc("tests/generics/a_field_of_unit.lin":22:9)
    %sw25 = arith.trunci %v24 : i64 to i8 loc("tests/generics/a_field_of_unit.lin":19:5)
    llvm.store %sw25, %s4 : i8, !llvm.ptr loc("tests/generics/a_field_of_unit.lin":19:5)
    cf.br ^b3 loc("tests/generics/a_field_of_unit.lin":19:5)
  ^b3:
    %lw27 = llvm.load %s4 : !llvm.ptr -> i8 loc("tests/generics/a_field_of_unit.lin":19:5)
    %v27 = arith.extui %lw27 : i8 to i64 loc("tests/generics/a_field_of_unit.lin":19:5)
    func.return %v27 : i64 loc("tests/generics/a_field_of_unit.lin":19:5)
  }
  func.func private @"lin.;both[UInt8,$28$29]"(%sret: !llvm.ptr, %a0: i64, %a1: i64) attributes {llvm.linkage = #llvm.linkage<internal>, passthrough = [["probe-stack", "inline-asm"]]} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 1 : i64
    %s1 = llvm.alloca %z1 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z2 = arith.constant 1 : i64
    %s2 = llvm.alloca %z2 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %pw0 = arith.trunci %a0 : i64 to i8
    llvm.store %pw0, %s0 : i8, !llvm.ptr
    llvm.store %a1, %s1 : i64, !llvm.ptr
    cf.br ^b0
  ^b0:
    %v1 = arith.constant 0 : i64 loc("tests/generics/a_field_of_unit.lin":10:5)
    %lw3 = llvm.load %s0 : !llvm.ptr -> i8 loc("tests/generics/a_field_of_unit.lin":10:17)
    %v3 = arith.extui %lw3 : i8 to i64 loc("tests/generics/a_field_of_unit.lin":10:17)
    %iw4 = arith.trunci %v3 : i64 to i8 loc("tests/generics/a_field_of_unit.lin":10:5)
    llvm.store %iw4, %s2 : i8, !llvm.ptr loc("tests/generics/a_field_of_unit.lin":10:5)
    %v5 = arith.constant 1 : i64 loc("tests/generics/a_field_of_unit.lin":10:5)
    %v6 = llvm.getelementptr %s2[%v5] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("tests/generics/a_field_of_unit.lin":10:5)
    %v7 = llvm.load %s1 : !llvm.ptr -> i64 loc("tests/generics/a_field_of_unit.lin":10:30)
    %rl8 = arith.constant 1 : i64 loc("tests/generics/a_field_of_unit.lin":10:5)
    "llvm.intr.memcpy"(%sret, %s2, %rl8) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("tests/generics/a_field_of_unit.lin":10:5)
    func.return loc("tests/generics/a_field_of_unit.lin":10:5)
  }
  func.func @main(%argc: i32, %argv: !llvm.ptr) -> i32 {
    func.call @linea_set_args(%argc, %argv) : (i32, !llvm.ptr) -> ()
    %status = func.call @"lin.;main"() : () -> i64
    %status32 = arith.trunci %status : i64 to i32
    func.return %status32 : i32
  }
}
