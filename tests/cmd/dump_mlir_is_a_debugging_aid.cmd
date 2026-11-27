MLIR inspection is listed beside the other debugging aids.

  $ linea dump-mlir --scope=bad missing.lin 2>/dev/null
  [64]
  $ linea help > help
  $ sed -n '/^debugging /,$p' help | grep 'dump-mlir' > /dev/null
  $ sed -n '/^debugging /,$p' help | awk '$1 == "dump-mono" || $1 == "dump-mlir" || $1 == "dump-asm" { print $1 }'
  dump-mono
  dump-mlir
  dump-asm
  $ grep -c '^      --scope=' help
  1
