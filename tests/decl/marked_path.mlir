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
  llvm.mlir.global internal constant @linea_file0("tests/decl/marked_path.lin\00") : !llvm.array<27 x i8>
  func.func private @linea_set_args(i32, !llvm.ptr)
  func.func private @linea_trap(i32, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @linea_panic(i64, i64, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @"lin.;main"() -> i64 attributes {llvm.linkage = #llvm.linkage<internal>, passthrough = [["probe-stack", "inline-asm"]]} {
    %z0 = arith.constant 2 : i64
    %s0 = llvm.alloca %z0 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    cf.br ^b0
  ^b0:
    %v1 = arith.constant 0 : i64 loc("tests/decl/marked_path.lin":19:20)
    %v3 = arith.constant 0 : i64 loc("tests/decl/marked_path.lin":19:31)
    %v5 = arith.constant 1 : i64 loc("tests/decl/marked_path.lin":19:38)
    %iw6 = arith.trunci %v5 : i64 to i8 loc("tests/decl/marked_path.lin":19:31)
    llvm.store %iw6, %s0 : i8, !llvm.ptr loc("tests/decl/marked_path.lin":19:31)
    %v7 = arith.constant 1 : i64 loc("tests/decl/marked_path.lin":19:20)
    %v8 = llvm.getelementptr %s0[%v7] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("tests/decl/marked_path.lin":19:20)
    %v9 = arith.constant 2 : i64 loc("tests/decl/marked_path.lin":19:47)
    %iw10 = arith.trunci %v9 : i64 to i8 loc("tests/decl/marked_path.lin":19:20)
    llvm.store %iw10, %v8 : i8, !llvm.ptr loc("tests/decl/marked_path.lin":19:20)
    %v12 = arith.constant 0 : i64 loc("tests/decl/marked_path.lin":24:11)
    %v14 = arith.constant 0 : i64 loc("tests/decl/marked_path.lin":24:10)
    %v16 = func.call @"lin.;bump"(%s0) : (!llvm.ptr) -> i64 loc("tests/decl/marked_path.lin":24:5)
    %v18 = arith.constant 0 : i64 loc("tests/decl/marked_path.lin":25:11)
    %v20 = func.call @"lin.;shift"(%s0) : (!llvm.ptr) -> i64 loc("tests/decl/marked_path.lin":25:5)
    %v22 = arith.constant 0 : i64 loc("tests/decl/marked_path.lin":27:5)
    %v24 = arith.constant 0 : i64 loc("tests/decl/marked_path.lin":27:5)
    %iw26 = llvm.load %s0 : !llvm.ptr -> i8 loc("tests/decl/marked_path.lin":27:5)
    %v26 = arith.extui %iw26 : i8 to i64 loc("tests/decl/marked_path.lin":27:5)
    %v28 = arith.constant 1 : i64 loc("tests/decl/marked_path.lin":27:17)
    %v29 = llvm.getelementptr %s0[%v28] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("tests/decl/marked_path.lin":27:17)
    %iw30 = llvm.load %v29 : !llvm.ptr -> i8 loc("tests/decl/marked_path.lin":27:17)
    %v30 = arith.extui %iw30 : i8 to i64 loc("tests/decl/marked_path.lin":27:17)
    %v31 = arith.addi %v26, %v30 : i64 loc("tests/decl/marked_path.lin":27:5)
    %k1m = arith.constant 255 : i64 loc("tests/decl/marked_path.lin":27:15)
    %k1 = arith.cmpi ugt, %v31, %k1m : i64 loc("tests/decl/marked_path.lin":27:15)
    cf.cond_br %k1, ^t1, ^c1 loc("tests/decl/marked_path.lin":27:15)
  ^t1:
    %tk1 = arith.constant 0 : i32 loc("tests/decl/marked_path.lin":27:15)
    %tf1 = llvm.mlir.addressof @linea_file0 : !llvm.ptr loc("tests/decl/marked_path.lin":27:15)
    %tl1 = arith.constant 27 : i32 loc("tests/decl/marked_path.lin":27:15)
    %tc1 = arith.constant 15 : i32 loc("tests/decl/marked_path.lin":27:15)
    func.call @linea_trap(%tk1, %tf1, %tl1, %tc1) : (i32, !llvm.ptr, i32, i32) -> () loc("tests/decl/marked_path.lin":27:15)
    llvm.unreachable loc("tests/decl/marked_path.lin":27:15)
  ^c1:
    %p32 = arith.constant 0 : i64 loc("tests/decl/marked_path.lin":27:15)
    %v32 = arith.addi %v31, %p32 : i64 loc("tests/decl/marked_path.lin":27:15)
    func.return %v32 : i64 loc("tests/decl/marked_path.lin":27:5)
  }
  func.func private @"lin.;bump"(%a0: !llvm.ptr) -> i64 attributes {llvm.linkage = #llvm.linkage<internal>, passthrough = [["probe-stack", "inline-asm"]]} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x !llvm.ptr {alignment = 8 : i64} : (i64) -> !llvm.ptr
    llvm.store %a0, %s0 : !llvm.ptr, !llvm.ptr
    cf.br ^b0
  ^b0:
    %v0 = llvm.load %s0 : !llvm.ptr -> !llvm.ptr loc("tests/decl/marked_path.lin":9:9)
    %iw1 = llvm.load %v0 : !llvm.ptr -> i8 loc("tests/decl/marked_path.lin":9:9)
    %v1 = arith.extui %iw1 : i8 to i64 loc("tests/decl/marked_path.lin":9:9)
    %v2 = arith.constant 1 : i64 loc("tests/decl/marked_path.lin":9:13)
    %v3 = arith.addi %v1, %v2 : i64 loc("tests/decl/marked_path.lin":9:9)
    %k1m = arith.constant 255 : i64 loc("tests/decl/marked_path.lin":9:11)
    %k1 = arith.cmpi ugt, %v3, %k1m : i64 loc("tests/decl/marked_path.lin":9:11)
    cf.cond_br %k1, ^t1, ^c1 loc("tests/decl/marked_path.lin":9:11)
  ^t1:
    %tk1 = arith.constant 0 : i32 loc("tests/decl/marked_path.lin":9:11)
    %tf1 = llvm.mlir.addressof @linea_file0 : !llvm.ptr loc("tests/decl/marked_path.lin":9:11)
    %tl1 = arith.constant 9 : i32 loc("tests/decl/marked_path.lin":9:11)
    %tc1 = arith.constant 11 : i32 loc("tests/decl/marked_path.lin":9:11)
    func.call @linea_trap(%tk1, %tf1, %tl1, %tc1) : (i32, !llvm.ptr, i32, i32) -> () loc("tests/decl/marked_path.lin":9:11)
    llvm.unreachable loc("tests/decl/marked_path.lin":9:11)
  ^c1:
    %p4 = arith.constant 0 : i64 loc("tests/decl/marked_path.lin":9:11)
    %v4 = arith.addi %v3, %p4 : i64 loc("tests/decl/marked_path.lin":9:11)
    %v5 = llvm.load %s0 : !llvm.ptr -> !llvm.ptr loc("tests/decl/marked_path.lin":9:5)
    %iw6 = arith.trunci %v4 : i64 to i8 loc("tests/decl/marked_path.lin":9:5)
    llvm.store %iw6, %v5 : i8, !llvm.ptr loc("tests/decl/marked_path.lin":9:5)
    %v7 = arith.constant 0 : i64 loc("tests/decl/marked_path.lin":9:5)
    func.return %v7 : i64 loc("tests/decl/marked_path.lin":9:5)
  }
  func.func private @"lin.;shift"(%a0: !llvm.ptr) -> i64 attributes {llvm.linkage = #llvm.linkage<internal>, passthrough = [["probe-stack", "inline-asm"]]} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x !llvm.ptr {alignment = 8 : i64} : (i64) -> !llvm.ptr
    llvm.store %a0, %s0 : !llvm.ptr, !llvm.ptr
    cf.br ^b0
  ^b0:
    %v0 = llvm.load %s0 : !llvm.ptr -> !llvm.ptr loc("tests/decl/marked_path.lin":15:11)
    %v1 = arith.constant 0 : i64 loc("tests/decl/marked_path.lin":15:11)
    %iw3 = llvm.load %v0 : !llvm.ptr -> i8 loc("tests/decl/marked_path.lin":15:11)
    %v3 = arith.extui %iw3 : i8 to i64 loc("tests/decl/marked_path.lin":15:11)
    %v4 = arith.constant 10 : i64 loc("tests/decl/marked_path.lin":15:17)
    %v5 = arith.addi %v3, %v4 : i64 loc("tests/decl/marked_path.lin":15:11)
    %k1m = arith.constant 255 : i64 loc("tests/decl/marked_path.lin":15:15)
    %k1 = arith.cmpi ugt, %v5, %k1m : i64 loc("tests/decl/marked_path.lin":15:15)
    cf.cond_br %k1, ^t1, ^c1 loc("tests/decl/marked_path.lin":15:15)
  ^t1:
    %tk1 = arith.constant 0 : i32 loc("tests/decl/marked_path.lin":15:15)
    %tf1 = llvm.mlir.addressof @linea_file0 : !llvm.ptr loc("tests/decl/marked_path.lin":15:15)
    %tl1 = arith.constant 15 : i32 loc("tests/decl/marked_path.lin":15:15)
    %tc1 = arith.constant 15 : i32 loc("tests/decl/marked_path.lin":15:15)
    func.call @linea_trap(%tk1, %tf1, %tl1, %tc1) : (i32, !llvm.ptr, i32, i32) -> () loc("tests/decl/marked_path.lin":15:15)
    llvm.unreachable loc("tests/decl/marked_path.lin":15:15)
  ^c1:
    %p6 = arith.constant 0 : i64 loc("tests/decl/marked_path.lin":15:15)
    %v6 = arith.addi %v5, %p6 : i64 loc("tests/decl/marked_path.lin":15:15)
    %v7 = llvm.load %s0 : !llvm.ptr -> !llvm.ptr loc("tests/decl/marked_path.lin":15:5)
    %v8 = arith.constant 0 : i64 loc("tests/decl/marked_path.lin":15:5)
    %iw10 = arith.trunci %v6 : i64 to i8 loc("tests/decl/marked_path.lin":15:5)
    llvm.store %iw10, %v7 : i8, !llvm.ptr loc("tests/decl/marked_path.lin":15:5)
    %v11 = arith.constant 0 : i64 loc("tests/decl/marked_path.lin":15:5)
    func.return %v11 : i64 loc("tests/decl/marked_path.lin":15:5)
  }
  func.func @main(%argc: i32, %argv: !llvm.ptr) -> i32 {
    func.call @linea_set_args(%argc, %argv) : (i32, !llvm.ptr) -> ()
    %status = func.call @"lin.;main"() : () -> i64
    %status32 = arith.trunci %status : i64 to i32
    func.return %status32 : i32
  }
}
