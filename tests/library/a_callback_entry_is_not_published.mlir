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
  llvm.mlir.global internal constant @linea_file0("tests/library/a_callback_entry_is_not_published/main.lin\00") : !llvm.array<57 x i8>
  func.func private @linea_set_args(i32, !llvm.ptr)
  func.func private @linea_trap(i32, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @linea_panic(i64, i64, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @visit(!llvm.ptr, !llvm.ptr) -> i32
  func.func private @"lin.;visited"() -> i64 attributes {llvm.linkage = #llvm.linkage<internal>, passthrough = [["probe-stack", "inline-asm"]]} {
    %z0 = arith.constant 8 : i64
    %s0 = llvm.alloca %z0 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 1 : i64
    %s1 = llvm.alloca %z1 x i32 {alignment = 4 : i64} : (i64) -> !llvm.ptr
    cf.br ^b0
  ^b0:
    %v1 = arith.constant 0 : i64 loc("tests/library/a_callback_entry_is_not_published/main.lin":15:17)
    %v3 = arith.constant 0 : i64 loc("tests/library/a_callback_entry_is_not_published/main.lin":15:33)
    llvm.store %v3, %s0 : i64, !llvm.ptr loc("tests/library/a_callback_entry_is_not_published/main.lin":15:17)
    %fa5 = func.constant @"lcb.;add" : (!llvm.ptr, i32) -> i32 loc("tests/library/a_callback_entry_is_not_published/main.lin":16:25)
    %v5 = builtin.unrealized_conversion_cast %fa5 : (!llvm.ptr, i32) -> i32 to !llvm.ptr loc("tests/library/a_callback_entry_is_not_published/main.lin":16:25)
    %vr7 = func.call @visit(%v5, %s0) : (!llvm.ptr, !llvm.ptr) -> i32 loc("tests/library/a_callback_entry_is_not_published/main.lin":16:19)
    %v7 = arith.extsi %vr7 : i32 to i64 loc("tests/library/a_callback_entry_is_not_published/main.lin":16:19)
    %sw8 = arith.trunci %v7 : i64 to i32 loc("tests/library/a_callback_entry_is_not_published/main.lin":16:5)
    llvm.store %sw8, %s1 : i32, !llvm.ptr loc("tests/library/a_callback_entry_is_not_published/main.lin":16:5)
    %v10 = arith.constant 0 : i64 loc("tests/library/a_callback_entry_is_not_published/main.lin":17:5)
    %v12 = llvm.load %s0 : !llvm.ptr -> i64 loc("tests/library/a_callback_entry_is_not_published/main.lin":17:5)
    func.return %v12 : i64 loc("tests/library/a_callback_entry_is_not_published/main.lin":17:5)
  }
  func.func private @"lin.;add"(%a0: !llvm.ptr, %a1: i64) -> i64 attributes {llvm.linkage = #llvm.linkage<internal>, passthrough = [["probe-stack", "inline-asm"]]} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x !llvm.ptr {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 1 : i64
    %s1 = llvm.alloca %z1 x i32 {alignment = 4 : i64} : (i64) -> !llvm.ptr
    llvm.store %a0, %s0 : !llvm.ptr, !llvm.ptr
    %pw1 = arith.trunci %a1 : i64 to i32
    llvm.store %pw1, %s1 : i32, !llvm.ptr
    cf.br ^b0
  ^b0:
    %lw0 = llvm.load %s1 : !llvm.ptr -> i32 loc("tests/library/a_callback_entry_is_not_published/main.lin":10:26)
    %v0 = arith.extsi %lw0 : i32 to i64 loc("tests/library/a_callback_entry_is_not_published/main.lin":10:26)
    %p1 = arith.constant 0 : i64 loc("tests/library/a_callback_entry_is_not_published/main.lin":10:20)
    %v1 = arith.addi %v0, %p1 : i64 loc("tests/library/a_callback_entry_is_not_published/main.lin":10:20)
    %v2 = llvm.load %s0 : !llvm.ptr -> !llvm.ptr loc("tests/library/a_callback_entry_is_not_published/main.lin":10:5)
    %v3 = arith.constant 0 : i64 loc("tests/library/a_callback_entry_is_not_published/main.lin":10:5)
    %v5 = llvm.load %v2 : !llvm.ptr -> i64 loc("tests/library/a_callback_entry_is_not_published/main.lin":10:5)
    %v6 = arith.addi %v5, %v1 : i64 loc("tests/library/a_callback_entry_is_not_published/main.lin":10:5)
    %k1a = arith.xori %v5, %v6 : i64 loc("tests/library/a_callback_entry_is_not_published/main.lin":10:17)
    %k1b = arith.xori %v1, %v6 : i64 loc("tests/library/a_callback_entry_is_not_published/main.lin":10:17)
    %k1c = arith.andi %k1a, %k1b : i64 loc("tests/library/a_callback_entry_is_not_published/main.lin":10:17)
    %k1z = arith.constant 0 : i64 loc("tests/library/a_callback_entry_is_not_published/main.lin":10:17)
    %k1 = arith.cmpi slt, %k1c, %k1z : i64 loc("tests/library/a_callback_entry_is_not_published/main.lin":10:17)
    cf.cond_br %k1, ^t1, ^c1 loc("tests/library/a_callback_entry_is_not_published/main.lin":10:17)
  ^t1:
    %tk1 = arith.constant 0 : i32 loc("tests/library/a_callback_entry_is_not_published/main.lin":10:17)
    %tf1 = llvm.mlir.addressof @linea_file0 : !llvm.ptr loc("tests/library/a_callback_entry_is_not_published/main.lin":10:17)
    %tl1 = arith.constant 10 : i32 loc("tests/library/a_callback_entry_is_not_published/main.lin":10:17)
    %tc1 = arith.constant 17 : i32 loc("tests/library/a_callback_entry_is_not_published/main.lin":10:17)
    func.call @linea_trap(%tk1, %tf1, %tl1, %tc1) : (i32, !llvm.ptr, i32, i32) -> () loc("tests/library/a_callback_entry_is_not_published/main.lin":10:17)
    llvm.unreachable loc("tests/library/a_callback_entry_is_not_published/main.lin":10:17)
  ^c1:
    %p7 = arith.constant 0 : i64 loc("tests/library/a_callback_entry_is_not_published/main.lin":10:17)
    %v7 = arith.addi %v6, %p7 : i64 loc("tests/library/a_callback_entry_is_not_published/main.lin":10:17)
    llvm.store %v7, %v2 : i64, !llvm.ptr loc("tests/library/a_callback_entry_is_not_published/main.lin":10:5)
    %v9 = arith.constant 0 : i64 loc("tests/library/a_callback_entry_is_not_published/main.lin":10:5)
    %v10 = arith.constant 0 : i64 loc("tests/library/a_callback_entry_is_not_published/main.lin":11:5)
    func.return %v10 : i64 loc("tests/library/a_callback_entry_is_not_published/main.lin":11:5)
  }
  func.func @visited() -> i64 {
    %answer = func.call @"lin.;visited"() : () -> i64
    func.return %answer : i64
  }
  func.func private @"lcb.;add"(%p0: !llvm.ptr, %p1: i32) -> i32 attributes {llvm.linkage = #llvm.linkage<internal>} {
    %w1 = arith.extsi %p1 : i32 to i64
    %answer = func.call @"lin.;add"(%p0, %w1) : (!llvm.ptr, i64) -> i64
    %narrow = arith.trunci %answer : i64 to i32
    func.return %narrow : i32
  }
}
