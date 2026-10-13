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
  llvm.mlir.global internal constant @linea_file0("tests/traits/two_lengths_are_two_symbols.lin\00") : !llvm.array<45 x i8>
  func.func private @linea_set_args(i32, !llvm.ptr)
  func.func private @linea_trap(i32, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @linea_panic(i64, i64, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @"lin.;main"() -> i64 attributes {llvm.linkage = #llvm.linkage<internal>} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 2 : i64
    %s1 = llvm.alloca %z1 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z2 = arith.constant 4 : i64
    %s2 = llvm.alloca %z2 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z3 = arith.constant 1 : i64
    %s3 = llvm.alloca %z3 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z4 = arith.constant 1 : i64
    %s4 = llvm.alloca %z4 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z5 = arith.constant 1 : i64
    %s5 = llvm.alloca %z5 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    cf.br ^b0
  ^b0:
    %v1 = arith.constant 0 : i64 loc("tests/traits/two_lengths_are_two_symbols.lin":16:21)
    %v3 = arith.constant 7 : i64 loc("tests/traits/two_lengths_are_two_symbols.lin":16:28)
    %iw4 = arith.trunci %v3 : i64 to i8 loc("tests/traits/two_lengths_are_two_symbols.lin":16:21)
    llvm.store %iw4, %s0 : i8, !llvm.ptr loc("tests/traits/two_lengths_are_two_symbols.lin":16:21)
    %v6 = arith.constant 0 : i64 loc("tests/traits/two_lengths_are_two_symbols.lin":17:27)
    %v8 = arith.constant 1 : i64 loc("tests/traits/two_lengths_are_two_symbols.lin":17:28)
    %iw9 = arith.trunci %v8 : i64 to i8 loc("tests/traits/two_lengths_are_two_symbols.lin":17:27)
    llvm.store %iw9, %s1 : i8, !llvm.ptr loc("tests/traits/two_lengths_are_two_symbols.lin":17:27)
    %v10 = arith.constant 1 : i64 loc("tests/traits/two_lengths_are_two_symbols.lin":17:27)
    %v11 = llvm.getelementptr %s1[%v10] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("tests/traits/two_lengths_are_two_symbols.lin":17:27)
    %v12 = arith.constant 2 : i64 loc("tests/traits/two_lengths_are_two_symbols.lin":17:31)
    %iw13 = arith.trunci %v12 : i64 to i8 loc("tests/traits/two_lengths_are_two_symbols.lin":17:27)
    llvm.store %iw13, %v11 : i8, !llvm.ptr loc("tests/traits/two_lengths_are_two_symbols.lin":17:27)
    %v15 = arith.constant 0 : i64 loc("tests/traits/two_lengths_are_two_symbols.lin":18:28)
    %v17 = arith.constant 1 : i64 loc("tests/traits/two_lengths_are_two_symbols.lin":18:29)
    %iw18 = arith.trunci %v17 : i64 to i8 loc("tests/traits/two_lengths_are_two_symbols.lin":18:28)
    llvm.store %iw18, %s2 : i8, !llvm.ptr loc("tests/traits/two_lengths_are_two_symbols.lin":18:28)
    %v19 = arith.constant 1 : i64 loc("tests/traits/two_lengths_are_two_symbols.lin":18:28)
    %v20 = llvm.getelementptr %s2[%v19] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("tests/traits/two_lengths_are_two_symbols.lin":18:28)
    %v21 = arith.constant 2 : i64 loc("tests/traits/two_lengths_are_two_symbols.lin":18:32)
    %iw22 = arith.trunci %v21 : i64 to i8 loc("tests/traits/two_lengths_are_two_symbols.lin":18:28)
    llvm.store %iw22, %v20 : i8, !llvm.ptr loc("tests/traits/two_lengths_are_two_symbols.lin":18:28)
    %v23 = arith.constant 2 : i64 loc("tests/traits/two_lengths_are_two_symbols.lin":18:28)
    %v24 = llvm.getelementptr %s2[%v23] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("tests/traits/two_lengths_are_two_symbols.lin":18:28)
    %v25 = arith.constant 3 : i64 loc("tests/traits/two_lengths_are_two_symbols.lin":18:35)
    %iw26 = arith.trunci %v25 : i64 to i8 loc("tests/traits/two_lengths_are_two_symbols.lin":18:28)
    llvm.store %iw26, %v24 : i8, !llvm.ptr loc("tests/traits/two_lengths_are_two_symbols.lin":18:28)
    %v27 = arith.constant 3 : i64 loc("tests/traits/two_lengths_are_two_symbols.lin":18:28)
    %v28 = llvm.getelementptr %s2[%v27] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("tests/traits/two_lengths_are_two_symbols.lin":18:28)
    %v29 = arith.constant 4 : i64 loc("tests/traits/two_lengths_are_two_symbols.lin":18:38)
    %iw30 = arith.trunci %v29 : i64 to i8 loc("tests/traits/two_lengths_are_two_symbols.lin":18:28)
    llvm.store %iw30, %v28 : i8, !llvm.ptr loc("tests/traits/two_lengths_are_two_symbols.lin":18:28)
    %v33 = func.call @"lin.;Holder.give[[UInt8;2]]"(%s0, %s1) : (!llvm.ptr, !llvm.ptr) -> i64 loc("tests/traits/two_lengths_are_two_symbols.lin":19:13)
    %sw34 = arith.trunci %v33 : i64 to i8 loc("tests/traits/two_lengths_are_two_symbols.lin":19:5)
    llvm.store %sw34, %s3 : i8, !llvm.ptr loc("tests/traits/two_lengths_are_two_symbols.lin":19:5)
    %v37 = func.call @"lin.;Holder.give[[UInt8;4]]"(%s0, %s2) : (!llvm.ptr, !llvm.ptr) -> i64 loc("tests/traits/two_lengths_are_two_symbols.lin":20:13)
    %sw38 = arith.trunci %v37 : i64 to i8 loc("tests/traits/two_lengths_are_two_symbols.lin":20:5)
    llvm.store %sw38, %s4 : i8, !llvm.ptr loc("tests/traits/two_lengths_are_two_symbols.lin":20:5)
    %cl41 = arith.constant 1 : i64 loc("tests/traits/two_lengths_are_two_symbols.lin":21:5)
    "llvm.intr.memcpy"(%s5, %s0, %cl41) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("tests/traits/two_lengths_are_two_symbols.lin":21:5)
    %lw42 = llvm.load %s3 : !llvm.ptr -> i8 loc("tests/traits/two_lengths_are_two_symbols.lin":22:5)
    %v42 = arith.extui %lw42 : i8 to i64 loc("tests/traits/two_lengths_are_two_symbols.lin":22:5)
    %lw43 = llvm.load %s4 : !llvm.ptr -> i8 loc("tests/traits/two_lengths_are_two_symbols.lin":22:9)
    %v43 = arith.extui %lw43 : i8 to i64 loc("tests/traits/two_lengths_are_two_symbols.lin":22:9)
    %v44 = arith.addi %v42, %v43 : i64 loc("tests/traits/two_lengths_are_two_symbols.lin":22:5)
    %k1m = arith.constant 255 : i64 loc("tests/traits/two_lengths_are_two_symbols.lin":22:7)
    %k1 = arith.cmpi ugt, %v44, %k1m : i64 loc("tests/traits/two_lengths_are_two_symbols.lin":22:7)
    cf.cond_br %k1, ^t1, ^c1 loc("tests/traits/two_lengths_are_two_symbols.lin":22:7)
  ^t1:
    %tk1 = arith.constant 0 : i32 loc("tests/traits/two_lengths_are_two_symbols.lin":22:7)
    %tf1 = llvm.mlir.addressof @linea_file0 : !llvm.ptr loc("tests/traits/two_lengths_are_two_symbols.lin":22:7)
    %tl1 = arith.constant 22 : i32 loc("tests/traits/two_lengths_are_two_symbols.lin":22:7)
    %tc1 = arith.constant 7 : i32 loc("tests/traits/two_lengths_are_two_symbols.lin":22:7)
    func.call @linea_trap(%tk1, %tf1, %tl1, %tc1) : (i32, !llvm.ptr, i32, i32) -> () loc("tests/traits/two_lengths_are_two_symbols.lin":22:7)
    llvm.unreachable loc("tests/traits/two_lengths_are_two_symbols.lin":22:7)
  ^c1:
    %p45 = arith.constant 0 : i64 loc("tests/traits/two_lengths_are_two_symbols.lin":22:7)
    %v45 = arith.addi %v44, %p45 : i64 loc("tests/traits/two_lengths_are_two_symbols.lin":22:7)
    func.return %v45 : i64 loc("tests/traits/two_lengths_are_two_symbols.lin":22:5)
  }
  func.func private @"lin.;Holder.give[[UInt8;2]]"(%a0: !llvm.ptr, %a1: !llvm.ptr) -> i64 attributes {llvm.linkage = #llvm.linkage<internal>} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x !llvm.ptr {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 1 : i64
    %s1 = llvm.alloca %z1 x !llvm.ptr {alignment = 8 : i64} : (i64) -> !llvm.ptr
    llvm.store %a0, %s0 : !llvm.ptr, !llvm.ptr
    llvm.store %a1, %s1 : !llvm.ptr, !llvm.ptr
    cf.br ^b0
  ^b0:
    %v0 = llvm.load %s0 : !llvm.ptr -> !llvm.ptr loc("tests/traits/two_lengths_are_two_symbols.lin":11:9)
    %v1 = arith.constant 0 : i64 loc("tests/traits/two_lengths_are_two_symbols.lin":11:9)
    %iw3 = llvm.load %v0 : !llvm.ptr -> i8 loc("tests/traits/two_lengths_are_two_symbols.lin":11:9)
    %v3 = arith.extui %iw3 : i8 to i64 loc("tests/traits/two_lengths_are_two_symbols.lin":11:9)
    func.return %v3 : i64 loc("tests/traits/two_lengths_are_two_symbols.lin":11:9)
  }
  func.func private @"lin.;Holder.give[[UInt8;4]]"(%a0: !llvm.ptr, %a1: !llvm.ptr) -> i64 attributes {llvm.linkage = #llvm.linkage<internal>} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x !llvm.ptr {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 1 : i64
    %s1 = llvm.alloca %z1 x !llvm.ptr {alignment = 8 : i64} : (i64) -> !llvm.ptr
    llvm.store %a0, %s0 : !llvm.ptr, !llvm.ptr
    llvm.store %a1, %s1 : !llvm.ptr, !llvm.ptr
    cf.br ^b0
  ^b0:
    %v0 = llvm.load %s0 : !llvm.ptr -> !llvm.ptr loc("tests/traits/two_lengths_are_two_symbols.lin":11:9)
    %v1 = arith.constant 0 : i64 loc("tests/traits/two_lengths_are_two_symbols.lin":11:9)
    %iw3 = llvm.load %v0 : !llvm.ptr -> i8 loc("tests/traits/two_lengths_are_two_symbols.lin":11:9)
    %v3 = arith.extui %iw3 : i8 to i64 loc("tests/traits/two_lengths_are_two_symbols.lin":11:9)
    func.return %v3 : i64 loc("tests/traits/two_lengths_are_two_symbols.lin":11:9)
  }
  func.func @main(%argc: i32, %argv: !llvm.ptr) -> i32 {
    func.call @linea_set_args(%argc, %argv) : (i32, !llvm.ptr) -> ()
    %status = func.call @"lin.;main"() : () -> i64
    %status32 = arith.trunci %status : i64 to i32
    func.return %status32 : i32
  }
}
