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
  llvm.mlir.global internal constant @linea_file0("tests/structs/a_copy_owns_its_storage.lin\00") : !llvm.array<42 x i8>
  func.func private @linea_set_args(i32, !llvm.ptr)
  func.func private @linea_trap(i32, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @linea_panic(i64, i64, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @"lin.;main"() -> i64 attributes {llvm.linkage = #llvm.linkage<internal>, passthrough = [["probe-stack", "inline-asm"]]} {
    %z0 = arith.constant 2 : i64
    %s0 = llvm.alloca %z0 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 1 : i64
    %s1 = llvm.alloca %z1 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z2 = arith.constant 2 : i64
    %s2 = llvm.alloca %z2 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    cf.br ^b0
  ^b0:
    %v1 = arith.constant 0 : i64 loc("tests/structs/a_copy_owns_its_storage.lin":23:16)
    %v3 = arith.constant 1 : i64 loc("tests/structs/a_copy_owns_its_storage.lin":23:23)
    %iw4 = arith.trunci %v3 : i64 to i8 loc("tests/structs/a_copy_owns_its_storage.lin":23:16)
    llvm.store %iw4, %s0 : i8, !llvm.ptr loc("tests/structs/a_copy_owns_its_storage.lin":23:16)
    %v5 = arith.constant 1 : i64 loc("tests/structs/a_copy_owns_its_storage.lin":23:16)
    %v6 = llvm.getelementptr %s0[%v5] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("tests/structs/a_copy_owns_its_storage.lin":23:16)
    %v7 = arith.constant 2 : i64 loc("tests/structs/a_copy_owns_its_storage.lin":23:30)
    %iw8 = arith.trunci %v7 : i64 to i8 loc("tests/structs/a_copy_owns_its_storage.lin":23:16)
    llvm.store %iw8, %v6 : i8, !llvm.ptr loc("tests/structs/a_copy_owns_its_storage.lin":23:16)
    %cl11 = arith.constant 2 : i64 loc("tests/structs/a_copy_owns_its_storage.lin":24:25)
    "llvm.intr.memcpy"(%s2, %s0, %cl11) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("tests/structs/a_copy_owns_its_storage.lin":24:25)
    %v13 = func.call @"lin.;take"(%s2) : (!llvm.ptr) -> i64 loc("tests/structs/a_copy_owns_its_storage.lin":24:20)
    %sw14 = arith.trunci %v13 : i64 to i8 loc("tests/structs/a_copy_owns_its_storage.lin":24:5)
    llvm.store %sw14, %s1 : i8, !llvm.ptr loc("tests/structs/a_copy_owns_its_storage.lin":24:5)
    %v15 = arith.constant 9 : i64 loc("tests/structs/a_copy_owns_its_storage.lin":25:11)
    %v17 = arith.constant 0 : i64 loc("tests/structs/a_copy_owns_its_storage.lin":25:5)
    %iw19 = arith.trunci %v15 : i64 to i8 loc("tests/structs/a_copy_owns_its_storage.lin":25:5)
    llvm.store %iw19, %s0 : i8, !llvm.ptr loc("tests/structs/a_copy_owns_its_storage.lin":25:5)
    %v20 = arith.constant 0 : i64 loc("tests/structs/a_copy_owns_its_storage.lin":25:5)
    %lw21 = llvm.load %s1 : !llvm.ptr -> i8 loc("tests/structs/a_copy_owns_its_storage.lin":26:5)
    %v21 = arith.extui %lw21 : i8 to i64 loc("tests/structs/a_copy_owns_its_storage.lin":26:5)
    %v23 = arith.constant 0 : i64 loc("tests/structs/a_copy_owns_its_storage.lin":26:9)
    %iw25 = llvm.load %s0 : !llvm.ptr -> i8 loc("tests/structs/a_copy_owns_its_storage.lin":26:9)
    %v25 = arith.extui %iw25 : i8 to i64 loc("tests/structs/a_copy_owns_its_storage.lin":26:9)
    %v26 = arith.addi %v21, %v25 : i64 loc("tests/structs/a_copy_owns_its_storage.lin":26:5)
    %k1m = arith.constant 255 : i64 loc("tests/structs/a_copy_owns_its_storage.lin":26:7)
    %k1 = arith.cmpi ugt, %v26, %k1m : i64 loc("tests/structs/a_copy_owns_its_storage.lin":26:7)
    cf.cond_br %k1, ^t1, ^c1 loc("tests/structs/a_copy_owns_its_storage.lin":26:7)
  ^t1:
    %tk1 = arith.constant 0 : i32 loc("tests/structs/a_copy_owns_its_storage.lin":26:7)
    %tf1 = llvm.mlir.addressof @linea_file0 : !llvm.ptr loc("tests/structs/a_copy_owns_its_storage.lin":26:7)
    %tl1 = arith.constant 26 : i32 loc("tests/structs/a_copy_owns_its_storage.lin":26:7)
    %tc1 = arith.constant 7 : i32 loc("tests/structs/a_copy_owns_its_storage.lin":26:7)
    func.call @linea_trap(%tk1, %tf1, %tl1, %tc1) : (i32, !llvm.ptr, i32, i32) -> () loc("tests/structs/a_copy_owns_its_storage.lin":26:7)
    llvm.unreachable loc("tests/structs/a_copy_owns_its_storage.lin":26:7)
  ^c1:
    %p27 = arith.constant 0 : i64 loc("tests/structs/a_copy_owns_its_storage.lin":26:7)
    %v27 = arith.addi %v26, %p27 : i64 loc("tests/structs/a_copy_owns_its_storage.lin":26:7)
    func.return %v27 : i64 loc("tests/structs/a_copy_owns_its_storage.lin":26:5)
  }
  func.func private @"lin.;take"(%a0: !llvm.ptr) -> i64 attributes {llvm.linkage = #llvm.linkage<internal>, passthrough = [["probe-stack", "inline-asm"]]} {
    %z0 = arith.constant 2 : i64
    %s0 = llvm.alloca %z0 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %pl0 = arith.constant 2 : i64
    "llvm.intr.memcpy"(%s0, %a0, %pl0) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> ()
    cf.br ^b0
  ^b0:
    %v1 = arith.constant 0 : i64 loc("tests/structs/a_copy_owns_its_storage.lin":19:5)
    %iw3 = llvm.load %s0 : !llvm.ptr -> i8 loc("tests/structs/a_copy_owns_its_storage.lin":19:5)
    %v3 = arith.extui %iw3 : i8 to i64 loc("tests/structs/a_copy_owns_its_storage.lin":19:5)
    func.return %v3 : i64 loc("tests/structs/a_copy_owns_its_storage.lin":19:5)
  }
  func.func @main(%argc: i32, %argv: !llvm.ptr) -> i32 {
    func.call @linea_set_args(%argc, %argv) : (i32, !llvm.ptr) -> ()
    %status = func.call @"lin.;main"() : () -> i64
    %status32 = arith.trunci %status : i64 to i32
    func.return %status32 : i32
  }
}
