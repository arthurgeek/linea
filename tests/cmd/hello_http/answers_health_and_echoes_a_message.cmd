GET /health answers ok, and POST /echo sends the text of a JSON message back
as JSON. The server listens until the transcript stops it.

  $ port=$((20000 + $$ % 20000)); linea run "$LINEA_ROOT"/examples/hello_http.lin -- $port > server.log 2>&1 & server=$!
  $ for i in $(seq 2400); do curl -s -o /dev/null --max-time 30 "http://127.0.0.1:$port/health" && break; kill -0 $server 2>/dev/null || break; sleep 0.05; done
  $ curl -s --max-time 30 -w ' %{http_code}\n' "http://127.0.0.1:$port/health"
  ok 200
  $ curl -s --max-time 30 -H 'Content-Type: application/json' -X POST --data '{"text":"hello"}' "http://127.0.0.1:$port/echo"
  {"echo":"hello"}
  $ curl -s --max-time 30 -w ' %{http_code}\n' -H 'Content-Type: application/json' -X POST --data '{}' "http://127.0.0.1:$port/echo"
  missing field at $["text"]
   422
  $ curl -s --max-time 30 -w ' %{http_code}\n' "http://127.0.0.1:$port/echo"
  method not allowed
   405
  $ curl -s --max-time 30 -w ' %{http_code}\n' "http://127.0.0.1:$port/missing"
  not found
   404
  $ { kill -TERM $server; wait $server; } 2>/dev/null; echo "the run ended with status $?"
  the run ended with status 143
  $ sed -E 's/127[.]0[.]0[.]1:[0-9]+/127.0.0.1:PORT/g' server.log
  listening on http://127.0.0.1:PORT
