The guest book refuses oversized bodies, empty or overlong fields, cross-site
posts, and unknown methods or paths.

  $ linea build "$LINEA_ROOT"/examples/guest-book -o book
  $ : > server.log; GUEST_BOOK_DATABASE=guests.db ./book 0 > server.log 2>&1 & server=$!
  $ for i in $(seq 2400); do grep -q listening server.log && break; kill -0 $server 2>/dev/null || break; sleep 0.05; done; grep -q listening server.log || cat server.log
  $ port=$(sed -n 's/.* listening address=127.0.0.1://p' server.log)

The body limit is the longest form the page sends: a 60-character name and a
500-character message, every character four bytes of UTF-8 written as `%XX`.
That form is accepted, and one byte more is refused with 413 before the
handler reads it.

  $ { printf 'name='; for i in $(seq 60); do printf '%%F0%%9F%%98%%80'; done; printf '&message='; for i in $(seq 500); do printf '%%F0%%9F%%98%%80'; done; } > longest
  $ wc -c < longest | tr -d ' '
  6734
  $ curl -s --max-time 30 -o /dev/null -w '%{http_code}\n' -X POST --data-binary @longest "http://127.0.0.1:$port/sign"
  303
  $ { cat longest; printf 'a'; } > oversized
  $ curl -s --max-time 30 -o /dev/null -w '%{http_code}\n' -X POST --data-binary @oversized "http://127.0.0.1:$port/sign"
  413

A control character in the name, such as a NUL or a line break, is refused
with 422.

  $ curl -s --max-time 30 -w '%{http_code}\n' -X POST --data 'name=a%00b%0D%0ASet-Cookie:+x=1&message=hi' "http://127.0.0.1:$port/sign"
  a name holds no control characters, and a message only line breaks and tabs
  422

An empty message (after trimming spaces) is refused with 422.

  $ curl -s --max-time 30 -w '%{http_code}\n' -X POST --data 'name=Ada&message=+++' "http://127.0.0.1:$port/sign"
  a signature needs a name and a message
  422

A post from another site is refused with 403, whether reported by
`Sec-Fetch-Site` or by an `Origin` header whose host differs from `Host`.

  $ curl -s --max-time 30 -w '%{http_code}\n' -H 'Sec-Fetch-Site: cross-site' -X POST --data 'name=Ada&message=Hello' "http://127.0.0.1:$port/sign"
  a signature is accepted only from this guest book's own page
  403
  $ curl -s --max-time 30 -w '%{http_code}\n' -H 'Host: example.test' -H 'Origin: http://other.test' -X POST --data 'name=Ada&message=Hello' "http://127.0.0.1:$port/sign"
  a signature is accepted only from this guest book's own page
  403

An unsupported method answers 405, and an unknown path answers 404.

  $ curl -s --max-time 30 -w '%{http_code}\n' -X DELETE "http://127.0.0.1:$port/"
  method not allowed
  405
  $ curl -s --max-time 30 -w '%{http_code}\n' "http://127.0.0.1:$port/nowhere"
  not found
  404
  $ { kill -TERM $server; wait $server; } 2>/dev/null; echo "the server stopped with status $?"
  the server stopped with status 143

When SQLite cannot open the database file, its sentence is written to standard
error and the program exits 1 before listening.

  $ GUEST_BOOK_DATABASE=missing/dir/guests.db ./book 0
  guest-book: unable to open database file (SQLite code 14)
  [1]
