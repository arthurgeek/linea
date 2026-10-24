The echo example, built once and run as a server and as a client.

A command that is not a mode and a port names what is missing, prints the
usage and exits with 64.

  $ linea build "$LINEA_ROOT"/examples/tcp_echo.lin -o echo
  $ ./echo serve
  error: missing required argument 'port'
  usage: tcp_echo <command>
  
  Echo text over TCP
  
  commands:
    serve <port> [clients]      listen for and echo connections
    send <port> <message>...    send messages to an echo server
  
  [64]

  Echo text over TCP

  commands:
    serve <port> [clients]      listen for and echo connections
    send <port> <message>...    send messages to an echo server

  [64]

The echo server sends back everything the client sent.

  $ : > server.log; ./echo serve 0 1 > server.log 2>&1 & server=$!
  $ for i in $(seq 2400); do grep -q listening server.log && break; kill -0 $server 2>/dev/null || break; sleep 0.05; done; grep -q listening server.log || cat server.log
  $ port=$(sed -n 's/^listening on 127.0.0.1://p' server.log)
  $ ./echo send "$port" hello "two words"
  hello
  two words
  $ for i in $(seq 600); do kill -0 $server 2>/dev/null || break; sleep 0.05; done; kill $server 2>/dev/null && echo "the server did not stop"; wait $server
  $ sed -E 's/127[.]0[.]0[.]1:[0-9]+/127.0.0.1:PORT/g' server.log
  listening on 127.0.0.1:PORT
  echoed 16 bytes to 127.0.0.1:PORT

The server answers clients one after another and stops after the last one.

  $ : > server.log; ./echo serve 0 2 > server.log 2>&1 & server=$!
  $ for i in $(seq 2400); do grep -q listening server.log && break; kill -0 $server 2>/dev/null || break; sleep 0.05; done; grep -q listening server.log || cat server.log
  $ port=$(sed -n 's/^listening on 127.0.0.1://p' server.log)
  $ ./echo send "$port" first
  first
  $ ./echo send "$port" second
  second
  $ for i in $(seq 600); do kill -0 $server 2>/dev/null || break; sleep 0.05; done; kill $server 2>/dev/null && echo "the server did not stop"; wait $server
  $ sed -E 's/127[.]0[.]0[.]1:[0-9]+/127.0.0.1:PORT/g' server.log
  listening on 127.0.0.1:PORT
  echoed 6 bytes to 127.0.0.1:PORT
  echoed 7 bytes to 127.0.0.1:PORT

Sending to a port nothing listens on reports a refused connection.

  $ ./echo serve 0 0 2> server.log
  $ port=$(sed -n 's/^listening on 127.0.0.1://p' server.log)
  $ ./echo send "$port" hi > out 2> err
  [1]
  $ sed -e "s/$port/PORT/" -e 's/errno [0-9]*/errno N/' err
  cannot connect to port PORT: Connect failed (ConnectionRefused) after 0 bytes; errno N
  $ cat out
