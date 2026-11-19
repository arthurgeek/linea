A root's source is the directory the filesystem finds, however its manifest
spells the path to it. A program whose `source` is a symbolic link to a
library's directory reads that library's modules, so the two overlap and the
library is refused.

  $ mkdir -p app/lib/src
  $ ln -s lib app/code
  $ printf '{ "source": "code", "dependencies": { "lib": { "path": "lib" } } }\n' > app/linea.json
  $ printf '{ "kind": "library", "name": "lib", "source": "src" }\n' > app/lib/linea.json
  $ printf 'pub fn value() -> UInt8 {\n    7\n}\n' > app/lib/src/lib.lin
  $ printf 'import lib\nimport src\n\nfn main() -> UInt8 {\n    lib.value() + src.value()\n}\n' > app/lib/main.lin
  $ linea check app
  error[M-Dependency]: the source of `lib` overlaps the source of `this root`
   --> app/linea.json:1:39
    |
  1 | { "source": "code", "dependencies": { "lib": { "path": "lib" } } }
    |                                       ^^^^^ two roots may not read the same modules
    |
    = help: keep each library's source apart; `this root` reads modules from `app/code`
  [1]

So is a library whose `source` is a symbolic link into the program's own
source.

  $ mkdir -p shop/code/util shop/lib
  $ printf '{ "source": "code", "dependencies": { "lib": { "path": "lib" } } }\n' > shop/linea.json
  $ printf 'pub fn value() -> UInt8 {\n    7\n}\n' > shop/code/util/util.lin
  $ printf 'import lib\nimport util\n\nfn main() -> UInt8 {\n    lib.value() + util.value()\n}\n' > shop/code/main.lin
  $ printf '{ "kind": "library", "name": "lib", "source": "s" }\n' > shop/lib/linea.json
  $ ln -s ../code/util shop/lib/s
  $ linea check shop
  error[M-Dependency]: the source of `lib` overlaps the source of `this root`
   --> shop/linea.json:1:39
    |
  1 | { "source": "code", "dependencies": { "lib": { "path": "lib" } } }
    |                                       ^^^^^ two roots may not read the same modules
    |
    = help: keep each library's source apart; `this root` reads modules from `shop/code`
  [1]

A library inside the program's directory is a root of its own only where its
manifest stands between the program's source and the library's. One whose
`source` links out of its own directory into a module of the program reads
that module, and is refused.

  $ mkdir -p yard/lib yard/util
  $ printf '{ "dependencies": { "lib": { "path": "lib" } } }\n' > yard/linea.json
  $ printf '{ "kind": "library", "name": "lib", "source": "src" }\n' > yard/lib/linea.json
  $ ln -s ../util yard/lib/src
  $ printf 'pub fn value() -> UInt8 {\n    7\n}\n' > yard/util/util.lin
  $ printf 'import lib\nimport util\n\nfn main() -> UInt8 {\n    util.value() + lib.value()\n}\n' > yard/main.lin
  $ linea check yard
  error[M-Dependency]: the source of `lib` overlaps the source of `this root`
   --> yard/linea.json:1:21
    |
  1 | { "dependencies": { "lib": { "path": "lib" } } }
    |                     ^^^^^ two roots may not read the same modules
    |
    = help: keep each library's source apart; `this root` reads modules from `yard`
  [1]

A `source` that is a link to itself names no directory, and the manifest
naming it is what is refused.

  $ mkdir -p loop
  $ ln -s src loop/src
  $ printf '{ "source": "src" }\n' > loop/linea.json
  $ linea check loop
  error: cannot read 'loop'
    its source, 'loop/src', is a symbolic link that leads back to itself; name a directory in the linea.json
  [74]
