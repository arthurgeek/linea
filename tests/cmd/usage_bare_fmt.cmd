Usage bare fmt.

  $ linea fmt > out
  usage: linea fmt <path>... [options]
  
  rewrite source in canonical form, in place
  
  options:
    --stdin                   read one file from stdin, write to stdout
    --check                   report what would change, writing nothing
  
  common:
    --color=auto|always|never colour output (default: auto)
    --error-format=human|json diagnostic format (default: human)
  [64]
  $ cat out
