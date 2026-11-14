A library is built into an object and nothing is linked, so a compiler with
no runtime beside it still builds one. A program is linked against the
runtime and says so when there is none.

  $ mkdir -p alone shelf app && cp "$(command -v linea)" alone/linea
  $ printf 'export fn seven() -> UInt8 {\n    7\n}\n' > shelf/shelf.lin
  $ echo '{ "kind": "library", "name": "shelf" }' > shelf/linea.json
  $ printf 'fn main() -> UInt8 {\n    0\n}\n' > app/main.lin
  $ env -u LINEA_RUNTIME alone/linea build shelf -o shelf.o
  $ test -s shelf.o
  $ env -u LINEA_RUNTIME alone/linea build app -o app.out
  error: cannot find liblinea_rt.a beside the compiler
  [74]
