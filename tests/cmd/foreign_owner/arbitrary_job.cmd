The restricted owner API refuses invalid access or authority transitions.

  $ cp -R "$LINEA_ROOT"/tests/ffi/thread_bound_owner/cleanup_retry app
  $ cp "$LINEA_ROOT"/tests/cmd/foreign_owner/fixtures/arbitrary-job.fixture app/main.lin
  $ linea check app
  error[T-UnknownOperation]: `confined.Client` has no operation `call`
   --> app/main.lin:5:5
    |
  5 |     active.client().call(|inout state| state)
    |     ^^^^^^^^^^^^^^^^^^^^ no operation of this name is declared for this type
  [1]
