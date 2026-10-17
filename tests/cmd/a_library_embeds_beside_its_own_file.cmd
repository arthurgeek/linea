A library's module embeds a file beside its own source, and a path climbing
above the library's manifest is refused.

  $ mkdir -p shelf/catalog
  $ printf '{ "kind": "library" }\n' > shelf/linea.json
  $ printf 'pub fn total() -> UInt64 {\n    1\n}\n' > shelf/shelf.lin
  $ printf 'import std.testing\n\npub fn title() -> Str {\n    embed("title.txt")\n}\n\ntest fn title_is_the_file() {\n    testing.assert_eq(title(), "Catalog", "the title is not the file")?\n    .Ok(())\n}\n' > shelf/catalog/catalog.lin
  $ printf 'Catalog' > shelf/catalog/title.txt
  $ linea test shelf
  ok    catalog.title_is_the_file
  
  1 passed, 0 failed
  $ printf 'import std.testing\n\npub fn title() -> Str {\n    embed("../../title.txt")\n}\n\ntest fn title_is_the_file() {\n    testing.assert_eq(title(), "Catalog", "the title is not the file")?\n    .Ok(())\n}\n' > shelf/catalog/catalog.lin
  $ linea test shelf
  error[M-Embed]: "../../title.txt" climbs above the library's root
   --> shelf/catalog/catalog.lin:4:11
    |
  4 |     embed("../../title.txt")
    |           ^^^^^^^^^^^^^^^^^ an embedded file is inside the directory holding the library's `linea.json`
  [1]
