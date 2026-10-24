A statement is linear, so a caller that prepares one and returns without
finishing it is refused at compile time.

  $ mkdir app
  $ printf '{ "dependencies": { "sqlite": { "path": "%s/examples/guest-book/sqlite", "extern": true } } }\n' "$LINEA_ROOT" > app/linea.json
  $ printf 'import sqlite\n\nuse sqlite.Database\n\npub fn check_count(db: Database) -> Result[(), sqlite.Error] {\n    let _statement = db.prepare("SELECT COUNT(*) FROM entries")?\n    .Ok(())\n}\n\nfn main() -> UInt8 {\n    0\n}\n' > app/main.lin
  $ linea check app
  error[O-Leak]: `_statement` (a linear `sqlite.Statement`) is still owned when this path leaves
   --> app/main.lin:6:9
    |
  6 |     let _statement = db.prepare("SELECT COUNT(*) FROM entries")?
    |         ^^^^^^^^^^ never settled on the path that reaches the end of this block
  8 | }
    | - the block ends here
    |
    = help: settle it first with `_statement.release()` or `_statement.finish()`
  [1]

And a program whose manifest does not consent to the library's C declarations
is refused before any code is checked.

  $ printf '{\n  "dependencies": {\n    "sqlite": {\n      "path": "%s/examples/guest-book/sqlite"\n    }\n  }\n}\n' "$LINEA_ROOT" > app/linea.json
  $ linea check app
  error[M-Dependency]: the manifest of `sqlite` grants it `extern`, and this entry does not consent to it
   --> app/linea.json:3:5
    |
  3 |     "sqlite": {
    |     ^^^^^^^^ write `"extern": true` in this entry to trust the signatures it declares
  error[T-Infer]: the type of this variant cannot be determined
   --> app/main.lin:7:5
    |
  7 |     .Ok(())
    |     ^^^ name its enum, or give the binding a type
  [1]
