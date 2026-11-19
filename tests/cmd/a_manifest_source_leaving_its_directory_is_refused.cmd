A manifest's `source` names a directory inside the one holding the manifest,
by a path down from it. One that leaves it, by climbing with `..` or by naming
an absolute path, would make another directory's files the program's, so it is
refused. So is one whose `..` climbs back in: where a component it climbs out
of is a symbolic link, the filesystem finds another directory than the
spelling names, and the program and a library read from it would hold
different files.

  $ mkdir -p outer/app outer/elsewhere/src
  $ printf 'fn main() -> UInt8 {\n    0\n}\n' > outer/elsewhere/src/main.lin
  $ printf '{"source": "../elsewhere/src"}\n' > outer/app/linea.json
  $ linea check outer/app
  error: cannot read 'outer/app'
    the `source` in its linea.json is not a path down from the directory holding it; name a directory inside that one, without `..`
  [74]
  $ printf '{"source": "/tmp"}\n' > outer/app/linea.json
  $ linea check outer/app
  error: cannot read 'outer/app'
    the `source` in its linea.json is not a path down from the directory holding it; name a directory inside that one, without `..`
  [74]
  $ printf '{"source": "src/../../elsewhere/src"}\n' > outer/app/linea.json
  $ linea check outer/app
  error: cannot read 'outer/app'
    the `source` in its linea.json is not a path down from the directory holding it; name a directory inside that one, without `..`
  [74]
  $ mkdir -p outer/app/src && cp outer/elsewhere/src/main.lin outer/app/src/main.lin
  $ printf '{"source": "src/../src"}\n' > outer/app/linea.json
  $ linea check outer/app
  error: cannot read 'outer/app'
    the `source` in its linea.json is not a path down from the directory holding it; name a directory inside that one, without `..`
  [74]
  $ printf '{"source": "./src/"}\n' > outer/app/linea.json
  $ linea check outer/app
