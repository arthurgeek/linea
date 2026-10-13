The party RSVP program answers one CGI request each time it runs. A web
server describes the request in environment variables and sends a form's body
on standard input; `env -i` starts each run with only the variables written
here, as a web server would.

  $ linea build "$LINEA_ROOT"/examples/party_rsvp.lin -o rsvp

Run without `REQUEST_METHOD`, no web server started it, so there is no request
to answer.

  $ env -i ./rsvp
  party_rsvp: REQUEST_METHOD is not set, so no web server started this program to answer a request
  run it from a web server, or describe a request: REQUEST_METHOD=GET party_rsvp
  [64]

GET / answers the invitation page. The head starts with a `Status` header, its
lines end in CRLF, and a blank line separates it from the body. `tr` drops the
carriage returns so the answer reads plainly; standard error holds the log
line, with its time and duration masked. The form posts to the program's own
address, which `SCRIPT_NAME` names. `SERVER_PROTOCOL` is how the browser spoke
to the web server, here HTTP/2; the program never speaks it, so it answers
whatever it says.

  $ env -i REQUEST_METHOD=GET PATH_INFO=/ SCRIPT_NAME=/cgi-bin/party_rsvp SERVER_PROTOCOL=HTTP/2.0 ./rsvp > page 2> log
  $ awk '/\r$/ { n++ } END { print n }' page
  3
  $ tr -d '\r' < page
  Status: 200 OK
  Content-Type: text/html; charset=utf-8
  
  <!doctype html>
  <title>Party</title>
  <form method="post" action="/cgi-bin/party_rsvp/reply">
    <label>Name <input name="name"></label>
    <label>Guests <input name="guests" type="number" value="0"></label>
    <button>Reply</button>
  </form>
  $ sed -E -e 's/^[0-9T:-]+Z /TIME /' -e 's/duration=[^ ]+/duration=D/' log
  TIME INFO request method=GET path=/ status=200 bytes=237 duration=D

POST /reply reads the form from standard input, exactly `CONTENT_LENGTH`
bytes of it, and the date from `PARTY_DATE`.

  $ printf 'name=Ada&guests=2' | env -i REQUEST_METHOD=POST PATH_INFO=/reply CONTENT_TYPE=application/x-www-form-urlencoded CONTENT_LENGTH=17 PARTY_DATE='on Saturday' ./rsvp 2> /dev/null | tr -d '\r'
  Status: 200 OK
  Content-Type: application/json
  
  {"name":"Ada","guests":2,"message":"see you on Saturday"}

The web server takes a chunked upload apart before the program sees it, so
`HTTP_TRANSFER_ENCODING` describes how the browser sent the body, not how
standard input holds it; `CONTENT_LENGTH` alone says how long the body is.

  $ printf 'name=Ada&guests=2' | env -i REQUEST_METHOD=POST PATH_INFO=/reply CONTENT_TYPE=application/x-www-form-urlencoded CONTENT_LENGTH=17 HTTP_TRANSFER_ENCODING=chunked ./rsvp 2> /dev/null | tr -d '\r'
  Status: 200 OK
  Content-Type: application/json
  
  {"name":"Ada","guests":2,"message":"see you soon"}

A path that is not UTF-8 is encoded byte by byte, as a browser would send it,
so the router and the log see `/reply%E9`, the path it is, and not `/reply`.

  $ env -i REQUEST_METHOD=POST PATH_INFO="$(printf '/reply\351')" CONTENT_LENGTH=0 ./rsvp 2> log | tr -d '\r'
  Status: 405 Method Not Allowed
  Allow: GET, HEAD
  Content-Type: text/plain; charset=utf-8
  
  method not allowed
  $ sed -E -e 's/^[0-9T:-]+Z /TIME /' -e 's/duration=[^ ]+/duration=D/' log
  TIME WARN request method=POST path=/reply%E9 status=405 bytes=19 duration=D

A reply bringing too many guests is refused with 422 and the rule it broke.

  $ printf 'name=Ada&guests=9' | env -i REQUEST_METHOD=POST PATH_INFO=/reply CONTENT_TYPE=application/x-www-form-urlencoded CONTENT_LENGTH=17 ./rsvp 2> /dev/null | tr -d '\r'
  Status: 422 Unprocessable Content
  Content-Type: text/plain; charset=utf-8
  
  a reply may bring at most 4 guests

A body longer than the limits allow is refused with 413 before the program
reads it, and the log line says why.

  $ env -i REQUEST_METHOD=POST PATH_INFO=/reply CONTENT_LENGTH=2000000 ./rsvp < /dev/null 2> log | tr -d '\r'
  Status: 413 Content Too Large
  Content-Type: text/plain; charset=utf-8
  
  $ sed -E -e 's/^[0-9T:-]+Z /TIME /' log
  TIME WARN request status=413 bytes=0 error="reading the request failed: the request was refused with 413 Content Too Large"

A method no route names is answered 405, with the methods the path allows.

  $ env -i REQUEST_METHOD=DELETE PATH_INFO=/ ./rsvp 2> /dev/null | tr -d '\r'
  Status: 405 Method Not Allowed
  Allow: GET, HEAD
  Content-Type: text/plain; charset=utf-8
  
  method not allowed
