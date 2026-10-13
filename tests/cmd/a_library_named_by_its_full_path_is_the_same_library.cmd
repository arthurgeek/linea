A root named on the command line by its absolute path, from the directory
holding it, is the root its relative name names: the standard library's tests
compile to the same code whichever spelling reaches it. Each file is reported
under the spelling that reached it, so that spelling is set aside before the
two are compared.

  $ (cd "$LINEA_ROOT" && linea emit-mlir --tests "$LINEA_ROOT"/std/) > absolute.mlir 2>&1; echo "absolute $?"
  absolute 0
  $ (cd "$LINEA_ROOT" && linea emit-mlir --tests ./std) > dotted.mlir 2>&1; echo "dotted $?"
  dotted 0
  $ sed -e "s|$LINEA_ROOT/||g" -e '/@linea_file/ s/!llvm\.array<[0-9]* x i8>/!llvm.array<N x i8>/' absolute.mlir > absolute.compared
  $ sed -e '/@linea_file/ s/!llvm\.array<[0-9]* x i8>/!llvm.array<N x i8>/' dotted.mlir > dotted.compared
  $ cmp absolute.compared dotted.compared
