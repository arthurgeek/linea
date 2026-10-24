A statement observes the database it was prepared on, so closing or releasing
the database while the statement is still open is refused at compile time.

  $ mkdir app
  $ printf '{ "dependencies": { "sqlite": { "path": "%s/examples/guest-book/sqlite", "extern": true } } }\n' "$LINEA_ROOT" > app/linea.json
  $ printf 'import sqlite\n\nuse sqlite.Database\n\nfn main() -> UInt8 {\n    let database = Database.open_in_memory().unwrap()\n    let statement = database.prepare("SELECT 1").unwrap()\n    database.close()\n    statement.finish()\n    0\n}\n' > app/main.lin
  $ linea check app
  error[O-Borrow]: this operation invalidates a place that a later observation still needs
   --> app/main.lin:8:5
    |
  8 |     database.close()
    |     ^^^^^^^^ keep this place available until the last use of its observation
  9 |     statement.finish()
    |     --------- the observation is still used here
  [1]

  $ printf 'import sqlite\n\nuse sqlite.Database\n\nfn main() -> UInt8 {\n    let database = Database.open_in_memory().unwrap()\n    let statement = database.prepare("SELECT 1").unwrap()\n    database.release()\n    statement.finish()\n    0\n}\n' > app/main.lin
  $ linea check app
  error[O-Borrow]: this operation invalidates a place that a later observation still needs
   --> app/main.lin:8:5
    |
  8 |     database.release()
    |     ^^^^^^^^ keep this place available until the last use of its observation
  9 |     statement.finish()
    |     --------- the observation is still used here
  [1]

Finishing the statement first ends the observation, and the database closes.

  $ printf 'import sqlite\n\nuse sqlite.Database\n\nfn main() -> UInt8 {\n    let database = Database.open_in_memory().unwrap()\n    let statement = database.prepare("SELECT 1").unwrap()\n    statement.finish()\n    database.close()\n    0\n}\n' > app/main.lin
  $ linea check app
