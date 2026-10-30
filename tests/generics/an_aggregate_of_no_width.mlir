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
  llvm.mlir.global internal constant @linea_file0("tests/generics/an_aggregate_of_no_width.lin\00") : !llvm.array<44 x i8>
  func.func private @linea_set_args(i32, !llvm.ptr)
  func.func private @linea_trap(i32, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @linea_panic(i64, i64, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @"lin.;main"() -> i64 attributes {llvm.linkage = #llvm.linkage<internal>, passthrough = [["probe-stack", "inline-asm"]]} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 0 : i64
    %s1 = llvm.alloca %z1 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z2 = arith.constant 1 : i64
    %s2 = llvm.alloca %z2 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z3 = arith.constant 1 : i64
    %s3 = llvm.alloca %z3 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %rz4 = arith.constant 0 : i64
    %rs4 = llvm.alloca %rz4 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    cf.br ^b0
  ^b0:
    %v0 = arith.constant -6148914691236517206 : i64 loc("tests/generics/an_aggregate_of_no_width.lin":29:25)
    llvm.store %v0, %s0 : i64, !llvm.ptr loc("tests/generics/an_aggregate_of_no_width.lin":29:5)
    %v3 = arith.constant 0 : i64 loc("tests/generics/an_aggregate_of_no_width.lin":30:18)
    func.call @"lin.;wrap[$28$29]"(%rs4, %v3) : (!llvm.ptr, i64) -> () loc("tests/generics/an_aggregate_of_no_width.lin":30:13)
    %cl5 = arith.constant 0 : i64 loc("tests/generics/an_aggregate_of_no_width.lin":30:5)
    "llvm.intr.memcpy"(%s1, %rs4, %cl5) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("tests/generics/an_aggregate_of_no_width.lin":30:5)
    %v7 = arith.constant 0 : i64 loc("tests/generics/an_aggregate_of_no_width.lin":31:25)
    %v9 = arith.constant 0 : i64 loc("tests/generics/an_aggregate_of_no_width.lin":31:25)
    llvm.store %v9, %s2 : i64, !llvm.ptr loc("tests/generics/an_aggregate_of_no_width.lin":31:5)
    %v11 = llvm.load %s0 : !llvm.ptr -> i64 loc("tests/generics/an_aggregate_of_no_width.lin":33:8)
    %v12 = arith.constant -6148914691236517206 : i64 loc("tests/generics/an_aggregate_of_no_width.lin":33:17)
    %v13 = arith.cmpi ne, %v11, %v12 : i64 loc("tests/generics/an_aggregate_of_no_width.lin":33:8)
    cf.cond_br %v13, ^b1, ^b2 loc("tests/generics/an_aggregate_of_no_width.lin":33:5)
  ^b1:
    %v15 = arith.constant 1 : i64 loc("tests/generics/an_aggregate_of_no_width.lin":34:9)
    %sw16 = arith.trunci %v15 : i64 to i8 loc("tests/generics/an_aggregate_of_no_width.lin":33:5)
    llvm.store %sw16, %s3 : i8, !llvm.ptr loc("tests/generics/an_aggregate_of_no_width.lin":33:5)
    cf.br ^b3 loc("tests/generics/an_aggregate_of_no_width.lin":33:5)
  ^b2:
    %v18 = arith.constant 7 : i64 loc("tests/generics/an_aggregate_of_no_width.lin":36:9)
    %sw19 = arith.trunci %v18 : i64 to i8 loc("tests/generics/an_aggregate_of_no_width.lin":33:5)
    llvm.store %sw19, %s3 : i8, !llvm.ptr loc("tests/generics/an_aggregate_of_no_width.lin":33:5)
    cf.br ^b3 loc("tests/generics/an_aggregate_of_no_width.lin":33:5)
  ^b3:
    %lw21 = llvm.load %s3 : !llvm.ptr -> i8 loc("tests/generics/an_aggregate_of_no_width.lin":33:5)
    %v21 = arith.extui %lw21 : i8 to i64 loc("tests/generics/an_aggregate_of_no_width.lin":33:5)
    func.return %v21 : i64 loc("tests/generics/an_aggregate_of_no_width.lin":33:5)
  }
  func.func private @"lin.;wrap[$28$29]"(%sret: !llvm.ptr, %a0: i64) attributes {llvm.linkage = #llvm.linkage<internal>, passthrough = [["probe-stack", "inline-asm"]]} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 1 : i64
    %s1 = llvm.alloca %z1 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z2 = arith.constant 0 : i64
    %s2 = llvm.alloca %z2 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z3 = arith.constant 0 : i64
    %s3 = llvm.alloca %z3 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    llvm.store %a0, %s0 : i64, !llvm.ptr
    cf.br ^b0
  ^b0:
    %v0 = arith.constant -81985529216486896 : i64 loc("tests/generics/an_aggregate_of_no_width.lin":18:25)
    llvm.store %v0, %s1 : i64, !llvm.ptr loc("tests/generics/an_aggregate_of_no_width.lin":18:5)
    %v3 = arith.constant 0 : i64 loc("tests/generics/an_aggregate_of_no_width.lin":19:23)
    %v5 = llvm.load %s0 : !llvm.ptr -> i64 loc("tests/generics/an_aggregate_of_no_width.lin":19:35)
    %v6 = llvm.load %s1 : !llvm.ptr -> i64 loc("tests/generics/an_aggregate_of_no_width.lin":21:8)
    %v7 = arith.constant -81985529216486896 : i64 loc("tests/generics/an_aggregate_of_no_width.lin":21:17)
    %v8 = arith.cmpi ne, %v6, %v7 : i64 loc("tests/generics/an_aggregate_of_no_width.lin":21:8)
    cf.cond_br %v8, ^b1, ^b2 loc("tests/generics/an_aggregate_of_no_width.lin":21:5)
  ^b1:
    %v11 = arith.constant 0 : i64 loc("tests/generics/an_aggregate_of_no_width.lin":22:9)
    %v13 = llvm.load %s0 : !llvm.ptr -> i64 loc("tests/generics/an_aggregate_of_no_width.lin":22:21)
    cf.br ^b3 loc("tests/generics/an_aggregate_of_no_width.lin":21:5)
  ^b2:
    %cl17 = arith.constant 0 : i64 loc("tests/generics/an_aggregate_of_no_width.lin":21:5)
    "llvm.intr.memcpy"(%s3, %s2, %cl17) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("tests/generics/an_aggregate_of_no_width.lin":21:5)
    cf.br ^b3 loc("tests/generics/an_aggregate_of_no_width.lin":21:5)
  ^b3:
    %rl20 = arith.constant 0 : i64 loc("tests/generics/an_aggregate_of_no_width.lin":21:5)
    "llvm.intr.memcpy"(%sret, %s3, %rl20) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("tests/generics/an_aggregate_of_no_width.lin":21:5)
    func.return loc("tests/generics/an_aggregate_of_no_width.lin":21:5)
  }
  func.func @main(%argc: i32, %argv: !llvm.ptr) -> i32 {
    func.call @linea_set_args(%argc, %argv) : (i32, !llvm.ptr) -> ()
    %status = func.call @"lin.;main"() : () -> i64
    %status32 = arith.trunci %status : i64 to i32
    func.return %status32 : i32
  }
}
