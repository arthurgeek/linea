The restricted owner API refuses invalid access or authority transitions.

  $ cp -R "$LINEA_ROOT"/tests/ffi/thread_bound_owner/cleanup_retry app
  $ cp "$LINEA_ROOT"/tests/cmd/foreign_owner/fixtures/extract-resource.fixture app/main.lin
  $ linea check app
  error[M-Opaque]: `Client` is opaque outside `confined`
   --> app/main.lin:6:21
    |
  6 |     let _raw = copy(client.raw)
    |                     ^^^^^^^^^^ only its own module can read its parts
  [1]
