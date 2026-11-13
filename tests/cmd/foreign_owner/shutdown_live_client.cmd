The restricted owner API refuses invalid access or authority transitions.

  $ cp -R "$LINEA_ROOT"/tests/ffi/thread_bound_owner/cleanup_retry app
  $ cp "$LINEA_ROOT"/tests/cmd/foreign_owner/fixtures/shutdown-live-client.fixture app/main.lin
  $ linea check app
  error[O-Borrow]: this operation invalidates a place that a later observation still needs
   --> app/main.lin:6:18
    |
  6 |     let result = active.shutdown()
    |                  ^^^^^^ keep this place available until the last use of its observation
  7 |     let value = client.value()
    |                 ------ the observation is still used here
  [1]
