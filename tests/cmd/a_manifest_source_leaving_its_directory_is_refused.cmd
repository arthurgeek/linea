A manifest's `source` names a directory inside the one holding the manifest.
One that leaves it, by climbing with `..` or by naming an absolute path, would
make another directory's files the program's, so it is refused.

  $ mkdir -p outer/app outer/elsewhere/src
  $ printf 'fn main() -> UInt8 {\n    0\n}\n' > outer/elsewhere/src/main.lin
  $ printf '{"source": "../elsewhere/src"}\n' > outer/app/linea.json
  $ linea check outer/app
  error: cannot read 'outer/app'
    the `source` in its linea.json leaves the directory holding it; name a directory inside that one
  [74]
  $ printf '{"source": "/tmp"}\n' > outer/app/linea.json
  $ linea check outer/app
  error: cannot read 'outer/app'
    the `source` in its linea.json leaves the directory holding it; name a directory inside that one
  [74]
  $ printf '{"source": "src/../../elsewhere/src"}\n' > outer/app/linea.json
  $ linea check outer/app
  error: cannot read 'outer/app'
    the `source` in its linea.json leaves the directory holding it; name a directory inside that one
  [74]
  $ mkdir -p outer/app/src && cp outer/elsewhere/src/main.lin outer/app/src/main.lin
  $ printf '{"source": "./src/"}\n' > outer/app/linea.json
  $ linea check outer/app
