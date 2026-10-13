A program nested past the 1000-level limit is refused once, however deep it
goes, and the compiler does not overflow its stack on the way.

  $ rep() { awk -v s="$1" -v n="$2" 'BEGIN { for (i = 0; i < n; i++) printf "%s", s }'; }
  $ program() { printf 'struct _Box { v: UInt8 }\nimpl _Box {\n    fn _same(self: Self) -> Self {\n        _Box { v = self.v }\n    }\n}\nfn main() -> UInt8 {\n%s\n    0\n}\n' "$1"; }
  $ refused() { linea check "$1" 2>&1 | grep -c 'S-Nesting'; }

  $ program "    let _t = $(rep '|_a: UInt8| ' 5000)1" > lambdas.lin
  $ refused lambdas.lin
  1
  $ program "    let _t = _Box { v = 1 }$(rep '._same()' 5000)" > methods.lin
  $ refused methods.lin
  1
  $ program "    $(rep 'for _a in [1] { ' 5000)break$(rep ' }' 5000)" > loops.lin
  $ refused loops.lin
  1
  $ program "    let _t = $(rep '(1, ' 5000)1$(rep ')' 5000)" > tuples.lin
  $ refused tuples.lin
  1
  $ program "    let _t: $(rep '(UInt8, ' 5000)UInt8$(rep ')' 5000) = Default.default()" > tuple_types.lin
  $ refused tuple_types.lin
  1
  $ program "    let _t = $(rep 'if true { 1 } else ' 5000){ 2 }" > arms.lin
  $ refused arms.lin
  1
