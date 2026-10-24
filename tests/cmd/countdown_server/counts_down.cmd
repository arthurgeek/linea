The countdown server, built once, answers each request below in turn and
stops after the last.

  $ linea build "$LINEA_ROOT"/examples/countdown-server -o countdown
  $ : > server.log; ./countdown --port 0 --requests 2 > server.log 2>&1 & server=$!
  $ for i in $(seq 2400); do grep -q listening server.log && break; kill -0 $server 2>/dev/null || break; sleep 0.05; done; grep -q listening server.log || cat server.log
  $ port=$(sed -n 's/.* listening address=127.0.0.1://p' server.log)

GET /countdown/1 sends `T-1`, then `liftoff` a second later, each line as soon
as it is written: the first byte arrives at least a second before the last,
because the server sends each line before it sleeps.

  $ curl -s -N --max-time 30 -o countdown.txt -w '%{time_starttransfer} %{time_total}\n' "http://127.0.0.1:$port/countdown/1" > times
  $ cat countdown.txt
  T-1
  liftoff
  $ awk '{ if ($2 - $1 >= 0.9) print "the lines arrived a second apart"; else print "the lines arrived together: " $0 }' times
  the lines arrived a second apart

A count past ten seconds is refused with 400 before anything is streamed, and
the refusal is logged as a warning.

  $ curl -s --max-time 30 -w '%{http_code}\n' "http://127.0.0.1:$port/countdown/60"
  60 is not a count from 1 to 10
  400
  $ for i in $(seq 600); do kill -0 $server 2>/dev/null || break; sleep 0.05; done; kill $server 2>/dev/null && echo "the server did not stop"; wait $server
  $ sed -E -e 's/^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z /TIME /' -e 's/duration=[^ ]+/duration=D/' -e 's/127[.]0[.]0[.]1:[0-9]+/127.0.0.1:PORT/g' server.log
  TIME INFO listening address=127.0.0.1:PORT
  TIME INFO starting a countdown seconds=1
  TIME INFO request method=GET path=/countdown/1 status=200 bytes=12 duration=D
  TIME WARN request method=GET path=/countdown/60 status=400 bytes=31 duration=D error="the handler refused the request: 60 is not a count from 1 to 10"

A port that is not a number is named in the error, before the usage.

  $ ./countdown --port eighty
  error: invalid value 'eighty' for option '--port'
  usage: countdown-server [options]
  
  Countdown server
  
  options:
    --port <value>        port to listen on
    --requests <value>    number of requests to serve
  
  [64]
