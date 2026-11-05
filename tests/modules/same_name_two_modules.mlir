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
  llvm.mlir.global internal constant @linea_file0("tests/modules/same_name_two_modules/main.lin\00") : !llvm.array<45 x i8>
  llvm.mlir.global internal constant @linea_file1("tests/modules/same_name_two_modules/a/a.lin\00") : !llvm.array<44 x i8>
  llvm.mlir.global internal constant @linea_file2("tests/modules/same_name_two_modules/b/b.lin\00") : !llvm.array<44 x i8>
  func.func private @linea_set_args(i32, !llvm.ptr)
  func.func private @linea_trap(i32, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @linea_panic(i64, i64, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @"lin.;main"() -> i64 attributes {llvm.linkage = #llvm.linkage<internal>, passthrough = [["probe-stack", "inline-asm"]]} {
    cf.br ^b0
  ^b0:
    %v0 = func.call @"lin.a;open"() : () -> i64 loc("tests/modules/same_name_two_modules/main.lin":9:5)
    %v1 = func.call @"lin.b;open"() : () -> i64 loc("tests/modules/same_name_two_modules/main.lin":9:16)
    %v2 = arith.addi %v0, %v1 : i64 loc("tests/modules/same_name_two_modules/main.lin":9:5)
    %k1m = arith.constant 255 : i64 loc("tests/modules/same_name_two_modules/main.lin":9:14)
    %k1 = arith.cmpi ugt, %v2, %k1m : i64 loc("tests/modules/same_name_two_modules/main.lin":9:14)
    cf.cond_br %k1, ^t1, ^c1 loc("tests/modules/same_name_two_modules/main.lin":9:14)
  ^t1:
    %tk1 = arith.constant 0 : i32 loc("tests/modules/same_name_two_modules/main.lin":9:14)
    %tf1 = llvm.mlir.addressof @linea_file0 : !llvm.ptr loc("tests/modules/same_name_two_modules/main.lin":9:14)
    %tl1 = arith.constant 9 : i32 loc("tests/modules/same_name_two_modules/main.lin":9:14)
    %tc1 = arith.constant 14 : i32 loc("tests/modules/same_name_two_modules/main.lin":9:14)
    func.call @linea_trap(%tk1, %tf1, %tl1, %tc1) : (i32, !llvm.ptr, i32, i32) -> () loc("tests/modules/same_name_two_modules/main.lin":9:14)
    llvm.unreachable loc("tests/modules/same_name_two_modules/main.lin":9:14)
  ^c1:
    %p3 = arith.constant 0 : i64 loc("tests/modules/same_name_two_modules/main.lin":9:14)
    %v3 = arith.addi %v2, %p3 : i64 loc("tests/modules/same_name_two_modules/main.lin":9:14)
    func.return %v3 : i64 loc("tests/modules/same_name_two_modules/main.lin":9:5)
  }
  func.func private @"lin.a;open"() -> i64 attributes {llvm.linkage = #llvm.linkage<internal>, passthrough = [["probe-stack", "inline-asm"]]} {
    cf.br ^b0
  ^b0:
    %v0 = arith.constant 3 : i64 loc("tests/modules/same_name_two_modules/a/a.lin":2:5)
    func.return %v0 : i64 loc("tests/modules/same_name_two_modules/a/a.lin":2:5)
  }
  func.func private @"lin.b;open"() -> i64 attributes {llvm.linkage = #llvm.linkage<internal>, passthrough = [["probe-stack", "inline-asm"]]} {
    cf.br ^b0
  ^b0:
    %v0 = arith.constant 4 : i64 loc("tests/modules/same_name_two_modules/b/b.lin":2:5)
    func.return %v0 : i64 loc("tests/modules/same_name_two_modules/b/b.lin":2:5)
  }
  func.func @main(%argc: i32, %argv: !llvm.ptr) -> i32 {
    func.call @linea_set_args(%argc, %argv) : (i32, !llvm.ptr) -> ()
    %status = func.call @"lin.;main"() : () -> i64
    %status32 = arith.trunci %status : i64 to i32
    func.return %status32 : i32
  }
}
