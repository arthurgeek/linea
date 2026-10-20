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
  llvm.mlir.global internal constant @linea_file0("tests/generics/a_symbol_holds_no_brackets.lin\00") : !llvm.array<46 x i8>
  func.func private @linea_set_args(i32, !llvm.ptr)
  func.func private @linea_trap(i32, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @linea_panic(i64, i64, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @"lin.;main"() -> i64 attributes {llvm.linkage = #llvm.linkage<internal>} {
    %z0 = arith.constant 16 : i64
    %s0 = llvm.alloca %z0 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 16 : i64
    %s1 = llvm.alloca %z1 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z2 = arith.constant 1 : i64
    %s2 = llvm.alloca %z2 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z3 = arith.constant 1 : i64
    %s3 = llvm.alloca %z3 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %rz9 = arith.constant 16 : i64
    %rs9 = llvm.alloca %rz9 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    cf.br ^b0
  ^b0:
    %v1 = arith.constant 1 : i64 loc("tests/generics/a_symbol_holds_no_brackets.lin":14:31)
    llvm.store %v1, %s0 : i64, !llvm.ptr loc("tests/generics/a_symbol_holds_no_brackets.lin":14:31)
    %v3 = arith.constant 8 : i64 loc("tests/generics/a_symbol_holds_no_brackets.lin":14:31)
    %v4 = llvm.getelementptr %s0[%v3] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("tests/generics/a_symbol_holds_no_brackets.lin":14:31)
    %v5 = arith.constant 3 : i64 loc("tests/generics/a_symbol_holds_no_brackets.lin":14:37)
    %iw6 = arith.trunci %v5 : i64 to i8 loc("tests/generics/a_symbol_holds_no_brackets.lin":14:31)
    llvm.store %iw6, %v4 : i8, !llvm.ptr loc("tests/generics/a_symbol_holds_no_brackets.lin":14:31)
    func.call @"lin.;ident[std.option.Option[UInt8]]"(%rs9, %s0) : (!llvm.ptr, !llvm.ptr) -> () loc("tests/generics/a_symbol_holds_no_brackets.lin":15:16)
    %cl10 = arith.constant 16 : i64 loc("tests/generics/a_symbol_holds_no_brackets.lin":15:5)
    "llvm.intr.memcpy"(%s1, %rs9, %cl10) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("tests/generics/a_symbol_holds_no_brackets.lin":15:5)
    %v12 = llvm.load %s1 : !llvm.ptr -> i64 loc("tests/generics/a_symbol_holds_no_brackets.lin":16:5)
    %v13 = arith.constant 0 : i64 loc("tests/generics/a_symbol_holds_no_brackets.lin":16:5)
    %v14 = arith.cmpi eq, %v12, %v13 : i64 loc("tests/generics/a_symbol_holds_no_brackets.lin":16:5)
    cf.cond_br %v14, ^b3, ^b2 loc("tests/generics/a_symbol_holds_no_brackets.lin":16:5)
  ^b1:
    %lw31 = llvm.load %s2 : !llvm.ptr -> i8 loc("tests/generics/a_symbol_holds_no_brackets.lin":16:5)
    %v31 = arith.extui %lw31 : i8 to i64 loc("tests/generics/a_symbol_holds_no_brackets.lin":16:5)
    func.return %v31 : i64 loc("tests/generics/a_symbol_holds_no_brackets.lin":16:5)
  ^b2:
    %v19 = llvm.load %s1 : !llvm.ptr -> i64 loc("tests/generics/a_symbol_holds_no_brackets.lin":16:5)
    %v20 = arith.constant 1 : i64 loc("tests/generics/a_symbol_holds_no_brackets.lin":16:5)
    %v21 = arith.cmpi eq, %v19, %v20 : i64 loc("tests/generics/a_symbol_holds_no_brackets.lin":16:5)
    cf.cond_br %v21, ^b5, ^b4 loc("tests/generics/a_symbol_holds_no_brackets.lin":16:5)
  ^b3:
    %v16 = arith.constant 0 : i64 loc("tests/generics/a_symbol_holds_no_brackets.lin":17:17)
    %sw17 = arith.trunci %v16 : i64 to i8 loc("tests/generics/a_symbol_holds_no_brackets.lin":16:5)
    llvm.store %sw17, %s2 : i8, !llvm.ptr loc("tests/generics/a_symbol_holds_no_brackets.lin":16:5)
    cf.br ^b1 loc("tests/generics/a_symbol_holds_no_brackets.lin":16:5)
  ^b4:
    %tk1 = arith.constant 3 : i32 loc("tests/generics/a_symbol_holds_no_brackets.lin":16:5)
    %tf1 = llvm.mlir.addressof @linea_file0 : !llvm.ptr loc("tests/generics/a_symbol_holds_no_brackets.lin":16:5)
    %tl1 = arith.constant 16 : i32 loc("tests/generics/a_symbol_holds_no_brackets.lin":16:5)
    %tc1 = arith.constant 5 : i32 loc("tests/generics/a_symbol_holds_no_brackets.lin":16:5)
    func.call @linea_trap(%tk1, %tf1, %tl1, %tc1) : (i32, !llvm.ptr, i32, i32) -> () loc("tests/generics/a_symbol_holds_no_brackets.lin":16:5)
    llvm.unreachable loc("tests/generics/a_symbol_holds_no_brackets.lin":16:5)
  ^b5:
    %v23 = arith.constant 8 : i64 loc("tests/generics/a_symbol_holds_no_brackets.lin":16:5)
    %v24 = llvm.getelementptr %s1[%v23] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("tests/generics/a_symbol_holds_no_brackets.lin":16:5)
    %iw25 = llvm.load %v24 : !llvm.ptr -> i8 loc("tests/generics/a_symbol_holds_no_brackets.lin":16:5)
    %v25 = arith.extui %iw25 : i8 to i64 loc("tests/generics/a_symbol_holds_no_brackets.lin":16:5)
    %sw26 = arith.trunci %v25 : i64 to i8 loc("tests/generics/a_symbol_holds_no_brackets.lin":16:5)
    llvm.store %sw26, %s3 : i8, !llvm.ptr loc("tests/generics/a_symbol_holds_no_brackets.lin":16:5)
    %lw27 = llvm.load %s3 : !llvm.ptr -> i8 loc("tests/generics/a_symbol_holds_no_brackets.lin":18:20)
    %v27 = arith.extui %lw27 : i8 to i64 loc("tests/generics/a_symbol_holds_no_brackets.lin":18:20)
    %sw28 = arith.trunci %v27 : i64 to i8 loc("tests/generics/a_symbol_holds_no_brackets.lin":16:5)
    llvm.store %sw28, %s2 : i8, !llvm.ptr loc("tests/generics/a_symbol_holds_no_brackets.lin":16:5)
    cf.br ^b1 loc("tests/generics/a_symbol_holds_no_brackets.lin":16:5)
  }
  func.func private @"lin.;ident[std.option.Option[UInt8]]"(%sret: !llvm.ptr, %a0: !llvm.ptr) attributes {llvm.linkage = #llvm.linkage<internal>} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x !llvm.ptr {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 16 : i64
    %s1 = llvm.alloca %z1 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    llvm.store %a0, %s0 : !llvm.ptr, !llvm.ptr
    cf.br ^b0
  ^b0:
    %v0 = llvm.load %s0 : !llvm.ptr -> !llvm.ptr loc("tests/generics/a_symbol_holds_no_brackets.lin":10:10)
    %cl2 = arith.constant 16 : i64 loc("tests/generics/a_symbol_holds_no_brackets.lin":10:5)
    "llvm.intr.memcpy"(%s1, %v0, %cl2) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("tests/generics/a_symbol_holds_no_brackets.lin":10:5)
    %rl4 = arith.constant 16 : i64 loc("tests/generics/a_symbol_holds_no_brackets.lin":10:5)
    "llvm.intr.memcpy"(%sret, %s1, %rl4) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("tests/generics/a_symbol_holds_no_brackets.lin":10:5)
    func.return loc("tests/generics/a_symbol_holds_no_brackets.lin":10:5)
  }
  func.func @main(%argc: i32, %argv: !llvm.ptr) -> i32 {
    func.call @linea_set_args(%argc, %argv) : (i32, !llvm.ptr) -> ()
    %status = func.call @"lin.;main"() : () -> i64
    %status32 = arith.trunci %status : i64 to i32
    func.return %status32 : i32
  }
}
