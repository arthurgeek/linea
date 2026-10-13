The standard library's raw memory primitives are recognised by their symbol
and signature, never by their parameters' names: renaming a parameter still
lowers every call to a checked access, and a primitive declared with another
signature is refused where it is declared.

  $ cp -R "$LINEA_ROOT"/std renamed
  $ sed 's/^extern fn linea_raw_load(at: UInt64/extern fn linea_raw_load(address: UInt64/' "$LINEA_ROOT"/std/mem/buffer.lin > renamed/mem/buffer.lin
  $ linea emit-mlir --tests renamed > renamed.mlir 2>&1; echo "renamed $?"
  renamed 0
  $ grep -c 'call @linea_raw_load(' renamed.mlir
  0
  [1]
  $ cp -R "$LINEA_ROOT"/std retyped
  $ sed 's/^extern fn linea_raw_load(at: UInt64/extern fn linea_raw_load(at: UInt32/' "$LINEA_ROOT"/std/mem/buffer.lin > retyped/mem/buffer.lin
  $ linea check retyped > retyped.out 2>&1; echo "retyped $?"
  retyped 1
  $ grep -A4 'T-ExternRuntime' retyped.out
  error[T-ExternRuntime]: the runtime gives `linea_raw_load` the signature `fn(UInt64, UInt64, UInt64) -> UInt64`
    --> retyped/mem/buffer.lin:44:11
     |
  44 | extern fn linea_raw_load(at: UInt32, len: UInt64, i: UInt64) -> UInt64
     |           ^^^^^^^^^^^^^^ declare it with the runtime's parameter types, conventions and result
