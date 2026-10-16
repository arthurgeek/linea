An application depends on a library that sits beside it, outside its own
directory. The path in its manifest is relative to the manifest.

  $ mkdir -p guests names
  $ cat > names/linea.json <<'JSON'
  > { "kind": "library", "name": "names" }
  > JSON
  $ cat > names/names.lin <<'LIN'
  > import std.testing
  > 
  > // `initial` answers the first byte of a name, or 0 for an empty one.
  > pub fn initial(name: Str) -> UInt8 {
  >     name.byte(0).unwrap_or(0)
  > }
  > 
  > test fn an_initial_is_the_first_byte() {
  >     testing.assert_eq(initial("Ada"), 65, "A is 65")?
  > }
  > LIN
  $ cat > guests/linea.json <<'JSON'
  > { "dependencies": { "names": { "path": "../names" } } }
  > JSON
  $ cat > guests/main.lin <<'LIN'
  > import names
  > import std.testing
  > 
  > fn main() -> UInt8 {
  >     names.initial("Grace")
  > }
  > 
  > test fn grace_starts_with_g() {
  >     testing.assert_eq(names.initial("Grace"), 71, "G is 71")?
  > }
  > LIN
  $ linea run guests
  [71]
  $ linea test names
  ok    an_initial_is_the_first_byte
  
  1 passed, 0 failed
  $ linea check names/names.lin

Testing the application runs its own tests, not the library's.

  $ linea test guests
  ok    grace_starts_with_g
  
  1 passed, 0 failed
