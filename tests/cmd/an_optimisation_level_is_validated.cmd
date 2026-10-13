An optimisation level is validated.

  $ linea build -O fast "$LINEA_ROOT"/tests/decl/a_helper_only_a_test_calls_is_used.lin > out
  error: invalid -O value
  usage: linea build <path> [options]
  
  compile a file or root to an executable, or a library to an object
  
  options:
    -o <path>                 output path (default: the source's own name)
    -O 0|1|2|3|s|z            optimisation level for the generated code (default: 2)
    --keep                    keep the intermediate .mlir, .mlir.llvm and .ll files
    --check-storage           abort on a use of freed storage (slower; always on for `test`)
  
  common:
    --color=auto|always|never colour output (default: auto)
    --error-format=human|json diagnostic format (default: human)
  [64]
  $ cat out
