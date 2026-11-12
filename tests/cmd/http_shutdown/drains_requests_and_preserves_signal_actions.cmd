Graceful shutdown completes an in-flight request, closes idle connections and
stops accepting work. Later signals use the restored action; Manual and an
inherited ignored signal keep their original meaning. Only the server child
process receives these signals.

  $ linea build "$LINEA_ROOT"/tests/cmd/fixtures/http_shutdown_server.lin -o shutdown-server
  $ node "$LINEA_ROOT"/tests/cmd/fixtures/http_shutdown.mjs ./shutdown-server
  SIGTERM drains in-flight, closes idle and refuses newcomers: ok
  SIGINT drains in-flight, closes idle and refuses newcomers: ok
  queued-ready requests finish beside the in-flight request during shutdown: ok
  second SIGTERM uses the restored termination action: ok
  Manual leaves the default signal action unchanged: ok
  an inherited ignored SIGTERM keeps serving: ok
  the application's own signal registration wakes beside the server's: ok
  Sequential finishes its current request before stopping: ok
