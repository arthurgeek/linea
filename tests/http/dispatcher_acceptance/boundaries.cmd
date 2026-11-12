Persistent connections preserve request boundaries, enforce body limits before
handlers run, bound a stalled body read, evict the oldest idle reader and stop
accepting when every connection in the budget is serving a request.

  $ linea build "$LINEA_ROOT"/tests/http/dispatcher_acceptance/server.lin -o dispatcher-server
  $ node "$LINEA_ROOT"/tests/http/dispatcher_acceptance/scenarios.mjs ./dispatcher-server
  unread body bytes are drained before the next pipelined request: ok
  a 128 KiB network body streams through a 64 KiB request arena: ok
  oversized bodies are refused for ignoring and consuming handlers: ok
  a stalled partial body reaches its request deadline: ok
  a newcomer evicts the oldest idle connection: ok
  active connections enforce backpressure without eviction: ok
  HTTP/1.0 closes even when keep-alive is requested: ok
  agreeing lengths preserve boundaries; malformed and disagreeing lengths close with 400: ok
  Transfer-Encoding beside Content-Length closes with 400 and no pipeline reuse: ok
  a folded header closes with 400 and no pipeline reuse: ok
