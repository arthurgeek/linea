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
  llvm.mlir.global internal constant @linea_file0("tests/enums/payload_pair.lin\00") : !llvm.array<29 x i8>
  func.func private @linea_set_args(i32, !llvm.ptr)
  func.func private @linea_trap(i32, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @linea_panic(i64, i64, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @"lin.;main"() -> i64 attributes {llvm.linkage = #llvm.linkage<internal>} {
    %z0 = arith.constant 16 : i64
    %s0 = llvm.alloca %z0 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 16 : i64
    %s1 = llvm.alloca %z1 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z2 = arith.constant 16 : i64
    %s2 = llvm.alloca %z2 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    cf.br ^b0
  ^b0:
    %v0 = arith.constant 0 : i64 loc("tests/enums/payload_pair.lin":19:10)
    llvm.store %v0, %s0 : i64, !llvm.ptr loc("tests/enums/payload_pair.lin":19:10)
    %v3 = arith.constant 8 : i64 loc("tests/enums/payload_pair.lin":19:10)
    %v4 = llvm.getelementptr %s0[%v3] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("tests/enums/payload_pair.lin":19:10)
    %v5 = arith.constant 3 : i64 loc("tests/enums/payload_pair.lin":19:21)
    %iw6 = arith.trunci %v5 : i64 to i8 loc("tests/enums/payload_pair.lin":19:10)
    llvm.store %iw6, %v4 : i8, !llvm.ptr loc("tests/enums/payload_pair.lin":19:10)
    %v7 = arith.constant 9 : i64 loc("tests/enums/payload_pair.lin":19:10)
    %v8 = llvm.getelementptr %s0[%v7] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("tests/enums/payload_pair.lin":19:10)
    %v9 = arith.constant 4 : i64 loc("tests/enums/payload_pair.lin":19:24)
    %iw10 = arith.trunci %v9 : i64 to i8 loc("tests/enums/payload_pair.lin":19:10)
    llvm.store %iw10, %v8 : i8, !llvm.ptr loc("tests/enums/payload_pair.lin":19:10)
    %v11 = func.call @"lin.;area"(%s0) : (!llvm.ptr) -> i64 loc("tests/enums/payload_pair.lin":19:5)
    %v12 = arith.constant 1 : i64 loc("tests/enums/payload_pair.lin":19:35)
    llvm.store %v12, %s1 : i64, !llvm.ptr loc("tests/enums/payload_pair.lin":19:35)
    %v15 = arith.constant 8 : i64 loc("tests/enums/payload_pair.lin":19:35)
    %v16 = llvm.getelementptr %s1[%v15] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("tests/enums/payload_pair.lin":19:35)
    %v17 = arith.constant 5 : i64 loc("tests/enums/payload_pair.lin":19:48)
    %iw18 = arith.trunci %v17 : i64 to i8 loc("tests/enums/payload_pair.lin":19:35)
    llvm.store %iw18, %v16 : i8, !llvm.ptr loc("tests/enums/payload_pair.lin":19:35)
    %v19 = func.call @"lin.;area"(%s1) : (!llvm.ptr) -> i64 loc("tests/enums/payload_pair.lin":19:30)
    %v20 = arith.addi %v11, %v19 : i64 loc("tests/enums/payload_pair.lin":19:5)
    %k1m = arith.constant 255 : i64 loc("tests/enums/payload_pair.lin":19:28)
    %k1 = arith.cmpi ugt, %v20, %k1m : i64 loc("tests/enums/payload_pair.lin":19:28)
    cf.cond_br %k1, ^t1, ^c1 loc("tests/enums/payload_pair.lin":19:28)
  ^t1:
    %tk1 = arith.constant 0 : i32 loc("tests/enums/payload_pair.lin":19:28)
    %tf1 = llvm.mlir.addressof @linea_file0 : !llvm.ptr loc("tests/enums/payload_pair.lin":19:28)
    %tl1 = arith.constant 19 : i32 loc("tests/enums/payload_pair.lin":19:28)
    %tc1 = arith.constant 28 : i32 loc("tests/enums/payload_pair.lin":19:28)
    func.call @linea_trap(%tk1, %tf1, %tl1, %tc1) : (i32, !llvm.ptr, i32, i32) -> () loc("tests/enums/payload_pair.lin":19:28)
    llvm.unreachable loc("tests/enums/payload_pair.lin":19:28)
  ^c1:
    %p21 = arith.constant 0 : i64 loc("tests/enums/payload_pair.lin":19:28)
    %v21 = arith.addi %v20, %p21 : i64 loc("tests/enums/payload_pair.lin":19:28)
    %v22 = arith.constant 2 : i64 loc("tests/enums/payload_pair.lin":19:59)
    llvm.store %v22, %s2 : i64, !llvm.ptr loc("tests/enums/payload_pair.lin":19:59)
    %v25 = func.call @"lin.;area"(%s2) : (!llvm.ptr) -> i64 loc("tests/enums/payload_pair.lin":19:54)
    %v26 = arith.addi %v21, %v25 : i64 loc("tests/enums/payload_pair.lin":19:5)
    %k2m = arith.constant 255 : i64 loc("tests/enums/payload_pair.lin":19:52)
    %k2 = arith.cmpi ugt, %v26, %k2m : i64 loc("tests/enums/payload_pair.lin":19:52)
    cf.cond_br %k2, ^t2, ^c2 loc("tests/enums/payload_pair.lin":19:52)
  ^t2:
    %tk2 = arith.constant 0 : i32 loc("tests/enums/payload_pair.lin":19:52)
    %tf2 = llvm.mlir.addressof @linea_file0 : !llvm.ptr loc("tests/enums/payload_pair.lin":19:52)
    %tl2 = arith.constant 19 : i32 loc("tests/enums/payload_pair.lin":19:52)
    %tc2 = arith.constant 52 : i32 loc("tests/enums/payload_pair.lin":19:52)
    func.call @linea_trap(%tk2, %tf2, %tl2, %tc2) : (i32, !llvm.ptr, i32, i32) -> () loc("tests/enums/payload_pair.lin":19:52)
    llvm.unreachable loc("tests/enums/payload_pair.lin":19:52)
  ^c2:
    %p27 = arith.constant 0 : i64 loc("tests/enums/payload_pair.lin":19:52)
    %v27 = arith.addi %v26, %p27 : i64 loc("tests/enums/payload_pair.lin":19:52)
    func.return %v27 : i64 loc("tests/enums/payload_pair.lin":19:5)
  }
  func.func private @"lin.;area"(%a0: !llvm.ptr) -> i64 attributes {llvm.linkage = #llvm.linkage<internal>} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x !llvm.ptr {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 1 : i64
    %s1 = llvm.alloca %z1 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    llvm.store %a0, %s0 : !llvm.ptr, !llvm.ptr
    cf.br ^b0
  ^b0:
    %v0 = llvm.load %s0 : !llvm.ptr -> !llvm.ptr loc("tests/enums/payload_pair.lin":8:16)
    %v1 = llvm.load %v0 : !llvm.ptr -> i64 loc("tests/enums/payload_pair.lin":8:5)
    %v2 = arith.constant 0 : i64 loc("tests/enums/payload_pair.lin":8:5)
    %v3 = arith.cmpi eq, %v1, %v2 : i64 loc("tests/enums/payload_pair.lin":8:5)
    cf.cond_br %v3, ^b2, ^b3 loc("tests/enums/payload_pair.lin":8:5)
  ^b1:
    %lw33 = llvm.load %s1 : !llvm.ptr -> i8 loc("tests/enums/payload_pair.lin":8:5)
    %v33 = arith.extui %lw33 : i8 to i64 loc("tests/enums/payload_pair.lin":8:5)
    func.return %v33 : i64 loc("tests/enums/payload_pair.lin":8:5)
  ^b2:
    %v5 = arith.constant 8 : i64 loc("tests/enums/payload_pair.lin":8:5)
    %v6 = llvm.getelementptr %v0[%v5] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("tests/enums/payload_pair.lin":8:5)
    %v7 = arith.constant 9 : i64 loc("tests/enums/payload_pair.lin":8:5)
    %v8 = llvm.getelementptr %v0[%v7] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("tests/enums/payload_pair.lin":8:5)
    %iw9 = llvm.load %v6 : !llvm.ptr -> i8 loc("tests/enums/payload_pair.lin":9:23)
    %v9 = arith.extui %iw9 : i8 to i64 loc("tests/enums/payload_pair.lin":9:23)
    %iw10 = llvm.load %v8 : !llvm.ptr -> i8 loc("tests/enums/payload_pair.lin":9:27)
    %v10 = arith.extui %iw10 : i8 to i64 loc("tests/enums/payload_pair.lin":9:27)
    %v11 = arith.muli %v9, %v10 : i64 loc("tests/enums/payload_pair.lin":9:23)
    %k1m = arith.constant 255 : i64 loc("tests/enums/payload_pair.lin":9:25)
    %k1 = arith.cmpi ugt, %v11, %k1m : i64 loc("tests/enums/payload_pair.lin":9:25)
    cf.cond_br %k1, ^t1, ^c1 loc("tests/enums/payload_pair.lin":9:25)
  ^t1:
    %tk1 = arith.constant 0 : i32 loc("tests/enums/payload_pair.lin":9:25)
    %tf1 = llvm.mlir.addressof @linea_file0 : !llvm.ptr loc("tests/enums/payload_pair.lin":9:25)
    %tl1 = arith.constant 9 : i32 loc("tests/enums/payload_pair.lin":9:25)
    %tc1 = arith.constant 25 : i32 loc("tests/enums/payload_pair.lin":9:25)
    func.call @linea_trap(%tk1, %tf1, %tl1, %tc1) : (i32, !llvm.ptr, i32, i32) -> () loc("tests/enums/payload_pair.lin":9:25)
    llvm.unreachable loc("tests/enums/payload_pair.lin":9:25)
  ^c1:
    %p12 = arith.constant 0 : i64 loc("tests/enums/payload_pair.lin":9:25)
    %v12 = arith.addi %v11, %p12 : i64 loc("tests/enums/payload_pair.lin":9:25)
    %sw13 = arith.trunci %v12 : i64 to i8 loc("tests/enums/payload_pair.lin":8:5)
    llvm.store %sw13, %s1 : i8, !llvm.ptr loc("tests/enums/payload_pair.lin":8:5)
    cf.br ^b1 loc("tests/enums/payload_pair.lin":8:5)
  ^b3:
    %v15 = arith.constant 1 : i64 loc("tests/enums/payload_pair.lin":8:5)
    %v16 = arith.cmpi eq, %v1, %v15 : i64 loc("tests/enums/payload_pair.lin":8:5)
    cf.cond_br %v16, ^b4, ^b5 loc("tests/enums/payload_pair.lin":8:5)
  ^b4:
    %v18 = arith.constant 8 : i64 loc("tests/enums/payload_pair.lin":8:5)
    %v19 = llvm.getelementptr %v0[%v18] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("tests/enums/payload_pair.lin":8:5)
    %iw20 = llvm.load %v19 : !llvm.ptr -> i8 loc("tests/enums/payload_pair.lin":10:25)
    %v20 = arith.extui %iw20 : i8 to i64 loc("tests/enums/payload_pair.lin":10:25)
    %iw21 = llvm.load %v19 : !llvm.ptr -> i8 loc("tests/enums/payload_pair.lin":10:32)
    %v21 = arith.extui %iw21 : i8 to i64 loc("tests/enums/payload_pair.lin":10:32)
    %v22 = arith.muli %v20, %v21 : i64 loc("tests/enums/payload_pair.lin":10:25)
    %k2m = arith.constant 255 : i64 loc("tests/enums/payload_pair.lin":10:30)
    %k2 = arith.cmpi ugt, %v22, %k2m : i64 loc("tests/enums/payload_pair.lin":10:30)
    cf.cond_br %k2, ^t2, ^c2 loc("tests/enums/payload_pair.lin":10:30)
  ^t2:
    %tk2 = arith.constant 0 : i32 loc("tests/enums/payload_pair.lin":10:30)
    %tf2 = llvm.mlir.addressof @linea_file0 : !llvm.ptr loc("tests/enums/payload_pair.lin":10:30)
    %tl2 = arith.constant 10 : i32 loc("tests/enums/payload_pair.lin":10:30)
    %tc2 = arith.constant 30 : i32 loc("tests/enums/payload_pair.lin":10:30)
    func.call @linea_trap(%tk2, %tf2, %tl2, %tc2) : (i32, !llvm.ptr, i32, i32) -> () loc("tests/enums/payload_pair.lin":10:30)
    llvm.unreachable loc("tests/enums/payload_pair.lin":10:30)
  ^c2:
    %p23 = arith.constant 0 : i64 loc("tests/enums/payload_pair.lin":10:30)
    %v23 = arith.addi %v22, %p23 : i64 loc("tests/enums/payload_pair.lin":10:30)
    %sw24 = arith.trunci %v23 : i64 to i8 loc("tests/enums/payload_pair.lin":8:5)
    llvm.store %sw24, %s1 : i8, !llvm.ptr loc("tests/enums/payload_pair.lin":8:5)
    cf.br ^b1 loc("tests/enums/payload_pair.lin":8:5)
  ^b5:
    %v26 = arith.constant 2 : i64 loc("tests/enums/payload_pair.lin":8:5)
    %v27 = arith.cmpi eq, %v1, %v26 : i64 loc("tests/enums/payload_pair.lin":8:5)
    cf.cond_br %v27, ^b6, ^b7 loc("tests/enums/payload_pair.lin":8:5)
  ^b6:
    %v29 = arith.constant 0 : i64 loc("tests/enums/payload_pair.lin":11:18)
    %sw30 = arith.trunci %v29 : i64 to i8 loc("tests/enums/payload_pair.lin":8:5)
    llvm.store %sw30, %s1 : i8, !llvm.ptr loc("tests/enums/payload_pair.lin":8:5)
    cf.br ^b1 loc("tests/enums/payload_pair.lin":8:5)
  ^b7:
    %tk3 = arith.constant 3 : i32 loc("tests/enums/payload_pair.lin":8:5)
    %tf3 = llvm.mlir.addressof @linea_file0 : !llvm.ptr loc("tests/enums/payload_pair.lin":8:5)
    %tl3 = arith.constant 8 : i32 loc("tests/enums/payload_pair.lin":8:5)
    %tc3 = arith.constant 5 : i32 loc("tests/enums/payload_pair.lin":8:5)
    func.call @linea_trap(%tk3, %tf3, %tl3, %tc3) : (i32, !llvm.ptr, i32, i32) -> () loc("tests/enums/payload_pair.lin":8:5)
    llvm.unreachable loc("tests/enums/payload_pair.lin":8:5)
  }
  func.func @main(%argc: i32, %argv: !llvm.ptr) -> i32 {
    func.call @linea_set_args(%argc, %argv) : (i32, !llvm.ptr) -> ()
    %status = func.call @"lin.;main"() : () -> i64
    %status32 = arith.trunci %status : i64 to i32
    func.return %status32 : i32
  }
}
