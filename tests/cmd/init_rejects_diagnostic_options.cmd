Init rejects diagnostic options.

  $ linea init --color=never > out
  error: unknown option '--color'
  usage: linea init <directory> [options]
  
  start a program or library in the named directory
  
  options:
    --library                 start a library with no entry point
    --yes                     start in a nonempty directory without prompting
  [64]
  $ cat out
