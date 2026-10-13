Usage wrong option.

  $ linea check "$LINEA_ROOT"/tests/decl/early_return.lin -o out > out
  error: `check` does not take `-o` -- it belongs to `build`
  usage: linea check <path> [options]
  
  report diagnostics without generating code
  
  common:
    --color=auto|always|never colour output (default: auto)
    --error-format=human|json diagnostic format (default: human)
  [64]
  $ cat out
