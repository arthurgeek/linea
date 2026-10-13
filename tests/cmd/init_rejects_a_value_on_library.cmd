Init rejects a value on library.

  $ linea init --library=false > out
  error: --library takes no value
  usage: linea init <directory> [options]
  
  start a program or library in the named directory
  
  options:
    --library                 start a library with no entry point
    --yes                     start in a nonempty directory without prompting
  [64]
  $ cat out
