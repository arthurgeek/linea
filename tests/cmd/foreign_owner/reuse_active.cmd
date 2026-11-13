The restricted owner API refuses invalid access or authority transitions.

  $ cp -R "$LINEA_ROOT"/tests/ffi/thread_bound_owner/cleanup_retry app
  $ cp "$LINEA_ROOT"/tests/cmd/foreign_owner/fixtures/reuse-active.fixture app/main.lin
  $ linea check app
  error[O-Move]: `active` has already been moved
   --> app/main.lin:6:11
    |
  5 |     match active.shutdown() { Ok(_) => (), Err(_) => panic("failed close") }
    |           ------ it was taken here
  6 |     UInt8(active.client().value())
    |           ^^^^^^ it was already taken, and a value is taken once
  [1]
