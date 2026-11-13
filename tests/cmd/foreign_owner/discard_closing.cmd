The restricted owner API refuses invalid access or authority transitions.

  $ cp -R "$LINEA_ROOT"/tests/ffi/thread_bound_owner/cleanup_retry app
  $ cp "$LINEA_ROOT"/tests/cmd/foreign_owner/fixtures/discard-closing.fixture app/main.lin
  $ linea check app
  error[O-Leak]: `_closing` (a linear `confined.Closing`) is still owned when this path leaves
   --> app/main.lin:5:9
    |
  5 |     let _closing = match active.shutdown() { Ok(_) => panic("expected failure"), Err(value) => value }
    |         ^^^^^^^^ never settled on the path that reaches the end of this block
  7 | }
    | - the block ends here
    |
    = help: end it with `_closing.retry()`, and settle what its `Err` hands back
  [1]
