Two roots overlap where both would read one module file. A program's walk of
its source stops at every directory holding a manifest, so a library whose
source sits beneath such a directory shares nothing with the program, however
its `source` reaches it.

A program whose source holds a library's directory reads that library's
modules, so the library is refused, once.

  $ mkdir -p l3/code/x
  $ printf '{ "source": "code", "dependencies": { "lib": { "path": "code" } } }\n' > l3/linea.json
  $ printf '{ "kind": "library", "name": "lib", "source": "x" }\n' > l3/code/linea.json
  $ printf 'pub fn value() -> UInt8 {\n    7\n}\n' > l3/code/x/x.lin
  $ printf 'import lib\n\nfn main() -> UInt8 {\n    lib.value()\n}\n' > l3/code/main.lin
  $ linea check l3
  error[M-Dependency]: the source of `lib` overlaps the source of `this root`
   --> l3/linea.json:1:39
    |
  1 | { "source": "code", "dependencies": { "lib": { "path": "code" } } }
    |                                       ^^^^^ two roots may not read the same modules
    |
    = help: keep each library's source apart; `this root` reads modules from `l3/code`
  [1]

A library whose `source` links to a directory holding another root's
manifest reads modules the program's walk never enters, so the program runs.

  $ mkdir -p l10/lib l10/other
  $ printf '{ "dependencies": { "lib": { "path": "lib" } } }\n' > l10/linea.json
  $ printf '{ "kind": "library", "name": "lib", "source": "src" }\n' > l10/lib/linea.json
  $ ln -s ../other l10/lib/src
  $ printf '{ "kind": "library", "name": "other" }\n' > l10/other/linea.json
  $ printf 'pub fn value() -> UInt8 {\n    7\n}\n' > l10/other/other.lin
  $ printf 'import lib\n\nfn main() -> UInt8 {\n    lib.value()\n}\n' > l10/main.lin
  $ linea run l10
  [7]
