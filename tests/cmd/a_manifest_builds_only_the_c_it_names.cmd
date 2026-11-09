A manifest names C sources under `native`, libraries under `link` and headers
under `headers`. A name that is not a library, a source outside the manifest's
directory, one spelled with a character a path does not need or one that does
not exist, a header outside the manifest's directory, and C named without an
`extern` grant are each refused before anything is compiled.

  $ mkdir -p flag outside quoted missing climbing ungranted && for d in flag outside quoted missing climbing ungranted; do echo 'fn main() -> UInt8 { 0 }' > $d/main.lin; done
  $ echo '{ "extern": ["."], "link": ["m -lfoo"] }' > flag/linea.json
  $ linea check flag
  error: cannot read 'flag'
    the linea.json names under `link` something other than a library name, such as "sqlite3" for -lsqlite3
  [74]
  $ echo '{ "extern": ["."], "native": ["../shim.c"] }' > outside/linea.json
  $ linea check outside
  error: cannot read 'outside'
    the linea.json names under `native` something other than a C source below it, such as "store/bind.c"
  [74]
  $ echo '{ "extern": ["."], "native": ["shim.c\" int twice(int); /* .c"] }' > quoted/linea.json
  $ linea check quoted
  error: cannot read 'quoted'
    the linea.json names under `native` something other than a C source below it, such as "store/bind.c"
  [74]
  $ echo '{ "extern": ["."], "native": ["shim.c"] }' > missing/linea.json
  $ linea check missing
  error: cannot read 'missing'
    the linea.json names under `native` a C source that does not exist
  [74]
  $ echo '{ "extern": ["."], "headers": ["../shim.h"] }' > climbing/linea.json
  $ linea check climbing
  error: cannot read 'climbing'
    the linea.json names under `headers` something other than a C header as an include names it, such as "sqlite3.h" or "store/shim.h"
  [74]
  $ echo '{ "link": ["sqlite3"] }' > ungranted/linea.json
  $ linea check ungranted
  error: cannot read 'ungranted'
    the linea.json names C to build or link but grants no module `extern`, so nothing could call it
  [74]
