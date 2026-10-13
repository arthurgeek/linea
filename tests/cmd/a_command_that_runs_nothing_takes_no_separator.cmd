A command that runs nothing takes no separator.

  $ linea check "$LINEA_ROOT"/tests/decl/a_test_declares_no_visibility.lin -- stray > out
  error: unknown option '--'
  usage: linea check <path> [options]
  
  report diagnostics without generating code
  
  common:
    --color=auto|always|never colour output (default: auto)
    --error-format=human|json diagnostic format (default: human)
  [64]
  $ cat out
