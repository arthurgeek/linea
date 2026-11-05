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
  llvm.mlir.global internal constant @linea_file0("tests/codegen/an_aggregate_returned_from_a_branch.lin\00") : !llvm.array<54 x i8>
  func.func private @linea_set_args(i32, !llvm.ptr)
  func.func private @linea_trap(i32, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @linea_panic(i64, i64, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @"lin.;main"() -> i64 attributes {llvm.linkage = #llvm.linkage<internal>, passthrough = [["probe-stack", "inline-asm"]]} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 1 : i64
    %s1 = llvm.alloca %z1 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %rz1 = arith.constant 24 : i64
    %rs1 = llvm.alloca %rz1 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz6 = arith.constant 24 : i64
    %rs6 = llvm.alloca %rz6 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    cf.br ^b0
  ^b0:
    %v0 = arith.constant 1 : i1 loc("tests/codegen/an_aggregate_returned_from_a_branch.lin":32:34)
    func.call @"lin.;pick"(%rs1, %v0) : (!llvm.ptr, i1) -> () loc("tests/codegen/an_aggregate_returned_from_a_branch.lin":32:29)
    %v2 = func.call @"lin.;noise"() : () -> i64 loc("tests/codegen/an_aggregate_returned_from_a_branch.lin":32:41)
    %v3 = func.call @"lin.;take"(%rs1, %v2) : (!llvm.ptr, i64) -> i64 loc("tests/codegen/an_aggregate_returned_from_a_branch.lin":32:24)
    %sw4 = arith.trunci %v3 : i64 to i8 loc("tests/codegen/an_aggregate_returned_from_a_branch.lin":32:5)
    llvm.store %sw4, %s0 : i8, !llvm.ptr loc("tests/codegen/an_aggregate_returned_from_a_branch.lin":32:5)
    %v5 = arith.constant 0 : i1 loc("tests/codegen/an_aggregate_returned_from_a_branch.lin":33:35)
    func.call @"lin.;pick"(%rs6, %v5) : (!llvm.ptr, i1) -> () loc("tests/codegen/an_aggregate_returned_from_a_branch.lin":33:30)
    %v7 = func.call @"lin.;noise"() : () -> i64 loc("tests/codegen/an_aggregate_returned_from_a_branch.lin":33:43)
    %v8 = func.call @"lin.;take"(%rs6, %v7) : (!llvm.ptr, i64) -> i64 loc("tests/codegen/an_aggregate_returned_from_a_branch.lin":33:25)
    %sw9 = arith.trunci %v8 : i64 to i8 loc("tests/codegen/an_aggregate_returned_from_a_branch.lin":33:5)
    llvm.store %sw9, %s1 : i8, !llvm.ptr loc("tests/codegen/an_aggregate_returned_from_a_branch.lin":33:5)
    %lw10 = llvm.load %s0 : !llvm.ptr -> i8 loc("tests/codegen/an_aggregate_returned_from_a_branch.lin":34:5)
    %v10 = arith.extui %lw10 : i8 to i64 loc("tests/codegen/an_aggregate_returned_from_a_branch.lin":34:5)
    %lw11 = llvm.load %s1 : !llvm.ptr -> i8 loc("tests/codegen/an_aggregate_returned_from_a_branch.lin":34:13)
    %v11 = arith.extui %lw11 : i8 to i64 loc("tests/codegen/an_aggregate_returned_from_a_branch.lin":34:13)
    %v12 = arith.addi %v10, %v11 : i64 loc("tests/codegen/an_aggregate_returned_from_a_branch.lin":34:5)
    %k1m = arith.constant 255 : i64 loc("tests/codegen/an_aggregate_returned_from_a_branch.lin":34:11)
    %k1 = arith.cmpi ugt, %v12, %k1m : i64 loc("tests/codegen/an_aggregate_returned_from_a_branch.lin":34:11)
    cf.cond_br %k1, ^t1, ^c1 loc("tests/codegen/an_aggregate_returned_from_a_branch.lin":34:11)
  ^t1:
    %tk1 = arith.constant 0 : i32 loc("tests/codegen/an_aggregate_returned_from_a_branch.lin":34:11)
    %tf1 = llvm.mlir.addressof @linea_file0 : !llvm.ptr loc("tests/codegen/an_aggregate_returned_from_a_branch.lin":34:11)
    %tl1 = arith.constant 34 : i32 loc("tests/codegen/an_aggregate_returned_from_a_branch.lin":34:11)
    %tc1 = arith.constant 11 : i32 loc("tests/codegen/an_aggregate_returned_from_a_branch.lin":34:11)
    func.call @linea_trap(%tk1, %tf1, %tl1, %tc1) : (i32, !llvm.ptr, i32, i32) -> () loc("tests/codegen/an_aggregate_returned_from_a_branch.lin":34:11)
    llvm.unreachable loc("tests/codegen/an_aggregate_returned_from_a_branch.lin":34:11)
  ^c1:
    %p13 = arith.constant 0 : i64 loc("tests/codegen/an_aggregate_returned_from_a_branch.lin":34:11)
    %v13 = arith.addi %v12, %p13 : i64 loc("tests/codegen/an_aggregate_returned_from_a_branch.lin":34:11)
    func.return %v13 : i64 loc("tests/codegen/an_aggregate_returned_from_a_branch.lin":34:5)
  }
  func.func private @"lin.;pick"(%sret: !llvm.ptr, %a0: i1) attributes {llvm.linkage = #llvm.linkage<internal>, passthrough = [["probe-stack", "inline-asm"]]} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 24 : i64
    %s1 = llvm.alloca %z1 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z2 = arith.constant 24 : i64
    %s2 = llvm.alloca %z2 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %pw0 = arith.extui %a0 : i1 to i8
    llvm.store %pw0, %s0 : i8, !llvm.ptr
    cf.br ^b0
  ^b0:
    %lw0 = llvm.load %s0 : !llvm.ptr -> i8 loc("tests/codegen/an_aggregate_returned_from_a_branch.lin":15:8)
    %lz0 = arith.constant 0 : i8 loc("tests/codegen/an_aggregate_returned_from_a_branch.lin":15:8)
    %v0 = arith.cmpi ne, %lw0, %lz0 : i8 loc("tests/codegen/an_aggregate_returned_from_a_branch.lin":15:8)
    cf.cond_br %v0, ^b1, ^b2 loc("tests/codegen/an_aggregate_returned_from_a_branch.lin":15:5)
  ^b1:
    %v3 = arith.constant 0 : i64 loc("tests/codegen/an_aggregate_returned_from_a_branch.lin":16:16)
    %v5 = arith.constant 1 : i64 loc("tests/codegen/an_aggregate_returned_from_a_branch.lin":16:23)
    llvm.store %v5, %s1 : i64, !llvm.ptr loc("tests/codegen/an_aggregate_returned_from_a_branch.lin":16:16)
    %v7 = arith.constant 8 : i64 loc("tests/codegen/an_aggregate_returned_from_a_branch.lin":16:16)
    %v8 = llvm.getelementptr %s1[%v7] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("tests/codegen/an_aggregate_returned_from_a_branch.lin":16:16)
    %v9 = arith.constant 2 : i64 loc("tests/codegen/an_aggregate_returned_from_a_branch.lin":16:30)
    llvm.store %v9, %v8 : i64, !llvm.ptr loc("tests/codegen/an_aggregate_returned_from_a_branch.lin":16:16)
    %v11 = arith.constant 16 : i64 loc("tests/codegen/an_aggregate_returned_from_a_branch.lin":16:16)
    %v12 = llvm.getelementptr %s1[%v11] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("tests/codegen/an_aggregate_returned_from_a_branch.lin":16:16)
    %v13 = arith.constant 3 : i64 loc("tests/codegen/an_aggregate_returned_from_a_branch.lin":16:37)
    llvm.store %v13, %v12 : i64, !llvm.ptr loc("tests/codegen/an_aggregate_returned_from_a_branch.lin":16:16)
    %rl15 = arith.constant 24 : i64 loc("tests/codegen/an_aggregate_returned_from_a_branch.lin":16:9)
    "llvm.intr.memcpy"(%sret, %s1, %rl15) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("tests/codegen/an_aggregate_returned_from_a_branch.lin":16:9)
    func.return loc("tests/codegen/an_aggregate_returned_from_a_branch.lin":16:9)
  ^b2:
    cf.br ^b3 loc("tests/codegen/an_aggregate_returned_from_a_branch.lin":15:5)
  ^b3:
    %v19 = arith.constant 0 : i64 loc("tests/codegen/an_aggregate_returned_from_a_branch.lin":15:5)
    %v21 = arith.constant 0 : i64 loc("tests/codegen/an_aggregate_returned_from_a_branch.lin":18:5)
    %v23 = arith.constant 4 : i64 loc("tests/codegen/an_aggregate_returned_from_a_branch.lin":18:12)
    llvm.store %v23, %s2 : i64, !llvm.ptr loc("tests/codegen/an_aggregate_returned_from_a_branch.lin":18:5)
    %v25 = arith.constant 8 : i64 loc("tests/codegen/an_aggregate_returned_from_a_branch.lin":18:5)
    %v26 = llvm.getelementptr %s2[%v25] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("tests/codegen/an_aggregate_returned_from_a_branch.lin":18:5)
    %v27 = arith.constant 5 : i64 loc("tests/codegen/an_aggregate_returned_from_a_branch.lin":18:19)
    llvm.store %v27, %v26 : i64, !llvm.ptr loc("tests/codegen/an_aggregate_returned_from_a_branch.lin":18:5)
    %v29 = arith.constant 16 : i64 loc("tests/codegen/an_aggregate_returned_from_a_branch.lin":18:5)
    %v30 = llvm.getelementptr %s2[%v29] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("tests/codegen/an_aggregate_returned_from_a_branch.lin":18:5)
    %v31 = arith.constant 6 : i64 loc("tests/codegen/an_aggregate_returned_from_a_branch.lin":18:26)
    llvm.store %v31, %v30 : i64, !llvm.ptr loc("tests/codegen/an_aggregate_returned_from_a_branch.lin":18:5)
    %rl33 = arith.constant 24 : i64 loc("tests/codegen/an_aggregate_returned_from_a_branch.lin":18:5)
    "llvm.intr.memcpy"(%sret, %s2, %rl33) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("tests/codegen/an_aggregate_returned_from_a_branch.lin":18:5)
    func.return loc("tests/codegen/an_aggregate_returned_from_a_branch.lin":18:5)
  }
  func.func private @"lin.;noise"() -> i64 attributes {llvm.linkage = #llvm.linkage<internal>, passthrough = [["probe-stack", "inline-asm"]]} {
    %z0 = arith.constant 24 : i64
    %s0 = llvm.alloca %z0 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    cf.br ^b0
  ^b0:
    %v1 = arith.constant 0 : i64 loc("tests/codegen/an_aggregate_returned_from_a_branch.lin":22:18)
    %v3 = arith.constant 99 : i64 loc("tests/codegen/an_aggregate_returned_from_a_branch.lin":22:25)
    llvm.store %v3, %s0 : i64, !llvm.ptr loc("tests/codegen/an_aggregate_returned_from_a_branch.lin":22:18)
    %v5 = arith.constant 8 : i64 loc("tests/codegen/an_aggregate_returned_from_a_branch.lin":22:18)
    %v6 = llvm.getelementptr %s0[%v5] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("tests/codegen/an_aggregate_returned_from_a_branch.lin":22:18)
    %v7 = arith.constant 98 : i64 loc("tests/codegen/an_aggregate_returned_from_a_branch.lin":22:33)
    llvm.store %v7, %v6 : i64, !llvm.ptr loc("tests/codegen/an_aggregate_returned_from_a_branch.lin":22:18)
    %v9 = arith.constant 16 : i64 loc("tests/codegen/an_aggregate_returned_from_a_branch.lin":22:18)
    %v10 = llvm.getelementptr %s0[%v9] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("tests/codegen/an_aggregate_returned_from_a_branch.lin":22:18)
    %v11 = arith.constant 97 : i64 loc("tests/codegen/an_aggregate_returned_from_a_branch.lin":22:41)
    llvm.store %v11, %v10 : i64, !llvm.ptr loc("tests/codegen/an_aggregate_returned_from_a_branch.lin":22:18)
    %v14 = arith.constant 0 : i64 loc("tests/codegen/an_aggregate_returned_from_a_branch.lin":23:11)
    %v16 = llvm.load %s0 : !llvm.ptr -> i64 loc("tests/codegen/an_aggregate_returned_from_a_branch.lin":23:11)
    %k1m = arith.constant 255 : i64 loc("tests/codegen/an_aggregate_returned_from_a_branch.lin":23:5)
    %k1 = arith.cmpi ugt, %v16, %k1m : i64 loc("tests/codegen/an_aggregate_returned_from_a_branch.lin":23:5)
    cf.cond_br %k1, ^t1, ^c1 loc("tests/codegen/an_aggregate_returned_from_a_branch.lin":23:5)
  ^t1:
    %tk1 = arith.constant 2 : i32 loc("tests/codegen/an_aggregate_returned_from_a_branch.lin":23:5)
    %tf1 = llvm.mlir.addressof @linea_file0 : !llvm.ptr loc("tests/codegen/an_aggregate_returned_from_a_branch.lin":23:5)
    %tl1 = arith.constant 23 : i32 loc("tests/codegen/an_aggregate_returned_from_a_branch.lin":23:5)
    %tc1 = arith.constant 5 : i32 loc("tests/codegen/an_aggregate_returned_from_a_branch.lin":23:5)
    func.call @linea_trap(%tk1, %tf1, %tl1, %tc1) : (i32, !llvm.ptr, i32, i32) -> () loc("tests/codegen/an_aggregate_returned_from_a_branch.lin":23:5)
    llvm.unreachable loc("tests/codegen/an_aggregate_returned_from_a_branch.lin":23:5)
  ^c1:
    %p17 = arith.constant 0 : i64 loc("tests/codegen/an_aggregate_returned_from_a_branch.lin":23:5)
    %v17 = arith.addi %v16, %p17 : i64 loc("tests/codegen/an_aggregate_returned_from_a_branch.lin":23:5)
    func.return %v17 : i64 loc("tests/codegen/an_aggregate_returned_from_a_branch.lin":23:5)
  }
  func.func private @"lin.;take"(%a0: !llvm.ptr, %a1: i64) -> i64 attributes {llvm.linkage = #llvm.linkage<internal>, passthrough = [["probe-stack", "inline-asm"]]} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x !llvm.ptr {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 1 : i64
    %s1 = llvm.alloca %z1 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z2 = arith.constant 1 : i64
    %s2 = llvm.alloca %z2 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    llvm.store %a0, %s0 : !llvm.ptr, !llvm.ptr
    %pw1 = arith.trunci %a1 : i64 to i8
    llvm.store %pw1, %s1 : i8, !llvm.ptr
    cf.br ^b0
  ^b0:
    %lw0 = llvm.load %s1 : !llvm.ptr -> i8 loc("tests/codegen/an_aggregate_returned_from_a_branch.lin":27:13)
    %v0 = arith.extui %lw0 : i8 to i64 loc("tests/codegen/an_aggregate_returned_from_a_branch.lin":27:13)
    %sw1 = arith.trunci %v0 : i64 to i8 loc("tests/codegen/an_aggregate_returned_from_a_branch.lin":27:5)
    llvm.store %sw1, %s2 : i8, !llvm.ptr loc("tests/codegen/an_aggregate_returned_from_a_branch.lin":27:5)
    %v2 = llvm.load %s0 : !llvm.ptr -> !llvm.ptr loc("tests/codegen/an_aggregate_returned_from_a_branch.lin":28:11)
    %v3 = arith.constant 0 : i64 loc("tests/codegen/an_aggregate_returned_from_a_branch.lin":28:11)
    %v5 = llvm.load %v2 : !llvm.ptr -> i64 loc("tests/codegen/an_aggregate_returned_from_a_branch.lin":28:11)
    %k1m = arith.constant 255 : i64 loc("tests/codegen/an_aggregate_returned_from_a_branch.lin":28:5)
    %k1 = arith.cmpi ugt, %v5, %k1m : i64 loc("tests/codegen/an_aggregate_returned_from_a_branch.lin":28:5)
    cf.cond_br %k1, ^t1, ^c1 loc("tests/codegen/an_aggregate_returned_from_a_branch.lin":28:5)
  ^t1:
    %tk1 = arith.constant 2 : i32 loc("tests/codegen/an_aggregate_returned_from_a_branch.lin":28:5)
    %tf1 = llvm.mlir.addressof @linea_file0 : !llvm.ptr loc("tests/codegen/an_aggregate_returned_from_a_branch.lin":28:5)
    %tl1 = arith.constant 28 : i32 loc("tests/codegen/an_aggregate_returned_from_a_branch.lin":28:5)
    %tc1 = arith.constant 5 : i32 loc("tests/codegen/an_aggregate_returned_from_a_branch.lin":28:5)
    func.call @linea_trap(%tk1, %tf1, %tl1, %tc1) : (i32, !llvm.ptr, i32, i32) -> () loc("tests/codegen/an_aggregate_returned_from_a_branch.lin":28:5)
    llvm.unreachable loc("tests/codegen/an_aggregate_returned_from_a_branch.lin":28:5)
  ^c1:
    %p6 = arith.constant 0 : i64 loc("tests/codegen/an_aggregate_returned_from_a_branch.lin":28:5)
    %v6 = arith.addi %v5, %p6 : i64 loc("tests/codegen/an_aggregate_returned_from_a_branch.lin":28:5)
    func.return %v6 : i64 loc("tests/codegen/an_aggregate_returned_from_a_branch.lin":28:5)
  }
  func.func @main(%argc: i32, %argv: !llvm.ptr) -> i32 {
    func.call @linea_set_args(%argc, %argv) : (i32, !llvm.ptr) -> ()
    %status = func.call @"lin.;main"() : () -> i64
    %status32 = arith.trunci %status : i64 to i32
    func.return %status32 : i32
  }
}
