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
  llvm.mlir.global internal constant @linea_file0("tests/enums/payload_returned.lin\00") : !llvm.array<33 x i8>
  func.func private @linea_set_args(i32, !llvm.ptr)
  func.func private @linea_trap(i32, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @linea_panic(i64, i64, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @"lin.;main"() -> i64 attributes {llvm.linkage = #llvm.linkage<internal>, passthrough = [["probe-stack", "inline-asm"]]} {
    %rz1 = arith.constant 16 : i64
    %rs1 = llvm.alloca %rz1 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz4 = arith.constant 16 : i64
    %rs4 = llvm.alloca %rz4 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    cf.br ^b0
  ^b0:
    %v0 = arith.constant 3 : i64 loc("tests/enums/payload_returned.lin":18:15)
    func.call @"lin.;make"(%rs1, %v0) : (!llvm.ptr, i64) -> () loc("tests/enums/payload_returned.lin":18:10)
    %v2 = func.call @"lin.;size"(%rs1) : (!llvm.ptr) -> i64 loc("tests/enums/payload_returned.lin":18:5)
    %v3 = arith.constant 40 : i64 loc("tests/enums/payload_returned.lin":18:31)
    func.call @"lin.;make"(%rs4, %v3) : (!llvm.ptr, i64) -> () loc("tests/enums/payload_returned.lin":18:26)
    %v5 = func.call @"lin.;size"(%rs4) : (!llvm.ptr) -> i64 loc("tests/enums/payload_returned.lin":18:21)
    %v6 = arith.addi %v2, %v5 : i64 loc("tests/enums/payload_returned.lin":18:5)
    %k1m = arith.constant 255 : i64 loc("tests/enums/payload_returned.lin":18:19)
    %k1 = arith.cmpi ugt, %v6, %k1m : i64 loc("tests/enums/payload_returned.lin":18:19)
    cf.cond_br %k1, ^t1, ^c1 loc("tests/enums/payload_returned.lin":18:19)
  ^t1:
    %tk1 = arith.constant 0 : i32 loc("tests/enums/payload_returned.lin":18:19)
    %tf1 = llvm.mlir.addressof @linea_file0 : !llvm.ptr loc("tests/enums/payload_returned.lin":18:19)
    %tl1 = arith.constant 18 : i32 loc("tests/enums/payload_returned.lin":18:19)
    %tc1 = arith.constant 19 : i32 loc("tests/enums/payload_returned.lin":18:19)
    func.call @linea_trap(%tk1, %tf1, %tl1, %tc1) : (i32, !llvm.ptr, i32, i32) -> () loc("tests/enums/payload_returned.lin":18:19)
    llvm.unreachable loc("tests/enums/payload_returned.lin":18:19)
  ^c1:
    %p7 = arith.constant 0 : i64 loc("tests/enums/payload_returned.lin":18:19)
    %v7 = arith.addi %v6, %p7 : i64 loc("tests/enums/payload_returned.lin":18:19)
    func.return %v7 : i64 loc("tests/enums/payload_returned.lin":18:5)
  }
  func.func private @"lin.;make"(%sret: !llvm.ptr, %a0: i64) attributes {llvm.linkage = #llvm.linkage<internal>, passthrough = [["probe-stack", "inline-asm"]]} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 16 : i64
    %s1 = llvm.alloca %z1 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %pw0 = arith.trunci %a0 : i64 to i8
    llvm.store %pw0, %s0 : i8, !llvm.ptr
    cf.br ^b0
  ^b0:
    %v0 = arith.constant 0 : i64 loc("tests/enums/payload_returned.lin":4:5)
    llvm.store %v0, %s1 : i64, !llvm.ptr loc("tests/enums/payload_returned.lin":4:5)
    %v3 = arith.constant 8 : i64 loc("tests/enums/payload_returned.lin":4:5)
    %v4 = llvm.getelementptr %s1[%v3] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("tests/enums/payload_returned.lin":4:5)
    %lw5 = llvm.load %s0 : !llvm.ptr -> i8 loc("tests/enums/payload_returned.lin":4:18)
    %v5 = arith.extui %lw5 : i8 to i64 loc("tests/enums/payload_returned.lin":4:18)
    %iw6 = arith.trunci %v5 : i64 to i8 loc("tests/enums/payload_returned.lin":4:5)
    llvm.store %iw6, %v4 : i8, !llvm.ptr loc("tests/enums/payload_returned.lin":4:5)
    %rl7 = arith.constant 16 : i64 loc("tests/enums/payload_returned.lin":4:5)
    "llvm.intr.memcpy"(%sret, %s1, %rl7) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("tests/enums/payload_returned.lin":4:5)
    func.return loc("tests/enums/payload_returned.lin":4:5)
  }
  func.func private @"lin.;size"(%a0: !llvm.ptr) -> i64 attributes {llvm.linkage = #llvm.linkage<internal>, passthrough = [["probe-stack", "inline-asm"]]} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x !llvm.ptr {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 1 : i64
    %s1 = llvm.alloca %z1 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    llvm.store %a0, %s0 : !llvm.ptr, !llvm.ptr
    cf.br ^b0
  ^b0:
    %v0 = llvm.load %s0 : !llvm.ptr -> !llvm.ptr loc("tests/enums/payload_returned.lin":8:16)
    %v1 = llvm.load %v0 : !llvm.ptr -> i64 loc("tests/enums/payload_returned.lin":8:5)
    %v2 = arith.constant 0 : i64 loc("tests/enums/payload_returned.lin":8:5)
    %v3 = arith.cmpi eq, %v1, %v2 : i64 loc("tests/enums/payload_returned.lin":8:5)
    cf.cond_br %v3, ^b3, ^b2 loc("tests/enums/payload_returned.lin":8:5)
  ^b1:
    %lw18 = llvm.load %s1 : !llvm.ptr -> i8 loc("tests/enums/payload_returned.lin":8:5)
    %v18 = arith.extui %lw18 : i8 to i64 loc("tests/enums/payload_returned.lin":8:5)
    func.return %v18 : i64 loc("tests/enums/payload_returned.lin":8:5)
  ^b2:
    %v10 = llvm.load %v0 : !llvm.ptr -> i64 loc("tests/enums/payload_returned.lin":8:5)
    %v11 = arith.constant 1 : i64 loc("tests/enums/payload_returned.lin":8:5)
    %v12 = arith.cmpi eq, %v10, %v11 : i64 loc("tests/enums/payload_returned.lin":8:5)
    cf.cond_br %v12, ^b5, ^b4 loc("tests/enums/payload_returned.lin":8:5)
  ^b3:
    %v5 = arith.constant 8 : i64 loc("tests/enums/payload_returned.lin":8:5)
    %v6 = llvm.getelementptr %v0[%v5] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("tests/enums/payload_returned.lin":8:5)
    %iw7 = llvm.load %v6 : !llvm.ptr -> i8 loc("tests/enums/payload_returned.lin":9:22)
    %v7 = arith.extui %iw7 : i8 to i64 loc("tests/enums/payload_returned.lin":9:22)
    %sw8 = arith.trunci %v7 : i64 to i8 loc("tests/enums/payload_returned.lin":8:5)
    llvm.store %sw8, %s1 : i8, !llvm.ptr loc("tests/enums/payload_returned.lin":8:5)
    cf.br ^b1 loc("tests/enums/payload_returned.lin":8:5)
  ^b4:
    %tk1 = arith.constant 3 : i32 loc("tests/enums/payload_returned.lin":8:5)
    %tf1 = llvm.mlir.addressof @linea_file0 : !llvm.ptr loc("tests/enums/payload_returned.lin":8:5)
    %tl1 = arith.constant 8 : i32 loc("tests/enums/payload_returned.lin":8:5)
    %tc1 = arith.constant 5 : i32 loc("tests/enums/payload_returned.lin":8:5)
    func.call @linea_trap(%tk1, %tf1, %tl1, %tc1) : (i32, !llvm.ptr, i32, i32) -> () loc("tests/enums/payload_returned.lin":8:5)
    llvm.unreachable loc("tests/enums/payload_returned.lin":8:5)
  ^b5:
    %v14 = arith.constant 1 : i64 loc("tests/enums/payload_returned.lin":10:19)
    %sw15 = arith.trunci %v14 : i64 to i8 loc("tests/enums/payload_returned.lin":8:5)
    llvm.store %sw15, %s1 : i8, !llvm.ptr loc("tests/enums/payload_returned.lin":8:5)
    cf.br ^b1 loc("tests/enums/payload_returned.lin":8:5)
  }
  func.func @main(%argc: i32, %argv: !llvm.ptr) -> i32 {
    func.call @linea_set_args(%argc, %argv) : (i32, !llvm.ptr) -> ()
    %status = func.call @"lin.;main"() : () -> i64
    %status32 = arith.trunci %status : i64 to i32
    func.return %status32 : i32
  }
}
