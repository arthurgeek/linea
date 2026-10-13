The bounded echo example, built once and run as a server and as a client.

The echo server sends every line back to the client that sent it.

  $ linea build "$LINEA_ROOT"/examples/bounded_echo.lin -o echo
  $ : > server.log; ./echo serve --port 0 --connections 1 > server.log 2>&1 & server=$!
  $ for i in $(seq 2400); do grep -q listening server.log && break; kill -0 $server 2>/dev/null || break; sleep 0.05; done; grep -q listening server.log || cat server.log
  $ port=$(sed -n 's/.* listening address=127.0.0.1://p' server.log)
  $ ./echo send --port "$port" hello "two words"
  hello
  two words
  $ for i in $(seq 600); do kill -0 $server 2>/dev/null || break; sleep 0.05; done; kill $server 2>/dev/null && echo "the server did not stop"; wait $server
  $ sed -E -e 's/^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z /TIME /' -e 's/duration=[^ ]+/duration=D/' -e 's/127[.]0[.]0[.]1:[0-9]+/127.0.0.1:PORT/g' server.log
  TIME INFO listening address=127.0.0.1:PORT
  TIME INFO echoed peer=127.0.0.1:PORT lines=2

The server answers connections one after another and stops after the last one.

  $ : > server.log; ./echo serve --port 0 --connections 2 > server.log 2>&1 & server=$!
  $ for i in $(seq 2400); do grep -q listening server.log && break; kill -0 $server 2>/dev/null || break; sleep 0.05; done; grep -q listening server.log || cat server.log
  $ port=$(sed -n 's/.* listening address=127.0.0.1://p' server.log)
  $ ./echo send --port "$port" first
  first
  $ ./echo send --port "$port" second
  second
  $ for i in $(seq 600); do kill -0 $server 2>/dev/null || break; sleep 0.05; done; kill $server 2>/dev/null && echo "the server did not stop"; wait $server
  $ sed -E -e 's/^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z /TIME /' -e 's/duration=[^ ]+/duration=D/' -e 's/127[.]0[.]0[.]1:[0-9]+/127.0.0.1:PORT/g' server.log
  TIME INFO listening address=127.0.0.1:PORT
  TIME INFO echoed peer=127.0.0.1:PORT lines=1
  TIME INFO echoed peer=127.0.0.1:PORT lines=1

Sending to a port nothing listens on reports a refused connection.

  $ ./echo serve --port 0 --connections 0 2> server.log
  $ port=$(sed -n 's/.* listening address=127.0.0.1://p' server.log)
  $ ./echo send --port "$port" hi > out 2> err
  [1]
  $ sed -e "s/$port/PORT/" -e 's/errno [0-9]*/errno N/' err
  bounded_echo: cannot connect to 127.0.0.1:PORT: Connect failed (ConnectionRefused) after 0 bytes; errno N
  $ cat out
