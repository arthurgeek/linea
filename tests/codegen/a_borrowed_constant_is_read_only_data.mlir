!linea_static0 = !llvm.struct<packed (i8, !llvm.array<7 x i8>, i64, i64, i8, !llvm.array<7 x i8>)>
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
  llvm.mlir.global internal constant @linea_file0("tests/codegen/a_borrowed_constant_is_read_only_data.lin\00") : !llvm.array<56 x i8>
  llvm.mlir.global internal constant @linea_str0("tea") : !llvm.array<3 x i8>
  llvm.mlir.global internal constant @linea_static0() {addr_space = 0 : i32, alignment = 8 : i64} : !linea_static0 {
    %s0 = llvm.mlir.undef : !linea_static0
    %e0 = llvm.mlir.constant(3 : i8) : i8
    %s1 = llvm.insertvalue %e0, %s0[0] : !linea_static0
    %e1 = llvm.mlir.zero : !llvm.array<7 x i8>
    %s2 = llvm.insertvalue %e1, %s1[1] : !linea_static0
    %a2 = llvm.mlir.addressof @linea_str0 : !llvm.ptr
    %e2 = llvm.ptrtoint %a2 : !llvm.ptr to i64
    %s3 = llvm.insertvalue %e2, %s2[2] : !linea_static0
    %e3 = llvm.mlir.constant(3 : i64) : i64
    %s4 = llvm.insertvalue %e3, %s3[3] : !linea_static0
    %e4 = llvm.mlir.constant(1 : i8) : i8
    %s5 = llvm.insertvalue %e4, %s4[4] : !linea_static0
    %e5 = llvm.mlir.zero : !llvm.array<7 x i8>
    %s6 = llvm.insertvalue %e5, %s5[5] : !linea_static0
    llvm.return %s6 : !linea_static0
  }
  func.func private @linea_set_args(i32, !llvm.ptr)
  func.func private @linea_trap(i32, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @linea_panic(i64, i64, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @"lin.;main"() -> i64 attributes {llvm.linkage = #llvm.linkage<internal>} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x !llvm.ptr {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 1 : i64
    %s1 = llvm.alloca %z1 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    cf.br ^b0
  ^b0:
    %v0 = func.call @"lin.;label"() : () -> !llvm.ptr loc("tests/codegen/a_borrowed_constant_is_read_only_data.lin":18:16)
    llvm.store %v0, %s0 : !llvm.ptr, !llvm.ptr loc("tests/codegen/a_borrowed_constant_is_read_only_data.lin":18:5)
    %v2 = llvm.load %s0 : !llvm.ptr -> !llvm.ptr loc("tests/codegen/a_borrowed_constant_is_read_only_data.lin":19:8)
    %v4 = arith.constant 24 : i64 loc("tests/codegen/a_borrowed_constant_is_read_only_data.lin":19:8)
    %v5 = llvm.getelementptr %v2[%v4] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("tests/codegen/a_borrowed_constant_is_read_only_data.lin":19:8)
    %iw6 = llvm.load %v5 : !llvm.ptr -> i8 loc("tests/codegen/a_borrowed_constant_is_read_only_data.lin":19:8)
    %iz6 = arith.constant 0 : i8 loc("tests/codegen/a_borrowed_constant_is_read_only_data.lin":19:8)
    %v6 = arith.cmpi ne, %iw6, %iz6 : i8 loc("tests/codegen/a_borrowed_constant_is_read_only_data.lin":19:8)
    cf.cond_br %v6, ^b1, ^b2 loc("tests/codegen/a_borrowed_constant_is_read_only_data.lin":19:5)
  ^b1:
    %v8 = llvm.load %s0 : !llvm.ptr -> !llvm.ptr loc("tests/codegen/a_borrowed_constant_is_read_only_data.lin":20:9)
    %v10 = arith.constant 0 : i64 loc("tests/codegen/a_borrowed_constant_is_read_only_data.lin":20:9)
    %iw12 = llvm.load %v8 : !llvm.ptr -> i8 loc("tests/codegen/a_borrowed_constant_is_read_only_data.lin":20:9)
    %v12 = arith.extui %iw12 : i8 to i64 loc("tests/codegen/a_borrowed_constant_is_read_only_data.lin":20:9)
    %sw13 = arith.trunci %v12 : i64 to i8 loc("tests/codegen/a_borrowed_constant_is_read_only_data.lin":19:5)
    llvm.store %sw13, %s1 : i8, !llvm.ptr loc("tests/codegen/a_borrowed_constant_is_read_only_data.lin":19:5)
    cf.br ^b3 loc("tests/codegen/a_borrowed_constant_is_read_only_data.lin":19:5)
  ^b2:
    %v15 = arith.constant 0 : i64 loc("tests/codegen/a_borrowed_constant_is_read_only_data.lin":22:9)
    %sw16 = arith.trunci %v15 : i64 to i8 loc("tests/codegen/a_borrowed_constant_is_read_only_data.lin":19:5)
    llvm.store %sw16, %s1 : i8, !llvm.ptr loc("tests/codegen/a_borrowed_constant_is_read_only_data.lin":19:5)
    cf.br ^b3 loc("tests/codegen/a_borrowed_constant_is_read_only_data.lin":19:5)
  ^b3:
    %lw18 = llvm.load %s1 : !llvm.ptr -> i8 loc("tests/codegen/a_borrowed_constant_is_read_only_data.lin":19:5)
    %v18 = arith.extui %lw18 : i8 to i64 loc("tests/codegen/a_borrowed_constant_is_read_only_data.lin":19:5)
    func.return %v18 : i64 loc("tests/codegen/a_borrowed_constant_is_read_only_data.lin":19:5)
  }
  func.func private @"lin.;label"() -> !llvm.ptr attributes {llvm.linkage = #llvm.linkage<internal>} {
    cf.br ^b0
  ^b0:
    %v0 = llvm.mlir.addressof @linea_static0 : !llvm.ptr loc("tests/codegen/a_borrowed_constant_is_read_only_data.lin":14:5)
    func.return %v0 : !llvm.ptr loc("tests/codegen/a_borrowed_constant_is_read_only_data.lin":14:5)
  }
  func.func @main(%argc: i32, %argv: !llvm.ptr) -> i32 {
    func.call @linea_set_args(%argc, %argv) : (i32, !llvm.ptr) -> ()
    %status = func.call @"lin.;main"() : () -> i64
    %status32 = arith.trunci %status : i64 to i32
    func.return %status32 : i32
  }
}
