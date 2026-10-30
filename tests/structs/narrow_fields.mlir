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
  llvm.mlir.global internal constant @linea_file0("tests/structs/narrow_fields.lin\00") : !llvm.array<32 x i8>
  func.func private @linea_set_args(i32, !llvm.ptr)
  func.func private @linea_trap(i32, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @linea_panic(i64, i64, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @"lin.;main"() -> i64 attributes {llvm.linkage = #llvm.linkage<internal>, passthrough = [["probe-stack", "inline-asm"]]} {
    %z0 = arith.constant 3 : i64
    %s0 = llvm.alloca %z0 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 4 : i64
    %s1 = llvm.alloca %z1 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    cf.br ^b0
  ^b0:
    %v1 = arith.constant 0 : i64 loc("tests/structs/narrow_fields.lin":22:20)
    %v3 = arith.constant 0 : i1 loc("tests/structs/narrow_fields.lin":22:27)
    %iw4 = arith.extui %v3 : i1 to i8 loc("tests/structs/narrow_fields.lin":22:20)
    llvm.store %iw4, %s0 : i8, !llvm.ptr loc("tests/structs/narrow_fields.lin":22:20)
    %v5 = arith.constant 1 : i64 loc("tests/structs/narrow_fields.lin":22:20)
    %v6 = llvm.getelementptr %s0[%v5] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("tests/structs/narrow_fields.lin":22:20)
    %v7 = arith.constant 1 : i1 loc("tests/structs/narrow_fields.lin":22:38)
    %iw8 = arith.extui %v7 : i1 to i8 loc("tests/structs/narrow_fields.lin":22:20)
    llvm.store %iw8, %v6 : i8, !llvm.ptr loc("tests/structs/narrow_fields.lin":22:20)
    %v9 = arith.constant 2 : i64 loc("tests/structs/narrow_fields.lin":22:20)
    %v10 = llvm.getelementptr %s0[%v9] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("tests/structs/narrow_fields.lin":22:20)
    %v11 = arith.constant 9 : i64 loc("tests/structs/narrow_fields.lin":22:48)
    %iw12 = arith.trunci %v11 : i64 to i8 loc("tests/structs/narrow_fields.lin":22:20)
    llvm.store %iw12, %v10 : i8, !llvm.ptr loc("tests/structs/narrow_fields.lin":22:20)
    %v14 = arith.constant 0 : i64 loc("tests/structs/narrow_fields.lin":26:19)
    %v16 = arith.constant 0 : i64 loc("tests/structs/narrow_fields.lin":26:30)
    %v18 = arith.constant 1 : i1 loc("tests/structs/narrow_fields.lin":26:37)
    %iw19 = arith.extui %v18 : i1 to i8 loc("tests/structs/narrow_fields.lin":26:30)
    llvm.store %iw19, %s1 : i8, !llvm.ptr loc("tests/structs/narrow_fields.lin":26:30)
    %v20 = arith.constant 1 : i64 loc("tests/structs/narrow_fields.lin":26:30)
    %v21 = llvm.getelementptr %s1[%v20] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("tests/structs/narrow_fields.lin":26:30)
    %v22 = arith.constant 0 : i1 loc("tests/structs/narrow_fields.lin":26:47)
    %iw23 = arith.extui %v22 : i1 to i8 loc("tests/structs/narrow_fields.lin":26:30)
    llvm.store %iw23, %v21 : i8, !llvm.ptr loc("tests/structs/narrow_fields.lin":26:30)
    %v24 = arith.constant 2 : i64 loc("tests/structs/narrow_fields.lin":26:30)
    %v25 = llvm.getelementptr %s1[%v24] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("tests/structs/narrow_fields.lin":26:30)
    %v26 = arith.constant 3 : i64 loc("tests/structs/narrow_fields.lin":26:58)
    %iw27 = arith.trunci %v26 : i64 to i8 loc("tests/structs/narrow_fields.lin":26:30)
    llvm.store %iw27, %v25 : i8, !llvm.ptr loc("tests/structs/narrow_fields.lin":26:30)
    %v28 = arith.constant 3 : i64 loc("tests/structs/narrow_fields.lin":26:19)
    %v29 = llvm.getelementptr %s1[%v28] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("tests/structs/narrow_fields.lin":26:19)
    %v30 = arith.constant 4 : i64 loc("tests/structs/narrow_fields.lin":26:67)
    %iw31 = arith.trunci %v30 : i64 to i8 loc("tests/structs/narrow_fields.lin":26:19)
    llvm.store %iw31, %v29 : i8, !llvm.ptr loc("tests/structs/narrow_fields.lin":26:19)
    %v33 = func.call @"lin.;pick"(%s0) : (!llvm.ptr) -> i64 loc("tests/structs/narrow_fields.lin":28:5)
    %v35 = arith.constant 0 : i64 loc("tests/structs/narrow_fields.lin":28:20)
    %v37 = func.call @"lin.;pick"(%s1) : (!llvm.ptr) -> i64 loc("tests/structs/narrow_fields.lin":28:15)
    %v38 = arith.addi %v33, %v37 : i64 loc("tests/structs/narrow_fields.lin":28:5)
    %k1m = arith.constant 255 : i64 loc("tests/structs/narrow_fields.lin":28:13)
    %k1 = arith.cmpi ugt, %v38, %k1m : i64 loc("tests/structs/narrow_fields.lin":28:13)
    cf.cond_br %k1, ^t1, ^c1 loc("tests/structs/narrow_fields.lin":28:13)
  ^t1:
    %tk1 = arith.constant 0 : i32 loc("tests/structs/narrow_fields.lin":28:13)
    %tf1 = llvm.mlir.addressof @linea_file0 : !llvm.ptr loc("tests/structs/narrow_fields.lin":28:13)
    %tl1 = arith.constant 28 : i32 loc("tests/structs/narrow_fields.lin":28:13)
    %tc1 = arith.constant 13 : i32 loc("tests/structs/narrow_fields.lin":28:13)
    func.call @linea_trap(%tk1, %tf1, %tl1, %tc1) : (i32, !llvm.ptr, i32, i32) -> () loc("tests/structs/narrow_fields.lin":28:13)
    llvm.unreachable loc("tests/structs/narrow_fields.lin":28:13)
  ^c1:
    %p39 = arith.constant 0 : i64 loc("tests/structs/narrow_fields.lin":28:13)
    %v39 = arith.addi %v38, %p39 : i64 loc("tests/structs/narrow_fields.lin":28:13)
    %v41 = arith.constant 3 : i64 loc("tests/structs/narrow_fields.lin":28:31)
    %v42 = llvm.getelementptr %s1[%v41] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("tests/structs/narrow_fields.lin":28:31)
    %iw43 = llvm.load %v42 : !llvm.ptr -> i8 loc("tests/structs/narrow_fields.lin":28:31)
    %v43 = arith.extui %iw43 : i8 to i64 loc("tests/structs/narrow_fields.lin":28:31)
    %v44 = arith.addi %v39, %v43 : i64 loc("tests/structs/narrow_fields.lin":28:5)
    %k2m = arith.constant 255 : i64 loc("tests/structs/narrow_fields.lin":28:29)
    %k2 = arith.cmpi ugt, %v44, %k2m : i64 loc("tests/structs/narrow_fields.lin":28:29)
    cf.cond_br %k2, ^t2, ^c2 loc("tests/structs/narrow_fields.lin":28:29)
  ^t2:
    %tk2 = arith.constant 0 : i32 loc("tests/structs/narrow_fields.lin":28:29)
    %tf2 = llvm.mlir.addressof @linea_file0 : !llvm.ptr loc("tests/structs/narrow_fields.lin":28:29)
    %tl2 = arith.constant 28 : i32 loc("tests/structs/narrow_fields.lin":28:29)
    %tc2 = arith.constant 29 : i32 loc("tests/structs/narrow_fields.lin":28:29)
    func.call @linea_trap(%tk2, %tf2, %tl2, %tc2) : (i32, !llvm.ptr, i32, i32) -> () loc("tests/structs/narrow_fields.lin":28:29)
    llvm.unreachable loc("tests/structs/narrow_fields.lin":28:29)
  ^c2:
    %p45 = arith.constant 0 : i64 loc("tests/structs/narrow_fields.lin":28:29)
    %v45 = arith.addi %v44, %p45 : i64 loc("tests/structs/narrow_fields.lin":28:29)
    func.return %v45 : i64 loc("tests/structs/narrow_fields.lin":28:5)
  }
  func.func private @"lin.;pick"(%a0: !llvm.ptr) -> i64 attributes {llvm.linkage = #llvm.linkage<internal>, passthrough = [["probe-stack", "inline-asm"]]} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x !llvm.ptr {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 1 : i64
    %s1 = llvm.alloca %z1 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z2 = arith.constant 1 : i64
    %s2 = llvm.alloca %z2 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    llvm.store %a0, %s0 : !llvm.ptr, !llvm.ptr
    cf.br ^b0
  ^b0:
    %v0 = llvm.load %s0 : !llvm.ptr -> !llvm.ptr loc("tests/structs/narrow_fields.lin":6:8)
    %v1 = arith.constant 0 : i64 loc("tests/structs/narrow_fields.lin":6:8)
    %iw3 = llvm.load %v0 : !llvm.ptr -> i8 loc("tests/structs/narrow_fields.lin":6:8)
    %iz3 = arith.constant 0 : i8 loc("tests/structs/narrow_fields.lin":6:8)
    %v3 = arith.cmpi ne, %iw3, %iz3 : i8 loc("tests/structs/narrow_fields.lin":6:8)
    cf.cond_br %v3, ^b1, ^b2 loc("tests/structs/narrow_fields.lin":6:5)
  ^b1:
    %v5 = llvm.load %s0 : !llvm.ptr -> !llvm.ptr loc("tests/structs/narrow_fields.lin":7:12)
    %v6 = arith.constant 1 : i64 loc("tests/structs/narrow_fields.lin":7:12)
    %v7 = llvm.getelementptr %v5[%v6] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("tests/structs/narrow_fields.lin":7:12)
    %iw8 = llvm.load %v7 : !llvm.ptr -> i8 loc("tests/structs/narrow_fields.lin":7:12)
    %iz8 = arith.constant 0 : i8 loc("tests/structs/narrow_fields.lin":7:12)
    %v8 = arith.cmpi ne, %iw8, %iz8 : i8 loc("tests/structs/narrow_fields.lin":7:12)
    cf.cond_br %v8, ^b4, ^b5 loc("tests/structs/narrow_fields.lin":7:9)
  ^b2:
    %v19 = llvm.load %s0 : !llvm.ptr -> !llvm.ptr loc("tests/structs/narrow_fields.lin":13:9)
    %v20 = arith.constant 2 : i64 loc("tests/structs/narrow_fields.lin":13:9)
    %v21 = llvm.getelementptr %v19[%v20] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("tests/structs/narrow_fields.lin":13:9)
    %iw22 = llvm.load %v21 : !llvm.ptr -> i8 loc("tests/structs/narrow_fields.lin":13:9)
    %v22 = arith.extui %iw22 : i8 to i64 loc("tests/structs/narrow_fields.lin":13:9)
    %sw23 = arith.trunci %v22 : i64 to i8 loc("tests/structs/narrow_fields.lin":6:5)
    llvm.store %sw23, %s1 : i8, !llvm.ptr loc("tests/structs/narrow_fields.lin":6:5)
    cf.br ^b3 loc("tests/structs/narrow_fields.lin":6:5)
  ^b3:
    %lw25 = llvm.load %s1 : !llvm.ptr -> i8 loc("tests/structs/narrow_fields.lin":6:5)
    %v25 = arith.extui %lw25 : i8 to i64 loc("tests/structs/narrow_fields.lin":6:5)
    func.return %v25 : i64 loc("tests/structs/narrow_fields.lin":6:5)
  ^b4:
    %v10 = arith.constant 1 : i64 loc("tests/structs/narrow_fields.lin":8:13)
    %sw11 = arith.trunci %v10 : i64 to i8 loc("tests/structs/narrow_fields.lin":7:9)
    llvm.store %sw11, %s2 : i8, !llvm.ptr loc("tests/structs/narrow_fields.lin":7:9)
    cf.br ^b6 loc("tests/structs/narrow_fields.lin":7:9)
  ^b5:
    %v13 = arith.constant 2 : i64 loc("tests/structs/narrow_fields.lin":10:13)
    %sw14 = arith.trunci %v13 : i64 to i8 loc("tests/structs/narrow_fields.lin":7:9)
    llvm.store %sw14, %s2 : i8, !llvm.ptr loc("tests/structs/narrow_fields.lin":7:9)
    cf.br ^b6 loc("tests/structs/narrow_fields.lin":7:9)
  ^b6:
    %lw16 = llvm.load %s2 : !llvm.ptr -> i8 loc("tests/structs/narrow_fields.lin":7:9)
    %v16 = arith.extui %lw16 : i8 to i64 loc("tests/structs/narrow_fields.lin":7:9)
    %sw17 = arith.trunci %v16 : i64 to i8 loc("tests/structs/narrow_fields.lin":6:5)
    llvm.store %sw17, %s1 : i8, !llvm.ptr loc("tests/structs/narrow_fields.lin":6:5)
    cf.br ^b3 loc("tests/structs/narrow_fields.lin":6:5)
  }
  func.func @main(%argc: i32, %argv: !llvm.ptr) -> i32 {
    func.call @linea_set_args(%argc, %argv) : (i32, !llvm.ptr) -> ()
    %status = func.call @"lin.;main"() : () -> i64
    %status32 = arith.trunci %status : i64 to i32
    func.return %status32 : i32
  }
}
