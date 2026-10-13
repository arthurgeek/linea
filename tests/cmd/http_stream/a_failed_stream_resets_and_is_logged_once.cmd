A streamed body that fails after its head resets the connection, so the client
reads an error rather than a short body, and the server logs one line.

  $ : > server.log; linea run "$LINEA_ROOT"/tests/cmd/fixtures/a_stream_that_fails_after_one_line.lin -- 0 > server.log 2>&1 & server=$!
  $ for i in $(seq 2400); do grep -q listening server.log && break; kill -0 $server 2>/dev/null || break; sleep 0.05; done; grep -q listening server.log || cat server.log
  $ port=$(sed -n 's/.* listening address=127.0.0.1://p' server.log)
  $ curl -s --max-time 30 -o report.txt "http://127.0.0.1:$port/report"; echo "curl exited $?"
  curl exited 56
  $ for i in $(seq 600); do kill -0 $server 2>/dev/null || break; sleep 0.05; done; kill $server 2>/dev/null && echo "the server did not stop"; wait $server
  $ sed -E -e 's/^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z /TIME /' -e 's/duration=[^ ]+/duration=D/' -e 's/127[.]0[.]0[.]1:[0-9]+/127.0.0.1:PORT/g' server.log
  TIME INFO listening address=127.0.0.1:PORT
  TIME ERROR request method=GET path=/report status=200 bytes=11 duration=D error="streaming the response failed with 500: the report's data ran out"
