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
