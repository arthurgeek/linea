The JSON echo server, built once and run twice.

With no requests to answer, the server reports the address it bound, then
stops and reports that it echoed nothing.

  $ linea build "$LINEA_ROOT"/examples/http-json-echo -o echo
  $ ./echo --port 0 --requests 0 2> server.log
  $ sed -E -e 's/^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z /TIME /' -e 's/duration=[^ ]+/duration=D/' -e 's/127[.]0[.]0[.]1:[0-9]+/127.0.0.1:PORT/g' server.log
  TIME INFO listening address=127.0.0.1:PORT
  TIME INFO stopped echoed=0

One server then answers every request below in turn, and stops after the last.

  $ : > server.log; ./echo --port 0 --requests 13 > server.log 2>&1 & server=$!
  $ for i in $(seq 2400); do grep -q listening server.log && break; kill -0 $server 2>/dev/null || break; sleep 0.05; done; grep -q listening server.log || cat server.log
  $ port=$(sed -n 's/.* listening address=127.0.0.1://p' server.log)

GET /health answers 200 with ok.

  $ curl -s --max-time 30 -w ' %{http_code}\n' "http://127.0.0.1:$port/health"
  ok 200

POST /echo decodes a message and sends its text back to the caller its
`Authorization` header names; the handler logs the message before the request
line.

  $ curl -s --max-time 30 -H 'Content-Type: application/json' -H 'Authorization: Bearer ada' -X POST --data '{"text":"hello"}' "http://127.0.0.1:$port/echo"
  {"to":"ada","echo":"hello"}

GET /greet/{name} greets the name the path carries.

  $ curl -s --max-time 30 "http://127.0.0.1:$port/greet/ada"
  {"hello":"ada"}

A body sent without `Content-Type: application/json` is answered 415 before it
is decoded; curl's `--data` sends a form.

  $ curl -s --max-time 30 -w '%{http_code}\n' -H 'Authorization: Bearer ada' -X POST --data '{"text":"hello"}' "http://127.0.0.1:$port/echo"
  expected a JSON body, sent with `Content-Type: application/json`
  415

A message without an `Authorization: Bearer` header names no caller, so it is
answered 401 with a `WWW-Authenticate` challenge naming the scheme to use.

  $ curl -s --max-time 30 -D headers.txt -w '%{http_code}\n' -H 'Content-Type: application/json' -X POST --data '{"text":"hello"}' "http://127.0.0.1:$port/echo"
  name the caller with `Authorization: Bearer <name>`
  401
  $ tr -d '\r' < headers.txt | grep -i '^www-authenticate'
  WWW-Authenticate: Bearer

A message without its text is answered 422, naming the missing field.

  $ curl -s --max-time 30 -w '%{http_code}\n' -H 'Content-Type: application/json' -H 'Authorization: Bearer ada' -X POST --data '{}' "http://127.0.0.1:$port/echo"
  missing field at $["text"]
  422

A body sent to POST /signup as JSON is answered 415 before it is decoded,
since the route reads a form.

  $ curl -s --max-time 30 -w '%{http_code}\n' -H 'Content-Type: application/json' -X POST --data '{"name":"Ada","age":30}' "http://127.0.0.1:$port/signup"
  expected a form body, sent with `Content-Type: application/x-www-form-urlencoded`
  415

POST /signup reads a form's fields by name, exactly as a browser's `<form>`
posts them, and confirms them as JSON.

  $ curl -s --max-time 30 --data-urlencode 'name=Ada López' --data-urlencode 'age=30' "http://127.0.0.1:$port/signup"
  {"signed_up":"Ada López","age":30}

A path matched only under other methods is answered 405, and Allow names them.

  $ curl -s --max-time 30 -D - -X DELETE "http://127.0.0.1:$port/echo" | tr -d '\r'
  HTTP/1.1 405 Method Not Allowed
  Connection: close
  Allow: POST
  X-Request-Id: 9
  Content-Type: text/plain; charset=utf-8
  
  method not allowed

A path no route matches is answered 404.

  $ curl -s --max-time 30 -w '%{http_code}\n' "http://127.0.0.1:$port/nowhere"
  not found
  404

A body one byte past the 1 MiB limit is answered 413 without being read, and
the server goes on answering the requests after it.

  $ head -c 1048577 /dev/zero | curl -s --max-time 30 -o /dev/null -w '%{http_code}\n' --expect100-timeout 30 --data-binary @- "http://127.0.0.1:$port/echo"
  413

GET /stats reports how many messages the server has echoed, a count every
handler shares through the router's state, and the server logs the count when
it stops.

  $ curl -s --max-time 30 -H 'Content-Type: application/json' -H 'Authorization: Bearer alan' -X POST --data '{"text":"hi"}' "http://127.0.0.1:$port/echo"
  {"to":"alan","echo":"hi"}
  $ curl -s --max-time 30 "http://127.0.0.1:$port/stats"
  {"echoed":2}
  $ for i in $(seq 600); do kill -0 $server 2>/dev/null || break; sleep 0.05; done; kill $server 2>/dev/null && echo "the server did not stop"; wait $server
  $ sed -E -e 's/^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z /TIME /' -e 's/duration=[^ ]+/duration=D/' -e 's/127[.]0[.]0[.]1:[0-9]+/127.0.0.1:PORT/g' server.log
  TIME INFO listening address=127.0.0.1:PORT
  TIME INFO request method=GET path=/health request_id=1 status=200 bytes=2 duration=D
  TIME INFO echoing a message caller=ada bytes=5
  TIME INFO request method=POST path=/echo request_id=2 status=200 bytes=27 duration=D
  TIME INFO greeting name=ada
  TIME INFO request method=GET path=/greet/ada request_id=3 status=200 bytes=15 duration=D
  TIME WARN request method=POST path=/echo request_id=4 status=415 bytes=65 duration=D error="the handler refused the request: expected a JSON body, sent with `Content-Type: application/json`"
  TIME WARN request method=POST path=/echo request_id=5 status=401 bytes=52 duration=D error="the handler refused the request: name the caller with `Authorization: Bearer <name>`"
  TIME WARN request method=POST path=/echo request_id=6 status=422 bytes=27 duration=D error="the handler refused the request: missing field at $[\"text\"]"
  TIME WARN request method=POST path=/signup request_id=7 status=415 bytes=82 duration=D error="the handler refused the request: expected a form body, sent with `Content-Type: application/x-www-form-urlencoded`"
  TIME INFO signed up name="Ada López" age=30
  TIME INFO request method=POST path=/signup request_id=8 status=200 bytes=35 duration=D
  TIME WARN request method=DELETE path=/echo request_id=9 status=405 bytes=19 duration=D
  TIME WARN request method=GET path=/nowhere request_id=10 status=404 bytes=10 duration=D error="the handler refused the request: not found"
  TIME WARN request status=413 bytes=0 error="reading the request failed: the request was refused with 413 Content Too Large"
  TIME INFO echoing a message caller=alan bytes=2
  TIME INFO request method=POST path=/echo request_id=11 status=200 bytes=25 duration=D
  TIME INFO request method=GET path=/stats request_id=12 status=200 bytes=12 duration=D
  TIME INFO stopped echoed=2
