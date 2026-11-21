The greeting server answers over HTTPS with the certificate the command line
names, and stops after the requests it was told to serve.

  $ linea build "$LINEA_ROOT"/examples/https-greeting -o greeting
  $ : > server.log; ./greeting --port 0 --requests 1 --certificate "$LINEA_ROOT"/examples/https-greeting/localhost.pem --key "$LINEA_ROOT"/examples/https-greeting/localhost_key.pem > server.log 2>&1 & server=$!
  $ for i in $(seq 2400); do grep -q listening server.log && break; kill -0 $server 2>/dev/null || break; sleep 0.05; done; grep -q listening server.log || cat server.log
  $ port=$(sed -n 's/.* listening address=127.0.0.1://p' server.log)

curl trusts the test root that issued the server's certificate, and checks
that the certificate names `localhost`.

  $ curl -s --max-time 30 --cacert "$LINEA_ROOT"/examples/https-greeting/test_ca.pem "https://localhost:$port/hello/ada"
  Hello, ada.
  $ for i in $(seq 600); do kill -0 $server 2>/dev/null || break; sleep 0.05; done; kill $server 2>/dev/null && echo "the server did not stop"; wait $server
  $ sed -E -e 's/^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z /TIME /' -e 's/duration=[^ ]+/duration=D/' -e 's/127[.]0[.]0[.]1:[0-9]+/127.0.0.1:PORT/g' server.log
  TIME INFO listening address=127.0.0.1:PORT
  TIME INFO request method=GET path=/hello/ada status=200 bytes=12 duration=D

A key file that does not exist is reported before anything listens.

  $ ./greeting --port 0 --certificate "$LINEA_ROOT"/examples/https-greeting/localhost.pem --key /no/such/key.pem
  https-greeting: the certificate cannot be used: file read failed: file operation failed after 0 bytes: Open failed (NotFound) after 0 bytes; errno 2
  [1]
