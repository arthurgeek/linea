Init rejects a value on yes.

  $ linea init --yes=false > out
  error: --yes takes no value
  usage: linea init <directory> [options]
  
  start a program or library in the named directory
  
  options:
    --library                 start a library with no entry point
    --yes                     start in a nonempty directory without prompting
  [64]
  $ cat out
