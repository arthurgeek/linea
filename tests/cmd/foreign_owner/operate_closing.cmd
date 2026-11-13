The restricted owner API refuses invalid access or authority transitions.

  $ cp -R "$LINEA_ROOT"/tests/ffi/thread_bound_owner/cleanup_retry app
  $ cp "$LINEA_ROOT"/tests/cmd/foreign_owner/fixtures/operate-closing.fixture app/main.lin
  $ linea check app
  error[T-UnknownOperation]: `confined.Closing` has no operation `client`
   --> app/main.lin:6:5
    |
  6 |     closing.client().value()
    |     ^^^^^^^^^^^^^^ no operation of this name is declared for this type
  [1]
