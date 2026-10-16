A library is the directory it sits in, however a manifest spells the path to
it: absolutely, relatively, or through a symbolic link.

  $ mkdir -p app a c
  $ ln -s c clink
  $ cat > c/linea.json <<'JSON'
  > { "kind": "library", "name": "c" }
  > JSON
  $ cat > c/c.lin <<'LIN'
  > pub fn three() -> UInt8 {
  >     3
  > }
  > LIN
  $ cat > a/linea.json <<'JSON'
  > { "kind": "library", "name": "a", "dependencies": { "c": { "path": "../clink" } } }
  > JSON
  $ cat > a/a.lin <<'LIN'
  > import c
  > 
  > pub fn four() -> UInt8 {
  >     c.three() + 1
  > }
  > LIN
  $ printf '{ "dependencies": { "a": { "path": "../a" }, "c": { "path": "%s/c" } } }\n' "$PWD" > app/linea.json
  $ cat > app/main.lin <<'LIN'
  > import a
  > import c
  > 
  > fn main() -> UInt8 {
  >     a.four() + c.three()
  > }
  > LIN
  $ linea run app
  [7]

A cycle back to the root is found whichever directory the command runs in.

  $ mkdir -p ring/lib ring/m
  $ cat > ring/lib/linea.json <<'JSON'
  > { "kind": "library", "name": "lib", "dependencies": { "m": { "path": "../m" } } }
  > JSON
  $ cat > ring/lib/lib.lin <<'LIN'
  > pub fn top() -> UInt8 {
  >     1
  > }
  > LIN
  $ cat > ring/m/linea.json <<'JSON'
  > { "kind": "library", "name": "m", "dependencies": { "lib": { "path": "../lib" } } }
  > JSON
  $ cat > ring/m/m.lin <<'LIN'
  > pub fn mid() -> UInt8 {
  >     1
  > }
  > LIN
  $ linea check ring/lib
  error[M-Dependency]: `lib` closes a cycle of dependencies
   --> ring/m/linea.json:1:53
    |
  1 | { "kind": "library", "name": "m", "dependencies": { "lib": { "path": "../lib" } } }
    |                                                     ^^^^^ a library cannot depend on itself, through others or directly
    |
    = help: drop one dependency from the cycle this root -> m -> this root
  [1]
  $ (cd ring/lib && linea check .)
  error[M-Dependency]: `lib` closes a cycle of dependencies
   --> ../m/linea.json:1:53
    |
  1 | { "kind": "library", "name": "m", "dependencies": { "lib": { "path": "../lib" } } }
    |                                                     ^^^^^ a library cannot depend on itself, through others or directly
    |
    = help: drop one dependency from the cycle this root -> m -> this root
  [1]
