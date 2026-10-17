A library's public signature states its allocator, and a program that depends
on the library chooses one per call.

  $ mkdir -p shout greeter shelf
  $ cat > shout/linea.json <<'JSON'
  > { "kind": "library", "name": "shout" }
  > JSON
  $ cat > shout/shout.lin <<'LIN'
  > import std.fmt
  > import std.mem
  > import std.testing
  > 
  > use mem.Owner
  > 
  > // `shout_in` builds the shouted word in the allocator its caller passes.
  > pub fn shout_in[A: Allocator](allocator: A, word: Str) -> Result[String[A], mem.Oom] where carries(.Ok: allocator) {
  >     fmt.render_owned_in(allocator, "{word}!")
  > }
  > 
  > test fn a_word_is_shouted_into_an_arena() {
  >     let arena = mem.Arena.open(mem.system(), size: 256)
  >     defer arena.release()
  >     let loud = shout_in(arena.handle(), "hi") else |_| {
  >         return .Err(testing.refused("the arena holds the word"))
  >     }
  >     testing.assert_eq(loud.view(), "hi!", "the word is shouted")?
  > }
  > 
  > // `shout` builds it from the system allocator, and its result says so.
  > pub fn shout(word: Str) -> Result[String[mem.SystemAllocator], mem.Oom] where carries() {
  >     shout_in(mem.system(), word)
  > }
  > 
  > test fn a_word_is_shouted_from_the_system_allocator() {
  >     defer let loud = shout("hi") else |_| {
  >         return .Err(testing.refused("the system allocator holds the word"))
  >     }
  >     testing.assert_eq(loud.view(), "hi!", "the word is shouted")?
  > }
  > LIN
  $ linea test shout
  ok    a_word_is_shouted_from_the_system_allocator
  ok    a_word_is_shouted_into_an_arena
  
  2 passed, 0 failed
  $ cat > greeter/linea.json <<'JSON'
  > { "dependencies": { "shout": { "path": "../shout" } } }
  > JSON
  $ cat > greeter/main.lin <<'LIN'
  > import shout
  > import std.io
  > import std.mem
  > 
  > use mem.Owner
  > 
  > fn main() -> Result[UInt8, io.IoError] {
  >     let arena = mem.Arena.open(mem.system(), size: 256)
  >     defer arena.release()
  >     let kept = shout.shout_in(arena.handle(), "hello") else |_| {
  >         return .Ok(1)
  >     }
  >     defer let loud = shout.shout("world") else |_| {
  >         return .Ok(1)
  >     }
  >     io.println("{kept.view()} {loud.view()}")?
  >     .Ok(0)
  > }
  > LIN
  $ linea run greeter
  hello! world!

A library whose public signature leaves the allocator to its default is
refused where it is written, when a program that depends on it is checked.

  $ cat > shelf/linea.json <<'JSON'
  > { "kind": "library", "name": "shelf" }
  > JSON
  $ cat > shelf/shelf.lin <<'LIN'
  > pub fn names() -> Vec[Str] {
  >     Vec.new()
  > }
  > LIN
  $ mkdir -p shelved
  $ cat > shelved/linea.json <<'JSON'
  > { "dependencies": { "shelf": { "path": "../shelf" } } }
  > JSON
  $ cat > shelved/main.lin <<'LIN'
  > import shelf
  > 
  > fn main() -> UInt8 {
  >     let titles = shelf.names()
  >     titles.release()
  >     0
  > }
  > LIN
  $ linea check shelved
  error[T-DefaultedAllocator]: Public library signature uses the default allocator for `Vec`.
   --> shelf/shelf.lin:1:19
    |
  1 | pub fn names() -> Vec[Str] {
    |                   ^^^ Specify `mem.SystemAllocator` to make this restriction intentional, or make the allocator a generic parameter to preserve allocator polymorphism.
  [1]
