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
  llvm.mlir.global internal constant @linea_file0("tests/traits/a_named_length_spells_its_digits.lin\00") : !llvm.array<50 x i8>
  func.func private @linea_set_args(i32, !llvm.ptr)
  func.func private @linea_trap(i32, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @linea_panic(i64, i64, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @"lin.;main"() -> i64 attributes {llvm.linkage = #llvm.linkage<internal>} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 4 : i64
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
    %v1 = arith.constant 0 : i64 loc("tests/traits/a_named_length_spells_its_digits.lin":19:21)
    %v3 = arith.constant 7 : i64 loc("tests/traits/a_named_length_spells_its_digits.lin":19:28)
    %iw4 = arith.trunci %v3 : i64 to i8 loc("tests/traits/a_named_length_spells_its_digits.lin":19:21)
    llvm.store %iw4, %s0 : i8, !llvm.ptr loc("tests/traits/a_named_length_spells_its_digits.lin":19:21)
    %v6 = arith.constant 0 : i64 loc("tests/traits/a_named_length_spells_its_digits.lin":20:29)
    %v8 = arith.constant 1 : i64 loc("tests/traits/a_named_length_spells_its_digits.lin":20:30)
    %iw9 = arith.trunci %v8 : i64 to i8 loc("tests/traits/a_named_length_spells_its_digits.lin":20:29)
    llvm.store %iw9, %s1 : i8, !llvm.ptr loc("tests/traits/a_named_length_spells_its_digits.lin":20:29)
    %v10 = arith.constant 1 : i64 loc("tests/traits/a_named_length_spells_its_digits.lin":20:29)
    %v11 = llvm.getelementptr %s1[%v10] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("tests/traits/a_named_length_spells_its_digits.lin":20:29)
    %v12 = arith.constant 2 : i64 loc("tests/traits/a_named_length_spells_its_digits.lin":20:33)
    %iw13 = arith.trunci %v12 : i64 to i8 loc("tests/traits/a_named_length_spells_its_digits.lin":20:29)
    llvm.store %iw13, %v11 : i8, !llvm.ptr loc("tests/traits/a_named_length_spells_its_digits.lin":20:29)
    %v14 = arith.constant 2 : i64 loc("tests/traits/a_named_length_spells_its_digits.lin":20:29)
    %v15 = llvm.getelementptr %s1[%v14] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("tests/traits/a_named_length_spells_its_digits.lin":20:29)
    %v16 = arith.constant 3 : i64 loc("tests/traits/a_named_length_spells_its_digits.lin":20:36)
    %iw17 = arith.trunci %v16 : i64 to i8 loc("tests/traits/a_named_length_spells_its_digits.lin":20:29)
    llvm.store %iw17, %v15 : i8, !llvm.ptr loc("tests/traits/a_named_length_spells_its_digits.lin":20:29)
    %v18 = arith.constant 3 : i64 loc("tests/traits/a_named_length_spells_its_digits.lin":20:29)
    %v19 = llvm.getelementptr %s1[%v18] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("tests/traits/a_named_length_spells_its_digits.lin":20:29)
    %v20 = arith.constant 4 : i64 loc("tests/traits/a_named_length_spells_its_digits.lin":20:39)
    %iw21 = arith.trunci %v20 : i64 to i8 loc("tests/traits/a_named_length_spells_its_digits.lin":20:29)
    llvm.store %iw21, %v19 : i8, !llvm.ptr loc("tests/traits/a_named_length_spells_its_digits.lin":20:29)
    %v23 = arith.constant 0 : i64 loc("tests/traits/a_named_length_spells_its_digits.lin":21:28)
    %v25 = arith.constant 5 : i64 loc("tests/traits/a_named_length_spells_its_digits.lin":21:29)
    %iw26 = arith.trunci %v25 : i64 to i8 loc("tests/traits/a_named_length_spells_its_digits.lin":21:28)
    llvm.store %iw26, %s2 : i8, !llvm.ptr loc("tests/traits/a_named_length_spells_its_digits.lin":21:28)
    %v27 = arith.constant 1 : i64 loc("tests/traits/a_named_length_spells_its_digits.lin":21:28)
    %v28 = llvm.getelementptr %s2[%v27] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("tests/traits/a_named_length_spells_its_digits.lin":21:28)
    %v29 = arith.constant 6 : i64 loc("tests/traits/a_named_length_spells_its_digits.lin":21:32)
    %iw30 = arith.trunci %v29 : i64 to i8 loc("tests/traits/a_named_length_spells_its_digits.lin":21:28)
    llvm.store %iw30, %v28 : i8, !llvm.ptr loc("tests/traits/a_named_length_spells_its_digits.lin":21:28)
    %v31 = arith.constant 2 : i64 loc("tests/traits/a_named_length_spells_its_digits.lin":21:28)
    %v32 = llvm.getelementptr %s2[%v31] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("tests/traits/a_named_length_spells_its_digits.lin":21:28)
    %v33 = arith.constant 7 : i64 loc("tests/traits/a_named_length_spells_its_digits.lin":21:35)
    %iw34 = arith.trunci %v33 : i64 to i8 loc("tests/traits/a_named_length_spells_its_digits.lin":21:28)
    llvm.store %iw34, %v32 : i8, !llvm.ptr loc("tests/traits/a_named_length_spells_its_digits.lin":21:28)
    %v35 = arith.constant 3 : i64 loc("tests/traits/a_named_length_spells_its_digits.lin":21:28)
    %v36 = llvm.getelementptr %s2[%v35] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("tests/traits/a_named_length_spells_its_digits.lin":21:28)
    %v37 = arith.constant 8 : i64 loc("tests/traits/a_named_length_spells_its_digits.lin":21:38)
    %iw38 = arith.trunci %v37 : i64 to i8 loc("tests/traits/a_named_length_spells_its_digits.lin":21:28)
    llvm.store %iw38, %v36 : i8, !llvm.ptr loc("tests/traits/a_named_length_spells_its_digits.lin":21:28)
    %v41 = func.call @"lin.;Holder.give[[UInt8;4]]"(%s0, %s1) : (!llvm.ptr, !llvm.ptr) -> i64 loc("tests/traits/a_named_length_spells_its_digits.lin":22:13)
    %sw42 = arith.trunci %v41 : i64 to i8 loc("tests/traits/a_named_length_spells_its_digits.lin":22:5)
    llvm.store %sw42, %s3 : i8, !llvm.ptr loc("tests/traits/a_named_length_spells_its_digits.lin":22:5)
    %v45 = func.call @"lin.;Holder.give[[UInt8;4]]"(%s0, %s2) : (!llvm.ptr, !llvm.ptr) -> i64 loc("tests/traits/a_named_length_spells_its_digits.lin":23:13)
    %sw46 = arith.trunci %v45 : i64 to i8 loc("tests/traits/a_named_length_spells_its_digits.lin":23:5)
    llvm.store %sw46, %s4 : i8, !llvm.ptr loc("tests/traits/a_named_length_spells_its_digits.lin":23:5)
    %cl49 = arith.constant 1 : i64 loc("tests/traits/a_named_length_spells_its_digits.lin":24:5)
    "llvm.intr.memcpy"(%s5, %s0, %cl49) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("tests/traits/a_named_length_spells_its_digits.lin":24:5)
    %lw50 = llvm.load %s3 : !llvm.ptr -> i8 loc("tests/traits/a_named_length_spells_its_digits.lin":25:5)
    %v50 = arith.extui %lw50 : i8 to i64 loc("tests/traits/a_named_length_spells_its_digits.lin":25:5)
    %lw51 = llvm.load %s4 : !llvm.ptr -> i8 loc("tests/traits/a_named_length_spells_its_digits.lin":25:9)
    %v51 = arith.extui %lw51 : i8 to i64 loc("tests/traits/a_named_length_spells_its_digits.lin":25:9)
    %v52 = arith.addi %v50, %v51 : i64 loc("tests/traits/a_named_length_spells_its_digits.lin":25:5)
    %k1m = arith.constant 255 : i64 loc("tests/traits/a_named_length_spells_its_digits.lin":25:7)
    %k1 = arith.cmpi ugt, %v52, %k1m : i64 loc("tests/traits/a_named_length_spells_its_digits.lin":25:7)
    cf.cond_br %k1, ^t1, ^c1 loc("tests/traits/a_named_length_spells_its_digits.lin":25:7)
  ^t1:
    %tk1 = arith.constant 0 : i32 loc("tests/traits/a_named_length_spells_its_digits.lin":25:7)
    %tf1 = llvm.mlir.addressof @linea_file0 : !llvm.ptr loc("tests/traits/a_named_length_spells_its_digits.lin":25:7)
    %tl1 = arith.constant 25 : i32 loc("tests/traits/a_named_length_spells_its_digits.lin":25:7)
    %tc1 = arith.constant 7 : i32 loc("tests/traits/a_named_length_spells_its_digits.lin":25:7)
    func.call @linea_trap(%tk1, %tf1, %tl1, %tc1) : (i32, !llvm.ptr, i32, i32) -> () loc("tests/traits/a_named_length_spells_its_digits.lin":25:7)
    llvm.unreachable loc("tests/traits/a_named_length_spells_its_digits.lin":25:7)
  ^c1:
    %p53 = arith.constant 0 : i64 loc("tests/traits/a_named_length_spells_its_digits.lin":25:7)
    %v53 = arith.addi %v52, %p53 : i64 loc("tests/traits/a_named_length_spells_its_digits.lin":25:7)
    func.return %v53 : i64 loc("tests/traits/a_named_length_spells_its_digits.lin":25:5)
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
    %v0 = llvm.load %s0 : !llvm.ptr -> !llvm.ptr loc("tests/traits/a_named_length_spells_its_digits.lin":14:9)
    %v1 = arith.constant 0 : i64 loc("tests/traits/a_named_length_spells_its_digits.lin":14:9)
    %iw3 = llvm.load %v0 : !llvm.ptr -> i8 loc("tests/traits/a_named_length_spells_its_digits.lin":14:9)
    %v3 = arith.extui %iw3 : i8 to i64 loc("tests/traits/a_named_length_spells_its_digits.lin":14:9)
    func.return %v3 : i64 loc("tests/traits/a_named_length_spells_its_digits.lin":14:9)
  }
  func.func @main(%argc: i32, %argv: !llvm.ptr) -> i32 {
    func.call @linea_set_args(%argc, %argv) : (i32, !llvm.ptr) -> ()
    %status = func.call @"lin.;main"() : () -> i64
    %status32 = arith.trunci %status : i64 to i32
    func.return %status32 : i32
  }
}
