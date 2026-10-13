Usage unknown option.

  $ linea check "$LINEA_ROOT"/tests/decl/early_return.lin --wat > out
  error: unknown option '--wat'
  usage: linea check <path> [options]
  
  report diagnostics without generating code
  
  common:
    --color=auto|always|never colour output (default: auto)
    --error-format=human|json diagnostic format (default: human)
  [64]
  $ cat out
