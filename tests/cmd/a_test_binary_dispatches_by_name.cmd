A test binary dispatches by name: its entry point calls the dispatcher, which
compares the name it was given with each test's qualified name and calls the
test that matches. The rest of what the binary holds is left out here.

  $ (cd "$LINEA_ROOT" && linea emit-mlir --tests tests/cmd/fixtures/a_module_declares_a_test) > out
  $ awk '/@linea_str[0-9]*\("deep\./ { print } /func\.func (private @lin\._h\.dispatch|@main)\(/ { shown = 1 } shown { print } shown && /^  }$/ { shown = 0 }' out
    llvm.mlir.global internal constant @linea_str0("deep.doubling_two_gives_four") : !llvm.array<28 x i8>
    llvm.mlir.global internal constant @linea_str1("deep.doubling_one_gives_two") : !llvm.array<27 x i8>
    func.func private @lin._h.dispatch() -> i64 attributes {llvm.linkage = #llvm.linkage<internal>} {
      %z0 = arith.constant 16 : i64
      %s0 = llvm.alloca %z0 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
      %z1 = arith.constant 16 : i64
      %s1 = llvm.alloca %z1 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
      %rz11 = arith.constant 48 : i64
      %rs11 = llvm.alloca %rz11 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
      %rz25 = arith.constant 48 : i64
      %rs25 = llvm.alloca %rz25 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
      cf.br ^b0
    ^b0:
      %ba1 = llvm.mlir.addressof @linea_str0 : !llvm.ptr loc("std/testing/testing.lin":L:C)
      %v1 = llvm.ptrtoint %ba1 : !llvm.ptr to i64 loc("std/testing/testing.lin":L:C)
      %v2 = arith.constant 0 : i64 loc("std/testing/testing.lin":L:C)
      llvm.store %v1, %s0 : i64, !llvm.ptr loc("std/testing/testing.lin":L:C)
      %v5 = arith.constant 28 : i64 loc("std/testing/testing.lin":L:C)
      %v6 = arith.constant 8 : i64 loc("std/testing/testing.lin":L:C)
      %v7 = llvm.getelementptr %s0[%v6] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/testing/testing.lin":L:C)
      llvm.store %v5, %v7 : i64, !llvm.ptr loc("std/testing/testing.lin":L:C)
      %v9 = func.call @"lin.std.testing;selected"(%s0) : (!llvm.ptr) -> i1 loc("std/testing/testing.lin":L:C)
      cf.cond_br %v9, ^b1, ^b2 loc("std/testing/testing.lin":L:C)
    ^b1:
      func.call @"lin.deep;doubling_two_gives_four"(%rs11) : (!llvm.ptr) -> () loc("std/testing/testing.lin":L:C)
      %v12 = func.call @"lin.std.io.core;ran[std.io.core.IoError]"(%rs11) : (!llvm.ptr) -> i64 loc("std/testing/testing.lin":L:C)
      func.return %v12 : i64 loc("std/testing/testing.lin":L:C)
    ^b2:
      %ba15 = llvm.mlir.addressof @linea_str1 : !llvm.ptr loc("std/testing/testing.lin":L:C)
      %v15 = llvm.ptrtoint %ba15 : !llvm.ptr to i64 loc("std/testing/testing.lin":L:C)
      %v16 = arith.constant 0 : i64 loc("std/testing/testing.lin":L:C)
      llvm.store %v15, %s1 : i64, !llvm.ptr loc("std/testing/testing.lin":L:C)
      %v19 = arith.constant 27 : i64 loc("std/testing/testing.lin":L:C)
      %v20 = arith.constant 8 : i64 loc("std/testing/testing.lin":L:C)
      %v21 = llvm.getelementptr %s1[%v20] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/testing/testing.lin":L:C)
      llvm.store %v19, %v21 : i64, !llvm.ptr loc("std/testing/testing.lin":L:C)
      %v23 = func.call @"lin.std.testing;selected"(%s1) : (!llvm.ptr) -> i1 loc("std/testing/testing.lin":L:C)
      cf.cond_br %v23, ^b3, ^b4 loc("std/testing/testing.lin":L:C)
    ^b3:
      func.call @"lin.deep;doubling_one_gives_two"(%rs25) : (!llvm.ptr) -> () loc("std/testing/testing.lin":L:C)
      %v26 = func.call @"lin.std.io.core;ran[std.io.core.IoError]"(%rs25) : (!llvm.ptr) -> i64 loc("std/testing/testing.lin":L:C)
      func.return %v26 : i64 loc("std/testing/testing.lin":L:C)
    ^b4:
      %v28 = func.call @"lin.std.testing;no_such_test"() : () -> i64 loc("std/testing/testing.lin":L:C)
      func.return %v28 : i64 loc("std/testing/testing.lin":L:C)
    }
    func.func @main(%argc: i32, %argv: !llvm.ptr) -> i32 {
      func.call @linea_set_args(%argc, %argv) : (i32, !llvm.ptr) -> ()
      %status = func.call @lin._h.dispatch() : () -> i64
      %status32 = arith.trunci %status : i64 to i32
      func.return %status32 : i32
    }
