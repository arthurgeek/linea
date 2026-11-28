Host tool errors retain a build's input for diagnosis, while tests and runs
remove their temporary artifacts. The successful build keeps intermediates
only when requested.

  $ printf 'fn main() -> UInt8 { 0 }\n' > main.lin
  $ mkdir tools missing tmp
  $ compiler=$(command -v linea)
  $ PATH="$PWD/missing" "$compiler" build main.lin -o absent
  error: mlir-opt is not installed
  [74]
  $ test -s absent.mlir
  $ test ! -e absent
  $ printf '#!/bin/sh\nprintf "forced lowering failure\\n" >&2\nexit 1\n' > tools/mlir-opt
  $ chmod +x tools/mlir-opt
  $ PATH="$PWD/tools:$PATH" linea build main.lin -o refused
  error: mlir-opt failed
  forced lowering failure
  [70]
  $ test -s refused.mlir
  $ PATH="$PWD/tools:$PATH" TMPDIR="$PWD/tmp" linea run main.lin
  error: mlir-opt failed
  forced lowering failure
  [70]
  $ PATH="$PWD/tools:$PATH" TMPDIR="$PWD/tmp" linea test "$LINEA_ROOT"/tests/cmd/fixtures/tests_named_by_strings
  error: mlir-opt failed
  forced lowering failure
  [70]
  $ for i in $(seq 600); do test -z "$(ls -A tmp)" && break; sleep 0.01; done; ls -A tmp
  $ linea build --keep main.lin -o retained
  $ test -s retained.mlir && test -s retained.mlir.llvm && test -s retained.ll
  $ ./retained
  $ linea build main.lin -o released
  $ test ! -e released.mlir && test ! -e released.mlir.llvm && test ! -e released.ll
  $ ./released
