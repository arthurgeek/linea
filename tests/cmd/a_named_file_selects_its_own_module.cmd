A `.lin` file named on the command line selects its own module as the entry of
the program its manifest identifies. `check` reads that module and everything
it reaches, even where the program's `main` never imports it; `run` runs that
module's own `main`, and refuses a module that declares none.

  $ mkdir -p app/util app/tools
  $ printf '{}\n' > app/linea.json
  $ printf 'fn main() -> UInt8 {\n    3\n}\n' > app/main.lin
  $ printf 'pub fn helper() -> UInt8 {\n    nope\n}\n' > app/util/u.lin
  $ printf 'fn main() -> UInt8 {\n    9\n}\n' > app/tools/gen.lin
  $ mkdir app/shapes
  $ printf 'pub fn area(width: UInt8, height: UInt8) -> UInt8 {\n    width * height\n}\n' > app/shapes/area.lin
  $ linea check app/util/u.lin
  error[N-Undefined]: undefined name `nope`
   --> app/util/u.lin:2:5
    |
  2 |     nope
    |     ^^^^ no binding with this name is in scope
  [1]
  $ linea check app
  $ linea run app/tools/gen.lin
  [9]
  $ linea check app/shapes/area.lin
  $ linea run app/shapes/area.lin
  error: the module of 'app/shapes/area.lin' declares no `main`, so there is nothing to run
    name a file of a module that declares one, or the program's own directory
  [64]
  $ linea run app/main.lin
  [3]
