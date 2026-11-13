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
  llvm.mlir.global internal constant @linea_file0("tests/library/a_library_granted_extern_declares_one/main.lin\00") : !llvm.array<61 x i8>
  llvm.mlir.global internal constant @linea_file1("std/time/time.lin\00") : !llvm.array<18 x i8>
  func.func private @linea_set_args(i32, !llvm.ptr)
  func.func private @linea_foreign_enter()
  func.func private @linea_foreign_leave()
  func.func private @linea_trap(i32, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @linea_panic(i64, i64, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @linea_clock_sleep(i64) -> i64
  func.func private @"lin.;pause"(%a0: i64) -> i64 attributes {llvm.linkage = #llvm.linkage<internal>, passthrough = [["probe-stack", "inline-asm"]]} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    llvm.store %a0, %s0 : i64, !llvm.ptr
    cf.br ^b0
  ^b0:
    %v0 = llvm.load %s0 : !llvm.ptr -> i64 loc("tests/library/a_library_granted_extern_declares_one/main.lin":4:23)
    %v1 = func.call @linea_clock_sleep(%v0) : (i64) -> i64 loc("tests/library/a_library_granted_extern_declares_one/main.lin":4:5)
    func.return %v1 : i64 loc("tests/library/a_library_granted_extern_declares_one/main.lin":4:5)
  }
  func.func @pause(%p0: i64) -> i64 {
    func.call @linea_foreign_enter() : () -> ()
    %answer = func.call @"lin.;pause"(%p0) : (i64) -> i64
    func.call @linea_foreign_leave() : () -> ()
    func.return %answer : i64
  }
}
