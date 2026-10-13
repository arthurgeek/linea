A program nested close to the 1000-level limit is checked and lowered in full,
whatever the construct and however large the compiler's stack frames are.

  $ rep() { awk -v s="$1" -v n="$2" 'BEGIN { for (i = 0; i < n; i++) printf "%s", s }'; }
  $ program() { printf 'struct _Box { v: UInt8 }\nimpl _Box {\n    fn _same(self: Self) -> Self {\n        _Box { v = self.v }\n    }\n}\nfn main() -> UInt8 {\n%s\n    0\n}\n' "$1"; }

Nested lambdas, each taking a parameter.

  $ program "    let _t = $(rep '|_a: UInt8| ' 990)1" > lambdas.lin
  $ linea check lambdas.lin
  $ linea emit-mlir lambdas.lin > /dev/null

A chain of method calls.

  $ program "    let _t = _Box { v = 1 }$(rep '._same()' 480)" > methods.lin
  $ linea check methods.lin
  $ linea emit-mlir methods.lin > /dev/null

Nested `for` loops.

  $ program "    $(rep 'for _a in [1] { ' 990)break$(rep ' }' 990)" > loops.lin
  $ linea check loops.lin

Nested tuple literals and the types they have.

  $ program "    let _t = $(rep '(1, ' 990)1$(rep ')' 990)" > tuples.lin
  $ linea check tuples.lin
  $ program "    let _t: $(rep '(UInt8, ' 990)UInt8$(rep ')' 990) = Default.default()" > tuple_types.lin
  $ linea check tuple_types.lin

A chain of `else if` arms.

  $ program "    let _t = $(rep 'if true { 1 } else ' 990){ 2 }" > arms.lin
  $ linea check arms.lin
  $ linea emit-mlir arms.lin > /dev/null
