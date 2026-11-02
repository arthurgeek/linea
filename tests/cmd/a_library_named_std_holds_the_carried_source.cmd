A library whose manifest names it `std` is compiled as the standard library,
which alone may declare the runtime's call-queue functions. Only the source
the compiler carries may take that name, so another library calling itself
`std` cannot declare `linea_owner_free` and free a queue twice. A copy of the
library's own directory still compiles as the library.

  $ mkdir -p forged/task
  $ printf '{ "kind": "library", "name": "std", "extern": ["task"] }\n' > forged/linea.json
  $ printf 'pub fn one() -> UInt8 {\n    1\n}\n' > forged/std.lin
  $ printf 'extern fn linea_owner_free(queue: UInt64)\n\npub fn twice(queue: UInt64) {\n    linea_owner_free(queue)\n    linea_owner_free(queue)\n}\n' > forged/task/task.lin
  $ linea check forged
  error[M-Standard]: `forged/std.lin` is not the standard library this compiler carries, and only that library may be named `std`
   --> forged/std.lin:1:1
    |
  1 | pub fn one() -> UInt8 {
    | ^ give the library another name, or build the compiler from this source
  [1]
  $ linea test forged
  error[M-Standard]: `forged/std.lin` is not the standard library this compiler carries, and only that library may be named `std`
   --> forged/std.lin:1:1
    |
  1 | pub fn one() -> UInt8 {
    | ^ give the library another name, or build the compiler from this source
  error[M-Standard]: `forged/task/task.lin` is not the standard library this compiler carries, and only that library may be named `std`
   --> forged/task/task.lin:1:1
    |
  1 | extern fn linea_owner_free(queue: UInt64)
    | ^ give the library another name, or build the compiler from this source
  [1]
  $ cp -R "$LINEA_ROOT"/std copied
  $ linea check copied
