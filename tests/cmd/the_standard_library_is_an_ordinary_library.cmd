The standard library is a library like any other: its manifest names it, so
checking or testing its directory, or one of its files, from any working
directory compiles it once, as itself, and its symbols are named by their
import routes wherever the directory sits. Only a library may take the name
`std`. A program's own directory named `std` belongs to that program, and an
import starting with `std` still names the standard library.

  $ (cd "$LINEA_ROOT" && linea check std) > checked 2>&1; echo "check std $?"
  check std 0
  $ cat checked
  $ linea emit-mlir --tests "$LINEA_ROOT"/std > tested.mlir 2>&1; echo "build its tests from elsewhere $?"
  build its tests from elsewhere 0
  $ grep -m 1 -o '@"lin\.std\.mem;system"' tested.mlir
  @"lin.std.mem;system"
  $ (cd "$LINEA_ROOT" && linea check std/mem/allocator.lin) > file 2>&1; echo "check one of its files $?"
  check one of its files 0
  $ cat file
  $ cp -R "$LINEA_ROOT"/std "my lib"
  $ linea emit-mlir --tests "my lib" > copy.mlir 2>&1; echo "emit a copy $?"
  emit a copy 0
  $ grep -c 'my\$20lib' copy.mlir
  0
  [1]
  $ grep -m 1 -o '@"lin\.std\.mem;system"' copy.mlir
  @"lin.std.mem;system"
  $ mkdir named
  $ printf '{ "name": "std" }\n' > named/linea.json
  $ printf 'fn main() -> UInt8 {\n    let answer: Option[UInt8] = .Some(0)\n    answer.unwrap_or(1)\n}\n' > named/main.lin
  $ linea check named
  error: a program may not be named `std`
    the linea.json for 'named' names it `std`, the library every program depends on: give it another name, or make it a library
  [64]
  $ mkdir std
  $ printf 'fn main() -> UInt8 {\n    return 7\n}\n\ntest fn the_program_is_its_own() {}\n' > std/main.lin
  $ linea check std
  $ linea run std
  [7]
  $ linea test std
  ok    the_program_is_its_own
  
  1 passed, 0 failed
  $ mkdir -p app/std/extra
  $ printf 'pub fn one() -> UInt8 {\n    1\n}\n' > app/std/extra/extra.lin
  $ printf 'import std.extra\n\nfn main() -> UInt8 {\n    extra.one()\n}\n' > app/main.lin
  $ linea check app
  error[M-Import]: the standard library holds no module named `extra`; an import starting with `std` names it, so this program's `app/std/extra` cannot be imported
   --> app/main.lin:1:8
    |
  1 | import std.extra
    |        ^^^^^^^^^ cannot import it
  [1]
