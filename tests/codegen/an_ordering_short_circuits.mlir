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
  llvm.mlir.global internal constant @linea_file0("tests/codegen/an_ordering_short_circuits.lin\00") : !llvm.array<45 x i8>
  func.func private @linea_set_args(i32, !llvm.ptr)
  func.func private @linea_trap(i32, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @linea_panic(i64, i64, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @"lin.;main"() -> i64 attributes {llvm.linkage = #llvm.linkage<internal>, passthrough = [["probe-stack", "inline-asm"]]} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 1 : i64
    %s1 = llvm.alloca %z1 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z2 = arith.constant 1 : i64
    %s2 = llvm.alloca %z2 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z3 = arith.constant 1 : i64
    %s3 = llvm.alloca %z3 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    cf.br ^b0
  ^b0:
    %v1 = arith.constant 0 : i64 loc("tests/codegen/an_ordering_short_circuits.lin":20:19)
    %v3 = arith.constant 1 : i64 loc("tests/codegen/an_ordering_short_circuits.lin":20:26)
    %iw4 = arith.trunci %v3 : i64 to i8 loc("tests/codegen/an_ordering_short_circuits.lin":20:19)
    llvm.store %iw4, %s0 : i8, !llvm.ptr loc("tests/codegen/an_ordering_short_circuits.lin":20:19)
    %v6 = arith.constant 0 : i64 loc("tests/codegen/an_ordering_short_circuits.lin":21:19)
    %v8 = arith.constant 1 : i64 loc("tests/codegen/an_ordering_short_circuits.lin":21:26)
    %iw9 = arith.trunci %v8 : i64 to i8 loc("tests/codegen/an_ordering_short_circuits.lin":21:19)
    llvm.store %iw9, %s1 : i8, !llvm.ptr loc("tests/codegen/an_ordering_short_circuits.lin":21:19)
    %v12 = func.call @"lin.Mark;std.cmp;Comparable.less"(%s0, %s1) : (!llvm.ptr, !llvm.ptr) -> i1 loc("tests/codegen/an_ordering_short_circuits.lin":22:8)
    cf.cond_br %v12, ^b1, ^b2 loc("tests/codegen/an_ordering_short_circuits.lin":22:8)
  ^b1:
    %v14 = arith.constant 1 : i1 loc("tests/codegen/an_ordering_short_circuits.lin":22:8)
    %sw15 = arith.extui %v14 : i1 to i8 loc("tests/codegen/an_ordering_short_circuits.lin":22:8)
    llvm.store %sw15, %s2 : i8, !llvm.ptr loc("tests/codegen/an_ordering_short_circuits.lin":22:8)
    cf.br ^b3 loc("tests/codegen/an_ordering_short_circuits.lin":22:8)
  ^b2:
    %v17 = func.call @"lin.Mark;std.cmp;Equatable.equals"(%s0, %s1) : (!llvm.ptr, !llvm.ptr) -> i1 loc("tests/codegen/an_ordering_short_circuits.lin":22:8)
    %sw18 = arith.extui %v17 : i1 to i8 loc("tests/codegen/an_ordering_short_circuits.lin":22:8)
    llvm.store %sw18, %s2 : i8, !llvm.ptr loc("tests/codegen/an_ordering_short_circuits.lin":22:8)
    cf.br ^b3 loc("tests/codegen/an_ordering_short_circuits.lin":22:8)
  ^b3:
    %lw20 = llvm.load %s2 : !llvm.ptr -> i8 loc("tests/codegen/an_ordering_short_circuits.lin":22:8)
    %lz20 = arith.constant 0 : i8 loc("tests/codegen/an_ordering_short_circuits.lin":22:8)
    %v20 = arith.cmpi ne, %lw20, %lz20 : i8 loc("tests/codegen/an_ordering_short_circuits.lin":22:8)
    cf.cond_br %v20, ^b4, ^b5 loc("tests/codegen/an_ordering_short_circuits.lin":22:5)
  ^b4:
    %v22 = arith.constant 0 : i64 loc("tests/codegen/an_ordering_short_circuits.lin":23:9)
    %sw23 = arith.trunci %v22 : i64 to i8 loc("tests/codegen/an_ordering_short_circuits.lin":22:5)
    llvm.store %sw23, %s3 : i8, !llvm.ptr loc("tests/codegen/an_ordering_short_circuits.lin":22:5)
    cf.br ^b6 loc("tests/codegen/an_ordering_short_circuits.lin":22:5)
  ^b5:
    %v25 = arith.constant 1 : i64 loc("tests/codegen/an_ordering_short_circuits.lin":25:9)
    %sw26 = arith.trunci %v25 : i64 to i8 loc("tests/codegen/an_ordering_short_circuits.lin":22:5)
    llvm.store %sw26, %s3 : i8, !llvm.ptr loc("tests/codegen/an_ordering_short_circuits.lin":22:5)
    cf.br ^b6 loc("tests/codegen/an_ordering_short_circuits.lin":22:5)
  ^b6:
    %lw28 = llvm.load %s3 : !llvm.ptr -> i8 loc("tests/codegen/an_ordering_short_circuits.lin":22:5)
    %v28 = arith.extui %lw28 : i8 to i64 loc("tests/codegen/an_ordering_short_circuits.lin":22:5)
    func.return %v28 : i64 loc("tests/codegen/an_ordering_short_circuits.lin":22:5)
  }
  func.func private @"lin.Mark;std.cmp;Comparable.less"(%a0: !llvm.ptr, %a1: !llvm.ptr) -> i1 attributes {llvm.linkage = #llvm.linkage<internal>, passthrough = [["probe-stack", "inline-asm"]]} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x !llvm.ptr {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 1 : i64
    %s1 = llvm.alloca %z1 x !llvm.ptr {alignment = 8 : i64} : (i64) -> !llvm.ptr
    llvm.store %a0, %s0 : !llvm.ptr, !llvm.ptr
    llvm.store %a1, %s1 : !llvm.ptr, !llvm.ptr
    cf.br ^b0
  ^b0:
    %v0 = llvm.load %s0 : !llvm.ptr -> !llvm.ptr loc("tests/codegen/an_ordering_short_circuits.lin":15:9)
    %v1 = arith.constant 0 : i64 loc("tests/codegen/an_ordering_short_circuits.lin":15:9)
    %iw3 = llvm.load %v0 : !llvm.ptr -> i8 loc("tests/codegen/an_ordering_short_circuits.lin":15:9)
    %v3 = arith.extui %iw3 : i8 to i64 loc("tests/codegen/an_ordering_short_circuits.lin":15:9)
    %v4 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("tests/codegen/an_ordering_short_circuits.lin":15:18)
    %v5 = arith.constant 0 : i64 loc("tests/codegen/an_ordering_short_circuits.lin":15:18)
    %iw7 = llvm.load %v4 : !llvm.ptr -> i8 loc("tests/codegen/an_ordering_short_circuits.lin":15:18)
    %v7 = arith.extui %iw7 : i8 to i64 loc("tests/codegen/an_ordering_short_circuits.lin":15:18)
    %v8 = arith.cmpi ult, %v3, %v7 : i64 loc("tests/codegen/an_ordering_short_circuits.lin":15:9)
    func.return %v8 : i1 loc("tests/codegen/an_ordering_short_circuits.lin":15:9)
  }
  func.func private @"lin.Mark;std.cmp;Equatable.equals"(%a0: !llvm.ptr, %a1: !llvm.ptr) -> i1 attributes {llvm.linkage = #llvm.linkage<internal>, passthrough = [["probe-stack", "inline-asm"]]} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x !llvm.ptr {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 1 : i64
    %s1 = llvm.alloca %z1 x !llvm.ptr {alignment = 8 : i64} : (i64) -> !llvm.ptr
    llvm.store %a0, %s0 : !llvm.ptr, !llvm.ptr
    llvm.store %a1, %s1 : !llvm.ptr, !llvm.ptr
    cf.br ^b0
  ^b0:
    %v0 = llvm.load %s0 : !llvm.ptr -> !llvm.ptr loc("tests/codegen/an_ordering_short_circuits.lin":9:9)
    %v1 = arith.constant 0 : i64 loc("tests/codegen/an_ordering_short_circuits.lin":9:9)
    %iw3 = llvm.load %v0 : !llvm.ptr -> i8 loc("tests/codegen/an_ordering_short_circuits.lin":9:9)
    %v3 = arith.extui %iw3 : i8 to i64 loc("tests/codegen/an_ordering_short_circuits.lin":9:9)
    %v4 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("tests/codegen/an_ordering_short_circuits.lin":9:19)
    %v5 = arith.constant 0 : i64 loc("tests/codegen/an_ordering_short_circuits.lin":9:19)
    %iw7 = llvm.load %v4 : !llvm.ptr -> i8 loc("tests/codegen/an_ordering_short_circuits.lin":9:19)
    %v7 = arith.extui %iw7 : i8 to i64 loc("tests/codegen/an_ordering_short_circuits.lin":9:19)
    %v8 = arith.cmpi eq, %v3, %v7 : i64 loc("tests/codegen/an_ordering_short_circuits.lin":9:9)
    func.return %v8 : i1 loc("tests/codegen/an_ordering_short_circuits.lin":9:9)
  }
  func.func @main(%argc: i32, %argv: !llvm.ptr) -> i32 {
    func.call @linea_set_args(%argc, %argv) : (i32, !llvm.ptr) -> ()
    %status = func.call @"lin.;main"() : () -> i64
    %status32 = arith.trunci %status : i64 to i32
    func.return %status32 : i32
  }
}
