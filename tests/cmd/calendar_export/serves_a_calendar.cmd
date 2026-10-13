The calendar export server, built once, answers each request below in turn
and stops after the last.

  $ linea build "$LINEA_ROOT"/examples/calendar-export -o calendar
  $ : > server.log; ./calendar --port 0 --requests 4 > server.log 2>&1 & server=$!
  $ for i in $(seq 2400); do grep -q listening server.log && break; kill -0 $server 2>/dev/null || break; sleep 0.05; done; grep -q listening server.log || cat server.log
  $ port=$(sed -n 's/.* listening address=127.0.0.1://p' server.log)

GET /calendar/{year} streams every day of the year as a CSV line, after a
header line: 2024 is a leap year, so it has 366 days and a 29 February.

  $ curl -s --max-time 30 -o calendar.csv "http://127.0.0.1:$port/calendar/2024"
  $ head -n 3 calendar.csv
  date,weekday,day_of_year
  2024-01-01,Monday,1
  2024-01-02,Tuesday,2
  $ grep -c '' calendar.csv
  367
  $ grep -- -02-29 calendar.csv
  2024-02-29,Thursday,60
  $ tail -n 1 calendar.csv
  2024-12-31,Tuesday,366

A HEAD request is answered with the calendar's head, and the body is never
produced.

  $ curl -s --max-time 30 -I "http://127.0.0.1:$port/calendar/2026" | tr -d '\r' | grep -v '^$'
  HTTP/1.1 200 OK
  Connection: close
  Content-Type: text/csv; charset=utf-8

A year past 9999 is answered 400 before anything is streamed, and the handler
logs the year it refused.

  $ curl -s --max-time 30 -w '%{http_code}\n' "http://127.0.0.1:$port/calendar/12000"
  12000 is not a year from 1 to 9999
  400

A year that is not a number is answered 400 before anything is streamed,
naming the path value and why it could not be read.

  $ curl -s --max-time 30 -w '%{http_code}\n' "http://127.0.0.1:$port/calendar/next"
  cannot read path value "year" from "next": invalid decimal syntax at byte 0
  400
  $ for i in $(seq 600); do kill -0 $server 2>/dev/null || break; sleep 0.05; done; kill $server 2>/dev/null && echo "the server did not stop"; wait $server
  $ sed -E -e 's/^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z /TIME /' -e 's/duration=[^ ]+/duration=D/' -e 's/127[.]0[.]0[.]1:[0-9]+/127.0.0.1:PORT/g' server.log
  TIME INFO listening address=127.0.0.1:PORT
  TIME INFO request method=GET path=/calendar/2024 status=200 bytes=8386 duration=D
  TIME INFO request method=HEAD path=/calendar/2026 status=200 bytes=0 duration=D
  TIME WARN refused a year year=12000
  TIME WARN request method=GET path=/calendar/12000 status=400 bytes=35 duration=D error="the handler refused the request: 12000 is not a year from 1 to 9999"
  TIME WARN refused a year year=next
  TIME WARN request method=GET path=/calendar/next status=400 bytes=76 duration=D error="the handler refused the request: cannot read path value \"year\" from \"next\": invalid decimal syntax at byte 0"
