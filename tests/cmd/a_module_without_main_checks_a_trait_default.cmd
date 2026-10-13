A module that declares no `main` is checked beside the program's entry, and a
trait's default operation in it is checked as a generic body: `Self` is a
parameter there, so the call through `self` reaches no implementation to ask
about.

  $ mkdir -p app/lib
  $ printf '{}\n' > app/linea.json
  $ printf 'fn main() -> UInt8 {\n    3\n}\n' > app/main.lin
  $ printf 'pub trait Bag {\n    fn first(self: Self) -> UInt8\n\n    fn doubled(self: Self) -> UInt8 {\n        self.first() * 2\n    }\n}\n' > app/lib/bag.lin
  $ linea check app/lib/bag.lin
