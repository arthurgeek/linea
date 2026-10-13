Stopping `linea run` stops the program it runs. The server has no connection
limit, so once the run has ended, the port refuses the first connection only
if the program ended with it.

  $ : > server.log; linea run "$LINEA_ROOT"/examples/bounded_echo.lin -- serve --port 0 > server.log 2>&1 & server=$!
  $ for i in $(seq 2400); do grep -q listening server.log && break; kill -0 $server 2>/dev/null || break; sleep 0.05; done; grep -q listening server.log || cat server.log
  $ port=$(sed -n 's/.* listening address=127.0.0.1://p' server.log)
  $ { kill -TERM $server; wait $server; } 2>/dev/null; echo "the run ended with status $?"
  the run ended with status 143
  $ linea run "$LINEA_ROOT"/examples/bounded_echo.lin -- send --port "$port" hi > out 2> err
  [1]
  $ sed -e "s/$port/PORT/" -e 's/errno [0-9]*/errno N/' err
  bounded_echo: cannot connect to 127.0.0.1:PORT: Connect failed (ConnectionRefused) after 0 bytes; errno N
  $ cat out
