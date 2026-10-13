Named command help succeeds.

  $ linea help init > out
  $ cat out
  usage: linea init <directory> [options]
  
  start a program or library in the named directory
  
  options:
    --library                 start a library with no entry point
    --yes                     start in a nonempty directory without prompting
