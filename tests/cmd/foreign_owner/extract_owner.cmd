The restricted owner API refuses invalid access or authority transitions.

  $ cp -R "$LINEA_ROOT"/tests/ffi/thread_bound_owner/cleanup_retry app
  $ cp "$LINEA_ROOT"/tests/cmd/foreign_owner/fixtures/extract-owner.fixture app/main.lin
  $ linea check app
  error[M-Opaque]: `Active` is opaque outside `confined`
   --> app/main.lin:5:18
    |
  5 |     let _owner = active.owner
    |                  ^^^^^^^^^^^^ only its own module can read its parts
  [1]
