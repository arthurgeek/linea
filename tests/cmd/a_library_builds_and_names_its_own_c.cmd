A library names its C relative to its own directory. A program that depends
on one whose source is missing is told which library and which file. Built on
its own, the library's object holds its C, and the libraries it links are
printed for whoever links the object.

  $ mkdir -p shelf/count app && printf 'extern fn count_squares(count: Int32) -> Int64\n\npub fn squares(n: Int32) -> Int64 {\n    count_squares(n)\n}\n' > shelf/count/count.lin
  $ printf 'import count\n\nexport fn shelf_squares(n: Int32) -> Int64 {\n    count.squares(n)\n}\n' > shelf/shelf.lin
  $ echo '{ "kind": "library", "name": "shelf", "extern": ["count"], "native": ["count/count.c"], "link": ["sqlite3"] }' > shelf/linea.json
  $ echo '{ "dependencies": { "shelf": { "path": "../shelf", "extern": true } } }' > app/linea.json
  $ printf 'fn main() -> UInt8 {\n    0\n}\n' > app/main.lin
  $ linea check app
  error[M-Dependency]: the linea.json in `../shelf` names `count/count.c` under `native`, and `../shelf` holds no such file
   --> app/linea.json:1:40
    |
  1 | { "dependencies": { "shelf": { "path": "../shelf", "extern": true } } }
    |                                        ^^^^^^^^^^ correct the library's manifest, or add the source it names
  [1]
  $ printf '#include <stdint.h>\nint64_t count_squares(int32_t n) { int64_t t = 0; for (int32_t i = 1; i <= n; i++) t += (int64_t)i * i; return t; }\n' > shelf/count/count.c
  $ linea build shelf -o shelf.o
  note: link 'shelf.o' with -lsqlite3
