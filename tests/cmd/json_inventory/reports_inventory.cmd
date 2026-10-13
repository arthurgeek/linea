The inventory report, built once, totals each file below, or says why it
cannot.

  $ linea build "$LINEA_ROOT"/examples/json_inventory.lin -o inventory

A file of products is totalled and written as JSON.

  $ ./inventory "$LINEA_ROOT"/tests/cmd/json_inventory/inventory.json > out
  $ cat out
  {"products":[{"units":7,"name":"tea"},{"units":11,"name":"coffee"}],"summary":{"total_units":18}}

A file that is not JSON is refused with where the syntax broke.

  $ ./inventory "$LINEA_ROOT"/tests/cmd/json_inventory/malformed.json > out
  inventory failed: File(Parse(ParseError { kind: Syntax, offset: 13 }))
  [1]
  $ cat out

A file that does not exist is refused with why it could not be opened.

  $ ./inventory "$LINEA_ROOT"/tests/cmd/json_inventory/absent.json > out
  inventory failed: File(Read(Read(ReadFileReason { primary: Some(Open(FsFailure { primary: Some(Io(IoError { operation: Open, category: NotFound, code: Some(2), progress: 0 })), close: None, remove: None, parent_close: None, published: false, written: 0 })), close: None })))
  [1]
  $ cat out
